#!/bin/bash
# gate-guard.sh — PreToolUse hook on Bash. Two things a hook can catch mechanically that a
# rulebook sentence can't enforce on its own:
# (a) a gate (a test run, a typecheck, a build check) is trustworthy only when its EXIT CODE
#     decides what happens next, joined with `&&`. Refused when the gate's output is piped
#     into a reader (tee/tail/head/grep/wc/sed/awk/less/cut, "|" or "|&") — the exit code
#     that reaches the shell is then the READER's, not the gate's — or when `;` (or a bare
#     newline) joins it to a commit, a push, or `echo READY`, which lets a red run continue
#     into either one anyway.
# (b) a loop that polls a log file for a marker (`while`/`until`/`for` … grep|tail … sleep)
#     is refused: waiting on a background job should block on the job itself (`wait`, a
#     job-control/monitor tool, a task-completion notification) and then read the result
#     file it wrote — not guess from a marker that might never appear. A loop whose
#     CONDITION checks a process or a port instead (curl/nc/kill -0/pgrep/lsof) is a
#     "is the server up yet" wait, not a log-marker poll, and is exempt. The loop is read
#     FLATTENED, so writing it across several lines is not a way out.
#
# WHAT IS NOT A GATE RUN, even though the word appears:
#   - a gate word that is some other command's ARGUMENT — `ls node_modules/.bin | grep
#     vitest | head`. The word must stand at command position (the start of a pipeline
#     segment, after optional VAR=value assignments).
#   - a query rather than a run: `npx tsc --version | head -1`, `vitest --help`.
#   - quoted text, -m/--message arguments and heredoc bodies (dropped before matching), so
#     a commit message that merely NAMES a gate cannot trigger a refusal. A `bash -c "…"` /
#     `sh -c "…"` / `zsh -c "…"` / `eval "…"` wrapper is unwrapped first, so the command
#     inside it is matched too, not hidden by the quote-strip.
#
# Which commands count as a "gate": a built-in default (vitest, playwright, tsc, npm test,
# npm run test, npm run typecheck) plus anything listed, one per line, in
# hooks/gate-guard.conf (see hooks/gate-guard.conf.example) — ADDED ON TOP of the built-in
# list, never replacing it, and never turning the built-ins into a blanket refusal (the
# conf-added names join the built-in group; they used to be spliced in as a top-level
# alternative, which made EVERY command holding a gate word a refusal).
# No conf file: the built-in list alone applies.
#
# GATE_OK=1 at the START of the command passes and writes a ledger line via
# override-ledger.sh, naming the rule it bypassed; if that line CANNOT be written (no
# ledger script, unwritable path) the override is REFUSED, not honoured.
#
# WHAT IT DOES WITHOUT ITS TOOLS. jq missing: fails CLOSED (exit 2) on input it cannot
# parse ONLY when the raw text still carries gate-shaped vocabulary (test, typecheck,
# vitest, privacy, READY, commit, push); anything else passes untouched. python3 missing:
# this guard passes everything with a one-line warning on stderr — it is INERT, not
# strict. That is deliberate and it is the one guard where failing OPEN is acceptable:
# it protects no data and can destroy nothing; it only enforces a habit about exit codes.
# Refusing every Bash command on a machine without python3 would cost far more than the
# habit is worth. hooks/guard-lib.sh missing: fails CLOSED — that file is part of this
# hook, not part of the machine, so its absence means a broken install, not a thin one.
# Tests: hooks/test-hooks.sh.
GUARD_LIB="$(dirname "$0")/guard-lib.sh"
if [ ! -r "$GUARD_LIB" ]; then
  echo "gate-guard: REFUSED — hooks/guard-lib.sh is missing next to this hook, so the command cannot be normalised before matching (fail closed, not open). Reinstall the hooks (install.sh copies hooks/*.sh)." >&2
  exit 2
fi
. "$GUARD_LIB"
input="$(< /dev/stdin)"; [ -z "$input" ] && exit 0
if ! printf '%s' "$input" | jq -e . >/dev/null 2>&1; then
  if printf '%s' "$input" | grep -Eq 'test|typecheck|vitest|privacy|READY|commit|push'; then
    echo "gate-guard: REFUSED — unparseable hook input carrying gate vocabulary (fail closed)" >&2; exit 2
  fi
  exit 0
