#!/bin/bash
# Two-sided tests for hooks/helper-ledger.py: a check that can never fail is not a check.
# Re-run after any edit to helper-ledger.py:
#   bash hooks/test-helper-ledger.sh
# Every case here is a MUST-FIRE (a new ledger line appears) or a MUST-NOT-FIRE (it
# doesn't). Everything runs against a throwaway HOME + CLAUDE_PROJECTS_DIR — no real ledger
# is ever touched. Exit 1 if any case fails.
#
# Where transcript files live (a Claude Code project folder): each project gets a folder
# under $CLAUDE_PROJECTS_DIR (default ~/.claude/projects); a subagent's own transcript is
# <project>/<parent-session-id>/subagents/agent-<id>.jsonl. helper-ledger.py walks that
# tree for every agent-*.jsonl, skips one whose mtime is under two minutes old (assumed
# still running), and appends one costed row per finished agent to ~/.claude/ledgers/
# helpers.tsv — never duplicating a row it already wrote for that agent id.
HOOKS_DIR="${HOOKS_DIR:-$(cd "$(dirname "$0")" && pwd -P)}"
LEDGER_SCRIPT="${LEDGER_SCRIPT:-$HOOKS_DIR/helper-ledger.py}"
PY=/usr/bin/python3
pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "  FAIL: $1"; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export CLAUDE_PROJECTS_DIR="$T/projects"
mkdir -p "$HOME" "$CLAUDE_PROJECTS_DIR/proj1/sess-aaa/subagents"
LEDGER="$HOME/.claude/ledgers/helpers.tsv"

back5min() { "$PY" -c "import os,time,sys; t=time.time()-300; os.utime(sys.argv[1], (t,t))" "$1"; }

# --- Case 1 (MUST-FIRE): a real, stable, 3-line/2-message-id agent transcript ---
CASE1="$CLAUDE_PROJECTS_DIR/proj1/sess-aaa/subagents/agent-case1.jsonl"
cat > "$CASE1" <<'EOF'
{"type":"assistant","timestamp":"2026-09-01T10:00:00.000Z","message":{"id":"msgA","model":"claude-opus-5","usage":{"input_tokens":2,"cache_creation_input_tokens":30000,"cache_read_input_tokens":20000,"output_tokens":10}}}
{"type":"assistant","timestamp":"2026-09-01T10:00:01.000Z","message":{"id":"msgA","model":"claude-opus-5","usage":{"input_tokens":2,"cache_creation_input_tokens":30000,"cache_read_input_tokens":20000,"output_tokens":50}}}
{"type":"assistant","timestamp":"2026-09-01T10:03:00.000Z","message":{"id":"msgB","model":"claude-opus-5","usage":{"input_tokens":2,"cache_creation_input_tokens":5000,"cache_read_input_tokens":80000,"output_tokens":20}}}
EOF
back5min "$CASE1"

# --- Case 2 (MUST-NOT-FIRE): identical shape, but mtime is now (still running) ---
CASE2="$CLAUDE_PROJECTS_DIR/proj1/sess-aaa/subagents/agent-case2.jsonl"
sed -e 's/msgA/msgC/' -e 's/msgB/msgD/' "$CASE1" > "$CASE2"
# leave CASE2's mtime at "now" (no back5min call)

# --- Case 3 (MUST-NOT-FIRE): a jsonl in the same dir that is not an agent transcript ---
echo '{"type":"assistant"}' > "$CLAUDE_PROJECTS_DIR/proj1/sess-aaa/subagents/notes.jsonl"

# --- Case 4 (MUST-NOT-FIRE): a corrupt agent-*.jsonl, stable mtime ---
CASE4="$CLAUDE_PROJECTS_DIR/proj1/sess-aaa/subagents/agent-corrupt.jsonl"
echo 'not valid json {{{' > "$CASE4"
back5min "$CASE4"

# The fixture timestamps above are UTC ("...Z"); pin the ledger's local-time column to UTC
# too so the expected row below doesn't depend on the machine's own timezone.
export TZ=UTC