fi
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"; [ "$tool" = "Bash" ] || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"; [ -z "$cmd" ] && exit 0
if ! command -v python3 >/dev/null 2>&1; then
  echo "gate-guard: python3 not found — this guard is INERT for this command (it only checks how gates are joined; it protects no data, so it passes rather than refusing). Install python3 to turn it back on." >&2
  exit 0
fi
GATE_EXTRA=""
CONF="$(dirname "$0")/gate-guard.conf"
if [ -f "$CONF" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"                       # a conf saved with CRLF must still bind
    case "$line" in ''|'#'*) continue ;; esac
    GATE_EXTRA="${GATE_EXTRA}${GATE_EXTRA:+$'\n'}$line"
  done < "$CONF"
fi
verdict="$(printf '%s' "$cmd" | GATE_EXTRA="$GATE_EXTRA" python3 -c "$GUARD_PY_COMMON"'
s = clean(sys.stdin.read())
override = "1" if override_at_start(blank_quoted(s), "GATE_OK") else "0"
s = blank_quoted(s)
gate = r"(?:(?:npx\s+)?(?:vitest|playwright|tsc)\b|npm\s+(?:run\s+)?(?:test(?::[\w-]+)?|typecheck)\b)"
extra = [ln.strip() for ln in os.environ.get("GATE_EXTRA", "").split("\n") if ln.strip()]
if extra:
    alts = [r"(?:npx\s+)?" + r"\s+".join(re.escape(w) for w in tok.split()) + r"\b" for tok in extra]
    gate = "(?:" + gate + "|" + "|".join(alts) + ")"
cmdpos = r"(?:^|[;&|(]|\n)\s*(?:[A-Za-z_][A-Za-z0-9_]*=[^\s]*\s+)*"   # the gate must BE the command
seg = r"(?:[^|;&\n]|\d?>&\d)*"     # the gate arguments: 2>&1 allowed; && ; | end them
query = re.compile(r"--(?:version|help|list)\b")
s_flat = re.sub(r"\n", ";", s)     # a bare newline joins statements exactly like ; for rule (a)
def out(v):
    print(v + "\t" + override); sys.exit()
for m in re.finditer(cmdpos + gate + seg, s_flat):
    if query.search(m.group(0)):
        continue
    rest = s_flat[m.end():]
    if re.match(r"\|&?\s*(?:tee|tail|head|grep|wc|sed|awk|less|cut)\b", rest):
        out("pipe")
    if re.match(r";\s*(?:git\s+(?:commit|push)\b|echo\s+READY\b)", rest):
        out("semicolon")
for m in re.finditer(r"\b(?:while|until|for)\b(.*?)(?:;|\bdo\b)", s_flat):
    cond = m.group(1)
    if re.search(r"\b(?:curl|nc|kill\s+-0|pgrep|lsof)\b", cond):
        continue
    body = s_flat[m.end():]
    k = body.find("done")
    if k >= 0:
        body = body[:k]
    both = cond + " " + body
    if re.search(r"\bsleep\b", both) and re.search(r"\b(?:grep|tail)\b", both):
        out("waiter")
out("ok")
' 2>/dev/null)" || verdict="parse-error"
rule="${verdict%%$'\t'*}"; over="${verdict##*$'\t'}"
if [ "$over" = 1 ]; then
  guard_log_override GATE_OK "$cmd" "$rule" || { guard_refuse_unrecorded "gate-guard" "GATE_OK=1"; exit 2; }
  exit 0
fi
case "$rule" in
  ok) exit 0;;
  pipe) echo "gate-guard: REFUSED — a gate piped into a reader hides its exit code (gate on the EXIT CODE, joined with &&; write the output to a log file and read that afterwards). Deliberate override: GATE_OK=1 <command>." >&2; exit 2;;
  semicolon) echo "gate-guard: REFUSED — ';' (or a bare newline) after a gate lets a red run continue into the commit or push; join with &&. Deliberate override: GATE_OK=1 <command>." >&2; exit 2;;
  waiter) echo "gate-guard: REFUSED — a loop polling a log waits on a marker: wait on the process, a job-control/monitor tool, or a task-completion notification, and read the result file it writes. Deliberate override: GATE_OK=1 <command>." >&2; exit 2;;
  *) echo "gate-guard: REFUSED — could not parse the command (fail closed)." >&2; exit 2;;
esac