echo "1 first scan: must-fire (case1) and three must-not-fire (case2/3/4) in one pass"
STDERR1="$T/stderr1.txt"
"$PY" "$LEDGER_SCRIPT" 2>"$STDERR1"
rc1=$?
[ "$rc1" = "0" ] && ok || bad "exit code must be 0 (got $rc1)"
[ ! -s "$STDERR1" ] && ok || bad "stderr must be empty on a corrupt-file run (got: $(cat "$STDERR1"))"
[ -f "$LEDGER" ] && ok || bad "ledger file must exist after a scan that found a helper"
n_lines() { tail -n +2 "$LEDGER" 2>/dev/null | grep -c . ; }
lc="$(n_lines)"
[ "$lc" = "1" ] || bad "expected exactly 1 ledger line after first scan, got $lc"
[ "$lc" = "1" ] && ok
line1="$(tail -n +2 "$LEDGER" | head -1)"
expect_line="2026-09-01 10:00	sess-aaa	case1	agent	opus	2	85002	70	3	0.40"
if [ "$line1" = "$expect_line" ]; then ok; else bad "case1 line mismatch:
  got:      $line1
  expected: $expect_line"; fi
grep -q $'\tcase2\t' "$LEDGER" 2>/dev/null && bad "case2 (fresh mtime, still running) must NOT appear" || ok
grep -q $'\tcorrupt\t' "$LEDGER" 2>/dev/null && bad "corrupt file must NOT appear" || ok
grep -q "notes" "$LEDGER" 2>/dev/null && bad "the non-agent notes.jsonl must NOT appear" || ok

echo "2 second scan (must-not-fire): re-running must not duplicate case1 or add case2/corrupt"
"$PY" "$LEDGER_SCRIPT" 2>"$T/stderr2.txt"
rc2=$?
[ "$rc2" = "0" ] && ok || bad "exit code must be 0 on the re-run (got $rc2)"
[ ! -s "$T/stderr2.txt" ] && ok || bad "stderr must stay empty on the re-run"
lc2="$(n_lines)"
[ "$lc2" = "1" ] && ok || bad "expected still exactly 1 ledger line after the re-run, got $lc2"

echo "3 case2 finishes: once its mtime is backdated past the still-running window, it MUST fire"
back5min "$CASE2"
"$PY" "$LEDGER_SCRIPT" 2>"$T/stderr3.txt"
[ ! -s "$T/stderr3.txt" ] && ok || bad "stderr must stay empty"
lc3="$(n_lines)"
[ "$lc3" = "2" ] && ok || bad "expected 2 ledger lines once case2 stopped being 'still running', got $lc3"
grep -q $'\tcase2\t' "$LEDGER" && ok || bad "case2 must appear once it is stable"

echo "4 concurrent invocation (must-not-fire): a held lock makes the second run skip, not race"
LOCK="$HOME/.claude/ledgers/.helper-ledger.lock"
"$PY" -c "
import fcntl, os, sys, time
fd = os.open(sys.argv[1], os.O_CREAT | os.O_RDWR)
fcntl.flock(fd, fcntl.LOCK_EX)
time.sleep(3)
" "$LOCK" &
holder_pid=$!
sleep 0.3
before="$(n_lines)"
"$PY" "$LEDGER_SCRIPT" 2>"$T/stderr5.txt"
rc5=$?
after="$(n_lines)"
wait "$holder_pid" 2>/dev/null
[ "$rc5" = "0" ] && ok || bad "exit code must be 0 while the lock is held (got $rc5)"
[ ! -s "$T/stderr5.txt" ] && ok || bad "stderr must stay empty while the lock is held"
[ "$after" = "$before" ] && ok || bad "ledger must be unchanged while another invocation holds the lock (before=$before after=$after)"

echo "5 --tail N: prints lines and a per-model summary, exits 0"
tail_out="$("$PY" "$LEDGER_SCRIPT" --tail 5 2>"$T/stderr4.txt")"
rc4=$?
[ "$rc4" = "0" ] && ok || bad "--tail must exit 0 (got $rc4)"
[ ! -s "$T/stderr4.txt" ] && ok || bad "--tail must not write to stderr"
echo "$tail_out" | grep -q "SUMMARY opus" && ok || bad "--tail must print an opus summary line"

echo
echo "test-helper-ledger.sh: $pass passed, $fail failed"
[ "$fail" = "0" ] || exit 1
