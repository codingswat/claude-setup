#!/bin/bash
# Two-sided tests for every hook in hooks/ and git-hooks/: a check that can never fail is
# not a check. Every case here is either a MUST-REFUSE case (the hook must block/refuse —
# exit 2 for a PreToolUse hook, exit 1 for a git hook) or a MUST-PASS case (the hook must
# let the action through — exit 0). clock-in-context.sh never blocks anything, so its
# two-sided proof is instead "the away notice MUST fire" / "MUST stay silent".
# Run: bash hooks/test-hooks.sh
# Everything runs in a throwaway temp folder with HOME overridden where relevant; the real
# ~/.claude is never touched. Test seam: HOOKS_DIR / GIT_HOOKS_DIR point the tests at a
# different copy (useful for proving a test goes red against a broken hook).
HOOKS_DIR="${HOOKS_DIR:-$(cd "$(dirname "$0")" && pwd -P)}"
GIT_HOOKS_DIR="${GIT_HOOKS_DIR:-$(cd "$(dirname "$0")/../git-hooks" && pwd -P)}"

pass=0; fail=0; refuse_n=0; pass_n=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "  FAIL: $1"; }
# expect <refuse|pass> <want-exit-code> <label> <command...>  (stdin comes from $INPUT)
expect() {
  local kind="$1" want="$2" label="$3"; shift 3
  printf '%s' "$INPUT" | "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then ok; else bad "$label (wanted exit $want, got $got)"; fi
  if [ "$kind" = refuse ]; then refuse_n=$((refuse_n+1)); else pass_n=$((pass_n+1)); fi
}
jstr() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }
json_bash() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(jstr "$1")"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# git-hooks/pre-commit's privacy check now fails CLOSED with no $HOME/.claude/.redaction-names.local
# at all (see git-hooks/pre-commit); every commit below that does NOT explicitly override HOME
# (mkrepo's seed commits, the block-dangerous-git/commit-pathspec-guard fixtures) would otherwise
# be judged against the machine actually running this suite. A suite-wide scratch HOME with its
# own placeholder list keeps every such commit hermetic; tests that exercise the privacy check
# itself override HOME per call to reach the missing-list / found-list paths deliberately.
export HOME="$T/suite-home"
mkdir -p "$HOME/.claude"
printf '# suite-wide placeholder, never matches real content\nZzqSuiteWideMarkerNeverInRealContent\n' > "$HOME/.claude/.redaction-names.local"
# heavy-suite-guard reads free memory from the real machine unless told otherwise; every case
# below that is not about memory runs with plenty free, so the suite does not depend on how busy
# the machine running it is. The memory cases (guard port 2026-10-10 (A)) set their own figure.
export HEAVY_SUITE_MEM_OVERRIDE=100
ID=(env GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.com GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.com)

echo "1 clock-in-context.sh"
mkjson() {   # hook_event_name [transcript_path]
  local ev="$1" tp="${2:-}"
  if [ -n "$tp" ]; then python3 -c 'import json,sys;print(json.dumps({"hook_event_name":sys.argv[1],"transcript_path":sys.argv[2]}))' "$ev" "$tp"
  else python3 -c 'import json,sys;print(json.dumps({"hook_event_name":sys.argv[1]}))' "$ev"; fi
}
run_hook() { local json="$1"; shift; printf '%s' "$json" | env "$@" bash "$HOOKS_DIR/clock-in-context.sh" 2>/dev/null; }

out="$(run_hook "$(mkjson SessionStart)")"
if printf '%s' "$out" | grep -qE '^Clock \(this machine\): [0-9]{4}-[0-9]{2}-[0-9]{2} +[0-9]{1,2}:[0-9]{2} (AM|PM) \([0-9]{2}:[0-9]{2} for file entries\)$'; then ok; else bad "clock line format (12h + 24h): '$out'"; fi
pass_n=$((pass_n+1))
if printf '%s' "$out" | grep -q '^HOW TO TALK TO ME (enforced)'; then ok; else bad "SessionStart must inject the FULL card"; fi
refuse_n=$((refuse_n+1))
for sec in 'Problem' 'Story' 'Result' 'Needs my input'; do
  if printf '%s' "$out" | grep -q "\*\*$sec\*\*"; then ok; else bad "card section missing on SessionStart: $sec"; fi
  pass_n=$((pass_n+1))
done

out2="$(run_hook "$(mkjson UserPromptSubmit)")"
if printf '%s' "$out2" | grep -q '^Card: a quick reply'; then ok; else bad "an ordinary prompt must get the one-line reminder"; fi
pass_n=$((pass_n+1))
if printf '%s' "$out2" | grep -q '^HOW TO TALK TO ME'; then bad "an ordinary prompt must NOT get the full card"; else ok; fi
pass_n=$((pass_n+1))
if printf '%s' "$out2" | grep -q 'YOU ARE RETURNING'; then bad "no transcript: away notice must NOT fire"; else ok; fi
pass_n=$((pass_n+1))

out3="$(CARD_FILE="$T/no-card.md" run_hook "$(mkjson SessionStart)")"
if printf '%s' "$out3" | grep -q '^WARNING: .*could not be injected' && printf '%s' "$out3" | grep -q '^Clock (this machine): '; then ok; else bad "missing card file on SessionStart: loud WARNING and the clock kept"; fi
refuse_n=$((refuse_n+1))

CTXTR="$T/ctx-transcript.jsonl"
printf '{"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","message":{"id":"m1","model":"x","usage":{"input_tokens":1000,"cache_creation_input_tokens":2000,"cache_read_input_tokens":3000,"output_tokens":10}}}\n' > "$CTXTR"
out_ctx="$(run_hook "$(mkjson UserPromptSubmit "$CTXTR")")"
if printf '%s' "$out_ctx" | grep -qE '^Context used: [0-9]+k tokens'; then ok; else bad "context line must appear with a usage-bearing transcript: '$out_ctx'"; fi
pass_n=$((pass_n+1))
if printf '%s' "$out2" | grep -q '^Context used:'; then bad "context line must be silent with no transcript"; else ok; fi
pass_n=$((pass_n+1))
NOUSAGE_TR="$T/nousage-transcript.jsonl"
printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"x"}]}}\n' > "$NOUSAGE_TR"
out_nou="$(run_hook "$(mkjson UserPromptSubmit "$NOUSAGE_TR")")"
if printf '%s' "$out_nou" | grep -q '^Context used:'; then bad "assistant line with no usage block: Context line must NOT print"; else ok; fi
pass_n=$((pass_n+1))
out_missing="$(run_hook "$(mkjson UserPromptSubmit "$T/no-such-transcript.jsonl")")"
if printf '%s' "$out_missing" | grep -q '^Context used:'; then bad "unreadable (missing) transcript file: Context line must NOT print"; else ok; fi
pass_n=$((pass_n+1))
printf 'not json at all\n{"type":"user","message":{"content":"x"}}\n' > "$T/garbage-transcript.jsonl"
garbage_err="$(printf '%s' "$(mkjson UserPromptSubmit "$T/garbage-transcript.jsonl")" | bash "$HOOKS_DIR/clock-in-context.sh" 2>&1 1>/dev/null)"
if [ -z "$garbage_err" ]; then ok; else bad "garbage transcript: stderr must stay empty (got: $garbage_err)"; fi
pass_n=$((pass_n+1))

# Away detector: fake transcripts. human:N = your own message N minutes ago, tool:N = a
# tool result (also a "user" line, must not count), assistant:N = a model reply.
mk_tr() { python3 - "$@" <<'PY2'
import sys, datetime, json
path = sys.argv[1]; lines = []
for spec in sys.argv[2:]:
    kind, mins = spec.split(':')
    ts = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=int(mins))).strftime('%Y-%m-%dT%H:%M:%S.000Z')
    if kind == 'human':   d = {"type": "user", "timestamp": ts, "promptId": "p1", "userType": "external", "message": {"role": "user", "content": "status?"}}
    elif kind == 'tool':  d = {"type": "user", "timestamp": ts, "promptId": "p1", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]}}
    else:                 d = {"type": "assistant", "timestamp": ts, "message": {"role": "assistant", "type": "message", "content": [{"type": "text", "text": "x"}]}}
    lines.append(json.dumps(d, separators=(',', ':')))
open(path, 'w').write('\n'.join(lines) + '\n')
PY2
}
away_out() { printf '{"session_id":"t","hook_event_name":"UserPromptSubmit","transcript_path":%s,"cwd":"/tmp"}' "$(jstr "$1")" | env "${@:2}" bash "$HOOKS_DIR/clock-in-context.sh" 2>/dev/null; }
fires() { printf '%s' "$1" | grep -qE "^YOU ARE RETURNING after ($2) minutes"; }
quiet() { ! printf '%s' "$1" | grep -q 'YOU ARE RETURNING'; }
TR="$T/transcript.jsonl"
mk_tr "$TR" human:30 assistant:29 tool:29 assistant:28; out="$(away_out "$TR")"
if fires "$out" '29|30|31'; then ok; else bad "away 30 min ago, model done 28 min ago: MUST fire: '$out'"; fi
refuse_n=$((refuse_n+1))
if printf '%s' "$out" | grep -q '^HOW TO TALK TO ME (enforced)'; then ok; else bad "a returning turn must inject the FULL card"; fi
refuse_n=$((refuse_n+1))
mk_tr "$TR" human:2 assistant:1; out="$(away_out "$TR")"
if quiet "$out"; then ok; else bad "away 2 min ago: must NOT fire"; fi
pass_n=$((pass_n+1))
mk_tr "$TR" human:30; out="$(away_out "$TR" AWAY_MINUTES=60)"
if quiet "$out"; then ok; else bad "AWAY_MINUTES=60 with a 30 min gap: must NOT fire"; fi
pass_n=$((pass_n+1))
printf 'not json at all\n{"type":"user","message":{"content":"x"}}\n' > "$TR"; out="$(away_out "$TR")"; rc=$?
if [ "$rc" = 0 ] && quiet "$out" && printf '%s' "$out" | grep -q '^Clock (this machine): '; then ok; else bad "garbage transcript: exit 0, silent, clock kept (rc=$rc)"; fi
pass_n=$((pass_n+1))

echo "2 block-dangerous-git.sh"
for c in 'git reset --hard HEAD~1' 'git reset HEAD~1 --hard' 'git reset abc1234 --hard' 'git reset --quiet HEAD~1 --hard' 'git reset origin/main --hard' 'cd /x && git reset HEAD~1 --hard' 'git -c core.pager=cat reset --hard' 'git --no-pager reset --hard' 'git -C /some/path reset --hard' 'git clean -fd' 'git clean -f' 'git branch -D feature' 'git branch -Df feature' 'git branch --delete --force feature' 'git checkout .' 'git checkout -- .' 'git checkout -f main' 'git checkout main .' 'git restore .' 'git restore -s HEAD -- .' 'git restore --staged --worktree .' 'git push --force origin main' 'git push -f origin main' 'git push --force-with-lease' 'git filter-branch --all' 'cd "/x y" && git reset --hard' 'git commit -m "GITGUARD=1 later" && git reset --hard' 'echo GITGUARD=1; git reset --hard'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "must refuse: $c" bash "$HOOKS_DIR/block-dangerous-git.sh"; done
for c in 'git push origin main' 'git push -u origin main' 'git push' 'git branch -d feature' 'git branch -a' 'git checkout main' 'git checkout -b feature' 'git restore file.ts' 'git restore --staged file.ts' 'git reset --soft HEAD~1' 'git reset file.ts' 'git reset' 'git reset --soft HEAD~1 && git status' 'git reset HEAD -- file.ts' 'GITGUARD=1 git reset HEAD~1 --hard' 'git commit -m "never run git reset --hard here"' 'git commit NOTES.md -m "never run git reset HEAD~1 --hard here"' 'git reset --soft HEAD~1; git push --hard-nothing' 'git clean -n' 'git push origin HEAD:main' 'git commit -m "note GITGUARD=1 for later"' 'cd /x && GITGUARD=1 git clean -fd' 'ls -la' 'echo "git reset --hardly"' 'digit reset --hard' 'git checkout main && cd .' 'git branch -a && ls -D' $'python3 - <<\'PY\'\nprint("git reset --hard")\nPY\ngit status'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "must allow: $c" bash "$HOOKS_DIR/block-dangerous-git.sh"; done

echo "2b block-dangerous-git.sh: git stash guard, opt-in via hooks/block-dangerous-git.conf"
SA="$T/stash-shared"; SB="$T/stash-other"; mkdir -p "$SA" "$SB"
git -C "$SA" init -q -b main; git -C "$SA" remote add origin https://github.com/testowner/shared-repo.git
git -C "$SB" init -q -b main; git -C "$SB" remote add origin https://github.com/testowner/other-repo.git
jbs() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$2"; }
expect_s() { local kind="$1" want="$2" label="$3" c="$4" cwd="$5" bin="${6:-$HOOKS_DIR/block-dangerous-git.sh}"; jbs "$c" "$cwd" | bash "$bin" >/dev/null 2>&1; local got=$?; if [ "$got" = "$want" ]; then ok; else bad "$label (wanted $want, got $got)"; fi; if [ "$kind" = refuse ]; then refuse_n=$((refuse_n+1)); else pass_n=$((pass_n+1)); fi; }
expect_s pass 0 "no block-dangerous-git.conf at all: bare stash passes (safe default)" 'git stash' "$SA"
CONFDIR="$T/confdir-bdg"; mkdir -p "$CONFDIR"; cp "$HOOKS_DIR/block-dangerous-git.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/override-ledger.sh" "$CONFDIR/"
printf 'testowner/shared-repo\n' > "$CONFDIR/block-dangerous-git.conf"
expect_s refuse 2 "listed repo cwd: bare stash refused"            'git stash' "$SA" "$CONFDIR/block-dangerous-git.sh"
expect_s refuse 2 "listed repo cwd: stash push -m refused"         'git stash push -m "wip"' "$SA" "$CONFDIR/block-dangerous-git.sh"
expect_s refuse 2 "listed repo cwd: stash pop refused"              'git stash pop' "$SA" "$CONFDIR/block-dangerous-git.sh"
expect_s refuse 2 "listed repo cwd: chained stash refused"          'git pull && git stash && git checkout main' "$SA" "$CONFDIR/block-dangerous-git.sh"
expect_s pass 0 "listed repo cwd: stash list passes"              'git stash list' "$SA" "$CONFDIR/block-dangerous-git.sh"
expect_s pass 0 "listed repo cwd: stash show -p | head passes"    'git stash show -p stash@{0} | head' "$SA" "$CONFDIR/block-dangerous-git.sh"
expect_s pass 0 "listed repo cwd: GITGUARD=1 stash passes"        'GITGUARD=1 git stash' "$SA" "$CONFDIR/block-dangerous-git.sh"
expect_s pass 0 "listed repo cwd: the word stash in a message passes" 'git commit NOTES.md -m "no git stash here"' "$SA" "$CONFDIR/block-dangerous-git.sh"
expect_s pass 0 "unlisted repo cwd: stash passes"                 'git stash' "$SB" "$CONFDIR/block-dangerous-git.sh"
expect_s refuse 2 "unlisted cwd, git -C the listed repo: refused"   "git -C $SA stash" "$SB" "$CONFDIR/block-dangerous-git.sh"
expect_s pass 0 "listed cwd, git -C the unlisted repo: passes"    "git -C $SB stash" "$SA" "$CONFDIR/block-dangerous-git.sh"
expect_s refuse 2 "unlisted cwd, cd into the listed repo: refused"  "cd $SA && git stash" "$SB" "$CONFDIR/block-dangerous-git.sh"
git -C "$SA" config core.hooksPath /dev/null; echo a > "$SA/a.txt"; git -C "$SA" add a.txt; "${ID[@]}" git -C "$SA" commit -q -m init
SAW="$T/stash-shared-wt"; git -C "$SA" worktree add -q "$SAW" -b seat/test
expect_s pass 0 "own linked worktree of the listed repo: stash passes"       'git stash' "$SAW" "$CONFDIR/block-dangerous-git.sh"
expect_s refuse 2 "listed repo ROOT cwd: stash still refused"                  'git stash' "$SA" "$CONFDIR/block-dangerous-git.sh"

echo "3 commit-pathspec-guard.sh"
r="$T/shared"; mkdir -p "$r"; git -C "$r" init -q -b main; git -C "$r" config core.hooksPath /dev/null; echo a > "$r/a.txt"; git -C "$r" add -A; "${ID[@]}" git -C "$r" commit -q -m init
jbc() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$2"; }
expect_c() { local kind="$1" want="$2" label="$3" c="$4"; jbc "$c" "$r" | bash "$HOOKS_DIR/commit-pathspec-guard.sh" >/dev/null 2>&1; local got=$?; if [ "$got" = "$want" ]; then ok; else bad "$label (wanted $want, got $got)"; fi; if [ "$kind" = refuse ]; then refuse_n=$((refuse_n+1)); else pass_n=$((pass_n+1)); fi; }
expect_c pass 0 "empty index: bare commit passes" 'git commit -m "x"'
echo b > "$r/b.txt"; git -C "$r" add b.txt
expect_c refuse 2 "staged file: bare commit must be refused" 'git commit -m "x"'
expect_c refuse 2 "git commit -a is always refused" 'git commit -a -m "x"'
expect_c refuse 2 "git commit . is refused like -a" 'git commit . -m "x"'
expect_c pass 0 "staged file: pathspec commit passes" 'git commit b.txt -m "x"'
expect_c pass 0 "staged file: pathspec after -- passes" 'git commit -m "x" -- b.txt'
expect_c pass 0 "staged file: -F with pathspec passes" 'git commit -F msg.txt b.txt'
expect_c refuse 2 "staged file: -F without pathspec refused" 'git commit -q -F msg.txt'
expect_c pass 0 "staged file: SWEEP=1 override passes" 'SWEEP=1 git commit -m "deliberate sweep"'
expect_c refuse 2 "staged file: SWEEP=1 inside the message does not disarm" 'git commit -m "SWEEP=1 later"'
expect_c refuse 2 "git commit -am is always refused" 'git commit -am "x"'
expect_c pass 0 "chained pathspec commit + push passes" 'git commit b.txt -m "x" && git push -q origin main'
expect_c refuse 2 "chained bare commit + push refused" 'git add x && git commit -m "x" && git push'
expect_c pass 0 "non-commit git commands pass" 'git status && git diff --cached --stat'
expect_c pass 0 "a commit inside a heredoc body is not a commit" $'python3 - <<\'PY\'\nprint("git commit -m x")\nPY'
git -C "$r" reset -q
expect_c pass 0 "index emptied: bare commit passes again" 'git commit -m "x"'

echo "3b commit-pathspec-guard.sh: exempt in a linked git worktree of the same repo"
RW="$T/shared-wt"; git -C "$r" worktree add -q "$RW" -b seat/test
echo c > "$RW/c.txt"; git -C "$RW" add c.txt
expect_w() { local kind="$1" want="$2" label="$3" c="$4" cwd="$5"; jbc "$c" "$cwd" | bash "$HOOKS_DIR/commit-pathspec-guard.sh" >/dev/null 2>&1; local got=$?; if [ "$got" = "$want" ]; then ok; else bad "$label (wanted $want, got $got)"; fi; if [ "$kind" = refuse ]; then refuse_n=$((refuse_n+1)); else pass_n=$((pass_n+1)); fi; }
expect_w pass 0 "worktree, staged file: bare commit passes" 'git commit -m "x"' "$RW"
expect_w pass 0 "worktree: git commit -a passes" 'git commit -a -m "x"' "$RW"
expect_w pass 0 "worktree: git commit . passes" 'git commit . -m "x"' "$RW"
expect_w pass 0 "root cwd, git -C the worktree: bare commit passes" "git -C $RW commit -m \"x\"" "$r"
echo b > "$r/b.txt"; git -C "$r" add b.txt
expect_w refuse 2 "ROOT, staged file: bare commit still refused" 'git commit -m "x"' "$r"
expect_w refuse 2 "ROOT: git commit -a still refused" 'git commit -a -m "x"' "$r"
expect_w refuse 2 "worktree cwd, git -C the ROOT: bare commit still refused" "git -C $r commit -m \"x\"" "$RW"
git -C "$r" reset -q

echo "4 heavy-suite-guard.sh"
for c in 'npm test' 'npm run test' 'npm run e2e' 'npx vitest run' 'npx playwright test -c apps/web/playwright.config.ts' 'npx vitest' 'vitest run' 'playwright test'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "load 12 must refuse: $c" env HEAVY_SUITE_LOAD_OVERRIDE=12 bash "$HOOKS_DIR/heavy-suite-guard.sh"; done
# NOTE: a command that names a *.test.* / *.spec.* file, carries -t/--testNamePattern, or
# asks --version/--list/--help is a TARGETED run and is exempt in that segment, whether or
# not PATTERN matches it (section 28 covers the pairs).
for c in 'npm run typecheck' 'ls' 'SUITE_OK=1 npm test' 'git commit -m "ran npm test and it passed"' 'npx vitest src/foo.test.ts'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "load 12 must allow: $c" env HEAVY_SUITE_LOAD_OVERRIDE=12 bash "$HOOKS_DIR/heavy-suite-guard.sh"; done
INPUT="$(json_bash 'npm test')"; expect pass 0 "load 2 must allow: npm test" env HEAVY_SUITE_LOAD_OVERRIDE=2 bash "$HOOKS_DIR/heavy-suite-guard.sh"
# custom conf: a command outside the default pattern, and a lower MAX_LOAD
CDIR="$T/confhook"; mkdir -p "$CDIR"; cp "$HOOKS_DIR/heavy-suite-guard.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/override-ledger.sh" "$CDIR/"
printf "PATTERN='(^|[;&| ])make +heavytest([ ;&|]|\$)'\nMAX_LOAD=3\n" > "$CDIR/heavy-suite.conf"
INPUT="$(json_bash 'make heavytest')"; expect refuse 2 "custom conf, load 5 (>=3): must refuse make heavytest" env HEAVY_SUITE_LOAD_OVERRIDE=5 bash "$CDIR/heavy-suite-guard.sh"
INPUT="$(json_bash 'make heavytest')"; expect pass 0 "custom conf, load 2 (<3): must allow make heavytest" env HEAVY_SUITE_LOAD_OVERRIDE=2 bash "$CDIR/heavy-suite-guard.sh"
INPUT="$(json_bash 'npm test')"; expect pass 0 "custom conf: npm test is no longer matched, must allow" env HEAVY_SUITE_LOAD_OVERRIDE=12 bash "$CDIR/heavy-suite-guard.sh"

echo "5 git-hooks/commit-msg"
INPUT=""
printf 'notes: a clean message\n' > "$T/m1"; expect pass 0 "clean message must pass" bash "$GIT_HOOKS_DIR/commit-msg" "$T/m1"
printf 'feat: x\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n' > "$T/m2"; expect refuse 1 "AI co-author trailer must be refused" bash "$GIT_HOOKS_DIR/commit-msg" "$T/m2"
printf 'feat: x\n\nGenerated with Claude Code\n' > "$T/m3"; expect refuse 1 "'Generated with' attribution must be refused" bash "$GIT_HOOKS_DIR/commit-msg" "$T/m3"

echo "6 git-hooks/pre-commit"
FAKE_HOME="$T/fakehome-pc"; mkdir -p "$FAKE_HOME/.claude/hooks"
cp "$HOOKS_DIR/override-ledger.sh" "$FAKE_HOME/.claude/hooks/"   # PRIVACY_OK=1 now logs (attack fix F10): the seed commits below need the ledger script
cat > "$FAKE_HOME/.claude/hooks/backup.conf" <<'EOF'
AUTHOR=Tester <tester@example.com>
MIRROR_DIR=
EOF
# the privacy check's names list, created NOW (not only later, where it used to sit) so the
# identity-only commits below are never incidentally refused by the (unrelated) fail-closed
# default — every commit against $FAKE_HOME from here on has a valid, reachable list.
printf '# list\nZebulonQuixote\n' > "$FAKE_HOME/.claude/.redaction-names.local"
repo="$T/repo"; mkdir -p "$repo"; git -C "$repo" init -q -b main; git -C "$repo" config core.hooksPath "$GIT_HOOKS_DIR"
commit_try() { git -C "$repo" add -A; env HOME="$FAKE_HOME" "$@" git -C "$repo" commit -q -m "test" >/dev/null 2>&1; }
ID_OTHER=(env GIT_AUTHOR_NAME="Someone Else" GIT_AUTHOR_EMAIL=someone@example.com GIT_COMMITTER_NAME="Someone Else" GIT_COMMITTER_EMAIL=someone@example.com)
echo "a" > "$repo/a.txt"; if commit_try "${ID[@]}"; then ok; else bad "matching identity (backup.conf set) must commit"; fi
pass_n=$((pass_n+1))
echo "b" > "$repo/b.txt"; if commit_try "${ID_OTHER[@]}"; then bad "a non-matching identity (backup.conf set) must be refused"; else ok; git -C "$repo" reset -q; rm -f "$repo/b.txt"; fi
refuse_n=$((refuse_n+1))
# no backup.conf at all: any identity passes (skip silently)
NOAUTH_HOME="$T/fakehome-noauth"; mkdir -p "$NOAUTH_HOME/.claude/hooks"
: > "$NOAUTH_HOME/.claude/.redaction-names.local"
commit_try_noauth() { git -C "$repo" add -A; env HOME="$NOAUTH_HOME" "$@" git -C "$repo" commit -q -m "test" >/dev/null 2>&1; }
echo "c" > "$repo/c.txt"; if commit_try_noauth "${ID_OTHER[@]}"; then ok; else bad "no backup.conf: any identity must pass (skip silently)"; fi
pass_n=$((pass_n+1))

# (4) privacy: home path + listed names, ADDED lines only (FAKE_HOME's list was set up above)
pr="$T/privrepo"; mkdir -p "$pr"; git -C "$pr" init -q -b main; git -C "$pr" config core.hooksPath "$GIT_HOOKS_DIR"
ptry() { git -C "$pr" add -A; env HOME="$FAKE_HOME" "${ID[@]}" git -C "$pr" commit -q -m "t" >/dev/null 2>&1; }
echo "clean seed" > "$pr/a.txt"; if ptry; then ok; else bad "privacy: a clean file must commit"; fi
pass_n=$((pass_n+1))
U="/User""s"; echo "see ${U}/alice/x.txt" > "$pr/b.txt"; if ptry; then bad "privacy: an absolute macOS home path must be refused"; else ok; git -C "$pr" reset -q; rm "$pr/b.txt"; fi
refuse_n=$((refuse_n+1))
echo "see /ho""me/bob/project" > "$pr/h.txt"; if ptry; then bad "privacy: an absolute /home/<name>/ path must be refused"; else ok; git -C "$pr" reset -q; rm "$pr/h.txt"; fi
refuse_n=$((refuse_n+1))
echo "met zebulonquixote today" > "$pr/c.txt"; if ptry; then bad "privacy: a listed name (case-insensitive) must be refused"; else ok; git -C "$pr" reset -q; rm "$pr/c.txt"; fi
refuse_n=$((refuse_n+1))
printf 'placeholders: %s... and %s<name>\n' "$U/" "$U/" > "$pr/d.txt"; if ptry; then ok; else bad "privacy: home-path placeholders (no real name after) must pass"; fi
pass_n=$((pass_n+1))
echo "commonword is fine" > "$pr/e.txt"; if ptry; then ok; else bad "privacy: an unlisted word must pass"; fi
pass_n=$((pass_n+1))
# no $HOME/.claude/.redaction-names.local AT ALL: fail closed, the commit is refused outright —
# a fresh install with no names configured must not silently skip the names check.
NOLIST_HOME="$T/fakehome-nolist"; mkdir -p "$NOLIST_HOME/.claude/hooks"
pn="$T/privnone"; mkdir -p "$pn"; git -C "$pn" init -q -b main; git -C "$pn" config core.hooksPath "$GIT_HOOKS_DIR"
echo "nothing sensitive here" > "$pn/a.txt"; git -C "$pn" add -A
pnout="$(env HOME="$NOLIST_HOME" "${ID[@]}" git -C "$pn" commit -q -m t 2>&1 1>/dev/null)"
if git -C "$pn" log -1 >/dev/null 2>&1; then bad "privacy: no .redaction-names.local anywhere must REFUSE (fail closed), even for clean content"; else ok; fi
refuse_n=$((refuse_n+1))
if printf '%s' "$pnout" | grep -q '.redaction-names.local'; then ok; else bad "privacy: the fail-closed refusal must name the missing file (got: $pnout)"; fi
pass_n=$((pass_n+1))
# an EXISTING but EMPTY .redaction-names.local: enough to proceed — only the home-path (and
# email) checks apply, with no names configured yet.
EMPTYLIST_HOME="$T/fakehome-emptylist"; mkdir -p "$EMPTYLIST_HOME/.claude"
: > "$EMPTYLIST_HOME/.claude/.redaction-names.local"
echo "zebulonquixote mentioned here" > "$pn/b.txt"; git -C "$pn" add -A
if env HOME="$EMPTYLIST_HOME" "${ID[@]}" git -C "$pn" commit -q -m t >/dev/null 2>&1; then ok; else bad "privacy: an EXISTING empty .redaction-names.local means no names configured, so unmatched content must pass"; fi
pass_n=$((pass_n+1))

echo "6b pre-commit privacy: an email address outside the allowed domains"
pe="$T/privemail"; mkdir -p "$pe"; git -C "$pe" init -q -b main; git -C "$pe" config core.hooksPath "$GIT_HOOKS_DIR"
petry() { git -C "$pe" add -A; env HOME="$FAKE_HOME" "${ID[@]}" git -C "$pe" commit -q -m "t" 2>"$T/pe-err.txt" >/dev/null; }
echo "clean seed" > "$pe/seed.txt"; if petry; then ok; else bad "email gate: a clean seed must commit"; fi
pass_n=$((pass_n+1))
PE_DOM="$(printf '%s%s' personal mail).com"   # built at runtime so no literal address sits in this file (the live pre-commit's email gate would refuse the suite itself)
printf 'contact someone@%s for details\n' "$PE_DOM" > "$pe/foreign.txt"
if petry; then bad "email gate: an unlisted domain must be refused"; else ok; git -C "$pe" reset -q; rm "$pe/foreign.txt"; fi
refuse_n=$((refuse_n+1))
if grep -qF "s***@$PE_DOM" "$T/pe-err.txt"; then ok; else bad "email gate: refusal message must show the masked form (got: $(cat "$T/pe-err.txt"))"; fi
pass_n=$((pass_n+1))
printf 'contact hello@example.com for details\n' > "$pe/allowed.txt"
if petry; then ok; else bad "email gate: a built-in allowed domain (example.com) must pass (got: $(cat "$T/pe-err.txt"))"; fi
pass_n=$((pass_n+1))
DOMCONF_HOME="$T/fakehome-domconf"; mkdir -p "$DOMCONF_HOME/.claude/hooks"
cp "$FAKE_HOME/.claude/.redaction-names.local" "$DOMCONF_HOME/.claude/.redaction-names.local"
printf 'ourcompany.test\n' > "$DOMCONF_HOME/.claude/hooks/allowed-email-domains.conf"
printf 'contact hello@%s for details\n' "$(printf '%s%s' ourcompany .test)" > "$pe/conf-allowed.txt"   # address built at runtime, never a literal in this file
petry_conf() { git -C "$pe" add -A; env HOME="$DOMCONF_HOME" "${ID[@]}" git -C "$pe" commit -q -m "t" >/dev/null 2>&1; }
if petry_conf; then ok; else bad "email gate: a domain added via hooks/allowed-email-domains.conf must pass"; fi
pass_n=$((pass_n+1))

echo "7 git-hooks/pre-push (typecheck of the pushed COMMIT, never the folder; opt-in gated)"
export HOOKS_DIR
mkrepo() { # $1 name, $2 typecheck script or "" for none, $3 opt-in value ("true" default, or "none" to leave hooks.typecheck unset)
  local r="$T/$1"; mkdir -p "$r"; git init -q --bare "$T/$1.git"; git -C "$r" init -q -b main
  git -C "$r" config core.hooksPath "$GIT_HOOKS_DIR"; git -C "$r" remote add origin "$T/$1.git"
  case "${3:-true}" in none) ;; *) git -C "$r" config hooks.typecheck "${3:-true}" ;; esac
  if [ -n "$2" ]; then python3 -c 'import json,sys;print(json.dumps({"name":"x","scripts":{"typecheck":sys.argv[1]}}))' "$2" > "$r/package.json"; else printf '{"name":"x"}\n' > "$r/package.json"; fi
  echo a > "$r/a.txt"; git -C "$r" add -A; "${ID[@]}" git -C "$r" commit -q -m init
}
mkrepo tcgood "exit 0"; if git -C "$T/tcgood" push -q origin main 2>/dev/null; then ok; else bad "typecheck passing: push must succeed"; fi
pass_n=$((pass_n+1))
mkrepo tcbad "exit 1"; if git -C "$T/tcbad" push -q origin main 2>/dev/null; then bad "typecheck failing: push must be refused"; else ok; fi
refuse_n=$((refuse_n+1))
mkrepo tcnone ""; if git -C "$T/tcnone" push -q origin main 2>/dev/null; then ok; else bad "no typecheck script at all: push must succeed"; fi
pass_n=$((pass_n+1))
mkrepo tcnoopt "exit 1" none; if git -C "$T/tcnoopt" push -q origin main 2>/dev/null; then ok; else bad "not opted in (no hooks.typecheck config): push must succeed — the repo's own script must be skipped, never run"; fi
pass_n=$((pass_n+1))
mkrepo tcoptin "exit 1" true; if git -C "$T/tcoptin" push -q origin main 2>/dev/null; then bad "opted in (hooks.typecheck=true): a failing typecheck must still be refused"; else ok; fi
refuse_n=$((refuse_n+1))

echo "7b git-hooks/pre-push: the COMMIT is checked, never the working folder; the pushed REF, not HEAD; a worktree pushes its own tip"
mkrepo tcdirty "sh -c '! grep -q BROKEN a.txt'"
echo BROKEN >> "$T/tcdirty/a.txt"   # uncommitted; the commit itself is clean
if git -C "$T/tcdirty" push -q origin main 2>/dev/null; then ok; else bad "folder broken, commit clean: push must succeed"; fi
pass_n=$((pass_n+1))
mkrepo tcfixed "sh -c '! grep -q BROKEN a.txt'"
echo BROKEN >> "$T/tcfixed/a.txt"; git -C "$T/tcfixed" add a.txt; "${ID[@]}" git -C "$T/tcfixed" commit -q -m broken
echo a > "$T/tcfixed/a.txt"   # fixed, uncommitted; the commit itself is broken
if git -C "$T/tcfixed" push -q origin main 2>/dev/null; then bad "commit broken, folder fixed: push must be refused"; else ok; fi
refuse_n=$((refuse_n+1))
mkrepo tcref "sh -c '! grep -q BROKEN a.txt'"
git -C "$T/tcref" checkout -q -b wip; echo BROKEN >> "$T/tcref/a.txt"; git -C "$T/tcref" add a.txt; "${ID[@]}" git -C "$T/tcref" commit -q -m broken
if git -C "$T/tcref" push -q origin main 2>/dev/null; then ok; else bad "HEAD is a broken wip branch, pushing the clean main: must succeed"; fi
pass_n=$((pass_n+1))
if git -C "$T/tcref" push -q origin wip 2>/dev/null; then bad "pushing the broken wip branch: must be refused"; else ok; fi
refuse_n=$((refuse_n+1))
mkrepo tcwt "sh -c '! grep -q BROKEN a.txt'"
WTW="$T/tcwt-wt"; git -C "$T/tcwt" worktree add -q "$WTW" -b seat/x
echo BROKEN >> "$T/tcwt/a.txt"   # the ROOT folder is dirty and broken
echo ok > "$WTW/b.txt"; git -C "$WTW" add b.txt; "${ID[@]}" git -C "$WTW" commit -q -m clean
if git -C "$WTW" push -q origin HEAD:main 2>/dev/null; then ok; else bad "worktree pushes a clean commit while the root folder is broken: must succeed"; fi
pass_n=$((pass_n+1))

echo "8 hooks/auto-backup.sh secret scan"
FH="$T/fakehome-ab"; mkdir -p "$FH/.claude/hooks"
git -C "$FH/.claude" init -q -b main
git -C "$FH/.claude" config user.name Tester; git -C "$FH/.claude" config user.email tester@example.com
cat > "$FH/.claude/hooks/backup.conf" <<'EOF'
AUTHOR=Tester <tester@example.com>
MIRROR_DIR=
EOF
echo "hello" > "$FH/.claude/CLAUDE.md"
before="$(git -C "$FH/.claude" log --oneline 2>/dev/null | wc -l | tr -d ' ')"
echo "sk-ant-""abcdefghij1234567890" >> "$FH/.claude/CLAUDE.md"   # split so no token-shaped literal sits in this file
env HOME="$FH" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
after="$(git -C "$FH/.claude" log --oneline 2>/dev/null | wc -l | tr -d ' ')"
if [ "$after" = "$before" ]; then ok; else bad "a changed file holding a secret-looking string must NOT be committed"; fi
refuse_n=$((refuse_n+1))
sed -i.bak '/sk-ant/d' "$FH/.claude/CLAUDE.md"; rm -f "$FH/.claude/CLAUDE.md.bak"
env HOME="$FH" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
after2="$(git -C "$FH/.claude" log --oneline 2>/dev/null | wc -l | tr -d ' ')"
if [ "$after2" -gt "$before" ]; then ok; else bad "a clean change (secret removed) must be committed"; fi
pass_n=$((pass_n+1))
# a new, wholly untracked DIRECTORY: `git status --porcelain` (no -z/--untracked-files=all)
# collapses this to one `?? newdir/` entry, so a secret inside it was never scanned even
# though `git add -A` still staged the file underneath.
mkdir -p "$FH/.claude/newdir"
echo "sk-ant-""zzzzzzzzzz1234567890" > "$FH/.claude/newdir/note.md"
env HOME="$FH" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
afterDir="$(git -C "$FH/.claude" log --oneline 2>/dev/null | wc -l | tr -d ' ')"
if [ "$afterDir" = "$after2" ]; then ok; else bad "a secret inside a brand-new untracked directory must NOT be committed"; fi
refuse_n=$((refuse_n+1))
rm -f "$FH/.claude/newdir/note.md"
# a clean file whose path contains a SPACE: plain `git status --porcelain` prints it quoted,
# so the old `awk '{print $NF}'` scan turned it into a non-existent filename and skipped it.
echo "clean note" > "$FH/.claude/hooks/my notes.md"
env HOME="$FH" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
afterSpace="$(git -C "$FH/.claude" log --oneline 2>/dev/null | wc -l | tr -d ' ')"
if [ "$afterSpace" -gt "$afterDir" ]; then ok; else bad "a clean file whose path contains a space must still be committed"; fi
pass_n=$((pass_n+1))

echo "9 hooks/auto-backup.sh mirror secret scan"
FH2="$T/fakehome-mirror"; mkdir -p "$FH2/.claude/hooks"
git -C "$FH2/.claude" init -q -b main
git -C "$FH2/.claude" config core.hooksPath /dev/null   # isolate from this MACHINE's own real git hooks
git -C "$FH2/.claude" config user.name Tester; git -C "$FH2/.claude" config user.email tester@example.com
MIR="$T/mirror-repo"; mkdir -p "$MIR"; git -C "$MIR" init -q -b main
git -C "$MIR" config core.hooksPath /dev/null            # isolate from this MACHINE's own real git hooks
git -C "$MIR" config user.name Tester; git -C "$MIR" config user.email tester@example.com
cat > "$FH2/.claude/hooks/backup.conf" <<EOF
AUTHOR=Tester <tester@example.com>
MIRROR_DIR=$MIR
EOF
echo "hello" > "$FH2/.claude/CLAUDE.md"
echo "#!/bin/bash" > "$FH2/.claude/hooks/check-claude-md.sh"
echo "#!/bin/bash" > "$FH2/.claude/hooks/auto-backup.sh"
printf '{"env":{"key":"%s"}}' "sk-ant-""zzzzzzzzzz1234567890" > "$FH2/.claude/settings.json"
# committed BY HAND before this turn's hook run: the config repo then reports NO changes, so
# part 1 never calls secret_scan at all — reproducing the real gap where only a mirror-side
# scan (this fix) can still catch the secret in the copy.
git -C "$FH2/.claude" add -A; git -C "$FH2/.claude" commit -q -m seed
beforeMirror="$(git -C "$MIR" log --oneline 2>/dev/null | wc -l | tr -d ' ')"
env HOME="$FH2" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
afterMirror="$(git -C "$MIR" log --oneline 2>/dev/null | wc -l | tr -d ' ')"
if [ "$afterMirror" = "$beforeMirror" ]; then ok; else bad "a secret already committed in settings.json (config repo reports no changes) must NOT reach the mirror copies"; fi
refuse_n=$((refuse_n+1))
printf '{"name":"clean"}' > "$FH2/.claude/settings.json"
git -C "$FH2/.claude" add -A; git -C "$FH2/.claude" commit -q -m clean
env HOME="$FH2" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
afterMirror2="$(git -C "$MIR" log --oneline 2>/dev/null | wc -l | tr -d ' ')"
if [ "$afterMirror2" -gt "$beforeMirror" ]; then ok; else bad "a clean settings.json must be refreshed into the mirror copies"; fi
pass_n=$((pass_n+1))

echo "9b hooks/auto-backup.sh: a commit left over from a failed push is retried on a later turn with no new file edits"
AB2="$T/ab2-claude"; AB2M="$T/ab2-mirror"; mkdir -p "$AB2/.claude/hooks" "$AB2M"
git init -q --bare "$T/ab2-claude.git"
git -C "$AB2/.claude" init -q -b main; git -C "$AB2/.claude" config core.hooksPath /dev/null
git -C "$AB2/.claude" config user.name Tester; git -C "$AB2/.claude" config user.email tester@example.com
git -C "$AB2/.claude" remote add origin "$T/ab2-claude.git"
cat > "$AB2/.claude/hooks/backup.conf" <<'EOF'
AUTHOR=Tester <tester@example.com>
MIRROR_DIR=
EOF
echo seed > "$AB2/.claude/CLAUDE.md"; git -C "$AB2/.claude" add -A; git -C "$AB2/.claude" commit -q -m seed; git -C "$AB2/.claude" push -q -u origin main
# Break the push (a bad remote URL stands in for "the remote is unreachable"), edit, run the
# hook: the commit lands locally but cannot reach the "remote".
git -C "$AB2/.claude" remote set-url origin "$T/ab2-claude-DOES-NOT-EXIST.git"
echo "changed" >> "$AB2/.claude/CLAUDE.md"
env HOME="$AB2" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
bare_before="$(git --git-dir="$T/ab2-claude.git" rev-list --count main 2>/dev/null)"
local_after_break="$(git -C "$AB2/.claude" rev-list --count HEAD)"
if [ "$local_after_break" -gt "$bare_before" ]; then ok; else bad "the commit must land locally even though the push failed"; fi
pass_n=$((pass_n+1))
# Restore the remote and run the hook again with NO file edits: the leftover commit must retry.
git -C "$AB2/.claude" remote set-url origin "$T/ab2-claude.git"
env HOME="$AB2" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
bare_after="$(git --git-dir="$T/ab2-claude.git" rev-list --count main 2>/dev/null)"
local_final="$(git -C "$AB2/.claude" rev-list --count HEAD)"
if [ "$bare_after" -eq "$local_final" ]; then ok; else bad "a clean tree with an unpushed commit must retry the push with no new edits (bare has $bare_after, local has $local_final)"; fi
pass_n=$((pass_n+1))

echo "9c hooks/auto-backup.sh: a RENAMED file carrying a secret in its NEW name is caught (NUL-safe rename handling)"
AB3="$T/ab3-claude"; mkdir -p "$AB3/.claude/hooks"
git -C "$AB3/.claude" init -q -b main; git -C "$AB3/.claude" config core.hooksPath /dev/null
git -C "$AB3/.claude" config user.name Tester; git -C "$AB3/.claude" config user.email tester@example.com
cat > "$AB3/.claude/hooks/backup.conf" <<'EOF'
AUTHOR=Tester <tester@example.com>
MIRROR_DIR=
EOF
# built at runtime (not a static literal) so this file never matches auto-backup.sh's SECRET_RE itself
MARKER="$(printf '%s' 'sk-an' 't-' 'ZZQSUITETESTMARKER1234567890')"
printf 'ordinary content, nothing sensitive here\n' > "$AB3/.claude/orig name.txt"
git -C "$AB3/.claude" add -A; git -C "$AB3/.claude" commit -q -m "add orig"
mv "$AB3/.claude/orig name.txt" "$AB3/.claude/renamed name.txt"
printf 'ordinary content, nothing sensitive here\n%s\n' "$MARKER" > "$AB3/.claude/renamed name.txt"
n_before_rn="$(git -C "$AB3/.claude" rev-list --count HEAD)"
out_rn="$(env HOME="$AB3" bash "$HOOKS_DIR/auto-backup.sh" 2>&1)"
n_after_rn="$(git -C "$AB3/.claude" rev-list --count HEAD)"
if printf '%s' "$out_rn" | grep -q "possible secret in: renamed name.txt" && [ "$n_after_rn" -eq "$n_before_rn" ]; then ok; else bad "a secret in a renamed file's NEW name must refuse the commit (got: $out_rn)"; fi
refuse_n=$((refuse_n+1))
rm -f "$AB3/.claude/renamed name.txt"; printf 'ordinary content, nothing sensitive here\n' > "$AB3/.claude/orig name.txt"
printf 'a genuinely new, clean file\n' > "$AB3/.claude/another.txt"
env HOME="$AB3" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
n_clean_rn="$(git -C "$AB3/.claude" rev-list --count HEAD)"
if [ "$n_clean_rn" -gt "$n_after_rn" ]; then ok; else bad "a clean change after a refused secret must still be backed up normally"; fi
pass_n=$((pass_n+1))

echo "10 hooks/block-dangerous-git.sh and commit-pathspec-guard.sh: fail closed with no jq/python3"
NOPARSE="$T/noparse-bin"; mkdir -p "$NOPARSE"
for b in cat grep bash; do p="$(command -v "$b" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$NOPARSE/$b"; done
# Test seam: a PATH pointing at a directory holding only bash + coreutils (no jq, no
# python3) — the harness's cleanest way to prove the missing-parser path without touching
# the real system's toolchain.
INPUT="$(json_bash 'git status')"
expect refuse 2 "no jq/python3 on PATH: must fail CLOSED even on a benign command" env -i "PATH=$NOPARSE" bash "$HOOKS_DIR/block-dangerous-git.sh"
INPUT="$(json_bash 'GITGUARD=1 git clean -fd')"
expect pass 0 "jq/python3 present: a legitimate override still passes after the anchor fix" bash "$HOOKS_DIR/block-dangerous-git.sh"

echo "11 git-hooks/pre-push: the pushed repo's OWN node_modules is linked into the export"
mkrepo tclinked "mytool"
mkdir -p "$T/tclinked/node_modules/.bin"
printf '#!/bin/bash\nexit 0\n' > "$T/tclinked/node_modules/.bin/mytool"; chmod +x "$T/tclinked/node_modules/.bin/mytool"
if git -C "$T/tclinked" push -q origin main 2>/dev/null; then ok; else bad "own node_modules linked, local binary exits 0: push must succeed"; fi
pass_n=$((pass_n+1))
mkrepo tclinkedbad "mytool"
mkdir -p "$T/tclinkedbad/node_modules/.bin"
printf '#!/bin/bash\nexit 1\n' > "$T/tclinkedbad/node_modules/.bin/mytool"; chmod +x "$T/tclinkedbad/node_modules/.bin/mytool"
if git -C "$T/tclinkedbad" push -q origin main 2>/dev/null; then bad "own node_modules linked, local binary exits 1: push must be refused"; else ok; fi
refuse_n=$((refuse_n+1))

echo "12 git-hooks/pre-commit privacy: ADDED lines only, with the placeholder allowlist"
pr2="$T/privrepo2"; mkdir -p "$pr2"; git -C "$pr2" init -q -b main; git -C "$pr2" config core.hooksPath "$GIT_HOOKS_DIR"
p2try() { git -C "$pr2" add -A; env HOME="$FAKE_HOME" "${ID[@]}" git -C "$pr2" commit -q -m "t" >/dev/null 2>&1; }
U2="/User""s"
printf 'see %s/alice/x.txt\nfirst line\n' "$U2" > "$pr2/a.txt"
git -C "$pr2" add -A; env HOME="$FAKE_HOME" PRIVACY_OK=1 "${ID[@]}" git -C "$pr2" commit -q -m seed >/dev/null 2>&1
printf 'see %s/alice/x.txt\nfirst line\nsecond line\n' "$U2" > "$pr2/a.txt"
if p2try; then ok; else bad "privacy: an old home-path line already committed must NOT be re-flagged just because the file is touched again"; fi
pass_n=$((pass_n+1))
echo "WORKDIR /ho""me/node/app" > "$pr2/Dockerfile"
if p2try; then ok; else bad "privacy: Dockerfile WORKDIR /home/node/app (a known placeholder name) must pass"; fi
pass_n=$((pass_n+1))
echo "see https://docs.example.com/home/faq" > "$pr2/docs.txt"
if p2try; then ok; else bad "privacy: a docs URL containing /home/faq must pass"; fi
pass_n=$((pass_n+1))

echo "13 git-hooks/pre-commit identity: per-repo opt-out (hooks.identity=false)"
idrepo="$T/idrepo"; mkdir -p "$idrepo"; git -C "$idrepo" init -q -b main; git -C "$idrepo" config core.hooksPath "$GIT_HOOKS_DIR"
idtry() { git -C "$idrepo" add -A; env HOME="$FAKE_HOME" "${ID_OTHER[@]}" git -C "$idrepo" commit -q -m "t" >/dev/null 2>&1; }
echo "x" > "$idrepo/x.txt"
if idtry; then bad "identity: a non-matching author must still be refused with no opt-out set"; else ok; git -C "$idrepo" reset -q; fi
refuse_n=$((refuse_n+1))
git -C "$idrepo" config --local hooks.identity false
if idtry; then ok; else bad "identity: with hooks.identity=false set, a non-matching author must be let through"; fi
pass_n=$((pass_n+1))

echo "13b git-hooks/pre-commit: optional channel-file insertion ceiling (hooks/channel-ceiling.conf)"
CEIL_HOME="$T/fakehome-ceiling"; mkdir -p "$CEIL_HOME/.claude/hooks"
: > "$CEIL_HOME/.claude/.redaction-names.local"
ceild="$T/ceilrepo"; mkdir -p "$ceild"; git -C "$ceild" init -q -b main; git -C "$ceild" config core.hooksPath "$GIT_HOOKS_DIR"
ceil_try() { git -C "$ceild" add -A >/dev/null 2>&1; CEIL_ERR="$(env HOME="$CEIL_HOME" "$@" "${ID[@]}" git -C "$ceild" commit -q -m test 2>&1 1>/dev/null)"; CEIL_RC=$?; }
echo seed > "$ceild/NOTES.md"; ceil_try   # a NEW file is always exempt regardless of size or conf
python3 -c "print('\n'.join(['line']*50))" >> "$ceild/NOTES.md"
ceil_try
if [ "$CEIL_RC" = 0 ]; then ok; else bad "no channel-ceiling.conf: a MODIFIED NOTES.md +50 lines must pass (check is inert); ERR='$CEIL_ERR'"; fi
pass_n=$((pass_n+1))
printf 'LIMIT=20\nNOTES.md\n' > "$CEIL_HOME/.claude/hooks/channel-ceiling.conf"
python3 -c "print('\n'.join(['line']*21))" >> "$ceild/NOTES.md"
ceil_try
if [ "$CEIL_RC" != 0 ]; then ok; git -C "$ceild" reset -q; else bad "channel-ceiling.conf LIMIT=20: NOTES.md +21 lines must be REFUSED; ERR='$CEIL_ERR'"; fi
refuse_n=$((refuse_n+1))
ceil_try SWEEP=1
if [ "$CEIL_RC" = 0 ]; then ok; else bad "SWEEP=1 must allow NOTES.md +21 over the configured ceiling; ERR='$CEIL_ERR'"; fi
pass_n=$((pass_n+1))
echo seed > "$ceild/README.md"; ceil_try
python3 -c "print('\n'.join(['line']*30))" >> "$ceild/README.md"
ceil_try
if [ "$CEIL_RC" = 0 ]; then ok; else bad "README.md is not in channel-ceiling.conf's list: must pass regardless of size; ERR='$CEIL_ERR'"; fi
pass_n=$((pass_n+1))

echo "14 hooks/check-claude-md.sh: PROCESS RULES heading present vs renamed"
CCM_HOME="$T/fakehome-ccm"; mkdir -p "$CCM_HOME/.claude/hooks"
cat > "$CCM_HOME/.claude/CLAUDE.md" <<'EOF'
# Test rulebook

## PROCESS RULES (enforced)
1. **Rule one** does a thing.
EOF
ccm_out() { printf '{"cwd":"%s"}' "$T" | env HOME="$CCM_HOME" bash "$HOOKS_DIR/check-claude-md.sh" 2>/dev/null; }
out="$(ccm_out)"
if printf '%s' "$out" | grep -qF 'ENFORCED:' && printf '%s' "$out" | grep -qF 'PROCESS RULES (enforced)'; then ok; else bad "heading present: the rules must be injected as ENFORCED"; fi
pass_n=$((pass_n+1))
printf '# Test rulebook\n\n## OLD HEADING\n1. text\n' > "$CCM_HOME/.claude/CLAUDE.md"
out2="$(ccm_out)"
if printf '%s' "$out2" | grep -qF 'WARNING:' && printf '%s' "$out2" | grep -qF 'was not found'; then ok; else bad "heading renamed: must degrade LOUDLY with a WARNING"; fi
refuse_n=$((refuse_n+1))

echo "15 hooks/auto-backup.sh: warn() must be defined before its first possible use"
WH="$T/fakehome-warn"; mkdir -p "$WH/.claude/hooks"
git -C "$WH/.claude" init -q -b main
git -C "$WH/.claude" config user.name Tester; git -C "$WH/.claude" config user.email tester@example.com
printf 'MIRROR_DIR=\n' > "$WH/.claude/hooks/backup.conf"
echo "hello" > "$WH/.claude/CLAUDE.md"
# warn() writes to the hook's combined output (no >&2 redirection in warn itself); capture
# both streams together so a "command not found" (a real shell error, always on stderr)
# and the intended warning text (wherever warn actually sends it) are both visible.
errout="$(env HOME="$WH" bash "$HOOKS_DIR/auto-backup.sh" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && printf '%s' "$errout" | grep -qF 'AUTHOR' && ! printf '%s' "$errout" | grep -q 'command not found'; then ok; else bad "no AUTHOR line: must print the warning and exit 0, not 'warn: command not found' (rc=$rc): $errout"; fi
refuse_n=$((refuse_n+1))
WH2="$T/fakehome-warnok"; mkdir -p "$WH2/.claude/hooks"
git -C "$WH2/.claude" init -q -b main
git -C "$WH2/.claude" config user.name Tester; git -C "$WH2/.claude" config user.email tester@example.com
printf 'AUTHOR=Tester <tester@example.com>\nMIRROR_DIR=\n' > "$WH2/.claude/hooks/backup.conf"
echo "hello" > "$WH2/.claude/CLAUDE.md"
errout2="$(env HOME="$WH2" bash "$HOOKS_DIR/auto-backup.sh" 2>&1)"; rc2=$?
if [ "$rc2" = 0 ] && ! printf '%s' "$errout2" | grep -qF 'AUTHOR'; then ok; else bad "complete conf: must NOT print the missing-AUTHOR warning (rc=$rc2): $errout2"; fi
pass_n=$((pass_n+1))

echo "16 hooks/block-dangerous-git.sh: a leading + on a push refspec means --force"
INPUT="$(json_bash 'git push origin +main')"; expect refuse 2 "must refuse: git push origin +main" bash "$HOOKS_DIR/block-dangerous-git.sh"
INPUT="$(json_bash 'git push origin +HEAD:main')"; expect refuse 2 "must refuse: git push origin +HEAD:main" bash "$HOOKS_DIR/block-dangerous-git.sh"

echo "17 hooks/auto-backup.sh: expanded secret patterns"
SH="$T/fakehome-secrets"; mkdir -p "$SH/.claude/hooks"
git -C "$SH/.claude" init -q -b main
git -C "$SH/.claude" config user.name Tester; git -C "$SH/.claude" config user.email tester@example.com
cat > "$SH/.claude/hooks/backup.conf" <<'EOF'
AUTHOR=Tester <tester@example.com>
MIRROR_DIR=
EOF
echo "hello" > "$SH/.claude/CLAUDE.md"
env HOME="$SH" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
beforeS="$(git -C "$SH/.claude" log --oneline 2>/dev/null | wc -l | tr -d ' ')"
echo "DATABASE_URL=postgres:/""/u:p4""ss@host/db" >> "$SH/.claude/CLAUDE.md"   # built from pieces: this file must pass the kit's own secret scan (B1)
env HOME="$SH" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
afterS="$(git -C "$SH/.claude" log --oneline 2>/dev/null | wc -l | tr -d ' ')"
if [ "$afterS" = "$beforeS" ]; then ok; else bad "a password inside a URL (DATABASE_URL=postgres, user u, password p4ss, host) must NOT be committed"; fi
refuse_n=$((refuse_n+1))
sed -i.bak '/DATABASE_URL/d' "$SH/.claude/CLAUDE.md"; rm -f "$SH/.claude/CLAUDE.md.bak"
echo 'API_KEY=' >> "$SH/.claude/CLAUDE.md"
env HOME="$SH" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
afterS2="$(git -C "$SH/.claude" log --oneline 2>/dev/null | wc -l | tr -d ' ')"
if [ "$afterS2" -gt "$beforeS" ]; then ok; else bad "an empty API_KEY= (nothing after it) must be committed, not refused"; fi
pass_n=$((pass_n+1))

echo "18 hooks/helper-ledger.py: a stable helper transcript yields one costed row, a transcript with no assistant records yields none"
LHOME="$T/fakehome-ledger"; mkdir -p "$LHOME"
LPROJ="$T/ledger-projects"; mkdir -p "$LPROJ/proj1/sess-aaa/subagents"
LEDGER="$LHOME/.claude/ledgers/helpers.tsv"
back5min() { python3 -c "import os,time,sys; t=time.time()-300; os.utime(sys.argv[1], (t,t))" "$1"; }
CASE_OK="$LPROJ/proj1/sess-aaa/subagents/agent-caseok.jsonl"
cat > "$CASE_OK" <<'EOF'
{"type":"assistant","timestamp":"2026-09-01T10:00:00.000Z","message":{"id":"msgA","model":"claude-sonnet-5","usage":{"input_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":10}}}
EOF
back5min "$CASE_OK"
CASE_EMPTY="$LPROJ/proj1/sess-aaa/subagents/agent-caseempty.jsonl"
echo '{"type":"user","message":{"content":"not an assistant record"}}' > "$CASE_EMPTY"
back5min "$CASE_EMPTY"
env HOME="$LHOME" CLAUDE_PROJECTS_DIR="$LPROJ" python3 "$HOOKS_DIR/helper-ledger.py" >/dev/null 2>&1
n_ledger_lines() { tail -n +2 "$LEDGER" 2>/dev/null | grep -c . ; }
lc="$(n_ledger_lines)"
if [ "$lc" = "1" ]; then ok; else bad "a helper with assistant usage must yield exactly one ledger row, got $lc"; fi
pass_n=$((pass_n+1))
grep -q $'\tcaseempty\t' "$LEDGER" 2>/dev/null && bad "a transcript with no assistant records must NOT yield a row" || ok
refuse_n=$((refuse_n+1))
line="$(tail -n +2 "$LEDGER" 2>/dev/null | grep caseok)"
expect_cost="$(printf '%s' "$line" | awk -F'\t' '{print $NF}')"
if [ "$expect_cost" = "0.00" ]; then ok; else bad "cost for a 2-input/10-output sonnet step should round to 0.00, got $expect_cost"; fi
pass_n=$((pass_n+1))

echo "19 git-hooks/pre-commit: root CLAUDE.md word cap"
mkwords() { python3 -c "import sys; print(' '.join(['w']*int(sys.argv[1])))" "$1"; }
capd="$T/caprepo"; mkdir -p "$capd"; git -C "$capd" init -q -b main; git -C "$capd" config core.hooksPath "$GIT_HOOKS_DIR"
# HOME=$FAKE_HOME (section 6's fixture, already carrying a matching AUTHOR and a
# .redaction-names.local) so these commits are judged on the CLAUDE.md word cap alone,
# never incidentally refused by the (unrelated) privacy check's fail-closed default.
cap_try() { git -C "$capd" add -A >/dev/null 2>&1; CAP_ERR="$(env HOME="$FAKE_HOME" "$@" "${ID[@]}" git -C "$capd" commit -q -m test 2>&1 1>/dev/null)"; CAP_RC=$?; git -C "$capd" reset -q >/dev/null 2>&1; }
mkwords 5751 > "$capd/CLAUDE.md"
cap_try
if [ "$CAP_RC" != 0 ] && printf '%s' "$CAP_ERR" | grep -q 'capped at 5750'; then ok; else bad "a 5751-word project CLAUDE.md must be REFUSED; RC=$CAP_RC ERR='$CAP_ERR'"; fi
refuse_n=$((refuse_n+1))
mkwords 5750 > "$capd/CLAUDE.md"
cap_try
if [ "$CAP_RC" = 0 ]; then ok; else bad "a 5750-word project CLAUDE.md must pass; RC=$CAP_RC ERR='$CAP_ERR'"; fi
pass_n=$((pass_n+1))
mkdir -p "$capd/sub"; mkwords 6000 > "$capd/sub/CLAUDE.md"
cap_try
if [ "$CAP_RC" = 0 ]; then ok; else bad "a 6000-word sub/CLAUDE.md must pass (only the repo-root file is capped); RC=$CAP_RC ERR='$CAP_ERR'"; fi
pass_n=$((pass_n+1))
rm -f "$capd/sub/CLAUDE.md"; cap_try
mkwords 5751 > "$capd/CLAUDE.md"
cap_try RULES_CAP_OK=1
if [ "$CAP_RC" = 0 ]; then ok; else bad "RULES_CAP_OK=1 with 5751 words must pass; RC=$CAP_RC ERR='$CAP_ERR'"; fi
pass_n=$((pass_n+1))
mkwords 5750 > "$capd/CLAUDE.md"; cap_try
FAKE_HOME_CAP="$T/fakehome-cap"; mkdir -p "$FAKE_HOME_CAP"; FAKE_HOME_CAP="$(cd "$FAKE_HOME_CAP" && pwd -P)"
capg="$FAKE_HOME_CAP/.claude"; mkdir -p "$capg"; git -C "$capg" init -q -b main; git -C "$capg" config core.hooksPath "$GIT_HOOKS_DIR"
: > "$capg/.redaction-names.local"   # $HOME/.claude/.redaction-names.local, satisfied so the privacy check's fail-closed default doesn't interfere with this word-cap test
cap_try_global() { git -C "$capg" add -A >/dev/null 2>&1; CAP_ERR="$(env HOME="$FAKE_HOME_CAP" "${ID[@]}" git -C "$capg" commit -q -m test 2>&1 1>/dev/null)"; CAP_RC=$?; git -C "$capg" reset -q >/dev/null 2>&1; }
mkwords 4001 > "$capg/CLAUDE.md"
cap_try_global
if [ "$CAP_RC" != 0 ] && printf '%s' "$CAP_ERR" | grep -q 'capped at 4000'; then ok; else bad "a 4001-word global CLAUDE.md (toplevel == \$HOME/.claude) must be REFUSED; RC=$CAP_RC ERR='$CAP_ERR'"; fi
refuse_n=$((refuse_n+1))
mkwords 4000 > "$capg/CLAUDE.md"
cap_try_global
if [ "$CAP_RC" = 0 ]; then ok; else bad "a 4000-word global CLAUDE.md must pass; RC=$CAP_RC ERR='$CAP_ERR'"; fi
pass_n=$((pass_n+1))

echo "20 hooks/override-ledger.sh"
OLL="$T/override-ledger.tsv"
r20="$T/ovl-repo"; mkdir -p "$r20/sub"; git -C "$r20" init -q -b main
rm -f "$OLL"
(cd "$r20/sub" && OVERRIDE_LEDGER="$OLL" bash "$HOOKS_DIR/override-ledger.sh" TESTWORD "some command")
folder20="$(tail -1 "$OLL" 2>/dev/null | cut -f2)"; name20="$(tail -1 "$OLL" 2>/dev/null | cut -f3)"; cmd20="$(tail -1 "$OLL" 2>/dev/null | cut -f5)"
if [ "$folder20" = "ovl-repo" ] && [ "$name20" = "TESTWORD" ] && [ "$cmd20" = "some command" ]; then ok; else bad "inside a repo (even from a subdir): folder must be the git TOPLEVEL basename; got folder='$folder20' name='$name20' cmd='$cmd20'"; fi
refuse_n=$((refuse_n+1))
OUT20="$T/ovl-outside"; mkdir -p "$OUT20"; base20="$(basename "$OUT20")"
rm -f "$OLL"
(cd "$OUT20" && OVERRIDE_LEDGER="$OLL" bash "$HOOKS_DIR/override-ledger.sh" TESTWORD "another one")
folder20b="$(tail -1 "$OLL" 2>/dev/null | cut -f2)"
if [ "$folder20b" = "$base20" ]; then ok; else bad "outside any repo: folder must fall back to \$PWD's own basename; got '$folder20b' want '$base20'"; fi
pass_n=$((pass_n+1))
# A long command is logged head AND tail (120 + 120), never a flat first-200 cut: the
# dangerous part of a padded command sits at the END (see section 28, finding 13).
LONGCMD="$(python3 -c "print('x'*250)")"
rm -f "$OLL"
(cd "$OUT20" && OVERRIDE_LEDGER="$OLL" bash "$HOOKS_DIR/override-ledger.sh" TESTWORD "${LONGCMD}TAILMARKER")
gotfield_full="$(tail -1 "$OLL" 2>/dev/null | cut -f5)"
if printf '%s' "$gotfield_full" | grep -q 'TAILMARKER'; then ok; else bad "a long command must still log its own tail; got '$gotfield_full'"; fi
refuse_n=$((refuse_n+1))
if printf '%s' "$gotfield_full" | grep -qF ' ... '; then ok; else bad "a long command must be logged as head ... tail"; fi
pass_n=$((pass_n+1))
rm -f "$OLL"
(cd "$OUT20" && OVERRIDE_LEDGER="$OLL" bash "$HOOKS_DIR/override-ledger.sh" TESTWORD "a short one" "the pattern")
if [ "$(tail -1 "$OLL" 2>/dev/null | cut -f4)" = "the pattern" ]; then ok; else bad "the pattern the override bypassed must be its own column"; fi
pass_n=$((pass_n+1))
if [ "$(tail -1 "$OLL" 2>/dev/null | cut -f5)" = "a short one" ]; then ok; else bad "a short command must be logged whole, with no ellipsis"; fi
pass_n=$((pass_n+1))
rm -f "$OLL"
NLCMD="$(printf 'line one\tline two\nline three')"
(cd "$OUT20" && OVERRIDE_LEDGER="$OLL" bash "$HOOKS_DIR/override-ledger.sh" TESTWORD "$NLCMD")
gotfield="$(tail -1 "$OLL" 2>/dev/null | cut -f5)"
if [ "$gotfield" = "line one line two line three" ]; then ok; else bad "newlines/tabs in the command must be flattened to single spaces, got '$gotfield'"; fi
pass_n=$((pass_n+1))
# An unwritable ledger must REPORT that (exit non-zero) so the calling hook can refuse the
# override instead of honouring an act nobody can see.
rc20=$(env OVERRIDE_LEDGER="/nonexistent-$$/deep/path/overrides.tsv" bash "$HOOKS_DIR/override-ledger.sh" X "y" >/dev/null 2>&1; echo $?)
if [ "$rc20" != 0 ]; then ok; else bad "override-ledger.sh must exit non-zero when its ledger path cannot be created"; fi
refuse_n=$((refuse_n+1))

echo "21 hooks/gate-guard.sh"
for c in 'npm test | tee out.log && git commit -m x' 'npm run typecheck | grep -q PASS && git commit -m x' 'vitest run | tail -20 && git push' 'npx playwright test; git commit -am "x"' 'while ! grep -q READY build.log; do sleep 2; done' 'until tail -1 build.log | grep -q DONE; do sleep 1; done'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "must refuse: $c" bash "$HOOKS_DIR/gate-guard.sh"; done
NLGATE=$'npm test\ngit push'
INPUT="$(json_bash "$NLGATE")"; expect refuse 2 "a bare newline joining a gate to a push must refuse" bash "$HOOKS_DIR/gate-guard.sh"
for c in 'npm test && git commit -am "x"' 'npm test && git push' 'ls -la' 'GATE_OK=1 npm test | tee out.log && git commit -m x' 'git commit -m "ran npm test and it passed"' 'while ! curl -sf localhost:3000/health; do sleep 2; done' 'npx vitest run src/foo.test.ts && echo done'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "must allow: $c" bash "$HOOKS_DIR/gate-guard.sh"; done
GGCONF="$T/gg-conf"; mkdir -p "$GGCONF"; cp "$HOOKS_DIR/gate-guard.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/override-ledger.sh" "$GGCONF/"
printf 'pytest\ngo test\n' > "$GGCONF/gate-guard.conf"
INPUT="$(json_bash 'pytest | tee out.log && git commit -m x')"; expect refuse 2 "conf-added gate 'pytest' piped must refuse" bash "$GGCONF/gate-guard.sh"
INPUT="$(json_bash 'go test | tee out.log && git commit -m x')"; expect refuse 2 "conf-added gate 'go test' piped must refuse" bash "$GGCONF/gate-guard.sh"
INPUT="$(json_bash 'pytest && echo done')"; expect pass 0 "conf-added gate 'pytest' joined with && must pass" bash "$GGCONF/gate-guard.sh"
INPUT="$(json_bash 'npm test')"; expect pass 0 "with no jq/no gate found at all: bare gate command alone (no pipe/semicolon) must pass" bash "$HOOKS_DIR/gate-guard.sh"

echo "22 hooks/channel-size-guard.sh"
huge="$(python3 -c "print(' '.join(['w']*99999))")"
INPUT="$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]}}))' "$T/anyfile/NOTES.md" "$huge")"
expect pass 0 "no hooks/channel-ceiling.conf at all: any size is ALLOWED (inert)" bash "$HOOKS_DIR/channel-size-guard.sh"
CSZ="$T/csz-conf"; mkdir -p "$CSZ"; cp "$HOOKS_DIR/channel-size-guard.sh" "$CSZ/"
printf 'LIMIT=100\nNOTES.md words 10 20\nMISTAKES.md lines 5 10\n*/NOTES.md words 10 20\n' > "$CSZ/channel-ceiling.conf"
jw() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]}}))' "$1" "$2"; }
je() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":sys.argv[2],"new_string":sys.argv[3]}}))' "$1" "$2" "$3"; }
jm() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"MultiEdit","tool_input":{"file_path":sys.argv[1],"edits":[{"old_string":sys.argv[2],"new_string":sys.argv[3]}]}}))' "$1" "$2" "$3"; }
jb2() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$2"; }
cszd="$T/cszrepo"; mkdir -p "$cszd/sub"
w21="$(python3 -c "print(' '.join(['w']*21))")"
printf '%s' "$w21" > "$cszd/NOTES.md"
INPUT="$(je "$cszd/NOTES.md" "$w21" "$w21 x y z")"; expect refuse 2 "Edit GROWING an over-stop NOTES.md must be REFUSED" bash "$CSZ/channel-size-guard.sh"
INPUT="$(je "$cszd/NOTES.md" "$w21" "w w w")"; expect pass 0 "Edit SHRINKING an over-stop NOTES.md must be ALLOWED (a sweep)" bash "$CSZ/channel-size-guard.sh"
w25="$(python3 -c "print(' '.join(['w']*25))")"
INPUT="$(jw "$cszd/NOTES.md" "$w25")"; expect refuse 2 "Write GROWING content on an over-stop NOTES.md must be REFUSED" bash "$CSZ/channel-size-guard.sh"
w5="$(python3 -c "print(' '.join(['w']*5))")"
INPUT="$(jw "$cszd/NOTES.md" "$w5")"; expect pass 0 "Write SHRINKING content on an over-stop NOTES.md must be ALLOWED" bash "$CSZ/channel-size-guard.sh"
printf '%s' "$w21" > "$cszd/sub/NOTES.md"
INPUT="$(je "$cszd/sub/NOTES.md" "$w21" "$w21 z")"; expect refuse 2 "a nested NOTES.md (matched via */NOTES.md by basename) growing over stop must be REFUSED" bash "$CSZ/channel-size-guard.sh"
w15="$(python3 -c "print(' '.join(['w']*15))")"
cszd2="$T/cszrepo2"; mkdir -p "$cszd2"; printf '%s' "$w15" > "$cszd2/NOTES.md"
INPUT="$(je "$cszd2/NOTES.md" "$w15" "$w15 x")"; expect pass 0 "growing within the band (over band, not over stop) must be ALLOWED, with a note" bash "$CSZ/channel-size-guard.sh"
mist11="$(python3 -c "print('\n'.join(['line']*11))")"
mistd="$T/cszrepo3"; mkdir -p "$mistd"; printf '%s\n' "$mist11" > "$mistd/MISTAKES.md"
INPUT="$(jm "$mistd/MISTAKES.md" "$mist11" "$mist11
more")"; expect refuse 2 "MultiEdit GROWING an over-stop MISTAKES.md (line band) must be REFUSED" bash "$CSZ/channel-size-guard.sh"
INPUT="$(jm "$mistd/MISTAKES.md" "$mist11" "line")"; expect pass 0 "MultiEdit SHRINKING an over-stop MISTAKES.md must be ALLOWED" bash "$CSZ/channel-size-guard.sh"
cszd3="$T/cszrepo4"; mkdir -p "$cszd3"; printf '%s' "$w21" > "$cszd3/NOTES.md"
INPUT="$(jb2 'echo more >> NOTES.md' "$cszd3")"; expect refuse 2 "Bash >> onto an over-stop NOTES.md must be REFUSED" bash "$CSZ/channel-size-guard.sh"
w3="$(python3 -c "print(' '.join(['w']*3))")"
printf '%s' "$w3" > "$cszd3/NOTES.md"
INPUT="$(jb2 'echo more >> NOTES.md' "$cszd3")"; expect pass 0 "Bash >> onto a small (under-band) NOTES.md must be ALLOWED" bash "$CSZ/channel-size-guard.sh"
INPUT="$(jb2 'echo hi' "$cszd3")"; expect pass 0 "a Bash command naming no watched file must be ALLOWED" bash "$CSZ/channel-size-guard.sh"

echo "23 hooks/provenance.py + commit-pathspec-guard.sh: session provenance for shared channel files"
PROVCONF="$T/prov-conf"; mkdir -p "$PROVCONF"
cp "$HOOKS_DIR/commit-pathspec-guard.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/provenance.py" "$HOOKS_DIR/override-ledger.sh" "$PROVCONF/"
printf 'NOTES.md\n' > "$PROVCONF/channel-ceiling.conf"
PROVSTATE="$T/prov-state"; mkdir -p "$PROVSTATE"
provd="$T/provrepo"; mkdir -p "$provd"; git -C "$provd" init -q -b main; git -C "$provd" config core.hooksPath /dev/null
echo seed > "$provd/NOTES.md"; git -C "$provd" add -A; "${ID[@]}" git -C "$provd" commit -q -m init
jhook() { python3 -c 'import json,sys;print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"file_path":sys.argv[2],"command":sys.argv[3]},"cwd":sys.argv[4],"session_id":sys.argv[5]}))' "$1" "$2" "$3" "$4" "$5"; }
run_prov() { printf '%s' "$2" | env PROVENANCE_STATE_DIR="$PROVSTATE" python3 "$PROVCONF/provenance.py" "$1" >/dev/null; }
SID_A="sess-A-$$"
run_prov pre  "$(jhook Write "$provd/NOTES.md" "" "$provd" "$SID_A")"
echo "session A note" >> "$provd/NOTES.md"
run_prov post "$(jhook Write "$provd/NOTES.md" "" "$provd" "$SID_A")"
git -C "$provd" add NOTES.md
outp="$(printf '%s' "$(jhook Bash "" "git commit NOTES.md -m x" "$provd" "$SID_A")" | env PROVENANCE_STATE_DIR="$PROVSTATE" bash "$PROVCONF/commit-pathspec-guard.sh" 2>&1)"; rcp=$?
if [ "$rcp" = 0 ]; then ok; else bad "session A commits its OWN recorded NOTES.md write: must be ALLOWED; rc=$rcp out='$outp'"; fi
pass_n=$((pass_n+1))
run_prov pre  "$(jhook Bash "" "git commit NOTES.md -m x" "$provd" "$SID_A")"
"${ID[@]}" git -C "$provd" commit -q -m "sessionA note"
run_prov post "$(jhook Bash "" "git commit NOTES.md -m x" "$provd" "$SID_A")"
echo "foreign unrecorded change" >> "$provd/NOTES.md"
git -C "$provd" add NOTES.md
outp2="$(printf '%s' "$(jhook Bash "" "git commit NOTES.md -m x" "$provd" "$SID_A")" | env PROVENANCE_STATE_DIR="$PROVSTATE" bash "$PROVCONF/commit-pathspec-guard.sh" 2>&1)"; rcp2=$?
if [ "$rcp2" = 2 ] && printf '%s' "$outp2" | grep -q 'no-record'; then ok; else bad "a foreign, unrecorded NOTES.md change must be REFUSED (no-record); rc=$rcp2 out='$outp2'"; fi
refuse_n=$((refuse_n+1))
outp3="$(printf '%s' "$(jhook Bash "" "SWEEP=1 git commit NOTES.md -m x" "$provd" "$SID_A")" | env PROVENANCE_STATE_DIR="$PROVSTATE" bash "$PROVCONF/commit-pathspec-guard.sh" 2>&1)"; rcp3=$?
if [ "$rcp3" = 0 ]; then ok; else bad "SWEEP=1 must override the provenance refusal; rc=$rcp3 out='$outp3'"; fi
pass_n=$((pass_n+1))
NOPROV="$T/noprovrepo"; mkdir -p "$NOPROV"; git -C "$NOPROV" init -q -b main; git -C "$NOPROV" config core.hooksPath /dev/null
echo seed > "$NOPROV/NOTES.md"; git -C "$NOPROV" add -A; "${ID[@]}" git -C "$NOPROV" commit -q -m init
echo "totally foreign" >> "$NOPROV/NOTES.md"; git -C "$NOPROV" add NOTES.md
outp4="$(printf '%s' "$(jhook Bash "" "git commit NOTES.md -m x" "$NOPROV" "nosession")" | bash "$HOOKS_DIR/commit-pathspec-guard.sh" 2>&1)"; rcp4=$?
if [ "$rcp4" = 0 ]; then ok; else bad "no hooks/channel-ceiling.conf at all: provenance must be INERT (always allow); rc=$rcp4 out='$outp4'"; fi
pass_n=$((pass_n+1))

echo "24 override-ledger.sh wiring: every override word logs one line"
ledger_has() { [ -f "$1" ] || return 1; cut -f3 "$1" | grep -qxF "$2"; }
WL="$T/wiring-ledger.tsv"
rm -f "$WL"; INPUT="$(json_bash 'GITGUARD=1 git reset --hard')"; printf '%s' "$INPUT" | env OVERRIDE_LEDGER="$WL" bash "$HOOKS_DIR/block-dangerous-git.sh" >/dev/null 2>&1
if ledger_has "$WL" GITGUARD; then ok; else bad "block-dangerous-git.sh: GITGUARD=1 must write a ledger line"; fi
pass_n=$((pass_n+1))
rm -f "$WL"; INPUT="$(json_bash 'SUITE_OK=1 npm test')"; printf '%s' "$INPUT" | env OVERRIDE_LEDGER="$WL" HEAVY_SUITE_LOAD_OVERRIDE=12 bash "$HOOKS_DIR/heavy-suite-guard.sh" >/dev/null 2>&1
if ledger_has "$WL" SUITE_OK; then ok; else bad "heavy-suite-guard.sh: SUITE_OK=1 must write a ledger line"; fi
pass_n=$((pass_n+1))
rm -f "$WL"; INPUT="$(json_bash 'GATE_OK=1 npm test | tee out.log && git commit -m x')"; printf '%s' "$INPUT" | env OVERRIDE_LEDGER="$WL" bash "$HOOKS_DIR/gate-guard.sh" >/dev/null 2>&1
if ledger_has "$WL" GATE_OK; then ok; else bad "gate-guard.sh: GATE_OK=1 must write a ledger line"; fi
pass_n=$((pass_n+1))
rm -f "$WL"
wlr="$T/wl-repo"; mkdir -p "$wlr"; git -C "$wlr" init -q -b main; git -C "$wlr" config core.hooksPath /dev/null
echo a > "$wlr/a.txt"; git -C "$wlr" add a.txt; "${ID[@]}" git -C "$wlr" commit -q -m init
echo b > "$wlr/b.txt"; git -C "$wlr" add b.txt
jbc2() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$2"; }
jbc2 'SWEEP=1 git commit -m "x"' "$wlr" | env OVERRIDE_LEDGER="$WL" bash "$HOOKS_DIR/commit-pathspec-guard.sh" >/dev/null 2>&1
if ledger_has "$WL" SWEEP; then ok; else bad "commit-pathspec-guard.sh: SWEEP=1 must write a ledger line"; fi
pass_n=$((pass_n+1))
rm -f "$WL"
pcHOME="$T/fakehome-wl"; mkdir -p "$pcHOME/.claude/hooks"
cp "$HOOKS_DIR/override-ledger.sh" "$pcHOME/.claude/hooks/"
: > "$pcHOME/.claude/.redaction-names.local"
printf 'LIMIT=1\nNOTES.md\n' > "$pcHOME/.claude/hooks/channel-ceiling.conf"
pcr="$T/wl-pc-repo"; mkdir -p "$pcr"; git -C "$pcr" init -q -b main; git -C "$pcr" config core.hooksPath "$GIT_HOOKS_DIR"
echo seed > "$pcr/NOTES.md"; env HOME="$pcHOME" git -C "$pcr" add -A; env HOME="$pcHOME" "${ID[@]}" git -C "$pcr" commit -q -m init >/dev/null 2>&1
printf 'a\nb\n' >> "$pcr/NOTES.md"; env HOME="$pcHOME" git -C "$pcr" add -A
env HOME="$pcHOME" OVERRIDE_LEDGER="$WL" SWEEP=1 "${ID[@]}" git -C "$pcr" commit -q -m test >/dev/null 2>&1
if ledger_has "$WL" SWEEP; then ok; else bad "git-hooks/pre-commit: SWEEP=1 (channel ceiling) must write a ledger line"; fi
pass_n=$((pass_n+1))
rm -f "$WL"
rcr="$T/wl-rc-repo"; mkdir -p "$rcr"; git -C "$rcr" init -q -b main; git -C "$rcr" config core.hooksPath "$GIT_HOOKS_DIR"
python3 -c "print(' '.join(['w']*5751))" > "$rcr/CLAUDE.md"
env HOME="$pcHOME" git -C "$rcr" add -A
env HOME="$pcHOME" OVERRIDE_LEDGER="$WL" RULES_CAP_OK=1 "${ID[@]}" git -C "$rcr" commit -q -m test >/dev/null 2>&1
if ledger_has "$WL" RULES_CAP_OK; then ok; else bad "git-hooks/pre-commit: RULES_CAP_OK=1 must write a ledger line"; fi
pass_n=$((pass_n+1))

echo "25 hooks/stop-state-check.sh: the per-role context floor and the state-file requirement"
SCD="$T/state-check-conf"; mkdir -p "$SCD"; cp "$HOOKS_DIR/stop-state-check.sh" "$HOOKS_DIR/guard-lib.sh"  "$SCD/"
printf 'STATE_FILE state/{role}.md\nmyapp-dev*  dev  5\n' > "$SCD/state-check.conf"
scr="$T/myapp-dev1"; mkdir -p "$scr/state"; git -C "$scr" init -q -b main; git -C "$scr" config core.hooksPath /dev/null
echo seed > "$scr/README.md"; git -C "$scr" add -A; "${ID[@]}" git -C "$scr" commit -q -m init
ssc_json() { python3 -c 'import json,sys;print(json.dumps({"cwd":sys.argv[1],"session_id":sys.argv[2],"stop_hook_active":sys.argv[3]=="true","transcript_path":sys.argv[4]}))' "$1" "$2" "$3" "$4"; }
# The state-file job only blocks when it can see that THIS turn changed something — the
# turn snapshot hooks/doorman.sh writes when the prompt arrives (see section 29's M12).
# Taken here with the tree still clean, so the change below is this turn's.
mkdir -p "$T/ssc-state/turnsnap"; printf '%s\t%s\t%s\t%s\n' "$(git -C "$scr" rev-parse HEAD)" none "$(git -C "$scr" diff HEAD | git -C "$scr" hash-object --stdin)" none > "$T/ssc-state/turnsnap/sidX"
echo more >> "$scr/README.md"
outss1="$(ssc_json "$scr" sidX false "" | STATE_CHECK_STATE_DIR="$T/ssc-state" bash "$SCD/stop-state-check.sh")"
if printf '%s' "$outss1" | grep -q '"decision":"block"'; then ok; else bad "stop-state-check.sh: a changed tracked file with the state file untouched must be BLOCKED; got '$outss1'"; fi
refuse_n=$((refuse_n+1))
printf '**Current task:** x\n**Next step:** y\n' > "$scr/state/dev.md"
git -C "$scr" add -A
outss2="$(ssc_json "$scr" sidX false "" | STATE_CHECK_STATE_DIR="$T/ssc-state" bash "$SCD/stop-state-check.sh")"
if printf '%s' "$outss2" | grep -q '"decision":"block"'; then bad "stop-state-check.sh: a changed AND FILLED state file must be ALLOWED; got '$outss2'"; else ok; fi
pass_n=$((pass_n+1))

echo "25b hooks/stop-state-check.sh: retirement past the role's context floor"
TP25="$T/ssc-transcript.jsonl"
printf '{"type":"assistant","timestamp":"2026-01-01T00:00:00Z","message":{"usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":8000,"output_tokens":10}}}\n' > "$TP25"
outss3="$(ssc_json "$scr" sidRET25 false "$TP25" | STATE_CHECK_STATE_DIR="$T/ssc-state" bash "$SCD/stop-state-check.sh" 2>&1)"   # the RETIRED sentence is on stderr since c2a (A42)
if printf '%s' "$outss3" | grep -q 'RETIRED at 8k'; then ok; else bad "stop-state-check.sh: context over the role's floor must RETIRE the session; got '$outss3'"; fi
pass_n=$((pass_n+1))
[ -f "$T/ssc-state/retired/sidRET25" ] && ok || bad "stop-state-check.sh: retirement must write state/retired/<session_id>"
pass_n=$((pass_n+1))

echo "25c hooks/stop-state-check.sh: no hooks/state-check.conf at all is INERT"
SCD2="$T/state-check-noconf"; mkdir -p "$SCD2"; cp "$HOOKS_DIR/stop-state-check.sh" "$HOOKS_DIR/guard-lib.sh"  "$SCD2/"
scr2="$T/myapp-dev2"; mkdir -p "$scr2"; git -C "$scr2" init -q -b main; git -C "$scr2" config core.hooksPath /dev/null
echo seed > "$scr2/README.md"; git -C "$scr2" add -A; "${ID[@]}" git -C "$scr2" commit -q -m init
echo more >> "$scr2/README.md"
outss4="$(ssc_json "$scr2" sidNC false "" | bash "$SCD2/stop-state-check.sh")"
if [ -z "$outss4" ]; then ok; else bad "stop-state-check.sh: no conf file must be INERT (no block); got '$outss4'"; fi
pass_n=$((pass_n+1))

echo "26 hooks/doorman.sh: refuses a RETIRED session (marker with its companion); passes a fresh one"
DCD="$T/doorman-conf"; mkdir -p "$DCD"; cp "$HOOKS_DIR/doorman.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/clock-in-context.sh" "$DCD/"
printf 'myapp-dev*  dev  850\n' > "$DCD/state-check.conf"
dm="$T/myapp-dev3"; mkdir -p "$dm"
dj() { python3 -c 'import json,sys;print(json.dumps({"cwd":sys.argv[1],"session_id":sys.argv[2],"prompt":sys.argv[3],"transcript_path":sys.argv[4]}))' "$1" "$2" "$3" "$4"; }

mkdir -p "$T/doorman-state/retired" "$T/doorman-state/retired-compacts"; echo "2026-01-01 00:00 dev 900k" > "$T/doorman-state/retired/sidDM-A"; echo 0 > "$T/doorman-state/retired-compacts/sidDM-A"
dj "$dm" sidDM-A hello "" | STATE_CHECK_STATE_DIR="$T/doorman-state" bash "$DCD/doorman.sh" >/dev/null 2>&1
rcA=$?
if [ "$rcA" = 2 ]; then ok; else bad "doorman.sh: a session already marked RETIRED must be REFUSED (exit 2), got $rcA"; fi
refuse_n=$((refuse_n+1))

dj "$dm" sidDM-B hello "" | STATE_CHECK_STATE_DIR="$T/doorman-state" bash "$DCD/doorman.sh" >/dev/null 2>&1
rcB=$?
if [ "$rcB" = 0 ]; then ok; else bad "doorman.sh: a fresh session with no transcript must PASS (fail open), got $rcB"; fi
pass_n=$((pass_n+1))

echo "26b hooks/doorman.sh: idle time never holds (the hold is the context cut-off only; c2b A52)"
T0E=$(python3 -c "import calendar,time; print(calendar.timegm(time.strptime('2026-01-01T00:00:00','%Y-%m-%dT%H:%M:%S')))")
NOWE=$((T0E + 70*60))
NOWT=$(python3 -c "import time; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime($NOWE)))")
RECE=$((NOWE - 2*60))
RECT=$(python3 -c "import time; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime($RECE)))")
TPC="$T/doorman-tp-c.jsonl"
cat > "$TPC" <<EOF
{"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"content":"hi"}}
{"type":"assistant","timestamp":"$RECT","message":{"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":5000,"output_tokens":1}}}
{"type":"user","timestamp":"$NOWT","message":{"content":"current prompt"}}
EOF
dj "$dm" sidDM-C "current prompt" "$TPC" | STATE_CHECK_STATE_DIR="$T/doorman-state" DOORMAN_NOW="$NOWE" DOORMAN_IDLE_MIN=10 DOORMAN_CTX_K=5 bash "$DCD/doorman.sh" >/dev/null 2>&1
rcC=$?
if [ "$rcC" = 0 ]; then ok; else bad "doorman.sh: the owner silent 70min but the SESSION active 2min ago must PASS (not idle), got $rcC"; fi
pass_n=$((pass_n+1))

TPD="$T/doorman-tp-d.jsonl"
cat > "$TPD" <<EOF
{"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"content":"hi"}}
{"type":"assistant","timestamp":"2026-01-01T00:00:05Z","message":{"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":5000,"output_tokens":1}}}
{"type":"user","timestamp":"$NOWT","message":{"content":"current prompt"}}
EOF
dj "$dm" sidDM-D "current prompt" "$TPD" | STATE_CHECK_STATE_DIR="$T/doorman-state" DOORMAN_NOW="$NOWE" DOORMAN_IDLE_MIN=10 DOORMAN_CTX_K=5 bash "$DCD/doorman.sh" >/dev/null 2>&1
rcD=$?
if [ "$rcD" = 0 ]; then ok; else bad "doorman.sh: BOTH sides quiet 70min with high context (under the floor) must PASS: idle no longer holds (A52), got $rcD"; fi
pass_n=$((pass_n+1))

echo "26c hooks/doorman.sh: no hooks/state-check.conf at all is INERT"
DCD2="$T/doorman-noconf"; mkdir -p "$DCD2"; cp "$HOOKS_DIR/doorman.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/clock-in-context.sh" "$DCD2/"
dj "$dm" sidDM-E hello "" | bash "$DCD2/doorman.sh" >/dev/null 2>&1
rcE=$?
if [ "$rcE" = 0 ]; then ok; else bad "doorman.sh: no conf file must be INERT (always pass), got $rcE"; fi
pass_n=$((pass_n+1))

echo "28 blind-attacker findings (parts 1-15): the five Bash guards hardened"
# Each guard gets its own copy of the hooks folder so a conf file (or a deliberately
# missing file) can be set per case without touching the tested checkout.
mk28() { local d="$1"; mkdir -p "$d"; cp "$HOOKS_DIR"/*.sh "$d/" 2>/dev/null; }
G28="$T/h28-gate";  mk28 "$G28";  printf 'pytest\ngo test\n' > "$G28/gate-guard.conf"
HS28="$T/h28-heavy"; mk28 "$HS28"
HSC28="$T/h28-heavy-crlf"; mk28 "$HSC28"
printf "PATTERN='(^|[;&| ])make +heavytest([ ;&|]|\$)'\r\nMAX_LOAD=3\r\n" > "$HSC28/heavy-suite.conf"
NOLIB28="$T/h28-nolib"; mk28 "$NOLIB28"; rm -f "$NOLIB28/guard-lib.sh"
NOLED28="$T/h28-noledger"; mk28 "$NOLED28"; rm -f "$NOLED28/override-ledger.sh"
OL28="$T/h28-ovl.tsv"

# --- 1 gate-guard: a conf file must ADD gates, never make every gate word a refusal ----
INPUT="$(json_bash 'npm test && git commit -m x f.ts')"; expect pass 0 "F1 conf present: a gate joined with && must pass" bash "$G28/gate-guard.sh"
INPUT="$(json_bash 'npx tsc --noEmit')"; expect pass 0 "F1 conf present: npx tsc --noEmit alone must pass" bash "$G28/gate-guard.sh"
INPUT="$(json_bash 'npm test | tee out.log && git commit -m x')"; expect refuse 2 "F1 pair: conf present, a built-in gate piped must still refuse" bash "$G28/gate-guard.sh"
INPUT="$(json_bash 'pytest | tee out.log && git commit -m x')"; expect refuse 2 "F1 pair: conf present, a conf-added gate piped must still refuse" bash "$G28/gate-guard.sh"

# --- 2,3,6 block-dangerous-git: trailing characters, quotes, tabs, wrappers, --force ----
for c in 'git -C /some/path reset --hard;' '(git reset --hard)' "sh -c 'git reset --hard'" 'git reset "--hard"' 'git clean --force -d' 'git clean --force' '"git" reset --hard' $'git\treset\t--hard' 'gi\t reset --hard' $'git push origin \\\n--force' 'bash -c "git push --force origin main"' 'git reset --hard>log' 'git reset --hard&&echo done'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "F2/3/6 must refuse: $c" bash "$HOOKS_DIR/block-dangerous-git.sh"; done
for c in 'git status; ls' 'echo "git reset --hardly"' 'git clean -n' 'git clean --dry-run' 'git restore file.ts' "sh -c 'git status'" 'git commit -m "we never run git reset --hard here"' 'git push origin main; echo pushed'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "F2/3/6 pair, must allow: $c" bash "$HOOKS_DIR/block-dangerous-git.sh"; done

# --- 4,7 commit-pathspec-guard: wrappers, substituted git, whole-tree pathspecs ---------
r28="$T/h28-commit"; mkdir -p "$r28"; git -C "$r28" init -q -b main; git -C "$r28" config core.hooksPath /dev/null
echo a > "$r28/a.txt"; git -C "$r28" add -A; "${ID[@]}" git -C "$r28" commit -q -m init
echo b > "$r28/b.txt"; git -C "$r28" add b.txt   # another session's staged file, ready to be swept
jb28() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$2"; }
ex28() { local kind="$1" want="$2" label="$3" c="$4" bin="${5:-$HOOKS_DIR/commit-pathspec-guard.sh}"
  jb28 "$c" "$r28" | bash "$bin" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then ok; else bad "$label (wanted exit $want, got $got)"; fi
  if [ "$kind" = refuse ]; then refuse_n=$((refuse_n+1)); else pass_n=$((pass_n+1)); fi; }
ex28 refuse 2 "F4 sh -c hiding a commit -a must be refused"      "sh -c 'git add -A && git commit -a -m sweep'"
ex28 refuse 2 "F4 eval hiding a bare commit must be refused"     'eval "git commit"'
ex28 refuse 2 "F4 a backticked git binary must be refused"       '`echo git` commit -m x'
ex28 refuse 2 "F4 a substituted git binary must be refused"      '$(which git) commit -m x'
ex28 pass 0 "F4 pair: sh -c around a read-only git command passes" "sh -c 'git status'"
ex28 pass 0 "F4 pair: bash -c around a pathspec commit passes"     'bash -c "git commit b.txt -m x"'
ex28 pass 0 "F4 pair: a substituted git that does not commit passes" '$(which git) status'
ex28 refuse 2 "F7 a * pathspec is a whole-tree sweep"   "git commit '*' -m x"
ex28 refuse 2 "F7 a .. pathspec is a whole-tree sweep"  'git commit .. -m x'
ex28 refuse 2 "F7 a / pathspec is a whole-tree sweep"   'git commit / -m x'
ex28 refuse 2 "F7 the repo root as a pathspec is a whole-tree sweep" "git commit $r28 -m x"
ex28 pass 0 "F7 pair: a glob naming real files passes"  'git commit src/*.ts -m x'
ex28 pass 0 "F7 pair: a path that merely starts with .. passes" 'git commit ../h28-commit/b.txt -m x'
ex28 pass 0 "F7 pair: a named file still passes"        'git commit b.txt -m x'

# --- 5 the override grep runs on quoted text: a message must not disarm a guard ---------
rm -f "$OL28"; INPUT="$(json_bash "git commit -m 'x; SUITE_OK=1 y' && npm test")"
expect refuse 2 "F5 SUITE_OK inside a commit message must NOT disarm the load guard" env OVERRIDE_LEDGER="$OL28" HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HS28/heavy-suite-guard.sh"
if [ -f "$OL28" ]; then bad "F5 a faked SUITE_OK must not write a ledger line"; else ok; fi; refuse_n=$((refuse_n+1))
rm -f "$OL28"; INPUT="$(json_bash 'SUITE_OK=1 npm test')"
expect pass 0 "F5 pair: a real SUITE_OK at the start still passes" env OVERRIDE_LEDGER="$OL28" HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HS28/heavy-suite-guard.sh"
if [ -f "$OL28" ]; then ok; else bad "F5 pair: a real SUITE_OK must write its ledger line"; fi; pass_n=$((pass_n+1))
rm -f "$OL28"; INPUT="$(json_bash "git commit -m 'x; GATE_OK=1 y' && npm test | tee out.log && git commit -m z")"
expect refuse 2 "F5 GATE_OK inside a commit message must NOT disarm gate-guard" env OVERRIDE_LEDGER="$OL28" bash "$HS28/gate-guard.sh"
if [ -f "$OL28" ]; then bad "F5 a faked GATE_OK must not write a ledger line"; else ok; fi; refuse_n=$((refuse_n+1))

# --- 8 heavy-suite-guard: config-path exemption, CRLF conf, >, yarn/pnpm, test:* --------
for c in 'vitest run --config vitest.config.ts' 'npm test>log' 'yarn test' 'pnpm test' 'npm run test:all' 'bash -c "npm test"'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "F8 load 25 must refuse: $c" env HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HS28/heavy-suite-guard.sh"; done
for c in 'npm run typecheck' 'npm run testdata' 'yarn lint' 'ls'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "F8 pair, load 25 must allow: $c" env HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HS28/heavy-suite-guard.sh"; done
INPUT="$(json_bash 'make heavytest')"; expect refuse 2 "F8 a CRLF-saved conf must still bind PATTERN" env HEAVY_SUITE_LOAD_OVERRIDE=5 bash "$HSC28/heavy-suite-guard.sh"
INPUT="$(json_bash 'make lighttest')"; expect pass 0 "F8 pair: CRLF conf, an unmatched command still passes" env HEAVY_SUITE_LOAD_OVERRIDE=5 bash "$HSC28/heavy-suite-guard.sh"

# --- 9 heavy-suite-guard: targeted runs, version/list queries, quoted prose -------------
for c in 'npm test -- src/a.test.ts' "vitest run -t 'renders the card'" 'npx vitest --version' 'npx playwright test --list' 'echo "run npm test later" >> DEBT.md'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "F9 load 25 must allow: $c" env HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HS28/heavy-suite-guard.sh"; done
for c in 'npm test' 'npx playwright test --headed' 'vitest run'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "F9 pair, load 25 must refuse: $c" env HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HS28/heavy-suite-guard.sh"; done

# --- 10 gate-guard: the gate word must be at command position ---------------------------
for c in 'ls node_modules/.bin | grep vitest | head' 'npx tsc --version | head -1' 'grep -rn "npm test" docs | head'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "F10 must allow: $c" bash "$HOOKS_DIR/gate-guard.sh"; done
for c in 'npx tsc --noEmit | head -1 && git commit -m x' 'vitest run | head -3 && git commit -m x'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "F10 pair, must refuse: $c" bash "$HOOKS_DIR/gate-guard.sh"; done

# --- 11 gate-guard with jq but no python3: inert and loud, never a blanket refusal ------
NOPY28="$T/h28-nopy-bin"; mkdir -p "$NOPY28"
for b in bash cat grep jq dirname sed env tr cut date mkdir awk; do p="$(command -v "$b" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$NOPY28/$b"; done
INPUT="$(json_bash 'ls -la')"; expect pass 0 "F11 jq present, python3 missing: an unrelated command must pass" env -i "PATH=$NOPY28" GUARD_PYTHON_PREFERRED=/nonexistent/python3 bash "$HOOKS_DIR/gate-guard.sh"
err28="$(printf '%s' "$INPUT" | env -i "PATH=$NOPY28" GUARD_PYTHON_PREFERRED=/nonexistent/python3 bash "$HOOKS_DIR/gate-guard.sh" 2>&1 1>/dev/null)"
if printf '%s' "$err28" | grep -q 'python3'; then ok; else bad "F11 the python3-missing pass must say so on stderr (got: '$err28')"; fi; pass_n=$((pass_n+1))
INPUT="$(json_bash 'ls -la')"; expect pass 0 "F11 pair: with python3 present an unrelated command still passes" bash "$HOOKS_DIR/gate-guard.sh"
INPUT="$(json_bash 'npm test | tee out.log && git commit -m x')"; expect refuse 2 "F11 pair: with python3 present a piped gate is still refused" bash "$HOOKS_DIR/gate-guard.sh"

# --- 12 gate-guard: the log-poll waiter across lines, and for-loops ---------------------
INPUT="$(json_bash "$(printf 'while ! grep -q READY /tmp/log; do\n  sleep 2\ndone\n')")"
expect refuse 2 "F12 a multi-line log-poll loop must refuse" bash "$HOOKS_DIR/gate-guard.sh"
INPUT="$(json_bash 'for i in $(seq 60); do grep -q READY /tmp/log && break; sleep 2; done')"
expect refuse 2 "F12 a for-loop log poll must refuse" bash "$HOOKS_DIR/gate-guard.sh"
INPUT="$(json_bash "$(printf 'until tail -1 /tmp/log | grep -q DONE; do\n  sleep 1\ndone\n')")"
expect refuse 2 "F12 a multi-line until/tail poll must refuse" bash "$HOOKS_DIR/gate-guard.sh"
INPUT="$(json_bash "$(printf 'while ! curl -sf localhost:3000/health; do\n  sleep 2\ndone\n')")"
expect pass 0 "F12 pair: a multi-line loop waiting on the server must pass" bash "$HOOKS_DIR/gate-guard.sh"
INPUT="$(json_bash 'for f in *.md; do wc -w "$f"; done')"
expect pass 0 "F12 pair: an ordinary for loop must pass" bash "$HOOKS_DIR/gate-guard.sh"

# --- 13 override-ledger: the line must show the act, not 200 characters of padding ------
rm -f "$OL28"; LONG28="$(python3 -c "print('x'*210)")"
(cd "$T" && OVERRIDE_LEDGER="$OL28" bash "$HOOKS_DIR/override-ledger.sh" GITGUARD "GITGUARD=1 echo $LONG28 && git push --force origin main" "git push --force") >/dev/null 2>&1
line28="$(tail -1 "$OL28" 2>/dev/null)"
if printf '%s' "$line28" | grep -q -- '--force'; then ok; else bad "F13 a padded command must still log its dangerous tail (--force)"; fi; refuse_n=$((refuse_n+1))
if [ "$(printf '%s' "$line28" | cut -f4)" = "git push --force" ]; then ok; else bad "F13 the matched pattern must be its own column (got '$(printf '%s' "$line28" | cut -f4)')"; fi; refuse_n=$((refuse_n+1))
rm -f "$OL28"
(cd "$T" && OVERRIDE_LEDGER="$OL28" bash "$HOOKS_DIR/override-ledger.sh" SWEEP "git commit a.md -m x" "bare commit") >/dev/null 2>&1
if [ "$(tail -1 "$OL28" 2>/dev/null | cut -f5)" = "git commit a.md -m x" ]; then ok; else bad "F13 pair: a short command must be logged whole and unchanged"; fi; pass_n=$((pass_n+1))

# --- 14 an override that cannot be recorded is not honoured -----------------------------
BADL28="$T/h28-badledger"; printf 'a file where a folder must be\n' > "$BADL28"
rc28="$(OVERRIDE_LEDGER="$BADL28/overrides.tsv" bash "$HOOKS_DIR/override-ledger.sh" X "y" "p" >/dev/null 2>&1; echo $?)"
if [ "$rc28" != 0 ]; then ok; else bad "F14 an unwritable ledger must report failure (exit non-zero)"; fi; refuse_n=$((refuse_n+1))
errl28="$(OVERRIDE_LEDGER="$BADL28/overrides.tsv" bash "$HOOKS_DIR/override-ledger.sh" X "y" "p" 2>&1 1>/dev/null)"
if [ -z "$errl28" ]; then ok; else bad "F14 an unwritable ledger must stay quiet (got: '$errl28')"; fi; pass_n=$((pass_n+1))
INPUT="$(json_bash 'GITGUARD=1 git reset --hard')"
expect refuse 2 "F14 an unrecordable GITGUARD override must be REFUSED" env OVERRIDE_LEDGER="$BADL28/overrides.tsv" bash "$HOOKS_DIR/block-dangerous-git.sh"
rm -f "$OL28"; INPUT="$(json_bash 'GITGUARD=1 git reset --hard')"
expect pass 0 "F14 pair: with a writable ledger the same override passes" env OVERRIDE_LEDGER="$OL28" bash "$HOOKS_DIR/block-dangerous-git.sh"
INPUT="$(json_bash 'SUITE_OK=1 npm test')"
expect refuse 2 "F14 no override-ledger.sh beside the guard: SUITE_OK must be REFUSED" env OVERRIDE_LEDGER="$OL28" HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$NOLED28/heavy-suite-guard.sh"

# --- 15 block-dangerous-git: unparseable input fails CLOSED -----------------------------
INPUT='{"tool_name":"Bash","tool_input":{"command":'
expect refuse 2 "F15 truncated JSON must fail CLOSED" bash "$HOOKS_DIR/block-dangerous-git.sh"
INPUT='not json at all'
expect refuse 2 "F15 garbage input must fail CLOSED" bash "$HOOKS_DIR/block-dangerous-git.sh"
INPUT=''
expect refuse 2 "F15 empty input must fail CLOSED" bash "$HOOKS_DIR/block-dangerous-git.sh"
INPUT='{"tool_name":"Write","tool_input":{"file_path":"/x/NOTES.md","content":"git reset --hard"}}'
expect pass 0 "F15 pair: a non-Bash tool call passes untouched" bash "$HOOKS_DIR/block-dangerous-git.sh"
INPUT="$(json_bash 'git status')"
expect pass 0 "F15 pair: well-formed Bash input with a safe command passes" bash "$HOOKS_DIR/block-dangerous-git.sh"

# --- the shared helper file: missing => every guard fails CLOSED, never open ------------
INPUT="$(json_bash 'git status')"; expect refuse 2 "missing guard-lib.sh: block-dangerous-git fails CLOSED" bash "$NOLIB28/block-dangerous-git.sh"
INPUT="$(json_bash 'ls -la')"; expect refuse 2 "missing guard-lib.sh: gate-guard fails CLOSED too" bash "$NOLIB28/gate-guard.sh"
INPUT="$(json_bash 'ls')"; expect refuse 2 "missing guard-lib.sh: heavy-suite-guard fails CLOSED" env HEAVY_SUITE_LOAD_OVERRIDE=2 bash "$NOLIB28/heavy-suite-guard.sh"
jb28 'git status' "$r28" > "$T/h28-nolib-in.json"
if bash "$NOLIB28/commit-pathspec-guard.sh" < "$T/h28-nolib-in.json" >/dev/null 2>&1; then bad "missing guard-lib.sh: commit-pathspec-guard must fail CLOSED"; else ok; fi; refuse_n=$((refuse_n+1))
INPUT="$(json_bash 'ls -la')"; expect pass 0 "pair: with guard-lib.sh present the same command passes" bash "$HOOKS_DIR/gate-guard.sh"


echo "29 blind-attacker findings (part 2): the git hooks, the size guard, the state pair"
REPO29="$(cd "$HOOKS_DIR/.." && pwd -P)"

# --- B1 a merge commit runs no pre-commit hook: git-hooks/pre-merge-commit -------------
mg="$T/mergerepo"; mkdir -p "$mg"; git -C "$mg" init -q -b main; git -C "$mg" config core.hooksPath "$GIT_HOOKS_DIR"
mgadd() { env HOME="$FAKE_HOME" git -C "$mg" add -A; }
mgcommit() { env HOME="$FAKE_HOME" "${ID[@]}" git -C "$mg" commit -q -m "$1" >/dev/null 2>&1; }
echo seed > "$mg/a.txt"; mgadd; mgcommit init
env HOME="$FAKE_HOME" git -C "$mg" checkout -q -b tainted
printf 'a note from ZebulonQuixote\n' > "$mg/t.txt"; mgadd
env HOME="$FAKE_HOME" PRIVACY_OK=1 "${ID[@]}" git -C "$mg" commit -q -m tainted >/dev/null 2>&1
env HOME="$FAKE_HOME" git -C "$mg" checkout -q main
echo other > "$mg/b.txt"; mgadd; mgcommit other
mg_before="$(git -C "$mg" rev-list --count HEAD)"
env HOME="$FAKE_HOME" "${ID[@]}" git -C "$mg" merge --no-ff -m "merge tainted" tainted >/dev/null 2>&1
mg_after="$(git -C "$mg" rev-list --count HEAD)"
if [ "$mg_after" = "$mg_before" ]; then ok; else bad "B1 git merge --no-ff carrying a listed name must be REFUSED (pre-merge-commit)"; fi
refuse_n=$((refuse_n+1))
env HOME="$FAKE_HOME" git -C "$mg" merge --abort >/dev/null 2>&1
env HOME="$FAKE_HOME" git -C "$mg" checkout -q -b cleanbranch
echo fine > "$mg/c.txt"; mgadd; mgcommit clean
env HOME="$FAKE_HOME" git -C "$mg" checkout -q main
mg_before2="$(git -C "$mg" rev-list --count HEAD)"
env HOME="$FAKE_HOME" "${ID[@]}" git -C "$mg" merge --no-ff -m "merge clean" cleanbranch >/dev/null 2>&1
mg_after2="$(git -C "$mg" rev-list --count HEAD)"
if [ "$mg_after2" -gt "$mg_before2" ]; then ok; else bad "B1 pair: a clean branch must still merge"; fi
pass_n=$((pass_n+1))

# --- B2/B3 pre-commit privacy: the FILENAME, and a blob git calls binary ----------------
pf="$T/privfile"; mkdir -p "$pf/x"; git -C "$pf" init -q -b main; git -C "$pf" config core.hooksPath "$GIT_HOOKS_DIR"
pftry() { git -C "$pf" add -A; env HOME="$FAKE_HOME" "${ID[@]}" git -C "$pf" commit -q -m t >/dev/null 2>&1; }
echo seed > "$pf/seed.txt"; pftry
echo "nothing sensitive in here" > "$pf/x/ZebulonQuixote-notes.md"
if pftry; then bad "B2 a listed name used as a FILENAME must be refused"; else ok; git -C "$pf" reset -q; rm -f "$pf/x/ZebulonQuixote-notes.md"; fi
refuse_n=$((refuse_n+1))
echo "nothing sensitive in here" > "$pf/x/ordinary-notes.md"
if pftry; then ok; else bad "B2 pair: an ordinary filename must still commit"; fi
pass_n=$((pass_n+1))
python3 -c 'import sys;open(sys.argv[1],"wb").write("a note from ZebulonQuixote\n".encode("utf-16-le"))' "$pf/u16.txt"
if pftry; then bad "B3 a listed name inside a UTF-16 blob (binary to git) must be refused"; else ok; git -C "$pf" reset -q; rm -f "$pf/u16.txt"; fi
refuse_n=$((refuse_n+1))
python3 -c 'import sys;open(sys.argv[1],"wb").write("an ordinary note\n".encode("utf-16-le"))' "$pf/u16ok.txt"
if pftry; then ok; else bad "B3 pair: a clean UTF-16 blob must still commit"; fi
pass_n=$((pass_n+1))
python3 -c 'import sys;open(sys.argv[1],"wb").write(bytes(range(256))*4)' "$pf/blob.bin"
if pftry; then ok; else bad "B3 pair: a genuinely binary file naming nobody must still commit"; fi
pass_n=$((pass_n+1))

# --- B4/m18 auto-backup: placeholders, the pragma, and a secret used as a FILENAME ------
PH="$T/fakehome-placeholder"; mkdir -p "$PH/.claude/hooks"
git -C "$PH/.claude" init -q -b main; git -C "$PH/.claude" config core.hooksPath /dev/null
git -C "$PH/.claude" config user.name Tester; git -C "$PH/.claude" config user.email tester@example.com
printf 'AUTHOR=Tester <tester@example.com>\nMIRROR_DIR=\n' > "$PH/.claude/hooks/backup.conf"
echo hello > "$PH/.claude/CLAUDE.md"
env HOME="$PH" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
ph0="$(git -C "$PH/.claude" rev-list --count HEAD 2>/dev/null || echo 0)"
printf 'OPENAI_API_KEY=%s\n' "$(printf '%s%s' 'your-' 'key-goes-here-xx')" >> "$PH/.claude/CLAUDE.md"
env HOME="$PH" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
ph1="$(git -C "$PH/.claude" rev-list --count HEAD)"
if [ "$ph1" -gt "$ph0" ]; then ok; else bad "B4 an obvious placeholder value (your-…) must NOT hold the backup"; fi
pass_n=$((pass_n+1))
BEAR29="$(printf '%s%s' 'Bea' 'rer ')abcdefghijklmnopqrstuvwx"
printf 'scan("%s")  # pragma: allow-secret\n' "$BEAR29" >> "$PH/.claude/CLAUDE.md"
env HOME="$PH" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
ph2="$(git -C "$PH/.claude" rev-list --count HEAD)"
if [ "$ph2" -gt "$ph1" ]; then ok; else bad "B4 a line marked '# pragma: allow-secret' must NOT hold the backup"; fi
pass_n=$((pass_n+1))
printf '%s\n' "$BEAR29" >> "$PH/.claude/CLAUDE.md"
ph_out="$(env HOME="$PH" bash "$HOOKS_DIR/auto-backup.sh" 2>&1)"
ph3="$(git -C "$PH/.claude" rev-list --count HEAD)"
if [ "$ph3" = "$ph2" ]; then ok; else bad "B4 pair: the same token with no pragma and no placeholder must still hold the backup"; fi
refuse_n=$((refuse_n+1))
if printf '%s' "$ph_out" | grep -q 'CLAUDE.md' && printf '%s' "$ph_out" | grep -q 'pragma: allow-secret'; then ok; else bad "B4 the blocking message must name the file AND the pragma (got: $ph_out)"; fi
pass_n=$((pass_n+1))
sed -i.bak "/abcdefghijklmnopqrstuvwx/d" "$PH/.claude/CLAUDE.md"; rm -f "$PH/.claude/CLAUDE.md.bak"
env HOME="$PH" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
ph4="$(git -C "$PH/.claude" rev-list --count HEAD)"
GHP29="$(printf '%s%s' 'gh' 'p_')abcdefghij1234567890"
printf 'harmless content\n' > "$PH/.claude/hooks/$GHP29.md"
env HOME="$PH" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
ph5="$(git -C "$PH/.claude" rev-list --count HEAD)"
if [ "$ph5" = "$ph4" ]; then ok; else bad "m18 a secret used as a FILENAME must hold the backup"; fi
refuse_n=$((refuse_n+1))
rm -f "$PH/.claude/hooks/$GHP29.md"
printf 'harmless content\n' > "$PH/.claude/hooks/ordinary-note.md"
env HOME="$PH" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
ph6="$(git -C "$PH/.claude" rev-list --count HEAD)"
if [ "$ph6" -gt "$ph4" ]; then ok; else bad "m18 pair: an ordinary filename must back up normally"; fi
pass_n=$((pass_n+1))

# --- B5 the COMMITTER identity is checked like the author ------------------------------
ci29="$T/committer-repo"; mkdir -p "$ci29"; git -C "$ci29" init -q -b main; git -C "$ci29" config core.hooksPath "$GIT_HOOKS_DIR"
echo a > "$ci29/a.txt"; git -C "$ci29" add -A
if env HOME="$FAKE_HOME" GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.com \
     GIT_COMMITTER_NAME=Claude GIT_COMMITTER_EMAIL=noreply@anthropic.com \
     git -C "$ci29" commit -q -m t >/dev/null 2>&1; then
  bad "B5 a matching AUTHOR with a Claude COMMITTER must be refused"; else ok; fi
refuse_n=$((refuse_n+1))
if env HOME="$FAKE_HOME" "${ID[@]}" git -C "$ci29" commit -q -m t >/dev/null 2>&1; then ok; else bad "B5 pair: a matching author AND committer must commit"; fi
pass_n=$((pass_n+1))
INPUT=""
printf 'notes: a clean message\n' > "$T/m29a"
expect refuse 1 "B5 commit-msg: a Claude COMMITTER identity must be refused" env GIT_COMMITTER_NAME=Claude GIT_COMMITTER_EMAIL=noreply@anthropic.com bash "$GIT_HOOKS_DIR/commit-msg" "$T/m29a"
expect pass 0 "B5 pair: commit-msg with an ordinary committer passes" env GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.com bash "$GIT_HOOKS_DIR/commit-msg" "$T/m29a"

# --- B6 commit-pathspec-guard: --pathspec-from-file, an unresolvable cd, bad input ------
c29="$T/h29-commit"; mkdir -p "$c29"; git -C "$c29" init -q -b main; git -C "$c29" config core.hooksPath /dev/null
echo a > "$c29/a.txt"; git -C "$c29" add -A; "${ID[@]}" git -C "$c29" commit -q -m init
echo b > "$c29/b.txt"; git -C "$c29" add b.txt
printf '.\n' > "$c29/sweep-list.txt"; printf 'b.txt\n' > "$c29/named-list.txt"
ex29() { local kind="$1" want="$2" label="$3" c="$4"
  jb28 "$c" "$c29" | bash "$HOOKS_DIR/commit-pathspec-guard.sh" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then ok; else bad "$label (wanted exit $want, got $got)"; fi
  if [ "$kind" = refuse ]; then refuse_n=$((refuse_n+1)); else pass_n=$((pass_n+1)); fi; }
ex29 refuse 2 "B6 --pathspec-from-file naming the whole tree must be refused" 'git commit --pathspec-from-file=sweep-list.txt -m x'
ex29 refuse 2 "B6 --pathspec-from-file whose file cannot be read must be refused" 'git commit --pathspec-from-file=no-such-list.txt -m x'
ex29 refuse 2 "B6 --pathspec-from-file reading stdin cannot be read: refuse" 'git commit --pathspec-from-file=- -m x'
ex29 pass 0 "B6 pair: --pathspec-from-file naming one real file passes" 'git commit --pathspec-from-file=named-list.txt -m x'
ex29 refuse 2 "B6 a cd target this guard cannot resolve must be refused" 'cd "$HOME/prov" && git commit NOTES.md -m x'
ex29 pass 0 "B6 pair: an absolute cd into a real repo still passes" "cd $c29 && git commit b.txt -m x"
ex29 pass 0 "B6 pair: an ordinary pathspec commit still passes" 'git commit b.txt -m x'
INPUT=''
expect refuse 2 "B6 empty hook input must fail CLOSED" bash "$HOOKS_DIR/commit-pathspec-guard.sh"
INPUT='{"tool_name":"Bash","tool_input":{"command":'
expect refuse 2 "B6 truncated JSON must fail CLOSED" bash "$HOOKS_DIR/commit-pathspec-guard.sh"
INPUT='{"tool_name":"Write","tool_input":{"file_path":"/x/NOTES.md","content":"git commit -a"}}'
expect pass 0 "B6 pair: a non-Bash tool call passes untouched" bash "$HOOKS_DIR/commit-pathspec-guard.sh"

# --- M7/M8/M9 channel-size-guard: word boundary, Bash shrinks, the post-write re-measure
CSZ29="$T/csz29"; mkdir -p "$CSZ29"
cp "$HOOKS_DIR/channel-size-guard.sh" "$CSZ29/" 2>/dev/null
cp "$HOOKS_DIR/channel-size-post.sh" "$CSZ29/" 2>/dev/null
printf 'LIMIT=100\nNOTES.md words 10 20\n' > "$CSZ29/channel-ceiling.conf"
d29="$T/csz29repo"; mkdir -p "$d29"
w21b="$(python3 -c "print(' '.join(['w']*21))")"
printf '%s' "$w21b" > "$d29/RELEASE-NOTES.md"; printf '%s' "$w21b" > "$d29/NOTES.md"
INPUT="$(jb2 'echo x >> RELEASE-NOTES.md' "$d29")"; expect pass 0 "M7 an unwatched RELEASE-NOTES.md must NOT be refused (both-side word boundary)" bash "$CSZ29/channel-size-guard.sh"
INPUT="$(jb2 'echo x >> NOTES.md' "$d29")"; expect refuse 2 "M7 pair: the watched NOTES.md over its stop is still refused" bash "$CSZ29/channel-size-guard.sh"
csz_allow=("sed -i '' '5,\$d' NOTES.md" ': > NOTES.md' 'cp NOTES.md NOTES-ARCHIVE.md' 'cat NOTES.md | head -5 > tmp.md')
for c in "${csz_allow[@]}"; do
  INPUT="$(jb2 "$c" "$d29")"; expect pass 0 "M8 a Bash shrink or copy must be ALLOWED: $c" bash "$CSZ29/channel-size-guard.sh"; done
csz_refuse=('echo x >> NOTES.md' 'cat extra.md >> NOTES.md' 'echo x | tee -a NOTES.md' 'cat a.md b.md > NOTES.md')
for c in "${csz_refuse[@]}"; do
  INPUT="$(jb2 "$c" "$d29")"; expect refuse 2 "M8 pair: visible growth is still REFUSED: $c" bash "$CSZ29/channel-size-guard.sh"; done
post29() { jb2 "$1" "$d29" | bash "$CSZ29/channel-size-post.sh" 2>&1; }
python3 -c "import sys;open(sys.argv[1],'w').write('x'*100000)" "$d29/NOTES.md"
o29p1="$(post29 'perl -pi -e "s/a/b/" NOTES.md')"
if printf '%s' "$o29p1" | grep -q 'NOTES.md'; then ok; else bad "M9 a file huge in BYTES but tiny in words must be named after the write (got: $o29p1)"; fi
refuse_n=$((refuse_n+1))
printf '%s' "$(python3 -c "print(' '.join(['w']*5))")" > "$d29/NOTES.md"
o29p2="$(post29 'perl -pi -e "s/a/b/" NOTES.md')"
if [ -z "$o29p2" ]; then ok; else bad "M9 pair: a small file must produce NO warning (got: $o29p2)"; fi
pass_n=$((pass_n+1))
printf '%s' "$(python3 -c "print(' '.join(['w']*25))")" > "$d29/NOTES.md"
o29p3="$(post29 'f=NOTES.md; echo x >> $f')"
if printf '%s' "$o29p3" | grep -q 'NOTES.md'; then ok; else bad "M9 a variable-named append is caught after the write (got: $o29p3)"; fi
refuse_n=$((refuse_n+1))
o29p4="$(je "$d29/NOTES.md" old new | bash "$CSZ29/channel-size-post.sh" 2>&1)"
if printf '%s' "$o29p4" | grep -q 'NOTES.md'; then ok; else bad "M9 an Edit on an over-stop file is named after the write (got: $o29p4)"; fi
refuse_n=$((refuse_n+1))

# --- M10/M12/M14 stop-state-check: a real state update, the turn snapshot, no session id
SCD29="$T/state-check-29"; mkdir -p "$SCD29"; cp "$HOOKS_DIR/stop-state-check.sh" "$HOOKS_DIR/guard-lib.sh"  "$SCD29/"
printf 'STATE_FILE state/{role}.md\nmyapp-dev*  dev  5\n' > "$SCD29/state-check.conf"
S29="$T/ssc29-state"
sr29="$T/myapp-dev29"; mkdir -p "$sr29/state"; git -C "$sr29" init -q -b main; git -C "$sr29" config core.hooksPath /dev/null
printf '**Current task:** first\n**Next step:** second\n' > "$sr29/state/dev.md"
echo seed > "$sr29/README.md"; git -C "$sr29" add -A; "${ID[@]}" git -C "$sr29" commit -q -m init
snap29() {   # the turn snapshot in the format doorman.sh writes: HEAD, state-file hash, hash of `git diff HEAD`, hash of the marker lines
  local sfh=none mk=none
  if [ -f "$sr29/state/dev.md" ]; then sfh=$(git -C "$sr29" hash-object "$sr29/state/dev.md"); mk=$({ grep -m1 -E '^\*\*Current task:\*\*' "$sr29/state/dev.md"; grep -m1 -E '^\*\*Next step:\*\*' "$sr29/state/dev.md"; } | git -C "$sr29" hash-object --stdin); fi
  mkdir -p "$S29/turnsnap"; printf '%s\t%s\t%s\t%s\n' "$(git -C "$sr29" rev-parse HEAD)" "$sfh" "$(git -C "$sr29" diff HEAD | git -C "$sr29" hash-object --stdin)" "$mk" > "$S29/turnsnap/$1"
}
run29() { ssc_json "$sr29" "$1" false "" | STATE_CHECK_STATE_DIR="$S29" bash "$SCD29/stop-state-check.sh"; }
snap29 sid29a
echo more >> "$sr29/README.md"
printf '   \n' >> "$sr29/state/dev.md"
o29a="$(run29 sid29a)"
if printf '%s' "$o29a" | grep -q '"decision":"block"'; then ok; else bad "M10 a whitespace-only append to the state file must still BLOCK (got: $o29a)"; fi
refuse_n=$((refuse_n+1))
sed 's/^\*\*Next step:\*\* second$/**Next step:** land the fix/' "$sr29/state/dev.md" > "$sr29/state/dev.md.new" && mv "$sr29/state/dev.md.new" "$sr29/state/dev.md"   # the FIRST Next step line itself moves (an appended second one no longer counts: c2a A41)
o29b="$(run29 sid29a)"
if printf '%s' "$o29b" | grep -q '"decision":"block"'; then bad "M10 pair: a real Next step update must be ALLOWED (got: $o29b)"; else ok; fi
pass_n=$((pass_n+1))
git -C "$sr29" add -A; "${ID[@]}" git -C "$sr29" commit -q -m land
echo dirt >> "$sr29/README.md"          # dirty from a PREVIOUS turn
snap29 sid29b                            # this turn starts in the already-dirty tree
o29c="$(run29 sid29b)"
if printf '%s' "$o29c" | grep -q '"decision":"block"'; then bad "M12 a read-only turn in an already-dirty tree must NOT block (got: $o29c)"; else ok; fi
pass_n=$((pass_n+1))
sfh29=$(git -C "$sr29" hash-object "$sr29/state/dev.md"); mk29=$({ grep -m1 -E '^\*\*Current task:\*\*' "$sr29/state/dev.md"; grep -m1 -E '^\*\*Next step:\*\*' "$sr29/state/dev.md"; } | git -C "$sr29" hash-object --stdin)
# a turn that started with a CLEAN tree (the empty diff's hash), HEAD as it is now
mkdir -p "$S29/turnsnap"; printf '%s\t%s\t%s\t%s\n' "$(git -C "$sr29" rev-parse HEAD)" "$sfh29" "$(: | git -C "$sr29" hash-object --stdin)" "$mk29" > "$S29/turnsnap/sid29c"
o29d="$(run29 sid29c)"
if printf '%s' "$o29d" | grep -q '"decision":"block"'; then ok; else bad "M12 pair: a turn that started CLEAN and left the tree dirty must BLOCK (got: $o29d)"; fi
refuse_n=$((refuse_n+1))
rm -f "$S29/turnsnap/sid29d"
o29e="$(run29 sid29d)"
if printf '%s' "$o29e" | grep -q '"decision":"block"'; then bad "M12 with no turn snapshot the gate must WARN, not block (got: $o29e)"; else ok; fi
pass_n=$((pass_n+1))
if printf '%s' "$o29e" | grep -qi 'doorman'; then ok; else bad "M12 the no-snapshot note must name doorman.sh (got: $o29e)"; fi
pass_n=$((pass_n+1))
cp "$S29/turnsnap/sid29c" "$S29/turnsnap/nosid-myapp-dev29"
o29f="$(ssc_json "$sr29" "" false "" | STATE_CHECK_STATE_DIR="$S29" bash "$SCD29/stop-state-check.sh")"
if printf '%s' "$o29f" | grep -q '"decision":"block"'; then ok; else bad "M14 an empty session_id must not switch the state-file job off (got: $o29f)"; fi
refuse_n=$((refuse_n+1))
TP29="$T/ssc29-transcript.jsonl"
printf '{"type":"assistant","timestamp":"2026-01-01T00:00:00Z","message":{"usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":9000,"output_tokens":10}}}\n' > "$TP29"
ssc_json "$sr29" "" false "$TP29" | STATE_CHECK_STATE_DIR="$S29" bash "$SCD29/stop-state-check.sh" >/dev/null 2>&1
n29ret="$(ls "$S29/retired" 2>/dev/null | wc -l | tr -d ' ')"
if [ "$n29ret" = "0" ]; then ok; else bad "M14 pair: with no session id no retirement marker may be written (got $n29ret)"; fi
pass_n=$((pass_n+1))
DCDS="$T/doorman-snap-conf"; mkdir -p "$DCDS"; cp "$HOOKS_DIR/doorman.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/clock-in-context.sh" "$DCDS/"
printf 'myapp-dev*  dev  850\n' > "$DCDS/state-check.conf"
rm -rf "$S29/turnsnap"
dj "$sr29" sid29g "hello" "" | STATE_CHECK_STATE_DIR="$S29" bash "$DCDS/doorman.sh" >/dev/null 2>&1
if [ -f "$S29/turnsnap/sid29g" ]; then ok; else bad "M12 doorman.sh must write the turn snapshot stop-state-check.sh reads"; fi
pass_n=$((pass_n+1))

# --- M11 the rules cap must see a RENAME into the repo root ----------------------------
rn29="$T/renamecap"; mkdir -p "$rn29/sub"; git -C "$rn29" init -q -b main; git -C "$rn29" config core.hooksPath "$GIT_HOOKS_DIR"
mkwords 6000 > "$rn29/sub/CLAUDE.md"
git -C "$rn29" add -A; env HOME="$FAKE_HOME" "${ID[@]}" git -C "$rn29" commit -q -m seed >/dev/null 2>&1
git -C "$rn29" mv sub/CLAUDE.md CLAUDE.md
if env HOME="$FAKE_HOME" "${ID[@]}" git -C "$rn29" commit -q -m t >/dev/null 2>&1; then bad "M11 git mv sub/CLAUDE.md CLAUDE.md must be REFUSED by the rules cap"; else ok; fi
refuse_n=$((refuse_n+1))
git -C "$rn29" mv CLAUDE.md sub/CLAUDE.md
echo x > "$rn29/other.txt"; git -C "$rn29" add -A
if env HOME="$FAKE_HOME" "${ID[@]}" git -C "$rn29" commit -q -m t >/dev/null 2>&1; then ok; else bad "M11 pair: moving a big rules file OUT of the root must pass"; fi
pass_n=$((pass_n+1))

# --- M13 doorman: a tool result is activity; an undated user/assistant line fails OPEN --
DCD29="$T/doorman29"; mkdir -p "$DCD29"; cp "$HOOKS_DIR/doorman.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/clock-in-context.sh" "$DCD29/"
printf 'myapp-dev*  dev  850\n' > "$DCD29/state-check.conf"
dm29="$T/myapp-dev30"; mkdir -p "$dm29"
TOOLT29=$(python3 -c "import time; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime($NOWE - 2*60)))")
TPE="$T/doorman-tp-e.jsonl"
cat > "$TPE" <<EOF
{"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"content":"hi"}}
{"type":"assistant","timestamp":"2026-01-01T00:00:05Z","message":{"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":5000,"output_tokens":1}}}
{"type":"user","timestamp":"$TOOLT29","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}
{"type":"user","timestamp":"$NOWT","message":{"content":"current prompt"}}
EOF
dj "$dm29" sidDM29A "current prompt" "$TPE" | STATE_CHECK_STATE_DIR="$T/doorman29-state" DOORMAN_NOW="$NOWE" DOORMAN_IDLE_MIN=10 DOORMAN_CTX_K=5 bash "$DCD29/doorman.sh" >/dev/null 2>&1
rc29a=$?
if [ "$rc29a" = 0 ]; then ok; else bad "M13 a tool result 2 min ago is activity: must PASS (got $rc29a)"; fi
pass_n=$((pass_n+1))
TPF="$T/doorman-tp-f.jsonl"
cat > "$TPF" <<EOF
{"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"content":"hi"}}
{"type":"assistant","timestamp":"2026-01-01T00:00:05Z","message":{"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":5000,"output_tokens":1}}}
{"type":"user","timestamp":"2026-01-01T00:00:10Z","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}
{"type":"user","timestamp":"$NOWT","message":{"content":"current prompt"}}
EOF
dj "$dm29" sidDM29B "current prompt" "$TPF" | STATE_CHECK_STATE_DIR="$T/doorman29-state" DOORMAN_NOW="$NOWE" DOORMAN_IDLE_MIN=10 DOORMAN_CTX_K=5 bash "$DCD29/doorman.sh" >/dev/null 2>&1
rc29b=$?
if [ "$rc29b" = 0 ]; then ok; else bad "M13 pair: the newest tool result 70 min old no longer holds either (A52; got $rc29b)"; fi
pass_n=$((pass_n+1))
TPG="$T/doorman-tp-g.jsonl"
cat > "$TPG" <<EOF
{"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"content":"hi"}}
{"type":"assistant","message":{"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":5000,"output_tokens":1}}}
{"type":"user","timestamp":"$NOWT","message":{"content":"current prompt"}}
EOF
dj "$dm29" sidDM29C "current prompt" "$TPG" | STATE_CHECK_STATE_DIR="$T/doorman29-state" DOORMAN_NOW="$NOWE" DOORMAN_IDLE_MIN=10 DOORMAN_CTX_K=5 bash "$DCD29/doorman.sh" >/dev/null 2>&1
rc29c=$?
if [ "$rc29c" = 0 ]; then ok; else bad "M13 an assistant line with NO timestamp must fail OPEN, as the header promises (got $rc29c)"; fi
pass_n=$((pass_n+1))

# --- m15/m16 commit-msg: zero-width, any Claude trailer, prose is not a trailer ---------
INPUT=""
ZWSP29="$(printf '\342\200\213')"
printf 'feat: x\n\nCo-Authored-By: Cla%sude <someone@users.noreply.github.com>\n' "$ZWSP29" > "$T/m29b"
expect refuse 1 "m15 a zero-width space inside Claude must still be caught" bash "$GIT_HOOKS_DIR/commit-msg" "$T/m29b"
printf 'feat: x\n\nAssisted-by: Claude Opus 5\n' > "$T/m29c"
expect refuse 1 "m15 any trailer whose value names Claude must be refused" bash "$GIT_HOOKS_DIR/commit-msg" "$T/m29c"
printf 'feat: x\n\nReviewed-by: Tester <tester@example.com>\n' > "$T/m29d"
expect pass 0 "m15 pair: an ordinary trailer must pass" bash "$GIT_HOOKS_DIR/commit-msg" "$T/m29d"
printf 'docs: explain why we never add Co-Authored-By: Claude lines\n' > "$T/m29e"
expect pass 0 "m16 a prose mention of the trailer must pass" bash "$GIT_HOOKS_DIR/commit-msg" "$T/m29e"
printf 'docs: explain the rule\n\nCo-Authored-By: Claude Opus 5\n' > "$T/m29f"
expect refuse 1 "m16 pair: the same words as a real trailer must be refused" bash "$GIT_HOOKS_DIR/commit-msg" "$T/m29f"

# --- m17 pre-commit: an scp-style git URL is not an email; short names are whole words --
printf 'clone it with git@%s:user/repo.git\n' github.com > "$pe/scp.txt"   # built at runtime: no literal address in this file
if petry; then ok; else bad "m17 an scp-style git URL must NOT be read as an email address (got: $(cat "$T/pe-err.txt"))"; fi
pass_n=$((pass_n+1))
printf 'write to someone@%s please\n' "$PE_DOM" > "$pe/still-bad.txt"
if petry; then bad "m17 pair: a real unlisted address must still be refused"; else ok; git -C "$pe" reset -q; rm -f "$pe/still-bad.txt"; fi
refuse_n=$((refuse_n+1))
SHORT_HOME="$T/fakehome-short"; mkdir -p "$SHORT_HOME/.claude/hooks"
cp "$FAKE_HOME/.claude/hooks/backup.conf" "$SHORT_HOME/.claude/hooks/backup.conf"
printf 'Zeb\nword:Quixote\n' > "$SHORT_HOME/.claude/.redaction-names.local"
sn29="$T/shortnames"; mkdir -p "$sn29"; git -C "$sn29" init -q -b main; git -C "$sn29" config core.hooksPath "$GIT_HOOKS_DIR"
sntry() { git -C "$sn29" add -A; env HOME="$SHORT_HOME" "${ID[@]}" git -C "$sn29" commit -q -m t >/dev/null 2>&1; }
echo seed > "$sn29/seed.txt"; sntry
echo "the word Zebulon appears here" > "$sn29/a.txt"
if sntry; then ok; else bad "m17 a listed name under six characters must match only as a WHOLE word"; fi
pass_n=$((pass_n+1))
echo "Zeb was here" > "$sn29/b.txt"
if sntry; then bad "m17 pair: the short name on its own must still be refused"; else ok; git -C "$sn29" reset -q; rm -f "$sn29/b.txt"; fi
refuse_n=$((refuse_n+1))
echo "several Quixotes appeared" > "$sn29/c.txt"
if sntry; then ok; else bad "m17 a word:-marked entry must match only as a whole word"; fi
pass_n=$((pass_n+1))
echo "Quixote appeared" > "$sn29/d.txt"
if sntry; then bad "m17 pair: the word:-marked entry on its own must be refused"; else ok; git -C "$sn29" reset -q; rm -f "$sn29/d.txt"; fi
refuse_n=$((refuse_n+1))

# --- m19 the channel ceiling must count an ADDED file too ------------------------------
CEIL29="$T/fakehome-ceil29"; mkdir -p "$CEIL29/.claude/hooks"
: > "$CEIL29/.claude/.redaction-names.local"
printf 'LIMIT=20\nNOTES.md\n' > "$CEIL29/.claude/hooks/channel-ceiling.conf"
cr29="$T/ceil29repo"; mkdir -p "$cr29"; git -C "$cr29" init -q -b main; git -C "$cr29" config core.hooksPath "$GIT_HOOKS_DIR"
c29try() { git -C "$cr29" add -A >/dev/null 2>&1; env HOME="$CEIL29" "${ID[@]}" git -C "$cr29" commit -q -m t >/dev/null 2>&1; }
echo seed > "$cr29/README.md"; c29try
python3 -c "print('\n'.join(['line']*50))" > "$cr29/NOTES.md"
if c29try; then bad "m19 a brand-new NOTES.md of 50 lines must be refused by the ceiling"; else ok; git -C "$cr29" reset -q; rm -f "$cr29/NOTES.md"; fi
refuse_n=$((refuse_n+1))
python3 -c "print('\n'.join(['line']*50))" > "$cr29/NOTES-ARCHIVE-2026-09.md"
if c29try; then ok; else bad "m19 pair: a new ARCHIVE file is exempt whatever its size"; fi
pass_n=$((pass_n+1))
python3 -c "print('\n'.join(['line']*50))" > "$cr29/OTHER.md"
if c29try; then ok; else bad "m19 pair: a new file outside the conf's list must pass"; fi
pass_n=$((pass_n+1))

# --- m20 a zero-width character inside a listed name --------------------------------
printf 'met Zebulon%sQuixote today\n' "$ZWSP29" > "$pr/zw.txt"
if ptry; then bad "m20 a zero-width character inside a listed name must not hide it"; else ok; git -C "$pr" reset -q; rm -f "$pr/zw.txt"; fi
refuse_n=$((refuse_n+1))
printf 'an ord%sinary word is still fine\n' "$ZWSP29" > "$pr/zw2.txt"
if ptry; then ok; else bad "m20 pair: a zero-width inside an unlisted word must still pass"; fi
pass_n=$((pass_n+1))

# --- m21 pre-push: a missing toolchain is not a type error -----------------------------
mkrepo tcmissing "definitely-not-a-real-binary-zzq --noEmit"
pperr29="$(git -C "$T/tcmissing" push origin main 2>&1 1>/dev/null)"
if printf '%s' "$pperr29" | grep -qi 'toolchain'; then ok; else bad "m21 a missing toolchain must say so, not 'fix the types' (got: $pperr29)"; fi
refuse_n=$((refuse_n+1))
if git -C "$T/tcmissing" push -q origin main 2>/dev/null; then bad "m21 a missing toolchain must still REFUSE the push"; else ok; fi
refuse_n=$((refuse_n+1))
mkrepo tctypeerr "exit 1"
pperr29b="$(git -C "$T/tctypeerr" push origin main 2>&1 1>/dev/null)"
if printf '%s' "$pperr29b" | grep -qi 'Fix the types'; then ok; else bad "m21 pair: a genuine type failure must still say 'Fix the types' (got: $pperr29b)"; fi
pass_n=$((pass_n+1))

echo "29b install.sh: a guard needing BOTH jq and python3 is registered only when both are there"
IH1="$T/inst-home-both"; mkdir -p "$IH1"
env HOME="$IH1" bash "$REPO29/install.sh" --yes >/dev/null 2>&1
if grep -q 'block-dangerous-git.sh' "$IH1/.claude/settings.json" 2>/dev/null; then ok; else bad "29b with jq and python3 both present the Bash guards must be registered"; fi
pass_n=$((pass_n+1))
if grep -q 'channel-size-post.sh' "$IH1/.claude/settings.json" 2>/dev/null; then ok; else bad "29b the PostToolUse size re-measure must be registered next to the pre hook"; fi
pass_n=$((pass_n+1))
IH2="$T/inst-home-nojq"; mkdir -p "$IH2"
env HOME="$IH2" INSTALL_PRETEND_MISSING=jq bash "$REPO29/install.sh" --yes >/dev/null 2>&1
if grep -q 'block-dangerous-git.sh' "$IH2/.claude/settings.json" 2>/dev/null; then bad "29b with jq missing, the guards that need BOTH must NOT be registered"; else ok; fi
refuse_n=$((refuse_n+1))
if grep -q 'gate-guard.sh' "$IH2/.claude/settings.json" 2>/dev/null; then ok; else bad "29b pair: gate-guard.sh needs only python3, so it must still be registered"; fi
pass_n=$((pass_n+1))


echo "30 blind-attacker findings (part 3): the parsers, the IFS spelling, per-segment overrides"
REPO30="$(cd "$HOOKS_DIR/.." && pwd -P)"
r30="$T/h30-commit"; mkdir -p "$r30"; git -C "$r30" init -q -b main; git -C "$r30" config core.hooksPath /dev/null
echo a > "$r30/a.txt"; git -C "$r30" add -A; "${ID[@]}" git -C "$r30" commit -q -m init
echo b > "$r30/b.txt"; git -C "$r30" add b.txt      # another session's staged file
jb30() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$2"; }
# ex30 <refuse|pass> <want> <label> <command> [runner...]  (default runner: commit-pathspec-guard)
ex30() { local kind="$1" want="$2" label="$3" c="$4"; shift 4
  if [ "$#" = 0 ]; then set -- bash "$HOOKS_DIR/commit-pathspec-guard.sh"; fi
  jb30 "$c" "$r30" | "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then ok; else bad "$label (wanted exit $want, got $got)"; fi
  if [ "$kind" = refuse ]; then refuse_n=$((refuse_n+1)); else pass_n=$((pass_n+1)); fi; }

# --- D1 a parser that EXISTS but fails: the substitution is empty, the guard must REFUSE -
PYBAD30="$T/h30-badpy"; mkdir -p "$PYBAD30"
printf '#!/bin/sh\nexit 1\n' > "$PYBAD30/python3"; chmod +x "$PYBAD30/python3"
PYQ30="$T/h30-quietpy"; mkdir -p "$PYQ30"
printf '#!/bin/sh\nexit 0\n' > "$PYQ30/python3"; chmod +x "$PYQ30/python3"
INPUT="$(json_bash 'git reset --hard')"
expect refuse 2 "D1 python3 present but failing: block-dangerous-git must REFUSE" env GUARD_PYTHON_PREFERRED=/nonexistent/python3 PATH="$PYBAD30:$PATH" bash "$HOOKS_DIR/block-dangerous-git.sh"
expect refuse 2 "D1 a python3 that exits 0 printing nothing must REFUSE too" env GUARD_PYTHON_PREFERRED=/nonexistent/python3 PATH="$PYQ30:$PATH" bash "$HOOKS_DIR/block-dangerous-git.sh"
err30="$(printf '%s' "$INPUT" | env GUARD_PYTHON_PREFERRED=/nonexistent/python3 PATH="$PYBAD30:$PATH" bash "$HOOKS_DIR/block-dangerous-git.sh" 2>&1 1>/dev/null)"
if printf '%s' "$err30" | grep -qi 'parse'; then ok; else bad "D1 the refusal must say the guard could not parse its input (got: '$err30')"; fi
refuse_n=$((refuse_n+1))
# --- D1b the PREFERRED interpreter exists but fails (a Mac without the Command Line Tools ships
# /usr/bin/python3 as a stub that exits non-zero): the resolver must fall back to a working python3
# on PATH instead of failing every guard closed; a failing PATH python3 still fails closed.
INPUT="$(json_bash 'ls -la')"
expect pass 0 "D1b stub preferred python, working python3 on PATH: an ordinary command must pass" env GUARD_PYTHON_PREFERRED="$PYBAD30/python3" bash "$HOOKS_DIR/block-dangerous-git.sh"
INPUT="$(json_bash 'git reset --hard')"
expect refuse 2 "D1b stub preferred python, working python3 on PATH: a destructive command is still refused" env GUARD_PYTHON_PREFERRED="$PYBAD30/python3" bash "$HOOKS_DIR/block-dangerous-git.sh"
INPUT="$(json_bash 'ls -la')"
expect refuse 2 "D1b stub preferred AND failing PATH python3: still fails closed" env GUARD_PYTHON_PREFERRED="$PYBAD30/python3" PATH="$PYBAD30:$PATH" bash "$HOOKS_DIR/block-dangerous-git.sh"
INPUT="$(json_bash 'npm test')"
expect refuse 2 "D1 python3 present but failing: heavy-suite-guard must REFUSE" env GUARD_PYTHON_PREFERRED=/nonexistent/python3 PATH="$PYBAD30:$PATH" HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HOOKS_DIR/heavy-suite-guard.sh"
ex30 refuse 2 "D1 python3 present but failing: commit-pathspec-guard must REFUSE" 'git commit --all -m x' env GUARD_PYTHON_PREFERRED=/nonexistent/python3 PATH="$PYBAD30:$PATH" bash "$HOOKS_DIR/commit-pathspec-guard.sh"
ex30 refuse 2 "D1 a silent python3 must not let a sweep through either" 'git commit --all -m x' env GUARD_PYTHON_PREFERRED=/nonexistent/python3 PATH="$PYQ30:$PATH" bash "$HOOKS_DIR/commit-pathspec-guard.sh"
INPUT="$(json_bash 'npm test | tee out.log && git commit -m x')"
expect refuse 2 "D1 gate-guard with a failing python3 stays closed" env GUARD_PYTHON_PREFERRED=/nonexistent/python3 PATH="$PYBAD30:$PATH" bash "$HOOKS_DIR/gate-guard.sh"
INPUT="$(json_bash 'git status')"; expect pass 0 "D1 pair: with a working python3 a safe git command passes" bash "$HOOKS_DIR/block-dangerous-git.sh"
INPUT="$(json_bash 'ls')"; expect pass 0 "D1 pair: heavy-suite-guard still allows an ordinary command" env HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HOOKS_DIR/heavy-suite-guard.sh"
ex30 pass 0 "D1 pair: a named-path commit still passes" 'git commit b.txt -m x'

# --- D2 ${IFS} as a word separator, and a command word hidden in a variable -------------
for c in 'git${IFS}reset${IFS}--hard' 'git $IFS reset --hard' 'GIT=git; $GIT reset --hard' 'G=git; ${G} push --force origin main'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "D2 must refuse: $c" bash "$HOOKS_DIR/block-dangerous-git.sh"; done
for c in 'git${IFS}status' 'echo "${IFS}"' 'W=x; $W/bin/lint.sh --fix' 'git status && echo ok'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "D2 pair, must allow: $c" bash "$HOOKS_DIR/block-dangerous-git.sh"; done
ex30 refuse 2 "D2 a commit --all spelled with \${IFS} must be refused" 'git${IFS}commit${IFS}--all -m x'
ex30 refuse 2 "D2 a commit whose git comes from a variable must be refused" 'G=git; $G commit --all -m x'
ex30 pass 0 "D2 pair: a substituted binary that does not commit still passes" '$(which git) status'
ex30 pass 0 "D2 pair: a variable-named tool that does not commit passes" 'W=x; $W/bin/lint.sh --fix'
for c in 'npm${IFS}test' 'T=npm; $T test'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "D2 load 25 must refuse: $c" env HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HOOKS_DIR/heavy-suite-guard.sh"; done
for c in 'npm${IFS}run${IFS}typecheck' 'W=x; $W/bin/lint.sh --fix'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "D2 pair, load 25 must allow: $c" env HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HOOKS_DIR/heavy-suite-guard.sh"; done
INPUT="$(json_bash 'npx${IFS}tsc${IFS}--noEmit | head && git commit -m x')"
expect refuse 2 "D2 gate-guard: a gate spelled with \${IFS} piped into a reader must refuse" bash "$HOOKS_DIR/gate-guard.sh"
INPUT="$(json_bash 'npx${IFS}tsc${IFS}--noEmit && git commit -m x f.ts')"
expect pass 0 "D2 pair: the same gate joined with && must pass" bash "$HOOKS_DIR/gate-guard.sh"

# --- D3 the override must stand at the start of the SAME segment that matched -----------
OL30="$T/h30-ovl.tsv"
for c in 'git push --force && GITGUARD=1 true' 'git push --force; GITGUARD=1 true' 'git reset --hard
GITGUARD=1 true'; do
  rm -f "$OL30"; INPUT="$(json_bash "$c")"
  expect refuse 2 "D3 an override on a LATER segment must not disarm: $c" env OVERRIDE_LEDGER="$OL30" bash "$HOOKS_DIR/block-dangerous-git.sh"; done
rm -f "$OL30"; INPUT="$(json_bash 'echo start && GITGUARD=1 git reset --hard')"
expect pass 0 "D3 pair: the override at the start of the matched segment still passes" env OVERRIDE_LEDGER="$OL30" bash "$HOOKS_DIR/block-dangerous-git.sh"
if [ -f "$OL30" ]; then ok; else bad "D3 pair: that honoured override must still write its ledger line"; fi
pass_n=$((pass_n+1))
rm -f "$OL30"; INPUT="$(json_bash 'GITGUARD=1 git reset --hard')"
expect pass 0 "D3 pair: the override at the start of the command still passes" env OVERRIDE_LEDGER="$OL30" bash "$HOOKS_DIR/block-dangerous-git.sh"
rm -f "$OL30"
ex30 refuse 2 "D3 SWEEP on a later segment must not disarm the sweep refusal" 'git commit -a -m x && SWEEP=1 true' env OVERRIDE_LEDGER="$OL30" bash "$HOOKS_DIR/commit-pathspec-guard.sh"
ex30 pass 0 "D3 pair: SWEEP at the start of the commit's own segment passes" 'echo start && SWEEP=1 git commit -m x' env OVERRIDE_LEDGER="$OL30" bash "$HOOKS_DIR/commit-pathspec-guard.sh"
rm -f "$OL30"; INPUT="$(json_bash 'SUITE_OK=1 true && npm test')"
expect refuse 2 "D3 SUITE_OK on another segment must not disarm the load guard" env OVERRIDE_LEDGER="$OL30" HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HOOKS_DIR/heavy-suite-guard.sh"
rm -f "$OL30"; INPUT="$(json_bash 'cd apps/web && SUITE_OK=1 npm test')"
expect pass 0 "D3 pair: SUITE_OK on the heavy segment itself passes" env OVERRIDE_LEDGER="$OL30" HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HOOKS_DIR/heavy-suite-guard.sh"
rm -f "$OL30"; INPUT="$(json_bash 'GATE_OK=1 true && npm test | tee out.log && git commit -m x')"
expect refuse 2 "D3 GATE_OK on another segment must not disarm gate-guard" env OVERRIDE_LEDGER="$OL30" bash "$HOOKS_DIR/gate-guard.sh"
rm -f "$OL30"; INPUT="$(json_bash 'GATE_OK=1 npm test | tee out.log && git commit -m x')"
expect pass 0 "D3 pair: GATE_OK on the gate's own segment still passes" env OVERRIDE_LEDGER="$OL30" bash "$HOOKS_DIR/gate-guard.sh"

# --- D4 a NUL byte inside a --pathspec-from-file list ----------------------------------
python3 -c 'import sys;open(sys.argv[1],"wb").write(b"b.txt\x00.\x00")' "$r30/nul-list.txt"
ex30 refuse 2 "D4 a NUL-separated list naming the whole tree must be REFUSED, not crash open" 'git commit --pathspec-from-file=nul-list.txt -m x'
python3 -c 'import sys;open(sys.argv[1],"wb").write(b"b.txt\x00")' "$r30/nul-ok.txt"
ex30 pass 0 "D4 pair: a NUL-separated list naming one file passes" 'git commit --pathspec-from-file=nul-ok.txt -m x'
printf 'b.txt\n' > "$r30/plain-list.txt"
ex30 pass 0 "D4 pair: a plain newline list naming one file still passes" 'git commit --pathspec-from-file=plain-list.txt -m x'

# --- D5 git-hooks/pre-push: the identity of every commit being pushed -------------------
AN_DOM30="$(printf '%s%s' anthro pic).com"   # built at runtime: no literal address in this file
CLA30="noreply@$AN_DOM30"
mkrepo idreb ""
git -C "$T/idreb" push -q origin main 2>/dev/null
git -C "$T/idreb" checkout -q -b rb; echo x > "$T/idreb/rb.txt"; git -C "$T/idreb" add -A; "${ID[@]}" git -C "$T/idreb" commit -q -m rb
git -C "$T/idreb" checkout -q main; echo y > "$T/idreb/y.txt"; git -C "$T/idreb" add -A; "${ID[@]}" git -C "$T/idreb" commit -q -m main2
git -C "$T/idreb" push -q origin main 2>/dev/null
env GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.com GIT_COMMITTER_NAME=Claude GIT_COMMITTER_EMAIL="$CLA30" git -C "$T/idreb" rebase -q main rb >/dev/null 2>&1
if git -C "$T/idreb" push -q origin rb 2>/dev/null; then bad "D5 a rebase that wrote a Claude COMMITTER must be refused at push"; else ok; fi
refuse_n=$((refuse_n+1))
pperr30="$(git -C "$T/idreb" push origin rb 2>&1 1>/dev/null)"
if printf '%s' "$pperr30" | grep -qi 'committer\|identity'; then ok; else bad "D5 the refusal must name the identity it found (got: $pperr30)"; fi
refuse_n=$((refuse_n+1))
mkrepo idreb2 ""
git -C "$T/idreb2" push -q origin main 2>/dev/null
git -C "$T/idreb2" checkout -q -b rb2; echo x > "$T/idreb2/rb.txt"; git -C "$T/idreb2" add -A; "${ID[@]}" git -C "$T/idreb2" commit -q -m rb
git -C "$T/idreb2" checkout -q main; echo y > "$T/idreb2/y.txt"; git -C "$T/idreb2" add -A; "${ID[@]}" git -C "$T/idreb2" commit -q -m main2
git -C "$T/idreb2" push -q origin main 2>/dev/null
"${ID[@]}" git -C "$T/idreb2" rebase -q main rb2 >/dev/null 2>&1
if git -C "$T/idreb2" push -q origin rb2 2>/dev/null; then ok; else bad "D5 pair: the same rebase with an ordinary identity must still push"; fi
pass_n=$((pass_n+1))
mkrepo idauth ""
echo z > "$T/idauth/z.txt"; git -C "$T/idauth" add -A
"${ID[@]}" git -C "$T/idauth" commit -q --author="Claude <$CLA30>" -m "authored elsewhere" >/dev/null 2>&1
if git -C "$T/idauth" push -q origin main 2>/dev/null; then bad "D5 a commit whose AUTHOR names Claude must be refused at push"; else ok; fi
refuse_n=$((refuse_n+1))

# --- D6 a bytes band in channel-ceiling.conf must be enforced by the PRE hook -----------
CSZ30="$T/csz30"; mkdir -p "$CSZ30"; cp "$HOOKS_DIR/channel-size-guard.sh" "$CSZ30/"
printf 'LIMIT=100\nNOTES.md bytes 100 200\n' > "$CSZ30/channel-ceiling.conf"
d30="$T/csz30repo"; mkdir -p "$d30"
python3 -c "import sys;open(sys.argv[1],'w').write('x'*300)" "$d30/NOTES.md"   # 300 bytes, ONE line
big30="$(python3 -c "print('y'*300, end='')")"
INPUT="$(jw "$d30/NOTES.md" "$big30")"; expect refuse 2 "D6 a Write growing a file over its BYTES hard stop must be REFUSED" bash "$CSZ30/channel-size-guard.sh"
INPUT="$(jb2 'echo x >> NOTES.md' "$d30")"; expect refuse 2 "D6 a Bash append onto a file over its BYTES hard stop must be REFUSED" bash "$CSZ30/channel-size-guard.sh"
small30="$(python3 -c "print('y'*50, end='')")"
INPUT="$(jw "$d30/NOTES.md" "$small30")"; expect pass 0 "D6 pair: a Write SHRINKING it under the byte stop must be ALLOWED" bash "$CSZ30/channel-size-guard.sh"
python3 -c "import sys;open(sys.argv[1],'w').write('x'*50)" "$d30/NOTES.md"
INPUT="$(jb2 'echo x >> NOTES.md' "$d30")"; expect pass 0 "D6 pair: an append onto a small file must be ALLOWED" bash "$CSZ30/channel-size-guard.sh"

# --- D7 the SHIPPED heavy-suite.conf.example, copied as the live conf -------------------
HSX30="$T/h30-example-conf"; mkdir -p "$HSX30"
cp "$HOOKS_DIR/heavy-suite-guard.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/override-ledger.sh" "$HSX30/"
cp "$REPO30/hooks/heavy-suite.conf.example" "$HSX30/heavy-suite.conf"
for c in 'yarn test' 'pnpm test' 'npm run test:all' 'npm test' 'npx vitest run'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "D7 shipped example conf, load 25 must refuse: $c" env HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HSX30/heavy-suite-guard.sh"; done
for c in 'npm run typecheck' 'yarn lint' 'ls'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "D7 pair, shipped example conf, load 25 must allow: $c" env HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HSX30/heavy-suite-guard.sh"; done


echo "31 confirmation-pass findings (part 4): the size projection, hidden sub-words, wrappers, the ledger"
REPO31="$(cd "$HOOKS_DIR/.." && pwd -P)"

# --- E1 an Edit/MultiEdit whose DELTA carries the file past its hard stop ---------------
# The band compare used the file's CURRENT size for an Edit, so a 601-byte insertion into
# a 1500-byte file with a 2000-byte stop was a WARNING and the file landed at 2100.
CSZ31="$T/csz31"; mkdir -p "$CSZ31"; cp "$HOOKS_DIR/channel-size-guard.sh" "$CSZ31/"
printf 'LIMIT=100\nBIG.md bytes 1000 2000\n' > "$CSZ31/channel-ceiling.conf"
d31="$T/csz31repo"; mkdir -p "$d31"
python3 -c "import sys;open(sys.argv[1],'w').write('x'*899 + 'M' + 'x'*600)" "$d31/BIG.md"   # 1500 bytes: over band, under stop
ins31="$(python3 -c "print('y'*601, end='')")"
INPUT="$(je "$d31/BIG.md" "M" "$ins31")"; expect refuse 2 "E1 an Edit whose delta carries BIG.md past its BYTE hard stop must be REFUSED" bash "$CSZ31/channel-size-guard.sh"
INPUT="$(jm "$d31/BIG.md" "M" "$ins31")"; expect refuse 2 "E1 the same delta spelled as a MultiEdit must be REFUSED" bash "$CSZ31/channel-size-guard.sh"
INPUT="$(je "$d31/BIG.md" "$ins31" "M")"; expect pass 0 "E1 pair: the same Edit REMOVING those bytes must be ALLOWED" bash "$CSZ31/channel-size-guard.sh"
INPUT="$(je "$d31/BIG.md" "M" "MM")"; expect pass 0 "E1 pair: a one-byte growth still inside the band must be ALLOWED" bash "$CSZ31/channel-size-guard.sh"
w31="$(python3 -c "print(' '.join(['w']*15))")"
d31w="$T/csz31words"; mkdir -p "$d31w"; printf '%s' "$w31" > "$d31w/NOTES.md"
INPUT="$(je "$d31w/NOTES.md" "w" "$(python3 -c "print(' '.join(['n']*8))")")"
expect refuse 2 "E1 the same hole in a WORDS band (15 words, stop 20, +7) must be REFUSED" bash "$CSZ/channel-size-guard.sh"
INPUT="$(je "$d31w/NOTES.md" "w" "n")"; expect pass 0 "E1 pair: a word-for-word Edit inside the band must be ALLOWED" bash "$CSZ/channel-size-guard.sh"

# --- E2 a hidden SUB-command word: git is plain, its ARGUMENT is a substitution ---------
for c in 'R=reset; git $R --hard' 'F=--force; git push origin $F' 'git ${SUB} --hard' 'git reset `echo --hard`'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "E2 must refuse, a git argument only the shell can expand: $c" bash "$HOOKS_DIR/block-dangerous-git.sh"; done
for c in 'git commit -m "$msg" file.ts' 'git log --author="$me"' 'git status' 'W=x; $W/bin/lint.sh --fix'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "E2 pair, must allow: $c" bash "$HOOKS_DIR/block-dangerous-git.sh"; done
ex30 refuse 2 "E2 a commit whose SUBCOMMAND comes from a variable must be refused" 'C=commit; git $C -a -m x'
ex30 refuse 2 "E2 a commit whose PATHSPEC comes from a variable must be refused" 'git commit $paths -m x'
ex30 pass 0 "E2 pair: a substitution only inside the message still passes" 'git commit -m "$msg" b.txt'
ex30 pass 0 "E2 pair: a substitution only inside a quoted value still passes" 'git log --author="$me"'
rm -f "$T/h31-ovl.tsv"; INPUT="$(json_bash 'GITGUARD=1 git $R --hard')"
expect pass 0 "E2 pair: an approved run of the same command still passes" env OVERRIDE_LEDGER="$T/h31-ovl.tsv" bash "$HOOKS_DIR/block-dangerous-git.sh"

# --- E3 eval / sh -c / bash -c handed something only the shell can expand ----------------
for c in 'eval "$cmd"' 'eval $cmd' 'sh -c "$CMD"' 'bash -c "$(cat run.sh)"' 'eval `cat run.sh`'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "E3 must refuse, a wrapper handed a substitution: $c" bash "$HOOKS_DIR/block-dangerous-git.sh"; done
for c in 'bash -c '"'"'ls -la'"'"'' 'sh -c '"'"'git status'"'"'' 'eval "git status"' 'bash -c "npm run typecheck"'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "E3 pair, a wrapper handed plain text: $c" bash "$HOOKS_DIR/block-dangerous-git.sh"; done

# --- E4 the ledger records an override only where it actually waived something ----------
OL31="$T/h31-ovl.tsv"
rm -f "$OL31"; INPUT="$(json_bash 'GITGUARD=1 true; git push --force')"
expect refuse 2 "E4 an override in front of a harmless segment must not disarm the force-push" env OVERRIDE_LEDGER="$OL31" bash "$HOOKS_DIR/block-dangerous-git.sh"
if [ -f "$OL31" ]; then bad "E4 a REFUSED command must leave NO ledger line (that override waived nothing)"; else ok; fi
refuse_n=$((refuse_n+1))
rm -f "$OL31"; INPUT="$(json_bash 'GITGUARD=1 git push --force origin main')"
expect pass 0 "E4 pair: the override in front of the force-push itself still passes" env OVERRIDE_LEDGER="$OL31" bash "$HOOKS_DIR/block-dangerous-git.sh"
if [ -f "$OL31" ]; then ok; else bad "E4 pair: an honoured override must still write its ledger line"; fi
pass_n=$((pass_n+1))
rm -f "$OL31"; INPUT="$(json_bash 'SUITE_OK=1 true && npm test')"
expect refuse 2 "E4 the same shape in heavy-suite-guard must still be refused" env OVERRIDE_LEDGER="$OL31" HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HOOKS_DIR/heavy-suite-guard.sh"
if [ -f "$OL31" ]; then bad "E4 heavy-suite: a REFUSED command must leave NO ledger line"; else ok; fi
refuse_n=$((refuse_n+1))
rm -f "$OL31"; INPUT="$(json_bash 'SUITE_OK=1 npm test')"
expect pass 0 "E4 pair: SUITE_OK on the heavy segment itself still passes" env OVERRIDE_LEDGER="$OL31" HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HOOKS_DIR/heavy-suite-guard.sh"
if [ -f "$OL31" ]; then ok; else bad "E4 pair: heavy-suite must still log an honoured SUITE_OK"; fi
pass_n=$((pass_n+1))
rm -f "$OL31"

# --- E5 the quoted-text trade-off, stated in INSTALL.md ---------------------------------
INPUT="$(json_bash 'echo "git reset --hard is dangerous"')"
expect refuse 2 "E5 the documented trade-off: a command merely QUOTING a dangerous git command is refused" bash "$HOOKS_DIR/block-dangerous-git.sh"
INPUT="$(json_bash 'echo "git reset --hardly"')"
expect pass 0 "E5 pair: quoted text that is not a dangerous command still passes" bash "$HOOKS_DIR/block-dangerous-git.sh"
if grep -qF 'merely quotes a dangerous git command' "$REPO31/INSTALL.md"; then ok; else bad "E5 INSTALL.md must state that quoted text is inspected too"; fi
pass_n=$((pass_n+1))
if grep -rlF 'merely quotes a dangerous git command' "$REPO31"/*.md | grep -qv '/INSTALL.md$'; then bad "E5 pair: that sentence belongs in INSTALL.md's own guard description"; else ok; fi
refuse_n=$((refuse_n+1))

# --- E6 git-hooks/pre-push: the article in front of the role it names --------------------
autherr31="$(git -C "$T/idauth" push origin main 2>&1 1>/dev/null)"
if printf '%s' "$autherr31" | grep -q 'has an author'; then ok; else bad "E6 the author refusal must read 'has an author' (got: $autherr31)"; fi
refuse_n=$((refuse_n+1))
if printf '%s' "$autherr31" | grep -q 'has a author'; then bad "E6 'has a author' must be gone"; else ok; fi
pass_n=$((pass_n+1))
comerr31="$(git -C "$T/idreb" push origin rb 2>&1 1>/dev/null)"
if printf '%s' "$comerr31" | grep -q 'has a committer'; then ok; else bad "E6 pair: the committer half must still read 'has a committer' (got: $comerr31)"; fi
pass_n=$((pass_n+1))


# ======================================================================================
echo "refresh 2026-09-29 (a): command-guard behaviours ported from the maintainer's live setup (A01 A06 A07 A08 A11 A12 A16 A17 A18 A21 A22 A23 A85)"
BDG="$HOOKS_DIR/block-dangerous-git.sh"
RAL="$T/ra-ledger.tsv"
ra_ledger_has() { [ -f "$1" ] || return 1; cut -f3 "$1" | grep -qxF "$2"; }

# --- A01 a variable elsewhere on a git line is an honest read; only a hidden SUBCOMMAND (or
#     the arguments of a mutating one) cannot be judged ----------------------------------
for c in 'git diff HEAD -- $paths' 'W=/tmp/x; git -C $W/repo status' 'git log --oneline -$n'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "A01 a variable in a read-only git command must pass: $c" bash "$BDG"; done
for c in 'V=push; git $V --force origin main' 'V=reset; git -C /x $V --hard' 'git -C $W/repo push origin $F'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "A01 pair: a hidden subcommand, or a hidden argument of push, is still refused: $c" bash "$BDG"; done
ex30 pass 0 "A01 commit-pathspec-guard: git diff HEAD -- \$paths is a read, not a commit" 'git diff HEAD -- $paths'
ex30 pass 0 "A01 commit-pathspec-guard: git -C \$W/repo status is not a commit" 'W=/tmp/x; git -C $W/repo status'
ex30 refuse 2 "A01 pair: a commit whose pathspec is a variable is still refused" 'git commit $paths -m x'

# --- A06 --no-verify and -c core.hooksPath= switch off every other hook -----------------
for c in 'git commit -m x f --no-verify' 'git -c core.hooksPath=/dev/null commit -m x f' 'git push --no-verify origin main' 'cd sub && git commit --no-verify -m y'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "A06 must refuse the off-switch: $c" env OVERRIDE_LEDGER="$RAL" bash "$BDG"; done
for c in 'git commit -m x f' 'echo "git commit --no-verify"' 'printf "%s" "git -c core.hooksPath=/dev/null commit"' 'git log --grep="--no-verify"' 'git commit -m "never use --no-verify" f'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "A06 pair: honest work and quoted mentions pass: $c" env OVERRIDE_LEDGER="$RAL" bash "$BDG"; done
rm -f "$RAL"; INPUT="$(json_bash 'GITGUARD=1 git commit --no-verify -m x f')"
expect pass 0 "A06 GITGUARD=1 at the start of the segment approves the off-switch" env OVERRIDE_LEDGER="$RAL" bash "$BDG"
if [ -f "$RAL" ]; then ok; else bad "A06 an honoured off-switch override must write its ledger line"; fi; pass_n=$((pass_n+1))
rm -f "$RAL"; INPUT="$(json_bash 'git commit --no-verify -m x f && GITGUARD=1 true')"
expect refuse 2 "A06 an override on a LATER segment must not approve the off-switch" env OVERRIDE_LEDGER="$RAL" bash "$BDG"
RA_NOWRITE="$T/ra-nowrite"; mkdir -p "$RA_NOWRITE"; chmod 555 "$RA_NOWRITE"
INPUT="$(json_bash 'GITGUARD=1 git commit --no-verify -m x f')"
expect refuse 2 "A06 an override whose ledger line cannot be written is refused" env OVERRIDE_LEDGER="$RA_NOWRITE/sub/overrides.tsv" bash "$BDG"
chmod 755 "$RA_NOWRITE"

# --- A07 the going-public stop ----------------------------------------------------------
for c in 'gh repo create x --public' 'gh repo create --public x' 'gh repo edit --visibility public' 'gh repo edit x --visibility=public' 'npm publish' 'npm publish --access public' 'cd pkg && npm publish'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "A07 must refuse making something public: $c" env OVERRIDE_LEDGER="$RAL" bash "$BDG"; done
for c in 'gh repo create x --private' 'gh repo view x' 'gh repo edit --visibility private' 'npm publish --dry-run' 'npm publish --dry-run=true' 'npm help publish' 'echo "npm publish"' 'gh pr create --title "run npm publish later" --body "gh repo create x --public"' 'git commit -m "npm publish notes" f'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "A07 pair: private, read-only, dry-run and quoted mentions pass: $c" env OVERRIDE_LEDGER="$RAL" bash "$BDG"; done
rm -f "$RAL"; INPUT="$(json_bash 'GITGUARD=1 npm publish')"
expect pass 0 "A07 GITGUARD=1 at the start of the segment approves the publish" env OVERRIDE_LEDGER="$RAL" bash "$BDG"
if ra_ledger_has "$RAL" GITGUARD; then ok; else bad "A07 an honoured going-public override must write its ledger line"; fi; pass_n=$((pass_n+1))
ra7err="$(printf '%s' "$(json_bash 'npm publish')" | env OVERRIDE_LEDGER="$RAL" bash "$BDG" 2>&1 1>/dev/null)"
if printf '%s' "$ra7err" | grep -q 'privacy check' && printf '%s' "$ra7err" | grep -q 'security review'; then ok; else bad "A07 the refusal must list the steps before going public (got: $ra7err)"; fi; refuse_n=$((refuse_n+1))

# --- A08 deleting a remote branch is judged by what it holds, not refused blindly -------
RA_BARE="$T/ra-bare.git"; git init -q --bare -b main "$RA_BARE" >/dev/null 2>&1
RA_WC="$T/ra-wc"; git clone -q "$RA_BARE" "$RA_WC" >/dev/null 2>&1
git -C "$RA_WC" config core.hooksPath /dev/null
echo base > "$RA_WC/a.txt"; git -C "$RA_WC" add -A; "${ID[@]}" git -C "$RA_WC" commit -q -m base; git -C "$RA_WC" push -q origin main >/dev/null 2>&1
ra_branch() { git -C "$RA_WC" checkout -q -b "$1" >/dev/null 2>&1
  if [ -n "$2" ]; then echo "$1" >> "$RA_WC/a.txt"; git -C "$RA_WC" add -A; "${ID[@]}" git -C "$RA_WC" commit -q -m "$1"; fi
  git -C "$RA_WC" push -q origin "$1" >/dev/null 2>&1; git -C "$RA_WC" checkout -q main >/dev/null 2>&1; }
ra_branch ra-clean; ra_branch ra-clean2; ra_branch ra-clean3; ra_branch ra-clean4; ra_branch ra-dirty unique; ra_branch ra-stale
rdel() { local kind="$1" want="$2" label="$3" c="$4" cwd="$5"   # judged in cwd, ledger in $RAL
  jb30 "$c" "$cwd" | env OVERRIDE_LEDGER="$RAL" bash "$BDG" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then ok; else bad "$label (wanted exit $want, got $got)"; fi
  if [ "$kind" = refuse ]; then refuse_n=$((refuse_n+1)); else pass_n=$((pass_n+1)); fi; }
rdel pass 0 "A08 deleting a branch fully merged into origin's default passes with no override" 'git push origin --delete ra-clean' "$RA_WC"
rdel pass 0 "A08 the -d spelling of a clean delete passes" 'git push origin -d ra-clean' "$RA_WC"
rdel pass 0 "A08 the flag BEFORE the remote passes" 'git push --delete origin ra-clean' "$RA_WC"
rdel pass 0 "A08 the :branch spelling of a clean delete passes" 'git push origin :ra-clean' "$RA_WC"
rdel pass 0 "A08 a refs/heads/ spelling of a clean delete passes" 'git push origin --delete refs/heads/ra-clean' "$RA_WC"
rdel pass 0 "A08 several clean branches at once pass" 'git push origin --delete ra-clean ra-clean2' "$RA_WC"
rdel refuse 2 "A08 a branch holding commits main does not have is refused" 'git push origin --delete ra-dirty' "$RA_WC"
rdel refuse 2 "A08 the -d spelling of a dirty delete is refused" 'git push origin -d ra-dirty' "$RA_WC"
rdel refuse 2 "A08 the flag before the remote, dirty, is refused" 'git push --delete origin ra-dirty' "$RA_WC"
rdel refuse 2 "A08 the :branch spelling of a dirty delete is refused" 'git push origin :ra-dirty' "$RA_WC"
rdel refuse 2 "A08 EVERY named branch is checked: clean first, dirty second" 'git push origin --delete ra-clean ra-dirty' "$RA_WC"
rdel refuse 2 "A08 a branch origin never had cannot be judged and is refused" 'git push origin --delete ra-ghost-never-existed' "$RA_WC"
rdel refuse 2 "A08 deleting the default branch itself is refused (it is trivially merged into itself)" 'git push origin --delete main' "$RA_WC"
rdel refuse 2 "A08 a remote other than origin is not judged and is refused" 'git push upstream --delete ra-clean' "$RA_WC"
rdel refuse 2 "A08 a variable branch name cannot be judged and is refused" 'B=$(echo ra-clean); git push origin --delete $B' "$RA_WC"
rdel pass 0 "A08 (F2 attack fix) a branch name assigned a plain value earlier on the same line is judged as that name" 'B=ra-clean; git push origin --delete $B' "$RA_WC"
rdel refuse 2 "A08 a command word hidden in a substitution is judged by its arguments: dirty" 'GIT=git; $GIT push origin --delete ra-dirty' "$RA_WC"
rdel pass 0 "A08 a hidden command word, clean branch: judged the same way and passes" 'GIT=git; $GIT push origin --delete ra-clean' "$RA_WC"
rdel pass 0 "A08 a quoted mention of the delete is not a delete" 'echo "git push origin --delete ra-dirty"' "$RA_WC"
rdel pass 0 "A08 a plain push is still allowed" 'git push origin main' "$RA_WC"
# the moved cases: these three used to sit in section 2's must-refuse loop and reached for the network from wherever the suite ran
rdel refuse 2 "A08 (moved from section 2) git push origin --delete feature: no such branch at origin" 'git push origin --delete feature' "$RA_WC"
rdel refuse 2 "A08 (moved from section 2) git push origin -d feature: no such branch at origin" 'git push origin -d feature' "$RA_WC"
rdel refuse 2 "A08 (moved from section 2) git push origin :feature: no such branch at origin" 'git push origin :feature' "$RA_WC"
# origin gained a commit after this clone last fetched: the local origin/<b> is stale, the guard must look again
RA_WC2="$T/ra-wc2"; git clone -q "$RA_BARE" "$RA_WC2" >/dev/null 2>&1; git -C "$RA_WC2" config core.hooksPath /dev/null
git -C "$RA_WC2" checkout -q ra-stale >/dev/null 2>&1; echo late >> "$RA_WC2/a.txt"; git -C "$RA_WC2" add -A; "${ID[@]}" git -C "$RA_WC2" commit -q -m late; git -C "$RA_WC2" push -q origin ra-stale >/dev/null 2>&1
rdel refuse 2 "A08 a stale local origin/<b> is refreshed first: the late commit makes it dirty" 'git push origin --delete ra-stale' "$RA_WC"
# where the repo is: a variable set earlier in the command, ~, and git -C
rdel refuse 2 "A08 cd \$VAR (set earlier on the line) is resolved: judged in that repo, dirty" "R=$RA_WC; cd \$R && git push origin --delete ra-dirty" "$T"
rdel pass 0 "A08 cd \$VAR resolved: clean in that repo passes even from a folder that is no repo" "R=$RA_WC; cd \$R && git push origin --delete ra-clean3" "$T"
ln -s "$RA_WC" "$HOME/ra-wc"
rdel pass 0 "A08 cd ~/<folder> is resolved against the home folder" 'cd ~/ra-wc && git push origin --delete ra-clean3' "$T"
rdel pass 0 "A08 git -C <path> is resolved" "git -C $RA_WC push origin --delete ra-clean4" "$T"
rdel refuse 2 "A08 git -C <path>, dirty, is refused" "git -C $RA_WC push origin --delete ra-dirty" "$T"
rm -f "$RAL"; rdel pass 0 "A08 GITGUARD=1 approves a dirty delete" 'GITGUARD=1 git push origin --delete ra-dirty' "$RA_WC"
if ra_ledger_has "$RAL" GITGUARD; then ok; else bad "A08 an approved dirty delete must write its ledger line"; fi; pass_n=$((pass_n+1))
rm -f "$RAL"; rdel pass 0 "A08 GITGUARD=1 approves a branch origin never had" 'GITGUARD=1 git push origin --delete ra-ghost-never-existed' "$RA_WC"
rm -f "$RAL"; rdel pass 0 "A08 GITGUARD=1 in front of a clean delete passes" 'GITGUARD=1 git push origin --delete ra-clean' "$RA_WC"
if [ -f "$RAL" ]; then bad "A08 an override that waived nothing must write NO ledger line"; else ok; fi; pass_n=$((pass_n+1))
rm -f "$RAL"; rdel refuse 2 "A08 an override on a LATER segment does not approve a dirty delete" 'git push origin --delete ra-dirty && GITGUARD=1 true' "$RA_WC"

# --- A11 a short flag with its value attached is not the -a cluster ----------------------
ex30 pass 0 "A11 git commit -Cabc b.txt (a reuse-message ref holding the letter a) is not -a" 'git commit -Cabc b.txt'
ex30 pass 0 "A11 git commit -mabc b.txt (a message attached to -m) is not -a" 'git commit -mabc b.txt'
ex30 refuse 2 "A11 pair: git commit -am x is a genuine -a cluster" 'git commit -am "x"'
ex30 refuse 2 "A11 pair: git commit -nam x (a cluster reaching a before m) is still -a" 'git commit -nam "x"'

# --- A12 the folder of a commit: ~, a variable set earlier on the line, git -C -----------
RA12="$HOME/ra-a12"; mkdir -p "$RA12"; git -C "$RA12" init -q -b main; git -C "$RA12" config core.hooksPath /dev/null
echo a > "$RA12/a.txt"; git -C "$RA12" add -A; "${ID[@]}" git -C "$RA12" commit -q -m init
RA12S="$HOME/ra-a12s"; mkdir -p "$RA12S"; git -C "$RA12S" init -q -b main; git -C "$RA12S" config core.hooksPath /dev/null
echo a > "$RA12S/a.txt"; git -C "$RA12S" add -A; "${ID[@]}" git -C "$RA12S" commit -q -m init; echo s > "$RA12S/s.txt"; git -C "$RA12S" add s.txt
ex30 pass 0 "A12 cd ~/<folder> is resolved: an empty-index commit there passes" 'cd ~/ra-a12 && git commit -m x'
ex30 pass 0 "A12 cd \$W with W= set earlier on the line is resolved" "W=$RA12; cd \$W && git commit -m x"
ex30 pass 0 "A12 cd \${W} with W= set earlier is resolved" "W=$RA12; cd \${W} && git commit -m x"
ex30 pass 0 "A12 git -C \$W with W= set earlier is resolved" "W=$RA12; git -C \$W commit -m x"
ex30 refuse 2 "A12 pair: the resolved folder is really judged: staged file, bare commit" 'cd ~/ra-a12s && git commit -m x'
ex30 refuse 2 "A12 pair: the resolved folder is really judged: -a" "W=$RA12S; git -C \$W commit -a -m x"
ex30 refuse 2 "A12 pair: a variable never set on the line stays unresolvable" 'cd $NOPE_A12 && git commit -m x'
ex30 refuse 2 "A12 pair: \$HOME is not resolved by the guard (only the shell can expand it)" 'cd "$HOME/ra-a12" && git commit a.txt -m x'
ex30 refuse 2 "A12 pair: git -C with a variable never set is unresolvable" 'git -C $NOPE_A12 commit -m x'

# --- A16 the heavy pattern only counts at the command position --------------------------
HSG="$HOOKS_DIR/heavy-suite-guard.sh"
for c in 'rg vitest docs/' 'which vitest' 'echo npm test >> /tmp/notes' 'cd docs && rg vitest'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "A16 a runner named as an ARGUMENT is not a run: $c" env HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HSG"; done
for c in 'npm test' 'CI=1 npm test' 'time npm test' '(npm test)' 'cd apps/web && vitest run' 'T=npm; $T test' 'vitest run a.test.ts && npm test'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "A16 pair: a real run is still refused: $c" env HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HSG"; done

# --- A17 the runner reached without npx, and npm --prefix -------------------------------
for c in 'node node_modules/.bin/vitest run' './node_modules/.bin/vitest run' 'npm --prefix apps/web test' 'npm --prefix=apps/web run test:unit'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "A17 must count as a heavy run: $c" env HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HSG"; done
for c in 'node scripts/build.js' 'npm --prefix apps/web run dev' './node_modules/.bin/vitest run src/a.test.ts' 'ls node_modules/.bin/vitest'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "A17 pair: not a full run: $c" env HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HSG"; done

# --- A18 the load refusal says what is true --------------------------------------------
INPUT="$(json_bash 'npm test')"
ra18="$(printf '%s' "$INPUT" | env HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HSG" 2>&1 1>/dev/null)"
if printf '%s' "$ra18" | grep -q 'the machine is busy (load 25'; then ok; else bad "A18 the refusal must read 'the machine is busy (load N' (got: $ra18)"; fi; refuse_n=$((refuse_n+1))
if printf '%s' "$ra18" | grep -qi 'another heavy suite'; then bad "A18 pair: the old claim of another running suite must be gone"; else ok; fi; pass_n=$((pass_n+1))

# --- A21 the pipe rule fires only when a commit or push rides on the piped gate ---------
GGD="$HOOKS_DIR/gate-guard.sh"
for c in 'npx vitest run x | tail -3' 'npm run typecheck 2>&1 | grep -c error' 'git commit -m x && npx vitest run x | tail -3' 'npx vitest run x | tail -3 && ls'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "A21 a piped gate with no commit riding on it passes: $c" bash "$GGD"; done
for c in 'npx vitest run x | tail -3 && git commit -m x' 'npx vitest run x | tail -3 && git push' 'npx vitest run x | tee out.log; git commit -m x' 'npx vitest run x | tail -3 && echo READY'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "A21 pair: a commit or push riding on the piped gate is refused: $c" bash "$GGD"; done

# --- A22 git -C <path> commit/push counts ------------------------------------------------
for c in 'npx vitest run x; git -C d commit -m x' 'npx vitest run x | tail -3 && git -C d push' 'npx vitest run x | tail -3 && git -c user.name=x commit -m y'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "A22 git with global flags before commit/push counts: $c" bash "$GGD"; done
for c in 'npx vitest run x; git -C d status' 'npx vitest run x && git -C d commit -m x'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "A22 pair: not a commit after a semicolon, or joined with &&: $c" bash "$GGD"; done

# --- A23 gate vocabulary: npm t, npm -w <ws> test; readers rg and cat -------------------
for c in 'npm t | tail -3 && git commit -m x' 'npm -w apps/web test | tail -3 && git commit -m x' 'npx vitest run x | rg PASS && git commit -m x' 'npx vitest run x | cat && git commit -m x'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "A23 must refuse: $c" bash "$GGD"; done
for c in 'npm t && git commit -m x' 'npm -w apps/web test && git commit -m x' 'npm test | rg PASS' 'npm ls | tail -3 && git commit -m x'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "A23 pair: must pass: $c" bash "$GGD"; done

# --- A85 a broken python3 earlier on PATH cannot refuse every Bash call ------------------
BADPYA="$T/ra-badpy"; mkdir -p "$BADPYA"; printf '#!/bin/sh\nexit 1\n' > "$BADPYA/python3"; chmod +x "$BADPYA/python3"
INPUT="$(json_bash 'git status')"; expect pass 0 "A85 block-dangerous-git: a broken PATH python3 does not refuse an honest command" env PATH="$BADPYA:$PATH" bash "$BDG"
INPUT="$(json_bash 'git reset --hard')"; expect refuse 2 "A85 pair: the same guard, same PATH, still refuses the dangerous one (the real python ran)" env PATH="$BADPYA:$PATH" bash "$BDG"
INPUT="$(json_bash 'ls -la')"; expect pass 0 "A85 heavy-suite-guard: a broken PATH python3 does not refuse an honest command" env PATH="$BADPYA:$PATH" HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HSG"
INPUT="$(json_bash 'ls -la')"; expect pass 0 "A85 gate-guard: a broken PATH python3 does not refuse an honest command" env PATH="$BADPYA:$PATH" bash "$GGD"
INPUT="$(json_bash 'npx vitest run x | tail -3 && git commit -m x')"; expect refuse 2 "A85 pair: gate-guard with the broken PATH python3 still judges (the real python ran)" env PATH="$BADPYA:$PATH" bash "$GGD"
ex30 pass 0 "A85 commit-pathspec-guard: a broken PATH python3 does not refuse git status" 'git status' env PATH="$BADPYA:$PATH" bash "$HOOKS_DIR/commit-pathspec-guard.sh"
# no /usr/bin/python3 (the preferred path is a test seam): the first python3 on PATH is used
FBPY="$T/ra-fbpy"; mkdir -p "$FBPY"; printf '#!/bin/sh\nexec %s "$@"\n' "$(command -v python3)" > "$FBPY/python3"; chmod +x "$FBPY/python3"
INPUT="$(json_bash 'git reset --hard')"; expect refuse 2 "A85 fallback: with no preferred python3 the PATH one judges and refuses" env GUARD_PYTHON_PREFERRED=/nonexistent/python3 PATH="$FBPY:$PATH" bash "$BDG"
INPUT="$(json_bash 'git status')"; expect pass 0 "A85 fallback pair: and passes an honest command" env GUARD_PYTHON_PREFERRED=/nonexistent/python3 PATH="$FBPY:$PATH" bash "$BDG"
INPUT="$(json_bash 'git status')"; expect refuse 2 "A85 fallback: with no preferred python3 a BROKEN PATH one still fails closed" env GUARD_PYTHON_PREFERRED=/nonexistent/python3 PATH="$BADPYA:$PATH" bash "$BDG"
INPUT="$(json_bash 'git status')"; expect refuse 2 "A85 no python3 anywhere: block-dangerous-git fails closed" env -i "PATH=$NOPY28" GUARD_PYTHON_PREFERRED=/nonexistent/python3 bash "$BDG"
rm -f "$HOME/ra-wc"
# ======================================================================================

echo "refresh 2026-09-29 (b): git-hook behaviours ported from the maintainer's live setup (A73 A74 A75 A76 A81 A82 A86)"
# Helpers. Every case gets a fresh throwaway repo with core.hooksPath at the hooks under
# test and its own HOME, so nothing here touches the real ~/.claude. Secret-shaped strings
# are built at run time from pieces so this file never holds a token-looking literal.
RB="$T/refresh-b"; mkdir -p "$RB"
rb_home() {   # name -> a HOME with a names list, the ledger script and no other config
  local h="$RB/home-$1"; mkdir -p "$h/.claude/hooks"
  cp "$HOOKS_DIR/override-ledger.sh" "$h/.claude/hooks/"
  printf '# list\nZebulonQuixote\nword:Pat\n' > "$h/.claude/.redaction-names.local"
  printf '%s' "$h"
}
rb_new() { local r; r="$(mktemp -d "$RB/r.XXXXXX")"; git -C "$r" init -q -b main; git -C "$r" config core.hooksPath "$GIT_HOOKS_DIR"; printf '%s' "$r"; }
# rb_run <refuse|pass> <label> <repo> <home> [env assignments...]: stage and commit; a refuse
# case must fail AND say REFUSED with $RB_WANT in its message (so it is refused for the right reason).
rb_run() {
  local kind="$1" label="$2" r="$3" h="$4"; shift 4
  git -C "$r" add ${RB_ADD:--A} >/dev/null 2>&1
  local err rc; err="$(env HOME="$h" "${ID[@]}" "$@" git -C "$r" commit -q -m t 2>&1 >/dev/null)"; rc=$?
  if [ "$kind" = refuse ]; then
    if [ "$rc" != 0 ] && printf '%s' "$err" | grep -q 'REFUSED' && printf '%s' "$err" | grep -qE "${RB_WANT:-.}"; then ok; else bad "$label (must refuse for '${RB_WANT:-.}'; rc=$rc err='$err')"; fi
    refuse_n=$((refuse_n+1))
  else
    if [ "$rc" = 0 ]; then ok; else bad "$label (must pass; rc=$rc err='$err')"; fi
    pass_n=$((pass_n+1))
  fi
}
rb_case() {   # kind label home file content [env...]: one file, one commit
  local kind="$1" label="$2" h="$3" fn="$4" content="$5"; shift 5
  local r; r="$(rb_new)"; mkdir -p "$r/$(dirname "$fn")"; printf '%s\n' "$content" > "$r/$fn"
  rb_run "$kind" "$label" "$r" "$h" "$@"
}
RBH="$(rb_home main)"
RBX="$(printf 'a%.0s' {1..24})"      # 24 filler characters

# built from pieces so no whole address sits in this file (a machine-wide email scan reads it)
STRANGER_MAIL="ops"'@'"stranger-corp.io"
echo "  A73 the email check is skipped in the settings repo itself (toplevel = ~/.claude), names and paths still bind"
H73="$(rb_home a73)"; R73="$H73/.claude"; git -C "$R73" init -q -b main; git -C "$R73" config core.hooksPath "$GIT_HOOKS_DIR"
RB_ADD="edge.txt"
RB_WANT='.'
printf 'write to %s\n' "$STRANGER_MAIL" > "$R73/edge.txt"; rb_run pass "A73: a non-allowlisted address in the ~/.claude repo must pass" "$R73" "$H73"
printf 'met zebulonquixote today\n' > "$R73/edge.txt"; RB_WANT='real name|listed name|matches'; rb_run refuse "A73: a listed name still binds inside ~/.claude" "$R73" "$H73"
git -C "$R73" reset -q
U73="/User""s"; printf 'see %s/alice/x\n' "$U73" > "$R73/edge.txt"; rb_run refuse "A73: a home path still binds inside ~/.claude" "$R73" "$H73"
unset RB_ADD; RB_WANT='email'
rb_case refuse "A73 twin: the same non-allowlisted address in any other repo is refused" "$H73" note.txt "write to $STRANGER_MAIL"
RB_WANT='.'

echo "  A74 key-shaped tokens in staged content are refused (no PRIVACY_OK); placeholders and prose pass"
RB_WANT='key-shaped'
S_ANT="sk-""ant-${RBX}"; S_GHP="gh""p_${RBX}"; S_PAT="github""_pat_${RBX}"; S_AWS="AK""IA$(printf 'Q%.0s' {1..16})"; S_SLACK="xo""xb-${RBX}"; S_PEM="-----BEGIN ""RSA PRIVATE KEY-----"
rb_case refuse "A74: an sk-ant- key in a file" "$RBH" a.env "TOKEN_VAR is $S_ANT"
rb_case refuse "A74: a ghp_ token" "$RBH" a.txt "token $S_GHP"
rb_case refuse "A74: a github_pat_ token" "$RBH" a.txt "token $S_PAT"
rb_case refuse "A74: an AWS access key id" "$RBH" a.txt "id $S_AWS"
rb_case refuse "A74: a Slack xox token" "$RBH" a.txt "slack $S_SLACK"
rb_case refuse "A74: a private-key header" "$RBH" a.txt "$S_PEM"
rb_case refuse "A74: PRIVACY_OK=1 does NOT lift the key refusal" "$RBH" a.txt "token $S_GHP" PRIVACY_OK=1
rb_case refuse "A74: a key-shaped FILE NAME" "$RBH" "notes-$S_GHP.md" "harmless body"
r74="$(rb_new)"; printf 'old %s\n' "$S_GHP" > "$r74/a.txt"; git -C "$r74" add -A; env HOME="$RBH" "${ID[@]}" git -C "$r74" commit -q --no-verify -m seed >/dev/null 2>&1
printf 'old %s\nnew clean line\n' "$S_GHP" > "$r74/a.txt"; unset RB_ADD; rb_run pass "A74: a key already in history is not re-flagged when the file is touched (added lines only)" "$r74" "$RBH"
rb_case pass "A74: sk-ant-your-key-here (placeholder) passes" "$RBH" a.md 'ANTHROPIC key: sk-ant-your-key-here'
rb_case pass "A74: sk-ant- followed by a run of x passes" "$RBH" a.md "key: sk-""ant-xxxxxxxxxxxxxxxx"
rb_case pass "A74: the AWS docs example key (ends EXAMPLE) passes" "$RBH" a.md "id AK""IAIOSFODNN7EXAMPLE"
rb_case pass "A74: prose naming the prefixes passes" "$RBH" a.md 'we refuse anything starting ghp_ or sk-ant- or AKIA in a commit'
rb_case pass "A74: a line marked '# pragma: allow-secret' passes (the backup hook's fixture marker)" "$RBH" a.sh "fixture=$S_GHP # pragma: allow-secret"
rb_case pass "A74: an honest file passes" "$RBH" a.txt 'nothing secret here'
# one list: the commit hook reads SECRET_RE out of hooks/auto-backup.sh, so the two cannot drift
if grep -q "^SECRET_RE=" "$HOOKS_DIR/auto-backup.sh" && grep -q 'auto-backup.sh' "$GIT_HOOKS_DIR/pre-commit"; then ok; else bad "A74: pre-commit must read the one SECRET_RE in hooks/auto-backup.sh"; fi
pass_n=$((pass_n+1))
# and a token shape only the shared list knows (a Google API key) is refused by it too
S_AIZA="AI""za$(printf 'B%.0s' {1..35})"
rb_case refuse "A74: the shared (wider) list catches a Google API key too" "$RBH" a.txt "g $S_AIZA"
# no auto-backup.sh next to the hooks: fail closed, not silently unscanned
NB="$RB/nobackup"; mkdir -p "$NB/git-hooks" "$NB/hooks"; cp "$GIT_HOOKS_DIR"/pre-commit "$GIT_HOOKS_DIR"/commit-msg "$NB/git-hooks/"
r74b="$(rb_new)"; git -C "$r74b" config core.hooksPath "$NB/git-hooks"; printf 'clean\n' > "$r74b/a.txt"
RB_WANT='SECRET_RE'; rb_run refuse "A74: no auto-backup.sh to read SECRET_RE from must refuse (fail closed)" "$r74b" "$RBH"; RB_WANT='.'

echo "  A75 staged files over the size limit (default 10 MB, hooks/commit-size.conf LIMIT_MB) are refused unless SIZE_OK=1, which writes one ledger line"
HSZ="$(rb_home size)"; printf 'LIMIT_MB=1\n' > "$HSZ/.claude/hooks/commit-size.conf"
mkbig() { head -c "$2" /dev/zero > "$1"; }
RB_WANT='MB'
r=$(rb_new); mkbig "$r/big.bin" 2097152; rb_run refuse "A75: a 2 MB file over LIMIT_MB=1 is refused" "$r" "$HSZ"
r=$(rb_new); mkbig "$r/a.bin" 450000; mkbig "$r/b.bin" 450000; mkbig "$r/c.bin" 450000; rb_run refuse "A75: three files that TOTAL over the limit are refused" "$r" "$HSZ"
r=$(rb_new); mkbig "$r/small.bin" 500000; RB_WANT='.'; rb_run pass "A75: a 0.5 MB file under LIMIT_MB=1 passes" "$r" "$HSZ"
r=$(rb_new); mkbig "$r/mid.bin" 3000000; rb_run pass "A75: no conf at all: 3 MB is under the built-in 10 MB and passes" "$r" "$RBH"
r=$(rb_new); mkbig "$r/huge.bin" 11534336; RB_WANT='MB'; rb_run refuse "A75: no conf at all: 11 MB is over the built-in 10 MB default" "$r" "$RBH"
RSL="$RB/size-ledger.tsv"; rm -f "$RSL"
r=$(rb_new); mkbig "$r/big.bin" 2097152; RB_WANT='.'; rb_run pass "A75: SIZE_OK=1 lets the big commit through" "$r" "$HSZ" SIZE_OK=1 OVERRIDE_LEDGER="$RSL"
if ledger_has "$RSL" SIZE_OK && [ "$(wc -l < "$RSL" | tr -d ' ')" = 1 ]; then ok; else bad "A75: SIZE_OK=1 must write exactly one ledger line"; fi
pass_n=$((pass_n+1))
rm -f "$RSL"
r=$(rb_new); mkbig "$r/small.bin" 500000; rb_run pass "A75: SIZE_OK=1 on a small commit passes without a ledger line" "$r" "$HSZ" SIZE_OK=1 OVERRIDE_LEDGER="$RSL"
if [ ! -s "$RSL" ]; then ok; else bad "A75: an unneeded SIZE_OK=1 must not write a ledger line"; fi
pass_n=$((pass_n+1))
r=$(rb_new); mkbig "$r/big.bin" 2097152; RB_WANT='ledger'; rb_run refuse "A75: SIZE_OK=1 with an unwritable ledger is refused" "$r" "$HSZ" SIZE_OK=1 OVERRIDE_LEDGER="/nonexistent-$$/deep/overrides.tsv"
HSZ2="$(rb_home size2)"; printf 'LIMIT_MB=1\n' > "$HSZ2/.claude/hooks/commit-size.conf"; rm -f "$HSZ2/.claude/hooks/override-ledger.sh"
r=$(rb_new); mkbig "$r/big.bin" 2097152; rb_run refuse "A75: SIZE_OK=1 with no override-ledger.sh at all is refused" "$r" "$HSZ2" SIZE_OK=1
RB_WANT='.'

echo "  A76 privacy names skipped for repos listed in ~/.claude/.privacy-name-exceptions.local; home path, email and keys still bind"
HEX="$(rb_home exc)"; REXC="$(rb_new)"; REXC_REAL="$(cd "$REXC" && pwd -P)"
printf '# repos that legitimately document the guard names\n\n%s\n' "$REXC_REAL" > "$HEX/.claude/.privacy-name-exceptions.local"
RB_ADD=; printf 'the guard refuses zebulonquixote\n' > "$REXC/n.txt"; rb_run pass "A76: a listed name in a listed repo passes" "$REXC" "$HEX"
mkdir -p "$REXC/zebulonquixote-docs"; printf 'x\n' > "$REXC/zebulonquixote-docs/f.txt"; rb_run pass "A76: a listed name in a PATH of a listed repo passes" "$REXC" "$HEX"
printf 'see %s/alice/x\n' "$U73" > "$REXC/p.txt"; RB_WANT='home path'; rb_run refuse "A76: a home path still binds in a listed repo" "$REXC" "$HEX"; git -C "$REXC" reset -q; rm "$REXC/p.txt"
printf '%s\n' "$STRANGER_MAIL" > "$REXC/e.txt"; RB_WANT='email'; rb_run refuse "A76: an email still binds in a listed repo" "$REXC" "$HEX"; git -C "$REXC" reset -q; rm "$REXC/e.txt"
printf 'k %s\n' "$S_GHP" > "$REXC/k.txt"; RB_WANT='key-shaped'; rb_run refuse "A76: a key still binds in a listed repo" "$REXC" "$HEX"; git -C "$REXC" reset -q; rm "$REXC/k.txt"
unset RB_ADD; RB_WANT='name'
rb_case refuse "A76: the same name in an UNLISTED repo is refused" "$HEX" n.txt 'the guard refuses zebulonquixote'
HEX2="$(rb_home exc2)"; printf '%s/somewhere-else\n' "$RB" > "$HEX2/.claude/.privacy-name-exceptions.local"
rb_case refuse "A76: a list naming only other repos does not exempt this one" "$HEX2" n.txt 'the guard refuses zebulonquixote'
RB_WANT='.'

echo "  A81 the attribution line is matched by its own shape, so 'generated with the Claude API' in a subject passes"
printf 'feat: room labels generated with the Claude API\n' > "$T/b81a"; expect pass 0 "A81: a subject about the Claude API passes" bash "$GIT_HOOKS_DIR/commit-msg" "$T/b81a"
printf 'feat: x\n\nGenerated with [Claude Code](https://claude.com/claude-code)\n' > "$T/b81b"; expect refuse 1 "A81: the bracketed footer is refused" bash "$GIT_HOOKS_DIR/commit-msg" "$T/b81b"
printf 'feat: x\n\ngenerated with claude code\n' > "$T/b81c"; expect refuse 1 "A81: the footer in lower case is refused" bash "$GIT_HOOKS_DIR/commit-msg" "$T/b81c"
printf 'feat: x\n\nThe labels are generated with Claude models at build time.\n' > "$T/b81d"; expect pass 0 "A81: prose about work done with Claude passes" bash "$GIT_HOOKS_DIR/commit-msg" "$T/b81d"

echo "  A82 a redaction-list name typed into the commit MESSAGE is refused"
INPUT=""
printf 'fix: thanks to ZebulonQuixote for the report\n' > "$T/b82a"; expect refuse 1 "A82: a listed name in the message" env HOME="$RBH" bash "$GIT_HOOKS_DIR/commit-msg" "$T/b82a"
printf 'fix: thanks to Zebulon%sQuixote for the report\n' "$(printf '\342\200\213')" > "$T/b82b"; expect refuse 1 "A82: a listed name split by a zero-width character" env HOME="$RBH" bash "$GIT_HOOKS_DIR/commit-msg" "$T/b82b"
printf 'fix: pair with Pat on the parser\n' > "$T/b82c"; expect refuse 1 "A82: a short listed name as a whole word" env HOME="$RBH" bash "$GIT_HOOKS_DIR/commit-msg" "$T/b82c"
printf 'fix: the pattern matcher and a patch\n' > "$T/b82d"; expect pass 0 "A82: a short listed name inside longer words passes" env HOME="$RBH" bash "$GIT_HOOKS_DIR/commit-msg" "$T/b82d"
printf 'fix: nothing sensitive in this message\n' > "$T/b82e"; expect pass 0 "A82: an honest message passes" env HOME="$RBH" bash "$GIT_HOOKS_DIR/commit-msg" "$T/b82e"
printf '# ZebulonQuixote in a comment line git drops\nfix: honest subject\n' > "$T/b82f"; expect pass 0 "A82: a name only in a # comment line (dropped by git) passes" env HOME="$RBH" bash "$GIT_HOOKS_DIR/commit-msg" "$T/b82f"
NOLIST82="$RB/home-nolist"; mkdir -p "$NOLIST82/.claude"
expect pass 0 "A82: no names list at all: the message check does not run (pre-commit fails closed on that)" env HOME="$NOLIST82" bash "$GIT_HOOKS_DIR/commit-msg" "$T/b82a"
r=$(rb_new); printf 'clean\n' > "$r/a.txt"; git -C "$r" add -A
env HOME="$RBH" "${ID[@]}" git -C "$r" commit -q -m "thanks ZebulonQuixote" >/dev/null 2>&1; rc=$?
if [ "$rc" != 0 ] && ! git -C "$r" log -1 >/dev/null 2>&1; then ok; else bad "A82: a real git commit whose -m holds a listed name must be refused (rc=$rc)"; fi
refuse_n=$((refuse_n+1))

echo "  A86 a broken python3 earlier on PATH must not refuse honest commits (the git hooks prefer /usr/bin/python3)"
REALPY="$(command -v python3)"
BADPYB="$RB/badpy"; mkdir -p "$BADPYB"; printf '#!/bin/bash\nexit 1\n' > "$BADPYB/python3"; chmod +x "$BADPYB/python3"
RB_WANT='.'
rb_case pass "A86: pre-commit with a broken PATH python3 still passes honest work" "$RBH" a.txt 'honest' GUARD_PYTHON_PREFERRED="$REALPY" PATH="$BADPYB:$PATH"
RB_WANT='name'; rb_case refuse "A86: pre-commit with a broken PATH python3 still refuses a listed name (the real python judged it)" "$RBH" a.txt 'met zebulonquixote' GUARD_PYTHON_PREFERRED="$REALPY" PATH="$BADPYB:$PATH"
expect pass 0 "A86: commit-msg with a broken PATH python3 passes an honest message" env HOME="$RBH" GUARD_PYTHON_PREFERRED="$REALPY" PATH="$BADPYB:$PATH" bash "$GIT_HOOKS_DIR/commit-msg" "$T/b82e"
expect refuse 1 "A86: commit-msg with a broken PATH python3 still refuses a listed name" env HOME="$RBH" GUARD_PYTHON_PREFERRED="$REALPY" PATH="$BADPYB:$PATH" bash "$GIT_HOOKS_DIR/commit-msg" "$T/b82a"
# with no preferred python3 the first one on PATH is used
GOODPYB="$RB/goodpy"; mkdir -p "$GOODPYB"; printf '#!/bin/sh\nexec %s "$@"\n' "$REALPY" > "$GOODPYB/python3"; chmod +x "$GOODPYB/python3"
RB_WANT='.'; rb_case pass "A86 fallback: no preferred python3, the PATH one judges honest work" "$RBH" a.txt 'honest' GUARD_PYTHON_PREFERRED=/nonexistent/python3 PATH="$GOODPYB:$PATH"
RB_WANT='name'; rb_case refuse "A86 fallback: no preferred python3, the PATH one still refuses a listed name" "$RBH" a.txt 'met zebulonquixote' GUARD_PYTHON_PREFERRED=/nonexistent/python3 PATH="$GOODPYB:$PATH"
unset RB_WANT RB_ADD

echo "refresh 2026-09-29 (c1): default session-hook behaviours ported from the maintainer's live setup (A26 A27 A28 A29 A33 A62 A63 A64 A65 A66 A67 A68 A87)"
C1H="$HOOKS_DIR/clock-in-context.sh"
C1="$T/c1"; mkdir -p "$C1"
# c1_tr <path> <spec>... : a fake transcript, file order = argument order. Spec = kind:minutes-ago[:arg]
#   human:M[:text]  your own typed line (default text "status?")   tool:M  a tool result (a "user" line, must not count)
#   usage:M:K       an assistant line whose usage sums to K thousand tokens   zero:M  an all-zero usage line (an API-error line)
#   compact:M       a compact-boundary system line   asst:M  an assistant line with no usage
#   filler:M:BYTES  a tool-result line of that many bytes (pushes older lines out of a fixed tail window)
c1_tr() { python3 - "$@" <<'PY3'
import sys, datetime, json
path = sys.argv[1]; lines = []
for spec in sys.argv[2:]:
    parts = spec.split(':', 2); kind = parts[0]; mins = int(parts[1]); arg = parts[2] if len(parts) > 2 else ''
    ts = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=mins)).strftime('%Y-%m-%dT%H:%M:%S.000Z')
    if kind == 'human':
        d = {"type": "user", "timestamp": ts, "promptId": "p1", "message": {"role": "user", "content": (arg or "status?").replace('\\n', '\n')}}
    elif kind == 'tool':
        d = {"type": "user", "timestamp": ts, "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]}}
    elif kind == 'filler':
        d = {"type": "user", "timestamp": ts, "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t2", "content": "z" * int(arg)}]}}
    elif kind == 'usage':
        k = int(arg); d = {"type": "assistant", "timestamp": ts, "message": {"role": "assistant", "usage": {"input_tokens": 1000, "cache_creation_input_tokens": 0, "cache_read_input_tokens": (k - 1) * 1000, "output_tokens": 5}}}
    elif kind == 'zero':
        d = {"type": "assistant", "timestamp": ts, "message": {"role": "assistant", "model": "<synthetic>", "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0}}}
    elif kind == 'compact':
        d = {"type": "system", "subtype": "compact_boundary", "timestamp": ts, "content": "Conversation compacted"}
    else:
        d = {"type": "assistant", "timestamp": ts, "message": {"role": "assistant", "content": [{"type": "text", "text": "x"}]}}
    lines.append(json.dumps(d, separators=(',', ':')))
open(path, 'w').write('\n'.join(lines) + '\n')
PY3
}
# c1_in <event> <transcript> [prompt] [cwd] : the hook's stdin JSON; no prompt argument = no prompt field
c1_in() { python3 -c '
import json,sys
d={"session_id":"c1s","hook_event_name":sys.argv[1],"transcript_path":sys.argv[2],"cwd":sys.argv[4] if len(sys.argv)>4 else "/tmp"}
if len(sys.argv)>3: d["prompt"]=sys.argv[3].replace("\\n","\n")
print(json.dumps(d))' "$@"; }
c1_run() { local json="$1"; shift; printf '%s' "$json" | env "$@" bash "$C1H" 2>/dev/null; }
c1_fire() { local l="$1" out="$2" pat="$3"; if printf '%s' "$out" | grep -qE "$pat"; then ok; else bad "$l: MUST show /$pat/ (got: $(printf '%s' "$out" | head -c 300))"; fi; refuse_n=$((refuse_n+1)); }
c1_quiet() { local l="$1" out="$2" pat="$3"; if printf '%s' "$out" | grep -qE "$pat"; then bad "$l: must NOT show /$pat/ (got: $(printf '%s' "$out" | head -c 300))"; else ok; fi; pass_n=$((pass_n+1)); }
RET='YOU ARE RETURNING after'
TRC="$C1/t.jsonl"

echo "  A62 the away detector fires only for the owner's own TYPED prompt; machine text is never the current or the previous message"
c1_tr "$TRC" human:120 tool:60 human:0
c1_fire "A62 baseline: typed prompt, previous typed message 120 min ago" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'status?')")" "$RET 1[12][0-9] minutes"
c1_tr "$TRC" human:120 human:1:'<task-notification>helper done</task-notification>' human:0
c1_fire "A62 a helper hand-back one minute ago is not the owner's previous message" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'status?')")" "$RET 1[12][0-9] minutes"
c1_tr "$TRC" human:120 human:5:'<agent-message from=x>hi</agent-message>' human:4:'<cross-session-message from=y>hi</cross-session-message>' human:3:'Another Claude session sent a message: hi' human:2:'<bash-input>ls</bash-input>' human:1:'<<autonomous-loop>>' human:0
c1_fire "A62 every machine shape between two typed messages is skipped, whatever the count" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'status?')")" "$RET 1[12][0-9] minutes"
c1_tr "$TRC" human:120 human:3:'[Cross-session delivery notice] a note arrived' human:0
c1_fire "A62 a past delivery notice (a whole-message notice) is not the owner's previous message" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'status?')")" "$RET 1[12][0-9] minutes"
c1_tr "$TRC" human:120 human:5 human:0
c1_quiet "A62 pair: a real typed message 5 min ago IS the previous message (no fire)" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'status?')")" "$RET"
c1_tr "$TRC" human:120 human:3:'please read <task-notification> tags for me' human:0
c1_quiet "A62 pair: a typed message that merely MENTIONS the frame mid-text is still typed (no fire)" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'status?')")" "$RET"
c1_tr "$TRC" human:120 human:3:'[Cross-session delivery notice] a note\nplease also do the other thing' human:0
c1_quiet "A62 pair: a message that starts with the notice frame but carries real text after it is typed (no fire)" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'status?')")" "$RET"
c1_tr "$TRC" human:120 human:0
for mp in '<task-notification>helper finished</task-notification>' '<agent-message from=x>hi' '<cross-session-message from=y>hi' 'Another Claude session sent a message: hi' '<bash-input>ls -la</bash-input>' '<<autonomous-loop>>' '   <task-notification>after leading spaces' '[Cross-session delivery notice] one line' '[Cross-session delivery notice] one\n[Cross-session delivery notice] two'; do
  o="$(c1_run "$(c1_in UserPromptSubmit "$TRC" "$mp")")"
  c1_quiet "A62 the CURRENT prompt is machine text ($(printf '%s' "$mp" | head -c 30)): no return notice, no full card" "$o" "$RET|HOW TO TALK TO ME"
done
c1_fire "A62 pair: an ordinary typed prompt with the same transcript fires" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'what is next?')")" "$RET"
c1_fire "A62 pair: a prompt that starts with the notice frame but adds real text is typed (fires)" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" '[Cross-session delivery notice] x\nand now do this')")" "$RET"
c1_quiet "A62 SessionStart is not a typed prompt: the return notice never fires there" "$(c1_run "$(c1_in SessionStart "$TRC")")" "$RET"
c1_fire "A62 pair: the SAME SessionStart still injects the full card" "$(c1_run "$(c1_in SessionStart "$TRC")")" "HOW TO TALK TO ME"
# the classifier a later hook can call: clock-in-context.sh --classify-prompt reads the text on stdin, exit 0 = machine text, exit 1 = typed
c1_cls() { local want="$1" label="$2" text="$3"; printf '%s' "$text" | bash "$C1H" --classify-prompt >/dev/null 2>&1; local got=$?; if [ "$got" = "$want" ]; then ok; else bad "classifier: $label (wanted $want, got $got)"; fi; if [ "$want" = 0 ]; then refuse_n=$((refuse_n+1)); else pass_n=$((pass_n+1)); fi; }
c1_cls 0 "a task notification is machine text" '<task-notification>x</task-notification>'
c1_cls 0 "leading whitespace before a machine prefix" $'  \n <cross-session-message>x'
c1_cls 0 "a whole-message delivery notice (two frames, one blank line between)" $'[Cross-session delivery notice] a\n\n[Cross-session delivery notice] b'
c1_cls 1 "an ordinary sentence is typed" 'please fix the build'
c1_cls 1 "an empty prompt is typed" ''
c1_cls 1 "a delivery notice followed by a plain line is typed" $'[Cross-session delivery notice] a\nplease do this'
c1_cls 1 "the frame in the middle of a sentence is typed" 'see the <task-notification> tag'

echo "  A67 a long paste must not outrun the hook (the prefix test reads a bounded head; a notice-only test is capped)"
LONGM="$(python3 -c 'print("<task-notification>" + "x " * 100000, end="")')"
c1_tr "$TRC" human:120 human:0
s0=$(date +%s); o="$(c1_run "$(c1_in UserPromptSubmit "$TRC" "$LONGM")")"; s1=$(date +%s)
c1_quiet "A67 a 200 KB machine-prefixed prompt is still recognised as machine (no return notice)" "$o" "$RET"
if [ $((s1 - s0)) -le 3 ]; then ok; else bad "A67 a 200 KB prompt took $((s1 - s0)) s (limit 3 s)"; fi; pass_n=$((pass_n+1))
LONGT="$(python3 -c 'print("please review " + "word " * 40000, end="")')"
s0=$(date +%s); o="$(c1_run "$(c1_in UserPromptSubmit "$TRC" "$LONGT")")"; s1=$(date +%s)
c1_fire "A67 pair: a 200 KB typed paste is typed (fires)" "$o" "$RET"
if [ $((s1 - s0)) -le 3 ]; then ok; else bad "A67 a 200 KB typed prompt took $((s1 - s0)) s (limit 3 s)"; fi; pass_n=$((pass_n+1))
LONGN="$(python3 -c 'print("\n".join(["[Cross-session delivery notice] line %d" % i for i in range(700)]), end="")')"
c1_cls 1 "a notice-only test is capped: 700 notice lines (over 16 KB) is treated as typed" "$LONGN"
SHORTN="$(python3 -c 'print("\n".join(["[Cross-session delivery notice] line %d" % i for i in range(20)]), end="")')"
c1_cls 0 "pair: 20 notice lines (under the cap) is machine text" "$SHORTN"
c1_cls 0 "a 200 KB machine-prefixed text classifies in bounded time" "$LONGM"

echo "  A62 with no jq on the machine the prompt is cut out of the JSON by awk (CIC_NO_JQ=1 forces that reader)"
c1_tr "$TRC" human:120 human:0
c1_quiet "A62 no-jq: a machine prompt is still recognised" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" '<task-notification>x</task-notification>')" CIC_NO_JQ=1)" "$RET"
c1_fire "A62 no-jq pair: a typed prompt still fires" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'what now? say "hi"')" CIC_NO_JQ=1)" "$RET"
c1_quiet "A62 no-jq: a two-line notice-only prompt (JSON-escaped newline) is machine" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" '[Cross-session delivery notice] a\n[Cross-session delivery notice] b')" CIC_NO_JQ=1)" "$RET"
c1_fire "A62 no-jq pair: a notice frame followed by real text is typed" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" '[Cross-session delivery notice] a\nplease do this')" CIC_NO_JQ=1)" "$RET"
s0=$(date +%s); o="$(c1_run "$(c1_in UserPromptSubmit "$TRC" "$LONGM")" CIC_NO_JQ=1)"; s1=$(date +%s)
c1_quiet "A67 no-jq: a 200 KB machine-prefixed prompt is machine" "$o" "$RET"
if [ $((s1 - s0)) -le 3 ]; then ok; else bad "A67 no-jq: a 200 KB prompt took $((s1 - s0)) s (limit 3 s)"; fi; pass_n=$((pass_n+1))

echo "  A63 the context line reads the whole transcript, newest first, skips all-zero usage lines, and stays silent after a compaction"
c1_tr "$TRC" usage:200:6 filler:190:300000 human:0
c1_fire "A63 a usage line more than 200 KB before the end is still found" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")")" '^Context used: 6k tokens'
c1_tr "$TRC" usage:200:6 filler:190:9500000 human:0
c1_fire "A63 a usage line more than 8 MB before the end (past the growing windows) is still found" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")")" '^Context used: 6k tokens'
c1_tr "$TRC" filler:200:300000 usage:20:7 compact:10 human:0
c1_quiet "A63 a compaction after the usage line inside the first window of a big file: unknown, print nothing" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")")" '^Context used:'
c1_tr "$TRC" filler:200:300000 usage:20:7 human:0
c1_fire "A63 pair: the same big file with no compaction measures normally" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")")" '^Context used: 7k tokens'
c1_tr "$TRC" usage:200:6 filler:190:300000 compact:100 human:0
c1_quiet "A63 a compaction newer than the last usage line, the usage line being outside the first window: unknown" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")")" '^Context used:'
c1_tr "$TRC" usage:20:6 zero:10 human:0
c1_fire "A63 a newer all-zero usage line is skipped (the value is 6k, not 0k)" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")")" '^Context used: 6k tokens'
c1_tr "$TRC" usage:20:6 usage:10:9 human:0
c1_fire "A63 pair: the NEWEST non-zero usage line wins" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")")" '^Context used: 9k tokens'
c1_tr "$TRC" zero:10 human:0
c1_quiet "A63 an all-zero usage line alone is no measurement: no context line" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")")" '^Context used:'
c1_tr "$TRC" usage:20:6 compact:10 human:0
c1_quiet "A63 a compaction after the last usage line: the number is unknown, print nothing" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")")" '^Context used:'
c1_tr "$TRC" usage:20:6 compact:15 zero:10 human:0
c1_quiet "A63 a compaction followed only by an all-zero line is still unknown" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")")" '^Context used:'
c1_tr "$TRC" compact:20 usage:10:7 human:0
c1_fire "A63 pair: a usage line AFTER the compaction measures normally" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")")" '^Context used: 7k tokens'

echo "  A64 override count on return: one line, from the ledger, since the owner's previous typed message"
c1_ledger() { python3 - "$@" <<'PY4'
import sys, datetime
path = sys.argv[1]; out = []
for spec in sys.argv[2:]:
    name, mins = spec.split(':')
    ts = (datetime.datetime.now() - datetime.timedelta(minutes=int(mins))).strftime('%Y-%m-%d %H:%M')
    out.append("%s\tsomefolder\t%s\tpattern\tsome command" % (ts, name))
out.append("garbage line with no tabs")
open(path, 'w').write('\n'.join(out) + '\n')
PY4
}
LED="$C1/ledger.tsv"
c1_tr "$TRC" human:120 human:0
c1_ledger "$LED" GITGUARD:30 GITGUARD:10 SWEEP:5 OLDONE:300
c1_fire "A64 overrides since the previous typed message are counted by name" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")" OVERRIDE_LEDGER="$LED")" '^Overrides while you were away: GITGUARD 2, SWEEP 1$'
c1_quiet "A64 an override from BEFORE the previous typed message is not counted" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")" OVERRIDE_LEDGER="$LED")" 'OLDONE'
c1_ledger "$LED" SAMEMIN:120 EARLIER:125
c1_fire "A64 the compare is at the ledger's minute resolution: an override in the very minute of the previous message counts" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")" OVERRIDE_LEDGER="$LED")" 'Overrides while you were away: SAMEMIN 1$'
c1_ledger "$LED" OLDONE:300 OLDTWO:200
c1_quiet "A64 pair: none written since the previous message: no line at all" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")" OVERRIDE_LEDGER="$LED")" 'Overrides while'
c1_tr "$TRC" human:2 human:0
c1_ledger "$LED" GITGUARD:1
c1_quiet "A64 pair: not returning (previous message 2 min ago): no override line" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")" OVERRIDE_LEDGER="$LED")" 'Overrides while'
c1_tr "$TRC" human:120 human:0
c1_ledger "$LED" GITGUARD:10
c1_quiet "A64 pair: a machine prompt is not a return: no override line" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" '<task-notification>x</task-notification>')" OVERRIDE_LEDGER="$LED")" 'Overrides while'
c1_quiet "A64 pair: a missing ledger file is silent" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")" OVERRIDE_LEDGER="$C1/no-such-ledger.tsv")" 'Overrides while'

echo "  A68 the returning line names the summarize skill"
c1_tr "$TRC" human:120 human:0
c1_fire "A68 the return notice tells the model to invoke the summarize skill" "$(c1_run "$(c1_in UserPromptSubmit "$TRC")")" "$RET.*summarize skill"
c1_tr "$TRC" human:2 human:0
c1_quiet "A68 pair: an ordinary prompt carries no summarize-skill instruction" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')")" 'summarize skill'

echo "  A66 the fullness note: from 400k the owner's typed prompt asks the reply to open with how full the chat is"
c1_tr "$TRC" usage:1:450 human:0
c1_fire "A66 450k, typed prompt: the fullness note prints" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')")" 'open your reply with one line on how full'
c1_tr "$TRC" usage:1:400 human:0
c1_fire "A66 exactly 400k prints (the threshold is inclusive)" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')")" 'open your reply with one line on how full'
c1_tr "$TRC" usage:1:399 human:0
c1_quiet "A66 399k: no note" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')")" 'how full'
c1_tr "$TRC" usage:1:450 human:0
c1_quiet "A66 a machine prompt at 450k gets no note" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" '<task-notification>x</task-notification>')")" 'how full'
c1_quiet "A66 SessionStart at 450k gets no note (typed prompts only)" "$(c1_run "$(c1_in SessionStart "$TRC")")" 'how full'
mkdir -p "$C1/subagents"; cp "$TRC" "$C1/subagents/agent-1.jsonl"
c1_quiet "A66 a helper's own transcript (a subagents/ path) gets no note" "$(c1_run "$(c1_in UserPromptSubmit "$C1/subagents/agent-1.jsonl" 'go on')")" 'how full'
c1_tr "$TRC" usage:1:250 human:0
c1_fire "A66 the threshold is adjustable: CONTEXT_NOTE_K=200 at 250k prints" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')" CONTEXT_NOTE_K=200)" 'how full'
c1_quiet "A66 pair: the default threshold at 250k prints nothing" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')")" 'how full'
c1_tr "$TRC" human:100 usage:90:450 human:0
c1_fire "A66 60+ minutes since the chat's newest line: the re-read note is added" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')")" 're-read the whole chat'
c1_tr "$TRC" human:100 usage:5:450 human:0
c1_quiet "A66 pair: the chat's own newest line is 5 min old (it was working while you were silent): no re-read note" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')")" 're-read the whole chat'
c1_quiet "A66 the context line carries no leftover floor suffix" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')")" 'floor'

echo "  A65 the backup watchdog: one line on a typed prompt when the settings repo has been dirty over 60 minutes or holds unpushed commits (only where backup.conf exists)"
W65="$C1/wd"; W65R="$C1/wd-remote.git"; mkdir -p "$W65/hooks"
git init -q --bare "$W65R"; git -C "$W65" init -q -b main; git -C "$W65" config core.hooksPath /dev/null; git -C "$W65" remote add origin "$W65R"
printf '# placeholder\n' > "$W65/hooks/backup.conf"; echo seed > "$W65/seed.txt"
git -C "$W65" add -A; "${ID[@]}" git -C "$W65" commit -q -m seed; git -C "$W65" push -q -u origin main >/dev/null 2>&1
c1_tr "$TRC" human:0
c1_quiet "A65 clean and pushed: silent" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')" WATCHDOG_CLAUDE_DIR="$W65")" 'WATCHDOG'
echo fresh > "$W65/fresh.txt"
c1_quiet "A65 dirty for a minute only: silent" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')" WATCHDOG_CLAUDE_DIR="$W65")" 'WATCHDOG'
echo old > "$W65/old.txt"; touch -t "$(python3 -c 'import datetime;print((datetime.datetime.now()-datetime.timedelta(minutes=125)).strftime("%Y%m%d%H%M"))')" "$W65/old.txt"
c1_fire "A65 a changed file older than 60 minutes: the watchdog line prints" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')" WATCHDOG_CLAUDE_DIR="$W65")" '^WATCHDOG: .*uncommitted'
c1_quiet "A65 a machine prompt never gets the watchdog line" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" '<task-notification>x</task-notification>')" WATCHDOG_CLAUDE_DIR="$W65")" 'WATCHDOG'
c1_quiet "A65 SessionStart gets no watchdog line" "$(c1_run "$(c1_in SessionStart "$TRC")" WATCHDOG_CLAUDE_DIR="$W65")" 'WATCHDOG'
mv "$W65/hooks/backup.conf" "$W65/hooks/backup.conf.off"
c1_quiet "A65 no hooks/backup.conf (the backup is not set up): silent even when dirty" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')" WATCHDOG_CLAUDE_DIR="$W65")" 'WATCHDOG'
mv "$W65/hooks/backup.conf.off" "$W65/hooks/backup.conf"
rm -f "$W65/old.txt" "$W65/fresh.txt"; echo local > "$W65/local.txt"; git -C "$W65" add -A >/dev/null 2>&1; "${ID[@]}" git -C "$W65" commit -q -m local-only >/dev/null 2>&1
c1_fire "A65 a commit not pushed to the remote: the watchdog line prints" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')" WATCHDOG_CLAUDE_DIR="$W65")" '^WATCHDOG: .*not pushed'
git -C "$W65" push -q >/dev/null 2>&1
c1_quiet "A65 pair: pushed again: silent" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')" WATCHDOG_CLAUDE_DIR="$W65")" 'WATCHDOG'
mkdir -p "$C1/nogit/hooks"; printf '# placeholder\n' > "$C1/nogit/hooks/backup.conf"
c1_quiet "A65 a folder that is not a git repo: silent" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')" WATCHDOG_CLAUDE_DIR="$C1/nogit")" 'WATCHDOG'

echo "  A33 the projects-root folder's own CLAUDE.md never counts as a project's"
CCM1="$T/c1-ccm-home"; mkdir -p "$CCM1/.claude/hooks" "$CCM1/repos/newproj/sub" "$CCM1/repos/oldproj/deep"
printf '## PROCESS RULES (enforced)\n1. x\n' > "$CCM1/.claude/CLAUDE.md"
printf 'ZzqInterviewMarkerC1\n' > "$CCM1/.claude/hooks/interview.md"
printf '%s\n' "$CCM1/repos" > "$CCM1/.claude/hooks/project-roots.conf"
printf 'shared rules\n' > "$CCM1/repos/CLAUDE.md"; printf 'own\n' > "$CCM1/repos/oldproj/CLAUDE.md"
ccm1() { printf '{"cwd":"%s"}' "$1" | env HOME="$CCM1" bash "$HOOKS_DIR/check-claude-md.sh" 2>/dev/null; }
if ccm1 "$CCM1/repos/newproj" | grep -q ZzqInterviewMarkerC1; then ok; else bad "A33 a new project must get the interview even when a shared CLAUDE.md sits at the projects root"; fi
refuse_n=$((refuse_n+1))
if ccm1 "$CCM1/repos/newproj/sub" | grep -q ZzqInterviewMarkerC1; then ok; else bad "A33 a subfolder of a new project must get the interview when the root holds a CLAUDE.md"; fi
refuse_n=$((refuse_n+1))
if ccm1 "$CCM1/repos/oldproj" | grep -q ZzqInterviewMarkerC1; then bad "A33 pair: a project with its OWN CLAUDE.md must not get the interview"; else ok; fi
pass_n=$((pass_n+1))
if ccm1 "$CCM1/repos/oldproj/deep" | grep -q ZzqInterviewMarkerC1; then bad "A33 pair: a subfolder of a project that has its own CLAUDE.md must not get the interview"; else ok; fi
pass_n=$((pass_n+1))
if ccm1 "$CCM1/elsewhere" | grep -q ZzqInterviewMarkerC1; then bad "A33 pair: a folder outside every root must not get the interview"; else ok; fi
pass_n=$((pass_n+1))

echo "  A87 the provenance wrappers prefer the fixed system python3 and fall back to the first on PATH"
PV="$C1/prov"; mkdir -p "$PV" "$C1/prov-state" "$C1/badpy" "$C1/goodpy" "$C1/onlydirname"
cp "$HOOKS_DIR/channel-provenance-pre.sh" "$HOOKS_DIR/channel-provenance-post.sh" "$HOOKS_DIR/provenance.py" "$PV/"
printf 'NOTES.md\n' > "$PV/channel-ceiling.conf"
PVR="$C1/provrepo"; mkdir -p "$PVR"; git -C "$PVR" init -q -b main; git -C "$PVR" config core.hooksPath /dev/null
echo seed > "$PVR/NOTES.md"; git -C "$PVR" add -A; "${ID[@]}" git -C "$PVR" commit -q -m init
REALPY3="$(command -v python3)"; BASH_BIN="$(command -v bash)"
printf '#!/bin/sh\nexit 1\n' > "$C1/badpy/python3"; chmod +x "$C1/badpy/python3"
printf '#!/bin/sh\nexec %s "$@"\n' "$REALPY3" > "$C1/goodpy/python3"; chmod +x "$C1/goodpy/python3"
ln -sf "$(command -v dirname)" "$C1/onlydirname/dirname"
pvjson() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":"echo x >> NOTES.md"},"cwd":sys.argv[1],"session_id":sys.argv[2]}))' "$PVR" "$1"; }
pv_run() { local sid="$1"; shift; rm -f "$C1/prov-state/$sid.json"; printf '%s' "$(pvjson "$sid")" | env PROVENANCE_STATE_DIR="$C1/prov-state" "$@" "$BASH_BIN" "$PV/channel-provenance-pre.sh" >/dev/null 2>&1; local rc=$?; [ -f "$C1/prov-state/$sid.json" ] && echo "written rc=$rc" || echo "none rc=$rc"; }
if [ "$(pv_run s87a GUARD_PYTHON_PREFERRED="$REALPY3" PATH="$C1/badpy:$PATH")" = "written rc=0" ]; then ok; else bad "A87 pre wrapper: a broken python3 first on PATH must not stop the snapshot (the preferred python runs)"; fi
refuse_n=$((refuse_n+1))
if [ "$(pv_run s87b GUARD_PYTHON_PREFERRED=/nonexistent/python3 PATH="$C1/goodpy:$PATH")" = "written rc=0" ]; then ok; else bad "A87 pre wrapper: with no preferred python3 the first on PATH is used"; fi
pass_n=$((pass_n+1))
if [ "$(pv_run s87c GUARD_PYTHON_PREFERRED=/nonexistent/python3 PATH="$C1/onlydirname")" = "none rc=0" ]; then ok; else bad "A87 pre wrapper: no python3 anywhere: exit 0 quietly, nothing written"; fi
pass_n=$((pass_n+1))
pv_post() { printf '%s' "$(pvjson s87d)" | env PROVENANCE_STATE_DIR="$C1/prov-state" GUARD_PYTHON_PREFERRED="$REALPY3" PATH="$C1/badpy:$PATH" "$BASH_BIN" "$PV/channel-provenance-pre.sh" >/dev/null 2>&1
  echo "session note" >> "$PVR/NOTES.md"
  printf '%s' "$(pvjson s87d)" | env PROVENANCE_STATE_DIR="$C1/prov-state" GUARD_PYTHON_PREFERRED="$REALPY3" PATH="$C1/badpy:$PATH" "$BASH_BIN" "$PV/channel-provenance-post.sh" >/dev/null 2>&1; echo "rc=$?"; }
rm -f "$C1/prov-state/s87d.json"; PVOUT="$(pv_post)"
if [ "$PVOUT" = "rc=0" ] && grep -q '"last_after"' "$C1/prov-state/s87d.json" 2>/dev/null; then ok; else bad "A87 post wrapper: with a broken PATH python3 the write must still be recorded (rc/out: $PVOUT; state: $(head -c 200 "$C1/prov-state/s87d.json" 2>/dev/null))"; fi
refuse_n=$((refuse_n+1))

echo "  A27 the target is the first token whose BASENAME is the channel name, not the first substring hit"
CSC="$C1/csz"; mkdir -p "$CSC/gitrepo/docs/plans" "$CSC/gitrepo/other"; cp "$HOOKS_DIR/channel-size-guard.sh" "$HOOKS_DIR/channel-size-post.sh" "$CSC/"
printf 'LIMIT=100\nNOTES.md words 10 20\n' > "$CSC/channel-ceiling.conf"
CW="$CSC/work"; mkdir -p "$CW"
w25c="$(python3 -c "print(' '.join(['w']*25))")"
printf '%s' "$w25c" > "$CW/NOTES.md"; printf 'a b c' > "$CW/proof-notes.md"; printf 'a b c' > "$CW/x.notes.md"
c1b() { INPUT="$(jb2 "$4" "$CW")"; expect "$1" "$2" "$3" bash "$CSC/channel-size-guard.sh"; }
c1b refuse 2 "A27 a look-alike file named first must not hide the real over-stop NOTES.md (tee -a proof-notes.md NOTES.md)" 'echo x | tee -a proof-notes.md NOTES.md'
c1b refuse 2 "A27 same with a dotted look-alike (tee -a x.notes.md NOTES.md)" 'echo x | tee -a x.notes.md NOTES.md'
c1b pass 0 "A27 pair: appending only to the look-alike proof-notes.md is allowed" 'echo x | tee -a proof-notes.md'
c1b pass 0 "A27 pair: NOTES.md.bak is not NOTES.md" 'echo x | tee -a NOTES.md.bak'
c1b refuse 2 "A27 pair: the real NOTES.md over its stop is still refused" 'cat proof-notes.md >> NOTES.md'

echo "  A28 a conf pattern with a slash matches the repo-relative path, not the bare file name"
CSD="$C1/csz-path"; mkdir -p "$CSD"; cp "$HOOKS_DIR/channel-size-guard.sh" "$HOOKS_DIR/channel-size-post.sh" "$CSD/"
printf 'LIMIT=100\ndocs/plans/NOTES.md words 10 20\n' > "$CSD/channel-ceiling.conf"
PR="$C1/pathrepo"; mkdir -p "$PR/docs/plans" "$PR/other"; git -C "$PR" init -q -b main
printf '%s' "$w25c" > "$PR/docs/plans/NOTES.md"; printf '%s' "$w25c" > "$PR/other/NOTES.md"
INPUT="$(je "$PR/docs/plans/NOTES.md" "w" "w w w w w w")"; expect refuse 2 "A28 growing the file at the conf's exact repo path is refused" bash "$CSD/channel-size-guard.sh"
INPUT="$(je "$PR/other/NOTES.md" "w" "w w w w w w")"; expect pass 0 "A28 the same name at another path in the repo is NOT the channel file (allowed)" bash "$CSD/channel-size-guard.sh"
INPUT="$(jb2 'echo x >> docs/plans/NOTES.md' "$PR")"; expect refuse 2 "A28 Bash append onto the exact repo path is refused" bash "$CSD/channel-size-guard.sh"
INPUT="$(jb2 'echo x >> other/NOTES.md' "$PR")"; expect pass 0 "A28 Bash append onto a same-named file elsewhere in the repo is allowed" bash "$CSD/channel-size-guard.sh"
NOGIT="$C1/pathnogit/docs/plans"; mkdir -p "$NOGIT"; printf '%s' "$w25c" > "$NOGIT/NOTES.md"
INPUT="$(je "$NOGIT/NOTES.md" "w" "w w w w w w")"; expect refuse 2 "A28 outside any git repo there is no repo path: the bare name is the whole test (refused)" bash "$CSD/channel-size-guard.sh"
printf '%s' "$w25c" > "$PR/other/NOTES.md"
o="$(printf '%s' "$(je "$PR/other/NOTES.md" old new)" | bash "$CSD/channel-size-post.sh" 2>&1)"
c1_quiet "A28 the post hook agrees: a same-named file elsewhere in the repo is not measured" "$o" 'NOTES.md'
o="$(printf '%s' "$(je "$PR/docs/plans/NOTES.md" old new)" | bash "$CSD/channel-size-post.sh" 2>&1)"
c1_fire "A28 pair: the post hook still names the file at the conf's path" "$o" 'NOTES.md'

echo "  A29 no band NOTE on stderr (nobody reads exit-0 stderr); the hard stop still refuses"
CSE="$C1/csz-note"; mkdir -p "$CSE/r"; cp "$HOOKS_DIR/channel-size-guard.sh" "$CSE/"
printf 'LIMIT=100\nNOTES.md words 10 20\n' > "$CSE/channel-ceiling.conf"
w15c="$(python3 -c "print(' '.join(['w']*15))")"; printf '%s' "$w15c" > "$CSE/r/NOTES.md"
o="$(printf '%s' "$(je "$CSE/r/NOTES.md" w "w w")" | bash "$CSE/channel-size-guard.sh" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ -z "$o" ]; then ok; else bad "A29 growth inside the band must print nothing and exit 0 (rc=$rc out='$o')"; fi
pass_n=$((pass_n+1))
o="$(printf '%s' "$(jb2 'echo x >> NOTES.md' "$CSE/r")" | bash "$CSE/channel-size-guard.sh" 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ -z "$o" ]; then ok; else bad "A29 a Bash append inside the band must print nothing and exit 0 (rc=$rc out='$o')"; fi
pass_n=$((pass_n+1))
o="$(printf '%s' "$(je "$CSE/r/NOTES.md" w "w w w w w w w w")" | bash "$CSE/channel-size-guard.sh" 2>&1)"; rc=$?
if [ "$rc" = 2 ] && printf '%s' "$o" | grep -q 'REFUSED'; then ok; else bad "A29 pair: growth past the hard stop is still refused with a message (rc=$rc out='$o')"; fi
refuse_n=$((refuse_n+1))

echo "  A26 (partial) a python open(...,'a') appending to a watched file is judged on its current size, heredoc or -c"
CSF="$C1/csz-py"; mkdir -p "$CSF/r"; cp "$HOOKS_DIR/channel-size-guard.sh" "$CSF/"
printf 'LIMIT=100\nNOTES.md words 10 20\n' > "$CSF/channel-ceiling.conf"
printf '%s' "$w25c" > "$CSF/r/NOTES.md"; mkdir -p "$CSF/small"; printf 'a b c' > "$CSF/small/NOTES.md"
INPUT="$(jb2 "python3 -c \"open('NOTES.md','a').write('x')\"" "$CSF/r")"; expect refuse 2 "A26 python -c open(NOTES.md,'a') on an over-stop file is refused" bash "$CSF/channel-size-guard.sh"
INPUT="$(jb2 $'python3 - <<\'E\'\nopen("NOTES.md", "a").write("x")\nE' "$CSF/r")"; expect refuse 2 "A26 the same inside a python heredoc is refused" bash "$CSF/channel-size-guard.sh"
INPUT="$(jb2 "python3 -c \"open('NOTES.md','a').write('x')\"" "$CSF/small")"; expect pass 0 "A26 pair: the same append on a small file is allowed" bash "$CSF/channel-size-guard.sh"
INPUT="$(jb2 "python3 -c \"print(open('NOTES.md').read())\"" "$CSF/r")"; expect pass 0 "A26 pair: a python READ of an over-stop file is allowed" bash "$CSF/channel-size-guard.sh"
INPUT="$(jb2 "python3 -c \"open('proof-notes.md','a').write('x')\"" "$CSF/r")"; expect pass 0 "A26 pair: a python append to a look-alike file is allowed" bash "$CSF/channel-size-guard.sh"
INPUT="$(jb2 "sed -i '' '5,\$d' NOTES.md" "$CSF/r")"; expect pass 0 "A26 deferred forms stay allowed (M8): sed -i, a sweep, on an over-stop file" bash "$CSF/channel-size-guard.sh"

echo "refresh 2026-09-29 (c2a): opt-in multi-chat group, the end-of-turn check and its prompt-time helpers (A03 A04 A40 A41 A42 A43 A44 A45 A46 A47 A48 A69 A70 A71)"
C2="$T/c2a"; HK="$C2/hk"; mkdir -p "$HK"
cp "$HOOKS_DIR/stop-state-check.sh" "$HOOKS_DIR/doorman.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/clock-in-context.sh" "$HK/"
# The role names below are plain words plus digits built into FOLDER names at run time.
c2_conf() { local l; { printf 'STATE_FILE state/{role}.md\n'; for l in "$@"; do printf '%s\n' "$l"; done; } > "$HK/state-check.conf"; }
c2_repo() {   # <dir> [role]: a git repo with a filled state file state/<role>.md, a README, a file two folders down
  local d="$1" r="${2:-dev}"
  mkdir -p "$d/state" "$d/sub/deep"; git -C "$d" init -q -b main; git -C "$d" config core.hooksPath /dev/null
  printf '**Current task:** first\n**Next step:** second\n' > "$d/state/$r.md"; echo seed > "$d/README.md"; echo x > "$d/sub/deep/f.txt"
  git -C "$d" add -A; "${ID[@]}" git -C "$d" commit -q -m init
}
c2_tp() {   # <file> <K> [agent]: a transcript whose newest usage line sums to K thousand tokens, after a human-origin prompt line
  local f="$1" k="$2"
  printf '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"go"}}\n' > "$f"
  [ "${3:-}" = agent ] && printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Agent","input":{}}]}}\n' >> "$f"
  printf '{"type":"assistant","message":{"usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":%d,"output_tokens":5}}}\n' $(( (k - 1) * 1000 )) >> "$f"
}
c2_sj() {   # <cwd> <sid> <active> <transcript> [crons-json-array]: the Stop hook's stdin
  python3 -c 'import json,sys
d={"cwd":sys.argv[1],"session_id":sys.argv[2],"stop_hook_active":sys.argv[3]=="true","transcript_path":sys.argv[4]}
if len(sys.argv)>5: d["session_crons"]=[{"prompt":p} for p in json.loads(sys.argv[5])]
print(json.dumps(d))' "$@"
}
c2_stop() {   # <cwd> <sid> <active> <transcript> [crons]: run the Stop hook against $S; stdout -> $C2/out, stderr -> $C2/err
  c2_sj "$@" | STATE_CHECK_STATE_DIR="$S" bash "$HK/stop-state-check.sh" > "$C2/out" 2> "$C2/err"; C2_RC=$?
}
c2_prompt() {   # <cwd> <sid> [transcript] [prompt]: run the prompt hook against $S; stdout -> $C2/pout, rc in $C2_PRC
  dj "$1" "$2" "${4:-hello}" "${3:-}" | STATE_CHECK_STATE_DIR="$S" bash "$HK/doorman.sh" > "$C2/pout" 2> "$C2/perr"; C2_PRC=$?
}
c2_chk() { local kind="$1" label="$2"; shift 2; if "$@"; then ok; else bad "$label"; fi; if [ "$kind" = refuse ]; then refuse_n=$((refuse_n+1)); else pass_n=$((pass_n+1)); fi; }
has() { grep -q -- "$1" "$2"; }
nothas() { ! grep -q -- "$1" "$2"; }
isjson() { python3 -c 'import json,sys;json.loads(sys.stdin.read())' < "$1" 2>/dev/null; }
starts_brace() { [ "$(head -c1 "$1")" = "{" ]; }
role_of() { ( . "$HK/guard-lib.sh"; hook_role_from_cwd "$1" "${2:-$HK/state-check.conf}" ); }
eq() { [ "$1" = "$2" ]; }
SENT="$C2/sentinel"; NOW=$(date +%s)

echo "  A42 the RETIRED sentence goes to stderr: it must never sit ahead of a state-file block on stdout"
S="$C2/s-a42"; R="$C2/myapp-dev1"; c2_repo "$R"; c2_conf 'myapp-dev*  dev  5'; c2_tp "$C2/tp-a42" 8
c2_prompt "$R" a42; echo more >> "$R/README.md"
c2_stop "$R" a42 false "$C2/tp-a42"
c2_chk refuse "A42 retire + state-file block on one turn: stdout is exactly one decision JSON" isjson "$C2/out"
c2_chk refuse "A42 the block is the state-file one and stdout starts with {" starts_brace "$C2/out"
c2_chk refuse "A42 the state-file block names the untouched state file" has 'state/dev.md did not change' "$C2/out"
c2_chk pass "A42 pair: the RETIRED sentence is still said, on stderr" has 'RETIRED at 8k' "$C2/err"
c2_chk pass "A42 pair: the RETIRED sentence is not on stdout" nothas 'RETIRED' "$C2/out"
c2_chk pass "A42 pair: the retirement marker is still written" test -f "$S/retired/a42"

echo "  A03 the role reader: git toplevel folder name, lower-cased, cut at the first digit, trailing hyphen dropped, aliases from the conf"
c2_conf 'myapp-dev*  dev  850'
R="$C2/myapp-dev3"; c2_repo "$R"
c2_chk refuse "A03 a chat opened two folders down reads the toplevel folder's role (myapp-dev3 -> myapp-dev)" eq "$(role_of "$R/sub/deep")" "myapp-dev"
mkdir -p "$C2/MyApp-Dev-7x"
c2_chk pass "A03 pair: not a git folder -> its own name; lower-cased, cut at the first digit, hyphen dropped (MyApp-Dev-7x)" eq "$(role_of "$C2/MyApp-Dev-7x")" "myapp-dev"
c2_conf 'myapp-dev*  dev  850' 'ROLE_ALIAS myapp-dev dev'
c2_chk refuse "A03 a ROLE_ALIAS line in the conf renames the derived role" eq "$(role_of "$R/sub")" "dev"
c2_conf 'myapp-dev*  dev  850'
c2_chk pass "A03 pair: without the alias line the role is the derived name" eq "$(role_of "$R/sub")" "myapp-dev"
mkdir -p "$C2/42"
role_of "$C2/42" >/dev/null 2>&1; c2_chk pass "A03 a folder name that is only digits gives no role (exit 1)" eq "$?" "1"
S="$C2/s-a03"; c2_conf 'myapp-dev*  dev  850'
c2_prompt "$R/sub/deep" a03; echo more >> "$R/README.md"
c2_chk refuse "A03 the prompt hook run from a subfolder still writes the turn snapshot" test -s "$S/turnsnap/a03"
c2_stop "$R/sub/deep" a03 false ""
c2_chk refuse "A03 a Stop from a subfolder of a matching seat folder is judged (state file untouched: block)" has '"decision":"block"' "$C2/out"
O="$C2/other-2"; c2_repo "$O"; c2_prompt "$O/sub/deep" a03b; echo more >> "$O/README.md"; c2_stop "$O/sub/deep" a03b false ""
c2_chk pass "A03 pair: a subfolder of a folder the conf does not name stays inert" test ! -s "$C2/out"
c2_conf 'myapp-dev3  dev  850'
c2_prompt "$R" a03c; echo more >> "$R/README.md"; c2_stop "$R" a03c false ""
c2_chk refuse "A03 a conf glob written WITH the digit still matches the folder as written (myapp-dev3)" has '"decision":"block"' "$C2/out"
AR="$C2/autoapp-Senior-2"; c2_repo "$AR" senior; c2_conf 'autoapp-*  auto  850' 'ROLE_ALIAS autoapp-senior senior'
S="$C2/s-a03d"; c2_prompt "$AR" a03d; echo more >> "$AR/README.md"; c2_stop "$AR" a03d false ""
c2_chk refuse "A03 role 'auto' + ROLE_ALIAS: the state file is state/senior.md" has 'state/senior.md did not change' "$C2/out"
c2_conf 'autoapp-*  auto  850'
c2_prompt "$AR" a03e; echo more2 >> "$AR/README.md"; c2_stop "$AR" a03e false ""
c2_chk pass "A03 pair: 'auto' without an alias uses the derived name (state/autoapp-senior.md)" has 'state/autoapp-senior.md did not change' "$C2/out"
HK2="$C2/hk-nolib"; mkdir -p "$HK2"; cp "$HOOKS_DIR/stop-state-check.sh" "$HOOKS_DIR/doorman.sh" "$HK2/"; printf 'STATE_FILE state/{role}.md\nmyapp-dev*  dev  850\n' > "$HK2/state-check.conf"
c2_sj "$R" a03f false "" | STATE_CHECK_STATE_DIR="$S" bash "$HK2/stop-state-check.sh" > "$C2/out" 2> "$C2/err"; rcl=$?
c2_chk pass "A03 the Stop hook without guard-lib.sh beside it does nothing and says so on stderr (fail open)" bash -c "[ $rcl = 0 ] && [ ! -s '$C2/out' ] && grep -q guard-lib '$C2/err'"
dj "$R" a03g hello "" | STATE_CHECK_STATE_DIR="$S" bash "$HK2/doorman.sh" > "$C2/out" 2> "$C2/err"; rcl=$?
c2_chk pass "A03 the prompt hook without guard-lib.sh beside it passes (exit 0) and says so on stderr" bash -c "[ $rcl = 0 ] && grep -q guard-lib '$C2/err'"

echo "  A04 the unattended-run reader: one file, an end time in epoch seconds; missing, garbled or past is a normal run"
UF="$C2/unatt"; c2_conf "UNATTENDED_UNTIL $UF"
ua() { ( . "$HK/guard-lib.sh"; unattended_run_active "$HK/state-check.conf" ); }
echo $((NOW + 3600)) > "$UF"; ua; c2_chk refuse "A04 an end time in the future: the run is unattended (exit 0)" eq "$?" "0"
echo $((NOW - 3600)) > "$UF"; ua; c2_chk pass "A04 an end time in the past: a normal run (exit 1)" eq "$?" "1"
echo "tomorrow" > "$UF"; ua; c2_chk pass "A04 a garbled file: a normal run" eq "$?" "1"
: > "$UF"; ua; c2_chk pass "A04 an empty file: a normal run" eq "$?" "1"
rm -f "$UF"; ua; c2_chk pass "A04 a missing file: a normal run" eq "$?" "1"
printf '%s\n%s\n' $((NOW + 3600)) 5 > "$UF"; ua; c2_chk refuse "A04 only the first line counts" eq "$?" "0"
c2_conf 'myapp-dev*  dev  850'; mkdir -p "$HOME/.claude/state"; echo $((NOW + 3600)) > "$HOME/.claude/state/unattended-until"
ua; c2_chk refuse "A04 no conf key: the default file is under ~/.claude/state/" eq "$?" "0"
rm -f "$HOME/.claude/state/unattended-until"; ua; c2_chk pass "A04 pair: default file removed: normal run" eq "$?" "1"
c2_conf 'UNATTENDED_UNTIL ~/.claude/state/u2'; echo $((NOW + 3600)) > "$HOME/.claude/state/u2"
ua; c2_chk refuse "A04 a leading ~/ in the conf path is expanded" eq "$?" "0"; rm -f "$HOME/.claude/state/u2"

echo "  A45 the wrap-up: the first Stop past WRAPUP_K in a listed role, once, never twice in one Stop output"
R="$C2/myapp-dev4"; c2_repo "$R"; c2_conf 'myapp-dev*  dev  850'; S="$C2/s-a45"
c2_tp "$C2/tp600" 600; c2_tp "$C2/tp599" 599
c2_prompt "$R" w1; c2_stop "$R" w1 false "$C2/tp600"
c2_chk refuse "A45 first Stop at 600k in a dev role, nothing else to say: the wrap-up block" has 'wrap-up point' "$C2/out"
c2_chk refuse "A45 the wrap-up block is one decision JSON" isjson "$C2/out"
c2_chk refuse "A45 it leaves the once-per-session marker" test -f "$S/wrapup-fired/w1"
c2_stop "$R" w1 false "$C2/tp600"
c2_chk pass "A45 pair: the second Stop of the same session says nothing" test ! -s "$C2/out"
c2_prompt "$R" w2; c2_stop "$R" w2 true "$C2/tp600"
c2_chk pass "A45 pair: never on the forced second stop (stop_hook_active)" test ! -s "$C2/out"
c2_chk pass "A45 pair: and that forced stop leaves no marker" test ! -f "$S/wrapup-fired/w2"
c2_prompt "$R" w3; c2_stop "$R" w3 false "$C2/tp599"
c2_chk pass "A45 pair: 599k is under the point: nothing" test ! -s "$C2/out"
c2_conf 'myapp-dev*  docs  850'; c2_prompt "$R" w4; c2_stop "$R" w4 false "$C2/tp600"
c2_chk pass "A45 pair: a role not in WRAPUP_ROLES (docs) gets no wrap-up" test ! -s "$C2/out"
c2_conf 'myapp-dev*  docs  850' 'WRAPUP_ROLES *'; c2_prompt "$R" w5; c2_stop "$R" w5 false "$C2/tp600"
c2_chk refuse "A45 WRAPUP_ROLES * reaches every role" has 'wrap-up point' "$C2/out"
c2_conf 'myapp-dev*  docs  850' 'WRAPUP_ROLES Docs qa'; c2_prompt "$R" w5b; c2_stop "$R" w5b false "$C2/tp600"
c2_chk refuse "A45 WRAPUP_ROLES names are matched case-insensitively" has 'wrap-up point' "$C2/out"
c2_tp "$C2/tp300" 300; c2_tp "$C2/tp299" 299
c2_conf 'myapp-dev*  dev  850' 'WRAPUP_K 300'; c2_prompt "$R" w6; c2_stop "$R" w6 false "$C2/tp300"
c2_chk refuse "A45 WRAPUP_K 300: a 300k chat is wrapped up" has '300k wrap-up point' "$C2/out"
c2_prompt "$R" w7; c2_stop "$R" w7 false "$C2/tp299"
c2_chk pass "A45 pair: WRAPUP_K 300: 299k is not" test ! -s "$C2/out"
c2_conf 'myapp-dev*  dev  850' "UNATTENDED_UNTIL $C2/unatt2"; echo $((NOW + 3600)) > "$C2/unatt2"
c2_prompt "$R" w8; c2_stop "$R" w8 false "$C2/tp600"
c2_chk pass "A45 an unattended run on: no wrap-up" test ! -s "$C2/out"
c2_chk pass "A45 an unattended run on: no marker either" test ! -f "$S/wrapup-fired/w8"
c2_prompt "$R" w8b; echo more >> "$R/README.md"; c2_stop "$R" w8b false "$C2/tp600"
c2_chk refuse "A45 the unattended run suppresses ONLY the wrap-up: the state-file block still fires" has 'state/dev.md did not change' "$C2/out"
git -C "$R" checkout -q -- README.md
echo $((NOW - 3600)) > "$C2/unatt2"; c2_prompt "$R" w9; c2_stop "$R" w9 false "$C2/tp600"
c2_chk refuse "A45 an expired unattended file is a normal run: wrap-up" has 'wrap-up point' "$C2/out"
c2_conf 'myapp-dev*  dev  850'; c2_prompt "$R" w10; echo more >> "$R/README.md"; c2_stop "$R" w10 false "$C2/tp600"
c2_chk refuse "A45 the state-file block comes first: at 600k with the state file untouched the ONE output is that block" has 'state/dev.md did not change' "$C2/out"
c2_chk refuse "A45 ... and it is a single JSON object, not two" isjson "$C2/out"
c2_chk pass "A45 ... and no wrap-up marker was spent on it" test ! -f "$S/wrapup-fired/w10"
git -C "$R" checkout -q -- README.md

echo "  A40 the turn snapshot (HEAD, state-file hash, content hash of the tracked diff): a commit-only turn is caught, a second edit is seen, a turn that changed nothing passes"
R="$C2/myapp-dev5"; c2_repo "$R"; c2_conf 'myapp-dev*  dev  850'; S="$C2/s-a40"
c2_prompt "$R" c1; echo more >> "$R/README.md"; "${ID[@]}" git -C "$R" commit -q -am "commit only"
c2_stop "$R" c1 false ""
c2_chk refuse "A40 a turn that only COMMITTED (tree clean at the end) with the state file untouched is blocked" has 'did not change since the turn started' "$C2/out"
c2_prompt "$R" c2; c2_stop "$R" c2 false ""
c2_chk pass "A40 pair: a turn that changed nothing passes" test ! -s "$C2/out"
echo one >> "$R/README.md"; c2_prompt "$R" c3; echo two >> "$R/README.md"; c2_stop "$R" c3 false ""
c2_chk refuse "A40 a second edit of an already-dirty file is seen (same path, new content)" has '"decision":"block"' "$C2/out"
c2_prompt "$R" c4; c2_stop "$R" c4 false ""
c2_chk pass "A40 pair: an already-dirty tree and a read-only turn: pass" test ! -s "$C2/out"
c2_prompt "$R" c5; echo newfile > "$R/scratch.txt"; c2_stop "$R" c5 false ""
c2_chk pass "A40 pair: a turn that only created an UNTRACKED file is not a change" test ! -s "$C2/out"; rm -f "$R/scratch.txt"
c2_prompt "$R" c6; sed 's/^\*\*Next step:\*\* second$/**Next step:** shipped/' "$R/state/dev.md" > "$R/state/dev.new" && mv "$R/state/dev.new" "$R/state/dev.md"; echo three >> "$R/README.md"; "${ID[@]}" git -C "$R" commit -q -am "work and state"
c2_stop "$R" c6 false ""
c2_chk pass "A40 pair: a commit-only turn that also moved the state file's Next step passes" test ! -s "$C2/out"
c2_prompt "$R" c7; echo four >> "$R/README.md"; "${ID[@]}" git -C "$R" commit -q -am more
printf 'M  README.md\n' > "$S/turnsnap/c7"; echo dirty >> "$R/README.md"
c2_stop "$R" c7 false ""
c2_chk pass "A40 an old-format (single text line) snapshot counts as no snapshot: no block" nothas '"decision"' "$C2/out"
c2_chk pass "A40 ... and the note says there is no turn snapshot" has 'no turn snapshot' "$C2/out"
echo five >> "$R/README.md"; rm -f "$S/turnsnap/c8"; c2_stop "$R" c8 false ""
c2_chk pass "A40 no snapshot at all: still a note, never a block" has 'no turn snapshot' "$C2/out"
git -C "$R" checkout -q -- README.md 2>/dev/null
c2_prompt "$R" ""; c2_chk refuse "A40 the prompt hook with no session id writes a snapshot under a folder-name key" test -s "$S/turnsnap/nosid-myapp-dev5"

echo "  A71 the writer half: the prompt hook writes five tab-separated fields the Stop hook compares against"
R="$C2/myapp-dev6"; c2_repo "$R"; S="$C2/s-a71"; c2_prompt "$R" s71
snapline="$(cat "$S/turnsnap/s71" 2>/dev/null)"
c2_chk refuse "A71 the snapshot is five tab-separated fields (the fifth is the repo folder: attack fixes (3) M4)" bash -c "[ \"\$(printf '%s' '$snapline' | awk -F'\t' '{print NF}')\" = 5 ]"
c2_chk pass "A71 field 1 is HEAD" eq "$(printf '%s' "$snapline" | cut -f1)" "$(git -C "$R" rev-parse HEAD)"
c2_chk pass "A71 field 2 is the state file's hash" eq "$(printf '%s' "$snapline" | cut -f2)" "$(git -C "$R" hash-object "$R/state/dev.md")"
c2_chk pass "A71 field 3 is the hash of the tracked diff (a clean tree: the empty hash)" eq "$(printf '%s' "$snapline" | cut -f3)" "$(: | git -C "$R" hash-object --stdin)"
echo more >> "$R/README.md"; c2_prompt "$R" s71b; snapline2="$(cat "$S/turnsnap/s71b")"
c2_chk refuse "A71 the tracked diff's hash moves when a tracked file changes" bash -c "[ '$(printf '%s' "$snapline" | cut -f3)' != '$(printf '%s' "$snapline2" | cut -f3)' ]"
git -C "$R" checkout -q -- README.md; rm -f "$R/state/dev.md"; git -C "$R" rm -q --cached state/dev.md 2>/dev/null; c2_prompt "$R" s71c
c2_chk pass "A71 no state file: its two hashes read none" bash -c "[ \"\$(cut -f2 '$S/turnsnap/s71c')\" = none ] && [ \"\$(cut -f4 '$S/turnsnap/s71c')\" = none ]"

echo "  A41 the FIRST Current task / Next step lines are canonical; a prose mention or a second marker line is not a handover"
R="$C2/myapp-dev7"; c2_repo "$R"; c2_conf 'myapp-dev*  dev  850'; S="$C2/s-a41"
c2_prompt "$R" m1; echo edit >> "$R/README.md"; echo 'as the **Current task:** line above says' >> "$R/state/dev.md"
c2_stop "$R" m1 false ""
c2_chk refuse "A41 a prose mention of the marker appended to the state file is not the line moving" has 'FIRST line that starts with' "$C2/out"
git -C "$R" checkout -q -- .
c2_prompt "$R" m2; echo edit >> "$R/README.md"; echo '**Next step:** an appended duplicate' >> "$R/state/dev.md"
c2_stop "$R" m2 false ""
c2_chk refuse "A41 a second **Next step:** line appended below the real one is not the line moving" has 'FIRST line that starts with' "$C2/out"
git -C "$R" checkout -q -- .
c2_prompt "$R" m3; echo edit >> "$R/README.md"; sed 's/^\*\*Next step:\*\* second$/**Next step:** reviewed/' "$R/state/dev.md" > "$R/state/dev.new" && mv "$R/state/dev.new" "$R/state/dev.md"
c2_stop "$R" m3 false ""
c2_chk pass "A41 pair: the FIRST Next step line rewritten passes" test ! -s "$C2/out"
git -C "$R" checkout -q -- .
c2_prompt "$R" m4; echo edit >> "$R/README.md"; sed 's/^\*\*Current task:\*\* first$/**Current task:**/' "$R/state/dev.md" > "$R/state/dev.new" && mv "$R/state/dev.new" "$R/state/dev.md"
c2_stop "$R" m4 false ""
c2_chk refuse "A41 a first Current task line emptied: 'missing a filled' block" has 'missing a filled' "$C2/out"
git -C "$R" checkout -q -- .
sed 's/^\*\*Next step:\*\* second$/**Next step:** carried over/' "$R/state/dev.md" > "$R/state/dev.new" && mv "$R/state/dev.new" "$R/state/dev.md"
c2_prompt "$R" m5; echo edit >> "$R/README.md"; printf '   \n' >> "$R/state/dev.md"
c2_stop "$R" m5 false ""
c2_chk refuse "A41 a state file already dirty at turn start: a whitespace-only append is still not a handover" has 'FIRST line that starts with' "$C2/out"
git -C "$R" checkout -q -- .

echo "  A46 the state file and every git call are resolved from the git toplevel, never the raw folder"
R="$C2/myapp-dev8"; c2_repo "$R"; c2_conf 'myapp-dev*  dev  850'; S="$C2/s-a46"
c2_prompt "$R/sub/deep" t1; echo edit >> "$R/README.md"; sed 's/^\*\*Next step:\*\* second$/**Next step:** done from below/' "$R/state/dev.md" > "$R/state/dev.new" && mv "$R/state/dev.new" "$R/state/dev.md"
c2_stop "$R/sub/deep" t1 false ""
c2_chk pass "A46 a Stop from two folders down finds the toplevel state file and passes" test ! -s "$C2/out"
git -C "$R" checkout -q -- .
c2_prompt "$R/sub/deep" t2; echo edit >> "$R/README.md"; c2_stop "$R/sub/deep" t2 false ""
c2_chk refuse "A46 pair: from two folders down with the state file untouched: blocked, naming the toplevel path" has 'state/dev.md did not change' "$C2/out"
git -C "$R" checkout -q -- .

echo "  A43 a symlink is never followed: inbox, its folder, turn-start, tell, the turn snapshot"
R="$C2/myapp-dev9"; c2_repo "$R"; c2_conf 'myapp-dev*  dev  5'; S="$C2/s-a43"; c2_tp "$C2/tp8" 8
echo keep > "$SENT"; mkdir -p "$S/inbox"; ln -s "$SENT" "$S/inbox/dev.md"; echo edit >> "$R/README.md"
c2_stop "$R" l1 false "$C2/tp8"
c2_chk refuse "A43 a symlinked inbox file: the target is left untouched" eq "$(cat "$SENT")" "keep"
c2_chk refuse "A43 ... and the hook says it skipped the record" has 'symlink' "$C2/err"
S="$C2/s-a43b"; c2_stop "$R" l2 false "$C2/tp8"
c2_chk pass "A43 pair: a plain inbox gets the retirement record" has 'RETIRED with uncommitted tracked changes' "$S/inbox/dev.md"
S="$C2/s-a43c"; mkdir -p "$C2/inboxtarget" "$S"; ln -s "$C2/inboxtarget" "$S/inbox"
c2_stop "$R" l3 false "$C2/tp8"
c2_chk refuse "A43 a symlinked inbox FOLDER: nothing written into its target" test -z "$(ls -A "$C2/inboxtarget")"
S="$C2/s-a43d"; mkdir -p "$S/turn-start"; ln -s "$SENT" "$S/turn-start/l4"
c2_stop "$R" l4 false "$C2/tp8"
c2_chk refuse "A43 a symlinked turn-start/<sid> is not written through" eq "$(cat "$SENT")" "keep"
c2_conf 'myapp-dev*  dev  850'; c2_tp "$C2/tp140" 140
S="$C2/s-a43e"; mkdir -p "$S/turn-start" "$S/tell"; echo 100 > "$S/turn-start/l5"; ln -s "$SENT" "$S/tell/l5"
c2_stop "$R" l5 false "$C2/tp140"
c2_chk refuse "A43 a symlinked tell/<sid> is not written through, though a tell was due" eq "$(cat "$SENT")" "keep"
S="$C2/s-a43f"; mkdir -p "$S/turnsnap"; printf '%s\t%s\t%s\t%s\n' "$(git -C "$R" rev-parse HEAD)" none "$(: | git -C "$R" hash-object --stdin)" none > "$C2/goodsnap"; ln -s "$C2/goodsnap" "$S/turnsnap/l6"
c2_stop "$R" l6 false ""
c2_chk refuse "A43 a symlinked turn snapshot is not followed (it would have blocked)" nothas '"decision"' "$C2/out"
c2_chk refuse "A43 ... and the hook says so" has 'symlink' "$C2/err"
git -C "$R" checkout -q -- .
S="$C2/s-a43g"; mkdir -p "$S/turn-start" "$S/tell" "$S/turnsnap"; ln -s "$SENT" "$S/turn-start/l7"; ln -s "$SENT" "$S/turnsnap/l7"; ln -s "$SENT" "$S/tell/l7"
c2_prompt "$R" l7 "$C2/tp140"
c2_chk refuse "A43 the prompt hook writes through none of turn-start, turnsnap (sentinel intact)" eq "$(cat "$SENT")" "keep"
c2_chk refuse "A43 the prompt hook neither shows nor deletes a symlinked tell" bash -c "[ -L '$S/tell/l7' ] && ! grep -q 'helper tell' '$C2/pout'"

echo "  A44 the helper tell (Stop half): a big turn with no helper leaves a one-line file, never stdout"
R="$C2/myapp-dev10"; c2_repo "$R"; c2_conf 'myapp-dev*  dev  850'; S="$C2/s-a44"
mkdir -p "$S/turn-start"; echo 100 > "$S/turn-start/h1"; c2_stop "$R" h1 false "$C2/tp140"
c2_chk refuse "A44 140k now, 100k at turn start, no helper launched: the tell file holds the growth" eq "$(cat "$S/tell/h1" 2>/dev/null)" "40"
c2_chk refuse "A44 the tell never goes to stdout" test ! -s "$C2/out"
c2_tp "$C2/tp140a" 140 agent; echo 100 > "$S/turn-start/h2"; c2_stop "$R" h2 false "$C2/tp140a"
c2_chk pass "A44 pair: an Agent launched this turn: no tell" test ! -e "$S/tell/h2"
c2_tp "$C2/tp120" 120; echo 100 > "$S/turn-start/h3"; c2_stop "$R" h3 false "$C2/tp120"
c2_chk pass "A44 pair: 20k of growth is under the threshold: no tell" test ! -e "$S/tell/h3"
c2_stop "$R" h4 false "$C2/tp140"
c2_chk pass "A44 pair: no turn-start snapshot: no tell" test ! -e "$S/tell/h4"
c2_conf 'myapp-dev*  dev  850' 'TELL_EXEMPT_ROLES Dev qa'; echo 100 > "$S/turn-start/h5"; c2_stop "$R" h5 false "$C2/tp140"
c2_chk pass "A44 pair: an exempt role (matched case-insensitively): no tell" test ! -e "$S/tell/h5"
c2_conf 'myapp-dev*  dev  850' 'TELL_GROWTH_K 50'; echo 100 > "$S/turn-start/h6"; c2_stop "$R" h6 false "$C2/tp140"
c2_chk pass "A44 pair: TELL_GROWTH_K 50 with 40k of growth: no tell" test ! -e "$S/tell/h6"
c2_conf 'myapp-dev*  dev  850' 'TELL_GROWTH_K 40'; echo 100 > "$S/turn-start/h7"; c2_stop "$R" h7 false "$C2/tp140"
c2_chk refuse "A44 TELL_GROWTH_K 40 with 40k of growth (inclusive): tell" test -e "$S/tell/h7"
c2_conf 'myapp-dev*  dev  850'; c2_stop "$R" h8 false "$C2/tp140"
c2_chk refuse "A44 the Stop hook rewrites the turn-start size with this turn's end size" eq "$(cat "$S/turn-start/h1")" "140"
printf '{"type":"assistant","message":{"usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":139000,"output_tokens":5}}}\n' > "$C2/tp-noprompt"; echo 100 > "$S/turn-start/h9"
c2_stop "$R" h9 false "$C2/tp-noprompt"
c2_chk pass "A44 pair: no human/peer prompt line to anchor the turn: no tell" test ! -e "$S/tell/h9"

echo "  A69 the tell's reader half and the turn-start size: the prompt hook shows the tell once, only on a passing prompt"
R="$C2/myapp-dev11"; c2_repo "$R"; c2_conf 'myapp-dev*  dev  850'; S="$C2/s-a69"; mkdir -p "$S/tell" "$S/retired" "$S/retired-compacts"
echo 41 > "$S/tell/p1"; c2_prompt "$R" p1
c2_chk refuse "A69 a passing prompt shows the tell (stdout, with the number)" has 'context by 41k' "$C2/pout"
c2_chk refuse "A69 ... and deletes it" test ! -e "$S/tell/p1"
c2_prompt "$R" p1
c2_chk pass "A69 pair: the next prompt shows nothing" nothas 'helper tell' "$C2/pout"
echo 42 > "$S/tell/p2"; echo "2026-01-01 00:00 dev 900k" > "$S/retired/p2"; echo 0 > "$S/retired-compacts/p2"; c2_prompt "$R" p2
c2_chk refuse "A69 a HELD prompt (retired session, exit 2) does not show the tell" bash -c "[ $C2_PRC = 2 ] && ! grep -q 'helper tell' '$C2/pout'"
c2_chk refuse "A69 ... and leaves it for the next prompt that passes" test -f "$S/tell/p2"
rm -f "$S/retired/p2"; c2_prompt "$R" p2
c2_chk refuse "A69 the survivor shows once the prompt passes" has 'context by 42k' "$C2/pout"
echo abc > "$S/tell/p3"; c2_prompt "$R" p3
c2_chk pass "A69 pair: a garbled tell file shows nothing" nothas 'helper tell' "$C2/pout"
echo 43 > "$S/tell/other"; c2_prompt "$R" p4
c2_chk pass "A69 pair: another session's tell is not shown" nothas 'helper tell' "$C2/pout"
c2_prompt "$R" p5 "$C2/tp140"
c2_chk refuse "A69 the prompt hook writes the turn-start size (140k transcript -> 140)" eq "$(cat "$S/turn-start/p5" 2>/dev/null)" "140"
c2_prompt "$R" "../x" "$C2/tp140"
c2_chk pass "A69 pair: a traversal-shaped session id writes no turn-start file" test ! -e "$S/x"
c2_prompt "$C2/nowhere-dir" p6
c2_chk pass "A69 pair: a folder the conf does not name: the prompt hook is inert" bash -c "[ $C2_PRC = 0 ] && [ ! -s '$C2/pout' ]"

echo "  A47 scheduled prompts are registered from the Stop input (needs jq; skipped silently without it)"
R="$C2/myapp-dev12"; c2_repo "$R"; c2_conf 'myapp-dev*  dev  850'; S="$C2/s-a47"
c2_stop "$R" k1 false "" '["  check the build  ","second one"]'
c2_chk refuse "A47 the session's cron prompts land in crons/<sid>, one per line, trimmed" eq "$(cat "$S/crons/k1" 2>/dev/null | tr '\n' '|')" '"check the build"|"second one"|'
c2_stop "$R" k1 false "" '[]'
c2_chk pass "A47 pair: an empty list removes the file" test ! -e "$S/crons/k1"
NOJQ="$C2/nojq"; mkdir -p "$NOJQ"; for tl in bash git head tail tr date mkdir rm cat cut sed grep awk sort dirname basename wc xargs env python3 find; do p="$(command -v $tl 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$NOJQ/$tl"; done
c2_chk pass "A47 (setup) the no-jq PATH really has no jq" bash -c "! PATH='$NOJQ' command -v jq >/dev/null 2>&1"
c2_sj "$R" k2 false "" '["x"]' | PATH="$NOJQ" STATE_CHECK_STATE_DIR="$S" bash "$HK/stop-state-check.sh" > "$C2/out" 2> "$C2/err"; rc=$?
c2_chk pass "A47 without jq: nothing written, no refusal, no noise" bash -c "[ $rc = 0 ] && [ ! -e '$S/crons/k2' ] && [ ! -s '$C2/out' ] && [ ! -s '$C2/err' ]"
mkdir -p "$S/crons"; ln -s "$SENT" "$S/crons/k3"; c2_stop "$R" k3 false "" '["y"]'
c2_chk refuse "A47 a symlinked crons/<sid> is not written through" eq "$(cat "$SENT")" "keep"

echo "  A48 retirement writes retired-compacts/<sid>; a marker without its companion counts as absent"
R="$C2/myapp-dev13"; c2_repo "$R"; c2_conf 'myapp-dev*  dev  5'; S="$C2/s-a48"
c2_tp "$C2/tp-cmp" 8; printf '{"type":"system","subtype":"compact_boundary"}\n{"type":"system","subtype":"compact_boundary"}\n' >> "$C2/tp-cmp"
c2_stop "$R" r1 false "$C2/tp-cmp"
c2_chk refuse "A48 the companion holds the compact-boundary count at retirement (2)" eq "$(cat "$S/retired-compacts/r1" 2>/dev/null)" "2"
echo more >> "$R/README.md"; c2_stop "$R" r1 false "$C2/tp-cmp"
c2_chk pass "A48 pair: a marker WITH its companion is not rewritten (no second inbox record for a dirty tree)" test ! -e "$S/inbox/dev.md"
mkdir -p "$S/retired"; echo "old marker" > "$S/retired/r2"
c2_stop "$R" r2 false "$C2/tp-cmp"
c2_chk refuse "A48 a marker with no companion is rewritten (companion now exists)" test -f "$S/retired-compacts/r2"
c2_chk refuse "A48 ... and the old marker text is replaced" nothas 'old marker' "$S/retired/r2"
mkdir -p "$S/retired"; echo "old" > "$S/retired/r3"; ln -s "$SENT" "$S/retired-compacts/r3"
c2_stop "$R" r3 false "$C2/tp-cmp"
c2_chk refuse "A48 a symlinked companion is replaced by a real file, the link target untouched" bash -c "[ ! -L '$S/retired-compacts/r3' ] && [ -f '$S/retired-compacts/r3' ] && [ \"\$(cat '$SENT')\" = keep ]"

echo "  A70 the wrap-up words in the always-on fullness line: read-only, only when the group's marker is there"
WS="$C2/s-a70"; mkdir -p "$WS/wrapup-fired"; echo 600 > "$WS/wrapup-fired/c1s"
c1_tr "$TRC" human:1 usage:1:650
c1_fire "A70 marker + 650k typed prompt: the wrap-up words replace the fullness line" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')" STATE_CHECK_STATE_DIR="$WS")" 'wrapping up: open a fresh chat'
c1_quiet "A70 ... and the plain fullness ask is gone" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')" STATE_CHECK_STATE_DIR="$WS")" 'open your reply with one line on how full'
c1_fire "A70 pair: NO group installed (no marker): the plain fullness line is unchanged" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')" STATE_CHECK_STATE_DIR="$C2/no-group")" 'open your reply with one line on how full'
c1_quiet "A70 pair: NO group installed: no wrap-up words" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')" STATE_CHECK_STATE_DIR="$C2/no-group")" 'wrapping up'
c1_tr "$TRC" human:1 usage:1:550
c1_fire "A70 pair: marker but the chat is under the marker's point (550k < 600k): the plain line" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')" STATE_CHECK_STATE_DIR="$WS")" 'open your reply with one line on how full'
c1_tr "$TRC" human:1 usage:1:650
mkdir -p "$WS/open"; : > "$WS/open/c1s"
c1_quiet "A70 pair: a later hook's own wrap-up marker (open/<sid>) already says it: no second wrap-up line here" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')" STATE_CHECK_STATE_DIR="$WS")" 'wrapping up'
rm -rf "$WS/open"; rm -f "$WS/wrapup-fired/c1s"; ln -s "$SENT" "$WS/wrapup-fired/c1s"
c1_quiet "A70 pair: a symlinked marker is not read" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" 'go on')" STATE_CHECK_STATE_DIR="$WS")" 'wrapping up'
rm -f "$WS/wrapup-fired/c1s"; echo 600 > "$WS/wrapup-fired/c1s"
c1_quiet "A70 pair: a machine prompt gets neither line" "$(c1_run "$(c1_in UserPromptSubmit "$TRC" '<task-notification>x</task-notification>')" STATE_CHECK_STATE_DIR="$WS")" 'wrapping up'
c1_quiet "A70 pair: a helper's own transcript gets neither line" "$(c1_run "$(c1_in UserPromptSubmit "$C1/subagents/agent-1.jsonl" 'go on')" STATE_CHECK_STATE_DIR="$WS")" 'wrapping up'
echo "keep" > "$SENT"

echo "refresh 2026-09-29 (c2b): opt-in doorman, the hold, delivery and compaction (A52 A53 A54 A55 A56 A57 A58 A59)"
C3="$T/c2b"; HK3="$C3/hk"; mkdir -p "$HK3"
cp "$HOOKS_DIR/doorman.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/clock-in-context.sh" "$HK3/"
c3_conf() { { printf 'STATE_FILE state/{role}.md\n'; local l; for l in "$@"; do printf '%s\n' "$l"; done; } > "$HK3/state-check.conf"; }
c3_p() {   # <cwd> <sid> [transcript] [prompt]: run the doorman against $S; stdout -> $C3/o, stderr -> $C3/e, rc in $C3_RC
  dj "$1" "$2" "${4:-hello}" "${3:-}" | STATE_CHECK_STATE_DIR="$S" bash "$HK3/doorman.sh" > "$C3/o" 2> "$C3/e"; C3_RC=$?
}
c3_ret() {   # <sid> [compact-count]: a live RETIRED marker (marker + companion)
  mkdir -p "$S/retired" "$S/retired-compacts"; echo "2026-01-01 00:00 dev 900k" > "$S/retired/$1"; echo "${2:-0}" > "$S/retired-compacts/$1"
}
c3_line() { printf '{"type":"assistant","message":{"usage":{"input_tokens":%d,"cache_creation_input_tokens":0,"cache_read_input_tokens":%d,"output_tokens":5}}}\n' 1000 $(( ($1 - 1) * 1000 )); }
c3_zero() { printf '{"type":"assistant","message":{"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}\n'; }
c3_bound() { printf '{"type":"system","subtype":"compact_boundary","content":"Conversation compacted"}\n'; }
rc_is() { [ "$C3_RC" = "$1" ]; }
out_empty() { [ ! -s "$C3/o" ]; }
c3_conf 'myapp-dev*  dev  850' 'myapp-ops*  ops  850'
D1="$C3/myapp-dev21"; D2="$C3/myapp-dev22"; O1="$C3/myapp-ops1"; mkdir -p "$D1" "$D2" "$O1"
c2_tp "$C3/tp900" 900; c2_tp "$C3/tp849" 849; c2_tp "$C3/tp850" 850; c2_tp "$C3/tp100" 100

echo "  A52 the hold fires only at the context cut-off (or a retired marker): no idle trigger, no 'wake anyway'"
S="$C3/s-a52"
cat > "$C3/tp-idle" <<'EOT'
{"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"content":"hi"}}
{"type":"assistant","timestamp":"2026-01-01T00:00:05Z","message":{"usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":499000,"output_tokens":1}}}
EOT
c3_p "$D1" a52a "$C3/tp-idle"
c2_chk pass "A52 pair: an idle-for-months chat at 500k (under the 850k floor) passes: idle no longer holds" rc_is 0
c3_p "$D1" a52b "$C3/tp850"
c2_chk refuse "A52 a chat at exactly its floor (850k) is held" rc_is 2
c3_p "$D1" a52c "$C3/tp849"
c2_chk pass "A52 pair: 849k (one thousand under the floor) passes" rc_is 0
c3_conf 'myapp-dev*  dev  5' 'myapp-ops*  ops  850'
c3_p "$D1" a52d "$C3/tp100"
c2_chk refuse "A52 the cut-off is the conf row's own number: a 5k floor holds a 100k chat" rc_is 2
c3_p "$O1" a52e "$C3/tp100"
c2_chk pass "A52 pair: another row's 850k floor does not hold the same 100k chat" rc_is 0
c3_conf 'myapp-dev*  dev  850' 'myapp-ops*  ops  850'
c3_ret a52f; c3_p "$D1" a52f "$C3/tp100" "wake anyway, please"
c2_chk refuse "A52 'wake anyway' no longer forces a retired chat open: it is held like any prompt" rc_is 2
c3_p "$D1" a52g "$C3/tp100" "wake anyway, please"
c2_chk pass "A52 pair: 'wake anyway' on a chat that is not retired or full is just a prompt: passes" rc_is 0
c2_chk pass "A52 the script no longer carries the idle trigger or the wake-anyway escape" bash -c "! grep -v '^[[:space:]]*#' '$HK3/doorman.sh' | grep -qiE 'wake anyway|IDLE_MIN|DOORMAN_CTX_K'"

echo "  A53 a held message: saved per session and stamped, refused with the plain sentence, nothing on stdout"
S="$C3/s-a53"; c3_p "$D1" a53 "$C3/tp900" "please build the thing"
c2_chk refuse "A53 a chat over its floor is refused (exit 2)" rc_is 2
c2_chk refuse "A53 the refusal says: don't retype: your next message carries this one" has "don't retype: your next message carries this one" "$C3/e"
c2_chk refuse "A53 stdout is empty on a held turn" out_empty
c2_chk refuse "A53 the held file holds the text" has "please build the thing" "$S/held/a53"
c2_chk refuse "A53 line 1 of the held file is a stamp, line 2 the folder, text from line 3" bash -c "sed -n 1p '$S/held/a53' | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\$' && [ \"\$(sed -n 2p '$S/held/a53')\" = '$D1' ] && [ \"\$(sed -n 3p '$S/held/a53')\" = 'please build the thing' ]"
c2_chk refuse "A53 the text is also appended to the role's inbox (a second, durable copy)" has "please build the thing" "$S/inbox/dev.md"
c3_p "$D1" a53b "$C3/tp100" "a normal message"
c2_chk pass "A53 pair: a passing prompt writes no held file" test ! -e "$S/held/a53b"
c2_chk pass "A53 pair: ... and nothing new in the inbox" nothas "a normal message" "$S/inbox/dev.md"
c3_p "$D1" "" "$C3/tp900" "no session id here"
c2_chk pass "A53 a chat with no session id cannot carry a held text, so it is never held (fails open)" rc_is 0

echo "  A54 the owner's next typed message passes and carries the held text; later prompts get the wrap-up note"
c3_p "$D1" a53 "$C3/tp900" "second message"
c2_chk refuse "A54 the next typed message passes (exit 0)" rc_is 0
c2_chk refuse "A54 stdout carries the held text, labelled with its stamped time" bash -c "grep -qE 'HELD MESSAGE delivered \\(held at [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\\): please build the thing' '$C3/o'"
c2_chk refuse "A54 the held file is gone and delivered/<sid> holds it (moved, not deleted)" bash -c "[ ! -e '$S/held/a53' ] && grep -q 'please build the thing' '$S/delivered/a53'"
c2_chk refuse "A54 the per-session open marker exists (the path clock-in-context.sh reads)" test -f "$S/open/a53"
c2_chk refuse "A54 the pass turn is told to wrap up" has "wrap up the task in hand" "$C3/o"
c3_p "$D1" a53 "$C3/tp900" "third message"
c2_chk refuse "A54 every later typed prompt passes" rc_is 0
c2_chk refuse "A54 ... and gets the wrap-up note" has "wrap up the task in hand" "$C3/o"
c2_chk pass "A54 pair: ... and the held text is not carried a second time" nothas "HELD MESSAGE" "$C3/o"
c3_p "$D1" a54fresh "$C3/tp100" "fresh chat prompt"
c2_chk pass "A54 pair: a chat that was never held gets no wrap-up note" nothas "wrap up" "$C3/o"
S="$C3/s-a54b"; c3_p "$D1" a54s "$C3/tp900" "yes A"; c3_p "$D1" a54s "$C3/tp900" "next"
c2_chk refuse "A54 a held body of 12 characters or fewer is delivered with a confirm-before-acting line" has 'confirm this answer with the owner' "$C3/o"
S="$C3/s-a54c"; c3_p "$D1" a54t "$C3/tp900" "yes A, that one"; c3_p "$D1" a54t "$C3/tp900" "next"
c2_chk pass "A54 pair: a 15-character body has no confirm line" nothas 'confirm this answer' "$C3/o"
S="$C3/s-a54d"; c3_p "$D1" a54u "$C3/tp900" "123456789012"; c3_p "$D1" a54u "$C3/tp900" "next"
c2_chk refuse "A54 exactly 12 characters still gets the confirm line" has 'confirm this answer' "$C3/o"
S="$C3/s-a54e"; c3_p "$D1" a54v "$C3/tp900" "1234567890123"; c3_p "$D1" a54v "$C3/tp900" "next"
c2_chk pass "A54 pair: 13 characters does not" nothas 'confirm this answer' "$C3/o"

echo "  A55 a retired chat is never locked out: the pass comes before the retired refusal"
S="$C3/s-a55"; c3_ret a55; c3_p "$D1" a55 "$C3/tp100" "first message"
c2_chk refuse "A55 a chat marked RETIRED (marker + companion) is held" rc_is 2
c2_chk refuse "A55 the refusal says retired" has "retired" "$C3/e"
c3_p "$D1" a55 "$C3/tp100" "second message"
c2_chk refuse "A55 its very next typed message passes, though the marker still stands" rc_is 0
c2_chk refuse "A55 ... and carries the first message" has "first message" "$C3/o"
c3_p "$D1" a55 "$C3/tp100" "third message"
c2_chk pass "A55 pair: the message after that passes too (open marker read first)" rc_is 0
c2_chk pass "A55 pair: the retired marker itself is left alone" test -f "$S/retired/a55"
S="$C3/s-a55b"; mkdir -p "$S/retired"; echo "old" > "$S/retired/a55b"; c3_p "$D1" a55b "$C3/tp100"
c2_chk pass "A55 pair: a marker with NO companion counts as absent: passes" rc_is 0
S="$C3/s-a55c"; mkdir -p "$S/retired" "$S/retired-compacts"; echo "x" > "$S/retired/a55c"; ln -s "$SENT" "$S/retired-compacts/a55c"; c3_p "$D1" a55c "$C3/tp100"
c2_chk pass "A55 pair: a symlinked companion is not honoured: passes" rc_is 0
S="$C3/s-a55d"; c3_ret a55d; c3_p "$D1" a55d ""
c2_chk refuse "A55 a retired chat is held even when its transcript cannot be read (retirement needs no size)" rc_is 2

echo "  A56 delivery: the same chat when woken; a fresh chat in the same folder only after the held chat is retired; once"
S="$C3/s-a56"; c3_ret a56old; c3_p "$D1" a56old "$C3/tp100" "carry me to the new chat"
c3_p "$D1" a56new "$C3/tp100" "hello in a fresh chat"
c2_chk refuse "A56 a fresh chat in the same folder receives the retired chat's held text" has "carry me to the new chat" "$C3/o"
c2_chk refuse "A56 ... labelled as held for the previous chat" has "held for the previous chat" "$C3/o"
c2_chk refuse "A56 ... and it moved to delivered/" bash -c "[ ! -e '$S/held/a56old' ] && [ -f '$S/delivered/a56old' ]"
c3_p "$D1" a56third "$C3/tp100" "another fresh chat"
c2_chk pass "A56 pair: a second fresh chat gets nothing (delivered once)" nothas "HELD MESSAGE" "$C3/o"
S="$C3/s-a56b"; c3_p "$D1" a56live "$C3/tp900" "held from a live chat"; c3_p "$D1" a56other "$C3/tp100" "fresh chat"
c2_chk pass "A56 pair: a chat that is only full, not retired, keeps its held text from a fresh chat" nothas "HELD MESSAGE" "$C3/o"
c2_chk pass "A56 pair: ... the held file stays" test -f "$S/held/a56live"
S="$C3/s-a56c"; c3_ret a56x; c3_p "$D1" a56x "$C3/tp100" "for folder one"; c3_p "$O1" a56y "$C3/tp100" "chat of another role"
c2_chk pass "A56 pair: a chat of another ROLE never receives it (another folder of the same role does: attack fixes (3) B3)" nothas "HELD MESSAGE" "$C3/o"
S="$C3/s-a56d"; c3_ret a56z; c3_p "$D1" a56z "$C3/tp100" "for the machine test"
c3_p "$D1" a56m "$C3/tp100" "<task-notification>done</task-notification>"
c2_chk pass "A56 pair: a machine prompt in a fresh chat does not take the held text" test -f "$S/held/a56z"
S="$C3/s-a56e"; c3_ret a56q; c3_p "$D1" a56q "$C3/tp100" "twice?"
( dj "$D1" a56q "next" "$C3/tp100" | STATE_CHECK_STATE_DIR="$S" bash "$HK3/doorman.sh" > "$C3/o1" 2>/dev/null ) &
( dj "$D1" a56q "next" "$C3/tp100" | STATE_CHECK_STATE_DIR="$S" bash "$HK3/doorman.sh" > "$C3/o2" 2>/dev/null ) &
wait
c2_chk refuse "A56 two prompts racing for one held text: it is delivered exactly once" eq "$(cat "$C3/o1" "$C3/o2" | grep -c 'HELD MESSAGE')" "1"

echo "  A57 machine prompts are never held, never the passing message, never counted (one classifier, clock-in-context.sh --classify-prompt)"
S="$C3/s-a57"; c3_ret a57
for m in '<task-notification>x</task-notification>' '<agent-message from="x">y</agent-message>' '<cross-session-message>z</cross-session-message>' 'Another Claude session sent a message: hi' '<bash-input>ls</bash-input>' '<<autonomous-loop>>' '[Cross-session delivery notice] see the file'; do
  c3_p "$D1" a57 "$C3/tp100" "$m"
  c2_chk pass "A57 a machine prompt on a retired chat passes, held nothing: ${m:0:30}" bash -c "[ '$C3_RC' = 0 ] && [ ! -e '$S/held/a57' ]"
done
c3_p "$D1" a57 "$C3/tp100" "hand-typed words"
c2_chk refuse "A57 pair: the same chat's typed prompt is held" rc_is 2
c3_p "$D1" a57 "$C3/tp100" "<task-notification>x</task-notification>"
c2_chk pass "A57 a machine prompt is not the passing message: the held text stays and no marker opens" bash -c "[ -f '$S/held/a57' ] && [ ! -e '$S/open/a57' ] && ! grep -q 'HELD MESSAGE' '$C3/o'"
S="$C3/s-a57b"; c3_p "$D1" a57b "$C3/tp900" "hold me"; c3_p "$D1" a57b "$C3/tp900" "second"; c3_p "$D1" a57b "$C3/tp900" "<task-notification>x</task-notification>"
c2_chk pass "A57 a machine prompt on an open chat gets no wrap-up note (it is not counted as a prompt)" nothas "wrap up" "$C3/o"
S="$C3/s-a57c"; mkdir -p "$S/crons"; c3_ret a57c
printf '%s\n' "$(printf '%s' 'check the build every hour' | jq -Rs .)" > "$S/crons/a57c"
c3_p "$D1" a57c "$C3/tp100" "  check the build every hour  "
c2_chk pass "A57 a fired scheduled prompt (in the cron registry, trimmed exact match) is machine: passes" rc_is 0
c3_p "$D1" a57c "$C3/tp100" "check the build every day"
c2_chk refuse "A57 pair: a typed prompt that is not in the registry is held" rc_is 2
HK4="$C3/hk-nocls"; mkdir -p "$HK4"; cp "$HOOKS_DIR/doorman.sh" "$HOOKS_DIR/guard-lib.sh" "$HK4/"; cp "$HK3/state-check.conf" "$HK4/"
S="$C3/s-a57d"; c3_ret a57d
dj "$D1" a57d "typed words" "$C3/tp100" | STATE_CHECK_STATE_DIR="$S" bash "$HK4/doorman.sh" > "$C3/o" 2> "$C3/e"; C3_RC=$?
c2_chk pass "A57 with no classifier beside the hook nothing is held (cannot tell: fail open, note on stderr)" bash -c "[ '$C3_RC' = 0 ] && grep -q 'classifier' '$C3/e'"
printf '#!/bin/bash\nexit 3\n' > "$HK4/clock-in-context.sh"
dj "$D1" a57d "typed words" "$C3/tp100" | STATE_CHECK_STATE_DIR="$S" bash "$HK4/doorman.sh" > "$C3/o" 2> "$C3/e"; C3_RC=$?
c2_chk pass "A57 a classifier that fails (exit 3) is not read as 'typed': passes" rc_is 0

echo "  A58 compaction (UNVERIFIED against a real payload): unknown context never holds; the chat is told; a later compaction clears the marker"
S="$C3/s-a58"; { c2_tp "$C3/tp-c1" 900; c3_bound >> "$C3/tp-c1"; }
c3_p "$D1" a58 "$C3/tp-c1"
c2_chk refuse "A58 a compact boundary after the 900k usage line: not held (context unknown)" rc_is 0
c2_chk refuse "A58 the chat is told it was compacted" has "was compacted" "$C3/o"
c2_chk refuse "A58 ... with the wrap-up words (a dev role)" has "wrapping up" "$C3/o"
c3_p "$O1" a58o "$C3/tp-c1"
c2_chk pass "A58 pair: a role not in WRAPUP_ROLES is told of the compaction without the wrap-up words" bash -c "grep -q 'was compacted' '$C3/o' && ! grep -q 'wrapping up' '$C3/o'"
{ c2_tp "$C3/tp-c2" 900; c3_bound >> "$C3/tp-c2"; c3_line 100 >> "$C3/tp-c2"; }
c3_p "$D1" a58b "$C3/tp-c2"
c2_chk pass "A58 pair: a usage line AFTER the boundary is a fresh measurement: no notice, passes" bash -c "[ '$C3_RC' = 0 ] && ! grep -q 'compacted' '$C3/o'"
{ c2_tp "$C3/tp-c3" 100; c3_bound >> "$C3/tp-c3"; c3_line 900 >> "$C3/tp-c3"; }
c3_p "$D1" a58c "$C3/tp-c3"
c2_chk refuse "A58 a chat that is over its floor AFTER the compaction is held again" rc_is 2
S="$C3/s-a58d"; c3_ret a58d 0; c3_p "$D1" a58d "$C3/tp-c2"
c2_chk refuse "A58 a compaction since the retirement (1 boundary now, 0 recorded) clears the retired marker: passes" bash -c "[ '$C3_RC' = 0 ] && [ ! -e '$S/retired/a58d' ] && [ ! -e '$S/retired-compacts/a58d' ]"
S="$C3/s-a58e"; c3_ret a58e 1; c3_p "$D1" a58e "$C3/tp-c2"
c2_chk refuse "A58 pair: the boundary was already counted at retirement (1 recorded): still retired, held" rc_is 2
S="$C3/s-a58f"; c3_p "$D1" a58f "$C3/tp900"
c2_chk refuse "A58 pair: no boundary at all: a 900k chat is held as before" rc_is 2
printf '{"type":"user","message":{"content":"hi"}}\n' > "$C3/tp-nousage"; S="$C3/s-a58g"
c3_p "$D1" a58g "$C3/tp-nousage"
c2_chk pass "A58 a transcript with no usage line at all is unknown: never held" rc_is 0
c3_p "$D1" a58g "$C3/does-not-exist"
c2_chk pass "A58 an unreadable transcript is unknown: never held" rc_is 0
ss_json() { python3 -c 'import json,sys;print(json.dumps({"hook_event_name":"SessionStart","source":sys.argv[2],"cwd":sys.argv[1],"session_id":"ss1"}))' "$1" "$2"; }
S="$C3/s-a58h"; mkdir -p "$S/tell"; echo 40 > "$S/tell/ss1"
ss_json "$D1" compact | STATE_CHECK_STATE_DIR="$S" bash "$HK3/doorman.sh" > "$C3/o" 2> "$C3/e"; C3_RC=$?
c2_chk refuse "A58 a SessionStart with source compact prints the compaction notice" has "was compacted" "$C3/o"
c2_chk pass "A58 pair: a session start is not a turn: no snapshot, and the tell is left alone" bash -c "[ ! -e '$S/turnsnap' ] && [ -f '$S/tell/ss1' ] && ! grep -q 'helper tell' '$C3/o'"
ss_json "$D1" startup | STATE_CHECK_STATE_DIR="$S" bash "$HK3/doorman.sh" > "$C3/o" 2> "$C3/e"; C3_RC=$?
c2_chk pass "A58 pair: a SessionStart with source startup prints nothing" out_empty
ss_json "$C3" compact | STATE_CHECK_STATE_DIR="$S" bash "$HK3/doorman.sh" > "$C3/o" 2> "$C3/e"
c2_chk pass "A58 pair: a compact SessionStart in a folder the conf does not name prints nothing (inert)" out_empty

echo "  A59 the context is read from the WHOLE transcript, newest usage line first; all-zero usage lines are skipped"
S="$C3/s-a59"; { c2_tp "$C3/tp-big" 900; python3 -c 'print("{\"type\":\"user\",\"message\":{\"content\":\"" + "x"*300000 + "\"}}")' >> "$C3/tp-big"; }
c3_p "$D1" a59 "$C3/tp-big"
c2_chk refuse "A59 a 300 KB tool result after the 900k usage line does not hide it: held" rc_is 2
S="$C3/s-a59b"; { c2_tp "$C3/tp-zero" 900; c3_zero >> "$C3/tp-zero"; }
c3_p "$D1" a59b "$C3/tp-zero"
c2_chk refuse "A59 a trailing all-zero usage line (an API error) is skipped: still held at 900k" rc_is 2
S="$C3/s-a59c"; { c2_tp "$C3/tp-zero2" 100; c3_zero >> "$C3/tp-zero2"; }
c3_p "$D1" a59c "$C3/tp-zero2"
c2_chk pass "A59 pair: ... and a 100k chat with a trailing zero line is 100k, not 0 and not held" bash -c "[ '$C3_RC' = 0 ] && [ \"\$(cat '$S/turn-start/a59c')\" = 100 ]"
S="$C3/s-a59d"; { c2_tp "$C3/tp-newer" 900; c3_line 100 >> "$C3/tp-newer"; }
c3_p "$D1" a59d "$C3/tp-newer"
c2_chk pass "A59 pair: the NEWEST non-zero line wins: 900k then 100k passes" rc_is 0
c2_chk pass "A59 the reader is portable: no BSD-only date -j / tail -r / stat -f / shasum in the code (comments aside)" bash -c "! grep -v '^[[:space:]]*#' '$HK3/doorman.sh' | grep -qE 'date -j|tail -r|stat -f|shasum '"

echo "  the failure paths: a kill between the hold and the pass, and inside the pass"
S="$C3/s-crash"; c3_p "$D1" k1 "$C3/tp900" "survive the crash"
# the hook is killed after the hold (exit 2 never seen); the next typed message is the pass
c3_p "$D1" k1 "$C3/tp900" "after the crash"
c2_chk refuse "crash after the hold: the next message delivers the held text" has "survive the crash" "$C3/o"
c3_p "$D1" k1 "$C3/tp900" "and again"
c2_chk pass "crash after the hold: ... exactly once (the message after that carries nothing)" nothas "survive the crash" "$C3/o"
S="$C3/s-crash2"; c3_p "$D1" k2 "$C3/tp900" "half way"
mkdir -p "$S/open"; : > "$S/open/k2"
c3_p "$D1" k2 "$C3/tp900" "next"
c2_chk refuse "crash after the open marker, before the rename: the held text is still delivered (held/ is read before the marker)" has "half way" "$C3/o"
S="$C3/s-crash3"; mkdir -p "$S/open" "$S/delivered"; : > "$S/open/k3"; echo "was delivered" > "$S/delivered/k3"; c3_ret k3
c3_p "$D1" k3 "$C3/tp900" "after a kill mid-print"
c2_chk pass "crash after the rename, before the print: the chat is not held again, the wrap-up note shows, the text is not shown twice" bash -c "[ '$C3_RC' = 0 ] && ! grep -q 'HELD MESSAGE' '$C3/o' && grep -q 'wrap up' '$C3/o'"
c2_chk pass "crash after the rename: the text is still on disk in delivered/" has "was delivered" "$S/delivered/k3"
S="$C3/s-crash4"; mkdir -p "$S/held"; printf '2026-01-01 00:00\n%s\nhalf a message' "$D1" > "$S/held/.k4.999"
c3_p "$D1" k4 "$C3/tp100" "plain"
c2_chk pass "crash mid-write of the held copy: a leftover temporary file is never delivered" bash -c "[ '$C3_RC' = 0 ] && ! grep -q 'HELD MESSAGE' '$C3/o'"
S="$C3/s-crash5"; mkdir -p "$C3/elsewhere" "$S"; ln -s "$C3/elsewhere" "$S/held"
c3_p "$D1" k5 "$C3/tp900" "through a link"
c2_chk pass "a symlinked held/ folder is never written through: the prompt passes (fail open) and the target stays empty" bash -c "[ '$C3_RC' = 0 ] && [ -z \"\$(ls -A '$C3/elsewhere')\" ]"
S="$C3/s-crash6"; mkdir -p "$S/held"; ln -s "$SENT" "$S/held/k6"; c3_p "$D1" k6 "$C3/tp100" "plain"
c2_chk pass "a symlinked held file is not delivered and its target is untouched" bash -c "[ '$C3_RC' = 0 ] && ! grep -q 'HELD MESSAGE' '$C3/o' && [ \"\$(cat '$SENT')\" = keep ]"

# ======================================================================================
echo "refresh 2026-09-29 (d1): agent-model-guard (B1)"
D1="$T/d1"; rm -rf "$D1"; mkdir -p "$D1"
d1_exp() {   # want label script [NAME=value...] : $INPUT through the script; want 2 counts as a must-refuse case
  local want="$1" label="$2" script="$3"; shift 3
  printf '%s' "$INPUT" | env "$@" bash "$script" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then ok; else bad "$label (wanted exit $want, got $got)"; fi
  if [ "$want" = 2 ]; then refuse_n=$((refuse_n+1)); else pass_n=$((pass_n+1)); fi
}
d1_msg() {   # want-substring label script [NAME=value...] : must exit 2 AND say the substring (refused for the right reason)
  local sub="$1" label="$2" script="$3"; shift 3
  local err; err="$(printf '%s' "$INPUT" | env "$@" bash "$script" 2>&1 >/dev/null)"; local got=$?
  if [ "$got" = 2 ] && printf '%s' "$err" | grep -qF -- "$sub"; then ok; else bad "$label (wanted exit 2 saying '$sub', got $got: $err)"; fi
  refuse_n=$((refuse_n+1))
}
d1_chk() { local label="$1"; shift; if "$@"; then ok; else bad "$label"; fi; pass_n=$((pass_n+1)); }
d1_agent() { python3 -c 'import json,sys;print(json.dumps({"tool_name":sys.argv[1],"tool_input":json.loads(sys.argv[2])}))' "$@"; }

# ---- B1 agent-model-guard ------------------------------------------------------------------
AMG="$HOOKS_DIR/agent-model-guard.sh"
for j in '{"subagent_type":"executor","description":"d","prompt":"p"}' '{"description":"d","prompt":"p"}' '{"model":""}' '{"model":"   "}' '{"model":"\t"}' '{"model":null}' '{"model":7}' \
         '{"description":"d","prompt":"use \"model\": \"haiku\" for this"}' '{"subagent_type":"fork2","prompt":"p"}'; do
  INPUT="$(d1_agent Agent "$j")"; d1_exp 2 "B1 must refuse an Agent launch whose model is missing or blank: $j" "$AMG"; done
for j in '{"model":"sonnet","prompt":"p"}' '{"model":"any-string-at-all-9"}' '{"subagent_type":"fork","description":"d","prompt":"p"}' '{"subagent_type":"fork","model":"haiku"}' '{"subagent_type":"executor","model":"opus"}'; do
  INPUT="$(d1_agent Agent "$j")"; d1_exp 0 "B1 must pass an Agent launch that names a model, or a fork: $j" "$AMG"; done
INPUT="$(json_bash 'ls')"; d1_exp 0 "B1 a Bash call with no model field is not its business" "$AMG"
INPUT="$(d1_agent Read '{"file_path":"/x"}')"; d1_exp 0 "B1 any other tool passes untouched" "$AMG"
INPUT=""; d1_exp 0 "B1 an empty payload passes (nothing to judge)" "$AMG"
INPUT="$(d1_agent Agent '{"prompt":"p"}')"; d1_msg "name the model for this helper" "B1 the refusal says what to do" "$AMG"
if bash "$AMG" < <(d1_agent Agent '{"prompt":"p"}') 2>&1 | grep -qiE 'rule [0-9]|fable|opus|sonnet|haiku'; then bad "B1 the refusal text must not name a private rule or a model"; else ok; fi; pass_n=$((pass_n+1))
d1_chk "B1 no private rule number, model name or path in the script" bash -c "[ -f '$HOOKS_DIR/agent-model-guard.sh' ] && ! grep -liE 'rule [0-9]+|fable|helper setup|ac'\"-\"'calc|/Us'\"ers\"'/|done-list' '$HOOKS_DIR/agent-model-guard.sh'"

echo "refresh 2026-09-29 (d2) install.sh: the new default guard, every conf example, timeouts, the doorman on SessionStart, a python3 that really runs, the upgrade path"
REPOD2="$(cd "$HOOKS_DIR/.." && pwd -P)"
# d2_settings_count <settings.json> <event> -> number of hook entries under that event
d2_count() { python3 -c 'import json,sys;s=json.load(open(sys.argv[1]));print(sum(len(g.get("hooks",[])) for g in s.get("hooks",{}).get(sys.argv[2],[])))' "$1" "$2" 2>/dev/null; }
# d2_field <settings.json> <event> <command-substring> <field> -> that field of the first matching entry ("-" when absent)
d2_field() { python3 -c '
import json,sys
p,ev,sub,f=sys.argv[1:5]
s=json.load(open(p))
for g in s.get("hooks",{}).get(ev,[]):
    for h in g.get("hooks",[]):
        if sub in h.get("command",""):
            print(h.get(f, g.get(f,"-")) if f!="matcher" else g.get("matcher","-")); sys.exit(0)
print("MISSING")' "$1" "$2" "$3" "$4" 2>/dev/null; }
# d2_yes <home> [env...]: run the installer on a real pty and answer the multi-chat question yes
d2_yes() { local h="$1"; shift
  env "$@" python3 - "$h" "$REPOD2/install.sh" <<'PY' >/dev/null 2>&1
import os,pty,sys
home,script=sys.argv[1:3]
pid,fd=pty.fork()
if pid==0:
    os.environ["HOME"]=home
    os.execvp("bash",["bash",script])
os.write(fd,b"\ny\n\n\n\n\n")
while True:
    try:
        if not os.read(fd,4096): break
    except OSError: break
_,st=os.waitpid(pid,0)
sys.exit(os.waitstatus_to_exitcode(st))
PY
}
DH1="$T/d2-fresh"; mkdir -p "$DH1"
env HOME="$DH1" bash "$REPOD2/install.sh" --yes >/dev/null 2>&1; d2rc=$?
S1="$DH1/.claude/settings.json"
if [ "$d2rc" = 0 ]; then ok; else bad "d2 a fresh install must exit 0 (got $d2rc)"; fi
pass_n=$((pass_n+1))
if [ -f "$DH1/.claude/hooks/agent-model-guard.sh" ] && [ -x "$DH1/.claude/hooks/agent-model-guard.sh" ]; then ok; else bad "d2 agent-model-guard.sh must be copied and executable"; fi
pass_n=$((pass_n+1))
if [ "$(d2_field "$S1" PreToolUse agent-model-guard.sh matcher)" = "Agent" ]; then ok; else bad "d2 the agent guard must be registered on PreToolUse with matcher Agent"; fi
pass_n=$((pass_n+1))
if [ "$(d2_field "$S1" PreToolUse agent-model-guard.sh timeout)" = "10" ] && [ "$(d2_field "$S1" PreToolUse agent-model-guard.sh statusMessage)" = "Agent launch names its model" ]; then ok; else bad "d2 the agent guard entry needs timeout 10 and its status message"; fi
pass_n=$((pass_n+1))
for ex in "$REPOD2"/hooks/*.conf.example; do
  if [ -f "$DH1/.claude/hooks/$(basename "$ex")" ]; then ok; else bad "d2 the installer must copy $(basename "$ex")"; fi
  pass_n=$((pass_n+1))
done
if [ "$(d2_field "$S1" SessionStart clock-in-context.sh timeout)" = "10" ] && [ "$(d2_field "$S1" UserPromptSubmit clock-in-context.sh timeout)" = "10" ]; then ok; else bad "d2 clock-in-context needs timeout 10 under SessionStart and UserPromptSubmit"; fi
pass_n=$((pass_n+1))
# the multi-chat group, answered yes on a pty
DH2="$T/d2-optin"; mkdir -p "$DH2"
d2_yes "$DH2"; d2rc=$?
S2="$DH2/.claude/settings.json"
if [ "$d2rc" = 0 ]; then ok; else bad "d2 an install with the multi-chat group on must exit 0 (got $d2rc)"; fi
pass_n=$((pass_n+1))
for spec in "UserPromptSubmit doorman.sh" "SessionStart doorman.sh" "Stop stop-state-check.sh"; do
  set -- $spec
  if [ "$(d2_field "$S2" "$1" "$2" timeout)" = "10" ]; then ok; else bad "d2 $2 under $1 must be registered with timeout 10 (got $(d2_field "$S2" "$1" "$2" timeout))"; fi
  pass_n=$((pass_n+1))
done
# a fresh install without the group must NOT register the doorman anywhere
if grep -q 'doorman.sh' "$S1"; then bad "d2 pair: the opt-in doorman must stay unregistered on a default install"; else ok; fi
refuse_n=$((refuse_n+1))
# idempotent: a second run changes nothing
cp "$S1" "$T/d2-s1.before"
env HOME="$DH1" bash "$REPOD2/install.sh" --yes >/dev/null 2>&1
if cmp -s "$T/d2-s1.before" "$S1"; then ok; else bad "d2 a second run must leave settings.json byte-identical"; fi
pass_n=$((pass_n+1))
# upgrade: an old-kit settings.json (no timeouts, no agent guard) plus an entry of the user's own
DH3="$T/d2-upgrade"; mkdir -p "$DH3/.claude"
python3 - "$DH3/.claude/settings.json" <<'PY'
import json,sys
C='/bin/bash "$HOME/.claude/hooks/%s"'
def e(n,m=None):
    g={"hooks":[{"type":"command","command":C%n}]}
    if m: g["matcher"]=m
    return g
s={"theme":"dark","hooks":{
 "SessionStart":[e("check-claude-md.sh"),e("clock-in-context.sh"),{"hooks":[{"type":"command","command":"echo mine"}]}],
 "UserPromptSubmit":[e("clock-in-context.sh"),e("doorman.sh")],
 "Stop":[e("stop-state-check.sh")]}}
json.dump(s,open(sys.argv[1],"w"))
PY
env HOME="$DH3" bash "$REPOD2/install.sh" --yes >/dev/null 2>&1; d2rc=$?
S3="$DH3/.claude/settings.json"
if [ "$d2rc" = 0 ]; then ok; else bad "d2 upgrade must exit 0 (got $d2rc)"; fi
pass_n=$((pass_n+1))
if [ "$(d2_field "$S3" SessionStart clock-in-context.sh timeout)" = "10" ] && [ "$(d2_field "$S3" UserPromptSubmit clock-in-context.sh timeout)" = "10" ] \
   && [ "$(d2_field "$S3" UserPromptSubmit doorman.sh timeout)" = "10" ] && [ "$(d2_field "$S3" Stop stop-state-check.sh timeout)" = "10" ]; then ok; else bad "d2 upgrade: existing entries must gain timeout 10"; fi
pass_n=$((pass_n+1))
if [ "$(d2_count "$S3" SessionStart)" = 3 ] && [ "$(d2_count "$S3" UserPromptSubmit)" = 2 ]; then ok; else bad "d2 upgrade: no duplicate entries (SessionStart $(d2_count "$S3" SessionStart), want 3; UserPromptSubmit $(d2_count "$S3" UserPromptSubmit), want 2)"; fi
pass_n=$((pass_n+1))
if grep -q '"echo mine"' "$S3" && grep -q '"theme": "dark"' "$S3"; then ok; else bad "d2 upgrade: the user's own entry and setting must survive"; fi
pass_n=$((pass_n+1))
# a timeout the user chose is never overwritten
DH4="$T/d2-usertimeout"; mkdir -p "$DH4/.claude"
printf '%s' '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"/bin/bash \"$HOME/.claude/hooks/clock-in-context.sh\"","timeout":99}]}]}}' > "$DH4/.claude/settings.json"
env HOME="$DH4" bash "$REPOD2/install.sh" --yes >/dev/null 2>&1
if [ "$(d2_field "$DH4/.claude/settings.json" UserPromptSubmit clock-in-context.sh timeout)" = "99" ]; then ok; else bad "d2 pair: a timeout the user set (99) must not be overwritten"; fi
pass_n=$((pass_n+1))
# a python3 that is on PATH but exits non-zero (the Mac stub without the Command Line Tools)
PYSTUB="$T/d2-pystub"; mkdir -p "$PYSTUB"; printf '#!/bin/sh\nexit 1\n' > "$PYSTUB/python3"; chmod +x "$PYSTUB/python3"
DH5="$T/d2-stub"; mkdir -p "$DH5"
d2out="$(env HOME="$DH5" PATH="$PYSTUB:$PATH" GUARD_PYTHON_PREFERRED=/nonexistent/python3 bash "$REPOD2/install.sh" --yes 2>&1)"; d2rc=$?
S5="$DH5/.claude/settings.json"
if [ "$d2rc" = 0 ]; then ok; else bad "d2 a failing python3 must not stop the installer (got $d2rc)"; fi
pass_n=$((pass_n+1))
for g in block-dangerous-git.sh commit-pathspec-guard.sh heavy-suite-guard.sh gate-guard.sh helper-ledger.py; do
  if grep -q "$g" "$S5"; then bad "d2 a failing python3 must be treated as no python3: $g must not be registered"; else ok; fi
  refuse_n=$((refuse_n+1))
done
if printf '%s' "$d2out" | grep -qi 'python3.*\(fails\|does not run\|not work\)'; then ok; else bad "d2 the warning must say python3 is present but does not run"; fi
pass_n=$((pass_n+1))
if grep -q 'agent-model-guard.sh' "$S5" && grep -q 'channel-size-guard.sh' "$S5"; then ok; else bad "d2 pair: the guards that need no python3 are still registered"; fi
pass_n=$((pass_n+1))
# the python3 registration branch (no node) must give the same upgrade result as the node branch
DH6="$T/d2-upgrade-py"; mkdir -p "$DH6/.claude";
python3 - "$DH6/.claude/settings.json" <<'PY'
import json,sys
C='/bin/bash "$HOME/.claude/hooks/%s"'
e=lambda n:{"hooks":[{"type":"command","command":C%n}]}
json.dump({"hooks":{"SessionStart":[e("clock-in-context.sh")],"UserPromptSubmit":[e("clock-in-context.sh"),e("doorman.sh")]}},open(sys.argv[1],"w"))
PY
env HOME="$DH6" INSTALL_PRETEND_MISSING=node bash "$REPOD2/install.sh" --yes >/dev/null 2>&1; d2rc=$?
S6="$DH6/.claude/settings.json"
if [ "$d2rc" = 0 ] && [ "$(d2_field "$S6" SessionStart clock-in-context.sh timeout)" = "10" ] && [ "$(d2_field "$S6" UserPromptSubmit doorman.sh timeout)" = "10" ] \
   && [ "$(d2_count "$S6" UserPromptSubmit)" = 2 ] && [ "$(d2_field "$S6" PreToolUse agent-model-guard.sh matcher)" = "Agent" ]; then ok; else bad "d2 the python3 branch (no node) must upgrade timeouts, add the agent guard, and not duplicate (rc=$d2rc)"; fi
pass_n=$((pass_n+1))

echo "attack fixes (1): the blind attack round's findings in the command guards, git hooks and override ledger (F1 F2 F3 F6 F9 F10 F12 B1 M9)"
AF_BDG="$HOOKS_DIR/block-dangerous-git.sh"
# ---- F1 force-push in every honest spelling ----
for c in 'git push -uf origin main' 'git push -fu origin main' 'git push -ufv origin main' 'git push origin main -uf' \
         'git push --force-with-lease=main origin main' 'git push origin main --force-with-lease=refs/heads/main' \
         'git push --force-if-includes origin main' 'git push --force-with-lease --force-if-includes origin main' \
         'git push --force=x origin main' 'git push origin +main' 'git push origin +HEAD:main' 'git push --force-with-lease origin main'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "F1 must refuse: $c" bash "$AF_BDG"
done
for c in 'git push -u origin main' 'git push --follow-tags origin main' 'git push origin feature-fix' 'git push -v origin main' \
         'git push --set-upstream origin fix-flag' 'git push origin main:staging-fix' 'git push --tags'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "F1 must pass: $c" bash "$AF_BDG"
done
# ---- F2 a variable set EARLIER IN THE SAME COMMAND is read; an unreadable one says how to fix it ----
for c in 'B=feature; git push origin $B' 'B=feature; git push origin HEAD:$B' 'B=feature; git checkout $B' 'NEW=topic; git checkout -b $NEW' \
         'F=file.ts; git restore $F' 'BASE=HEAD~1; git reset --soft $BASE' 'OLD=feature; git branch -d $OLD' 'B="feature"; git push origin ${B}' \
         'A=feat; B=$A; git push origin $B' 'R=status; git $R'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "F2 must pass (value known on the same line): $c" bash "$AF_BDG"
done
for c in 'B=--force; git push origin $B' 'R=reset; git $R --hard' 'M=--hard; git reset $M' 'G=git; $G push --force origin main' \
         'git push origin $BRANCH' 'B=$(git branch --show-current); git push origin $B' 'B=x; B=$(git branch --show-current); git push origin $B' \
         'D=main; git push origin --delete $D'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "F2 must refuse (force, or value unreadable): $c" bash "$AF_BDG"
done
INPUT="$(json_bash 'git push origin $BRANCH')"; af_err="$(printf '%s' "$INPUT" | bash "$AF_BDG" 2>&1 >/dev/null)"
if printf '%s' "$af_err" | grep -qi 'write the value out'; then ok; else bad "F2: the unreadable-variable refusal must say 'write the value out' (got: $af_err)"; fi
refuse_n=$((refuse_n+1))
# ---- F6 commit -i / --include carries the whole index ----
AFR="$T/af-f6"; mkdir -p "$AFR"; git -C "$AFR" init -q -b main; git -C "$AFR" config core.hooksPath /dev/null
echo a > "$AFR/a.txt"; git -C "$AFR" add -A; "${ID[@]}" git -C "$AFR" commit -q -m init
af_cp() { local kind="$1" want="$2" label="$3" c="$4"; python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$c" "$AFR" | bash "$HOOKS_DIR/commit-pathspec-guard.sh" >/dev/null 2>&1; local got=$?; if [ "$got" = "$want" ]; then ok; else bad "$label (wanted $want, got $got)"; fi; if [ "$kind" = refuse ]; then refuse_n=$((refuse_n+1)); else pass_n=$((pass_n+1)); fi; }
echo b > "$AFR/b.txt"; echo c > "$AFR/c.txt"; git -C "$AFR" add c.txt
af_cp refuse 2 "F6 must refuse: git commit -i b.txt with another file already staged" 'git commit -i b.txt -m x'
af_cp refuse 2 "F6 must refuse: git commit --include b.txt with another file already staged" 'git commit --include b.txt -m x'
af_cp refuse 2 "F6 must refuse: git commit -im x b.txt (clustered)" 'git commit -im x b.txt'
af_cp pass 0 "F6 control: a plain pathspec commit still passes" 'git commit b.txt -m x'
git -C "$AFR" reset -q
af_cp pass 0 "F6 must pass: git commit -i b.txt with an EMPTY index" 'git commit -i b.txt -m x'
git -C "$AFR" add b.txt
af_cp pass 0 "F6 must pass: git commit -i b.txt when the only staged file is b.txt itself" 'git commit -i b.txt -m x'
# ---- F3 / M9 the one secret list: shapes it missed, and placeholders it refused ----
AFX="$(printf 'a%.0s' {1..24})"; AFY="$(printf 'Q7%.0s' {1..24})"
AF_SKL="sk""-${AFY}"; AF_SKLIVE="sk""_live_${AFX}"; AF_RKLIVE="rk""_live_${AFX}"; AF_HF="hf""_${AFY}"; AF_NPM="npm""_${AFY}"
AF_PW="postgres:/""/u:p4""ss@host/db"
RBH="$(rb_home main)"; RB_WANT='key-shaped'
rb_case refuse "F3: a legacy sk- key" "$RBH" a.txt "OPENAI is $AF_SKL"
rb_case refuse "F3: an sk_live_ Stripe key" "$RBH" a.txt "stripe $AF_SKLIVE"
rb_case refuse "F3: an rk_live_ Stripe key" "$RBH" a.txt "stripe $AF_RKLIVE"
rb_case refuse "M9: JSON env STRIPE_SECRET_KEY" "$RBH" s.json "  \"STRIPE_SECRET_KEY\": \"$AF_SKLIVE\""
rb_case refuse "M9: JSON env HF_TOKEN" "$RBH" s.json "  \"HF_TOKEN\": \"$AF_HF\""
rb_case refuse "M9: JSON env NPM_TOKEN" "$RBH" s.json "  \"NPM_TOKEN\": \"$AF_NPM\""
rb_case refuse "M9: JSON env MY_SERVICE_API_KEY with a 40-char value" "$RBH" s.json "  \"MY_SERVICE_API_KEY\": \"${AFY}${AFY:0:8}\""
rb_case refuse "F3: a real-looking password in a URL is still refused" "$RBH" a.env "DATABASE_URL=$AF_PW"
rb_case refuse "F3: an hf_ token on its own" "$RBH" a.txt "tok $AF_HF"
rb_case refuse "F3: an npm_ token on its own" "$RBH" a.txt "tok $AF_NPM"
RB_WANT='.'
for pw in password pass changeme xxxxxxxx 'your-password' '${DB_PASS}' example-pw passwd; do
  rb_case pass "F3: a placeholder URL password ($pw) passes" "$RBH" a.env "DATABASE_URL=postgres://user:${pw}@localhost:5432/app"
done
rb_case pass "F3: an empty JSON key value passes" "$RBH" s.json '  "API_KEY": ""'
rb_case pass "F3: a JSON key with a placeholder value passes" "$RBH" s.json '  "OPENAI_API_KEY": "<your key here>"'
JKW=KEY   # built at run time: a stricter scanner on the committing machine must not read the fixture itself as a key
rb_case pass "F3: a JSON key whose value has spaces (prose) passes" "$RBH" s.json "  \"PRIMARY_${JKW}\": \"the column that identifies each row\""
rb_case pass "F3: a bare 64-hex string (a git hash) passes" "$RBH" a.txt "commit $(printf 'ab%.0s' {1..32})"
rb_case pass "F3: a pragma line with a real-shaped key passes" "$RBH" a.txt "$AF_SKL # pragma: allow-secret"
rb_case pass "F3: a hyphenated word ending in sk- inside prose passes" "$RBH" a.txt "the desk-lamp-with-a-long-hyphenated-name-for-the-css-class-x"
# the backup hook reads the same list
AFB="$T/af-backup"; mkdir -p "$AFB/.claude/hooks"; git -C "$AFB/.claude" init -q -b main
git -C "$AFB/.claude" config user.name Tester; git -C "$AFB/.claude" config user.email tester@example.com
printf 'AUTHOR=Tester <tester@example.com>\nMIRROR_DIR=\n' > "$AFB/.claude/hooks/backup.conf"
echo hello > "$AFB/.claude/CLAUDE.md"; env HOME="$AFB" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
af_n0="$(git -C "$AFB/.claude" log --oneline 2>/dev/null | wc -l | tr -d ' ')"
printf '{"env": {"HF_TOKEN": "%s"}}\n' "$AF_HF" > "$AFB/.claude/settings.json"
env HOME="$AFB" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
af_n1="$(git -C "$AFB/.claude" log --oneline 2>/dev/null | wc -l | tr -d ' ')"
if [ "$af_n1" = "$af_n0" ]; then ok; else bad "M9: the backup must NOT commit a settings.json holding a JSON HF_TOKEN"; fi
refuse_n=$((refuse_n+1))
printf '{"env": {}}\n' > "$AFB/.claude/settings.json"; echo 'DATABASE_URL=postgres://user:password@localhost/app' >> "$AFB/.claude/CLAUDE.md"
env HOME="$AFB" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
af_n2="$(git -C "$AFB/.claude" log --oneline 2>/dev/null | wc -l | tr -d ' ')"
if [ "$af_n2" -gt "$af_n1" ]; then ok; else bad "F3: the backup must commit a user:password@localhost placeholder URL"; fi
pass_n=$((pass_n+1))
# ---- F9 the ledger never stores a secret in clear text ----
AF_TOK="gh""p_${AFY}"
AFL="$T/af-ledger.tsv"; rm -f "$AFL"
env OVERRIDE_LEDGER="$AFL" bash "$HOOKS_DIR/override-ledger.sh" SUITE_OK "SUITE_OK=1 API_KEY=$AF_TOK npm test" "heavy suite"
if [ -s "$AFL" ] && ! grep -qF "$AF_TOK" "$AFL" && grep -qF 'API_KEY=***' "$AFL"; then ok; else bad "F9: a KEY=value in the command must be masked in the ledger: $(cat "$AFL" 2>/dev/null)"; fi
refuse_n=$((refuse_n+1))
rm -f "$AFL"; env OVERRIDE_LEDGER="$AFL" bash "$HOOKS_DIR/override-ledger.sh" GITGUARD "GITGUARD=1 git push https://u:${AF_TOK}@host/o/r.git --force" "force"
if [ -s "$AFL" ] && ! grep -qF "$AF_TOK" "$AFL" && grep -qF '://u:***@host' "$AFL"; then ok; else bad "F9: a URL password must be masked in the ledger: $(cat "$AFL" 2>/dev/null)"; fi
refuse_n=$((refuse_n+1))
rm -f "$AFL"; env OVERRIDE_LEDGER="$AFL" bash "$HOOKS_DIR/override-ledger.sh" GITGUARD "git push https://${AF_TOK}@host/o/r.git --force" "force"
if [ -s "$AFL" ] && ! grep -qF "$AF_TOK" "$AFL"; then ok; else bad "F9: a token used as the URL user must be masked in the ledger: $(cat "$AFL" 2>/dev/null)"; fi
refuse_n=$((refuse_n+1))
rm -f "$AFL"; env OVERRIDE_LEDGER="$AFL" bash "$HOOKS_DIR/override-ledger.sh" X "MY_SECRET='$AF_TOK' DB_PASSWORD=\"$AF_TOK\" run" "p"
if [ -s "$AFL" ] && ! grep -qF "$AF_TOK" "$AFL" && grep -qF ' run' "$AFL"; then ok; else bad "F9: quoted SECRET/PASSWORD values must be masked: $(cat "$AFL" 2>/dev/null)"; fi
refuse_n=$((refuse_n+1))
rm -f "$AFL"; env OVERRIDE_LEDGER="$AFL" bash "$HOOKS_DIR/override-ledger.sh" GITGUARD "GITGUARD=1 FOO=bar git reset --hard origin/main" "reset --hard"
if grep -qF 'GITGUARD=1 FOO=bar git reset --hard origin/main' "$AFL"; then ok; else bad "F9 control: an ordinary command must be logged unchanged: $(cat "$AFL" 2>/dev/null)"; fi
pass_n=$((pass_n+1))
rm -f "$AFL"; printf '%s' "$(json_bash "GITGUARD=1 git push https://u:${AF_TOK}@host/o/r.git --force")" | env OVERRIDE_LEDGER="$AFL" bash "$AF_BDG" >/dev/null 2>&1
if [ -s "$AFL" ] && ! grep -qF "$AF_TOK" "$AFL"; then ok; else bad "F9: through the real guard, the force-push URL token must not reach the ledger: $(cat "$AFL" 2>/dev/null)"; fi
refuse_n=$((refuse_n+1))
# ---- F10 PRIVACY_OK logs like every other override ----
HPV="$(rb_home privok)"; RPL="$RB/privok-ledger.tsv"; rm -f "$RPL"
RB_WANT='.'
rb_case pass "F10: PRIVACY_OK=1 still lets a listed name through" "$HPV" n.txt "met zebulonquixote today" PRIVACY_OK=1 OVERRIDE_LEDGER="$RPL"
if ledger_has "$RPL" PRIVACY_OK && [ "$(wc -l < "$RPL" | tr -d ' ')" = 1 ]; then ok; else bad "F10: PRIVACY_OK=1 must write exactly one ledger line: $(cat "$RPL" 2>/dev/null)"; fi
refuse_n=$((refuse_n+1))
if grep -qi 'zebulon' "$RPL" 2>/dev/null; then bad "F10: the ledger line must not carry the listed name"; else ok; fi
pass_n=$((pass_n+1))
rm -f "$RPL"; rb_case pass "F10: PRIVACY_OK=1 on a clean commit passes with no ledger line" "$HPV" ok.txt "nothing sensitive" PRIVACY_OK=1 OVERRIDE_LEDGER="$RPL"
if [ ! -s "$RPL" ]; then ok; else bad "F10: an unneeded PRIVACY_OK=1 must not write a ledger line"; fi
pass_n=$((pass_n+1))
RB_WANT='ledger'
rb_case refuse "F10: PRIVACY_OK=1 with an unwritable ledger is refused" "$HPV" n.txt "met zebulonquixote today" PRIVACY_OK=1 OVERRIDE_LEDGER="/nonexistent-$$/deep/overrides.tsv"
HPV2="$(rb_home privok2)"; rm -f "$HPV2/.claude/hooks/override-ledger.sh"
rb_case refuse "F10: PRIVACY_OK=1 with no override-ledger.sh at all is refused" "$HPV2" n.txt "met zebulonquixote today" PRIVACY_OK=1
RB_WANT='real name|listed name|matches'
rb_case refuse "F10 control: without PRIVACY_OK the listed name is still refused" "$HPV" n.txt "met zebulonquixote today" OVERRIDE_LEDGER="$RPL"
RB_WANT='.'
# ---- F12 the by-hand names list: section headers are not needles ----
AFN="$T/af-names.local"
sed -n "/^\[ -f ~\/.claude\/.redaction-names.local \] || cat > /,/^EOF\$/p" "$REPOD2/INSTALL.md" | sed '1d;$d' > "$AFN"
if [ -s "$AFN" ] && ! grep -qE '^\[' "$AFN"; then ok; else bad "F12: INSTALL.md's by-hand names list must not hold a bare [section] line (lines: $(wc -l < "$AFN" 2>/dev/null))"; fi
refuse_n=$((refuse_n+1))
HF12="$RB/home-f12"; mkdir -p "$HF12/.claude/hooks"; cp "$HOOKS_DIR/override-ledger.sh" "$HF12/.claude/hooks/"
cp "$AFN" "$HF12/.claude/.redaction-names.local"; printf 'ZebulonQuixote\n' >> "$HF12/.claude/.redaction-names.local"
rb_case pass "F12: a file that mentions [guard] commits under the by-hand names list" "$HF12" d.md "the [guard] and [redact-only] sections"
RB_WANT='real name|listed name|matches'; rb_case refuse "F12 control: a listed name under the by-hand list is still refused" "$HF12" d.md "met zebulonquixote"
RB_WANT='.'
HF12B="$RB/home-f12b"; mkdir -p "$HF12B/.claude/hooks"; cp "$HOOKS_DIR/override-ledger.sh" "$HF12B/.claude/hooks/"
printf '[guard]\nZebulonQuixote\n[redact-only]\n' > "$HF12B/.claude/.redaction-names.local"
rb_case pass "F12: a list that holds bare [guard] / [redact-only] lines (old by-hand install) does not refuse [guard]" "$HF12B" d.md "the [guard] section"
RB_WANT='real name|listed name|matches'; rb_case refuse "F12 control: the name in the same old-style list still refuses" "$HF12B" d.md "met zebulonquixote"
RB_WANT='.'
# ---- B1 the kit's own shipped files pass the kit's own secret scan ----
AFK="$(rb_new)"; AFKH="$(rb_home shipped)"; printf "# no names: this case is about the KEY scan only\n" > "$AFKH/.claude/.redaction-names.local"; af_files=0
while IFS= read -r rel; do
  [ -f "$REPOD2/$rel" ] || continue
  mkdir -p "$AFK/$(dirname "$rel")"; cp "$REPOD2/$rel" "$AFK/$rel"; af_files=$((af_files+1))
done < <(grep -oE '"\$SRC/[^"]+"' "$REPOD2/install.sh" | tr -d '"' | sed 's#^\$SRC/##' | sort -u; ls "$REPOD2"/git-hooks/* 2>/dev/null | sed "s#^$REPOD2/##")
if [ "$af_files" -ge 20 ]; then ok; else bad "B1: the scan must cover every file install.sh copies (found only $af_files)"; fi
refuse_n=$((refuse_n+1))
# The key scan (4b) runs BEFORE the privacy limb and refuses with "key-shaped": that word must be absent. (The privacy
# limb may still name the kit's own documented noreply address in its identity checks; that is not a secret.)
git -C "$AFK" add -A >/dev/null 2>&1
af_err="$(env HOME="$AFKH" "${ID[@]}" git -C "$AFK" commit -q -m t 2>&1 >/dev/null)"; af_rc=$?
if [ "$af_rc" = 0 ] || { ! printf '%s' "$af_err" | grep -q 'key-shaped' && ! printf '%s' "$af_err" | grep -q 'cannot read SECRET_RE'; }; then ok; else bad "B1: a file install.sh copies ($af_files files) trips the kit's own secret scan: $af_err"; fi
pass_n=$((pass_n+1))

echo "27 hooks/test-helper-ledger.sh and hooks/test-rules-cap.sh: run as their own suites, fold into RESULT"
HL_OUT="$(HOOKS_DIR="$HOOKS_DIR" bash "$HOOKS_DIR/test-helper-ledger.sh" 2>&1)"; HL_RC=$?
printf '%s\n' "$HL_OUT" | tail -3
HL_LAST="$(printf '%s\n' "$HL_OUT" | grep -E '^test-helper-ledger\.sh:' | tail -1)"
HL_P="$(printf '%s' "$HL_LAST" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')"
HL_F="$(printf '%s' "$HL_LAST" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+')"
if [ "$HL_RC" = 0 ] && [ "${HL_F:-1}" = 0 ]; then ok; else bad "hooks/test-helper-ledger.sh must exit 0 with 0 failed; rc=$HL_RC last='$HL_LAST'"; fi
pass_n=$((pass_n+1))
pass=$((pass + ${HL_P:-0})); fail=$((fail + ${HL_F:-0}))

RC_OUT="$(GIT_HOOKS_DIR="$GIT_HOOKS_DIR" bash "$HOOKS_DIR/test-rules-cap.sh" 2>&1)"; RC_RC=$?
printf '%s\n' "$RC_OUT" | tail -3
RC_LAST="$(printf '%s\n' "$RC_OUT" | grep -E '^test-rules-cap\.sh:' | tail -1)"
RC_P="$(printf '%s' "$RC_LAST" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')"
RC_F="$(printf '%s' "$RC_LAST" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+')"
if [ "$RC_RC" = 0 ] && [ "${RC_F:-1}" = 0 ]; then ok; else bad "hooks/test-rules-cap.sh must exit 0 with 0 failed; rc=$RC_RC last='$RC_LAST'"; fi
pass_n=$((pass_n+1))
pass=$((pass + ${RC_P:-0})); fail=$((fail + ${RC_F:-0}))

echo "attack fixes (2): installer, always-on session hooks, backup hook (refresh 2026-09-29, attack-B B2 M5 M6 M7 M8 M12 M13 M14 M16)"
ATK="$T/atk2"; mkdir -p "$ATK"
atk_mode() { python3 -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$1" 2>/dev/null; }
# ---- B2: the backup's mirror step commits and pushes only from the expected branch, with nothing unpushed of the person's ----
b2_new() {   # name [conf-branch-line] -> prints the fixture home; the mirror is a plain SUBFOLDER of the project repo
  local h="$ATK/$1"; mkdir -p "$h/.claude/hooks" "$h/state"
  git init -q --bare -b main "$h/proj.git"; git init -q --bare -b main "$h/cfg.git"
  git init -q -b main "$h/proj"; git -C "$h/proj" config core.hooksPath /dev/null
  git -C "$h/proj" config user.name Tester; git -C "$h/proj" config user.email tester@example.com
  git -C "$h/proj" remote add origin "$h/proj.git"; mkdir -p "$h/proj/docs/claude-copies"
  echo seed > "$h/proj/README"; git -C "$h/proj" add -A; git -C "$h/proj" commit -q -m initial; git -C "$h/proj" push -q -u origin main
  git -C "$h/.claude" init -q -b main; git -C "$h/.claude" config core.hooksPath /dev/null
  git -C "$h/.claude" config user.name Tester; git -C "$h/.claude" config user.email tester@example.com
  git -C "$h/.claude" remote add origin "$h/cfg.git"
  cp "$HOOKS_DIR/check-claude-md.sh" "$HOOKS_DIR/auto-backup.sh" "$h/.claude/hooks/"; echo "rules" > "$h/.claude/CLAUDE.md"; echo '{"name":"clean"}' > "$h/.claude/settings.json"
  printf 'AUTHOR=Tester <tester@example.com>\nMIRROR_DIR=%s\n%s\n' "$h/proj/docs/claude-copies" "${2:-}" > "$h/.claude/hooks/backup.conf"
  git -C "$h/.claude" add -A; git -C "$h/.claude" commit -q -m seed; git -C "$h/.claude" push -q -u origin main
  printf '%s' "$h"
}
b2_run() { env HOME="$1" STATE_CHECK_STATE_DIR="$1/state" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1; }
b2_refreshes() { git --git-dir="$1/proj.git" log --all --format=%s 2>/dev/null | grep -c '^auto-refresh copies'; }
b2_notice() { [ -s "$1/state/notices/auto-backup" ] && grep -qi 'mirror' "$1/state/notices/auto-backup"; }
B2A="$(b2_new feat)"
git -C "$B2A/proj" checkout -q -b feature/half-done; echo a > "$B2A/proj/w1"; git -C "$B2A/proj" add -A; git -C "$B2A/proj" commit -q -m "WIP: half-done"
git -C "$B2A/proj" push -q -u origin feature/half-done
echo b > "$B2A/proj/w2"; git -C "$B2A/proj" add -A; git -C "$B2A/proj" commit -q -m "WIP 2: do not push yet"
b2a_head="$(git -C "$B2A/proj" rev-parse HEAD)"; b2a_remote="$(git --git-dir="$B2A/proj.git" rev-parse feature/half-done)"
b2_run "$B2A"
if [ "$(b2_refreshes "$B2A")" = 0 ] && [ "$(git -C "$B2A/proj" rev-parse HEAD)" = "$b2a_head" ] && [ "$(git --git-dir="$B2A/proj.git" rev-parse feature/half-done)" = "$b2a_remote" ]; then ok; else bad "B2: a mirror inside the person's repo on a feature branch with an unpushed commit must get NO commit and NO push"; fi
refuse_n=$((refuse_n+1))
if b2_notice "$B2A"; then ok; else bad "B2: the skipped mirror must leave a pending notice naming the mirror"; fi
refuse_n=$((refuse_n+1))
B2B="$(b2_new ahead)"
echo b > "$B2B/proj/w2"; git -C "$B2B/proj" add -A; git -C "$B2B/proj" commit -q -m "WIP 2: do not push yet"
b2b_remote="$(git --git-dir="$B2B/proj.git" rev-parse main)"
b2_run "$B2B"
if [ "$(b2_refreshes "$B2B")" = 0 ] && [ "$(git --git-dir="$B2B/proj.git" rev-parse main)" = "$b2b_remote" ]; then ok; else bad "B2: the expected branch with a local commit ahead of its upstream must not be pushed"; fi
refuse_n=$((refuse_n+1))
B2C="$(b2_new good)"
b2_run "$B2C"
if [ "$(b2_refreshes "$B2C")" = 1 ] && git --git-dir="$B2C/proj.git" log main --format=%s | head -1 | grep -q '^auto-refresh copies'; then ok; else bad "B2 control: a mirror on main, in step with its upstream, must still be committed and pushed to main"; fi
pass_n=$((pass_n+1))
if [ ! -e "$B2C/state/notices/auto-backup" ]; then ok; else bad "B2 control: a clean mirror refresh must leave no notice"; fi
pass_n=$((pass_n+1))
B2D="$(b2_new trunk MIRROR_BRANCH=trunk)"
git -C "$B2D/proj" branch -q -m main trunk; git -C "$B2D/proj" push -q -u origin trunk
b2_run "$B2D"
if [ "$(git --git-dir="$B2D/proj.git" log trunk --format=%s | head -1 | grep -c '^auto-refresh copies')" = 1 ]; then ok; else bad "B2: MIRROR_BRANCH=trunk in the conf must be honoured for a mirror on trunk"; fi
pass_n=$((pass_n+1))
B2E="$(b2_new wrongbr)"
git -C "$B2E/proj" branch -q -m main trunk; git -C "$B2E/proj" push -q -u origin trunk
b2_run "$B2E"
if [ "$(b2_refreshes "$B2E")" = 0 ]; then ok; else bad "B2: with no MIRROR_BRANCH (default main) a mirror on trunk must be skipped"; fi
refuse_n=$((refuse_n+1))

# ---- M6: every promised warning reaches someone ----
# post hook: exit 2 + reason on stderr (the tool already ran, nothing is undone)
M6D="$ATK/m6post"; mkdir -p "$M6D"; cp "$HOOKS_DIR/channel-size-post.sh" "$M6D/"
printf 'LIMIT=100\nNOTES.md words 5 10\n' > "$M6D/channel-ceiling.conf"
python3 -c "print(' '.join(['w']*16))" > "$M6D/NOTES.md"
INPUT="$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":"x"}}))' "$M6D/NOTES.md")"
expect refuse 2 "M6: the size post hook must exit 2 (reason on stderr) when the file is over its hard stop" bash "$M6D/channel-size-post.sh"
m6err="$(printf '%s' "$INPUT" | bash "$M6D/channel-size-post.sh" 2>&1 >/dev/null)"
if printf '%s' "$m6err" | grep -q 'HARD STOP'; then ok; else bad "M6: the post hook's reason must be on stderr"; fi
refuse_n=$((refuse_n+1))
python3 -c "print(' '.join(['w']*8))" > "$M6D/NOTES.md"
expect pass 0 "M6 control: a file over the band but under the hard stop stays silent, exit 0" bash "$M6D/channel-size-post.sh"
# the notice file: printed and deleted by the always-on clock hook at the next TYPED prompt
M6N="$ATK/m6notice"; mkdir -p "$M6N/state/notices" "$M6N/.claude"
notice_run() { printf '{"session_id":"s","hook_event_name":"%s","prompt":"hello there"}' "$1" | env HOME="$M6N" STATE_CHECK_STATE_DIR="$M6N/state" bash "$HOOKS_DIR/clock-in-context.sh" 2>/dev/null; }
printf 'auto-backup: the mirror was skipped, tell the user (marker-m6)\n' > "$M6N/state/notices/auto-backup"
out="$(notice_run SessionStart)"
if ! printf '%s' "$out" | grep -q 'marker-m6' && [ -e "$M6N/state/notices/auto-backup" ]; then ok; else bad "M6 control: a SessionStart is not a typed prompt - the notice must wait"; fi
pass_n=$((pass_n+1))
out="$(notice_run UserPromptSubmit)"
if printf '%s' "$out" | grep -q 'marker-m6'; then ok; else bad "M6: a typed prompt must print the pending notice"; fi
refuse_n=$((refuse_n+1))
if [ ! -e "$M6N/state/notices/auto-backup" ]; then ok; else bad "M6: the notice must be deleted once printed"; fi
refuse_n=$((refuse_n+1))
out="$(notice_run UserPromptSubmit)"
if ! printf '%s' "$out" | grep -q 'marker-m6'; then ok; else bad "M6 control: the notice must print only once"; fi
pass_n=$((pass_n+1))
# a backup refusal (a secret in the config) leaves a notice, private mode; a clean run leaves none
M6B="$(b2_new secnote)"
printf 'k=%s\n' "gh""p_$(printf 'a%.0s' {1..30})" > "$M6B/.claude/leaked.txt"
b2_run "$M6B"
if [ -s "$M6B/state/notices/auto-backup" ] && grep -q 'leaked.txt' "$M6B/state/notices/auto-backup"; then ok; else bad "M6: a backup refusal over a secret must leave a pending notice naming the file"; fi
refuse_n=$((refuse_n+1))
if [ "$(atk_mode "$M6B/state/notices/auto-backup")" = 600 ] && [ "$(atk_mode "$M6B/state/notices")" = 700 ]; then ok; else bad "M6/M7: the notice file must be created private (600) in a private folder (700)"; fi
refuse_n=$((refuse_n+1))
rm -f "$M6B/.claude/leaked.txt"; rm -f "$M6B/state/notices/auto-backup"; b2_run "$M6B"
if [ ! -e "$M6B/state/notices/auto-backup" ]; then ok; else bad "M6 control: a clean backup run leaves no notice"; fi
pass_n=$((pass_n+1))

# ---- M5: a conf line's pattern is never glob-expanded against the folder the hook runs in ----
M5D="$ATK/m5"; mkdir -p "$M5D/hooks" "$M5D/proj/docs" "$M5D/proj/plans"
cp "$HOOKS_DIR/channel-size-guard.sh" "$HOOKS_DIR/channel-size-post.sh" "$M5D/hooks/"
printf 'LIMIT=100\n*/NOTES.md words 5 10\n' > "$M5D/hooks/channel-ceiling.conf"
python3 -c "print(' '.join(['w']*16))" > "$M5D/proj/docs/NOTES.md"; python3 -c "print(' '.join(['w']*16))" > "$M5D/proj/plans/NOTES.md"
m5run() { ( cd "$M5D/proj" && printf '%s' "$2" | bash "$M5D/hooks/$1" >/dev/null 2>&1 ); echo $?; }
m5cmd="$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":"echo more >> plans/NOTES.md"},"cwd":sys.argv[1]}))' "$M5D/proj")"
if [ "$(m5run channel-size-guard.sh "$m5cmd")" = 2 ]; then ok; else bad "M5: with */NOTES.md in the conf and two matching folders, an append to an over-stop NOTES.md must be refused from the project folder"; fi
refuse_n=$((refuse_n+1))
m5w="$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1]+"/plans/NOTES.md","old_string":"w","new_string":"w w w"}}))' "$M5D/proj")"
if [ "$(m5run channel-size-guard.sh "$m5w")" = 2 ]; then ok; else bad "M5: a growing Edit of plans/NOTES.md over its stop must be refused from the project folder"; fi
refuse_n=$((refuse_n+1))
m5p="$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1]+"/plans/NOTES.md","content":"x"}}))' "$M5D/proj")"
if [ "$(m5run channel-size-post.sh "$m5p")" = 2 ]; then ok; else bad "M5: the post hook must warn about an over-stop NOTES.md from the project folder too"; fi
refuse_n=$((refuse_n+1))
python3 -c "print(' '.join(['w']*4))" > "$M5D/proj/plans/NOTES.md"
if [ "$(m5run channel-size-guard.sh "$m5cmd")" = 0 ]; then ok; else bad "M5 control: an append to a small NOTES.md must pass from the project folder"; fi
pass_n=$((pass_n+1))

# ---- M12: the size guard parses a long command once, not once per line ----
M12D="$ATK/m12"; mkdir -p "$M12D/hooks" "$M12D/proj"; cp "$HOOKS_DIR/channel-size-guard.sh" "$M12D/hooks/"
printf 'LIMIT=100\nNOTES.md words 5 10\nMISTAKES.md lines 5 10\nDECISIONS.md words 5 10\n' > "$M12D/hooks/channel-ceiling.conf"
python3 -c "print(' '.join(['w']*16))" > "$M12D/proj/NOTES.md"
m12_cmd() { python3 - "$1" "$2" <<'PY'
import sys
n=int(sys.argv[1]); tail=sys.argv[2]
lines=["cat > big.txt <<'EOF'"]+["line %d of an ordinary heredoc body, some words here" % i for i in range(n)]+["EOF"]
if tail: lines.append(tail)
print("\n".join(lines))
PY
}
m12_json() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$2"; }
m12_json "$(m12_cmd 1500 '')" "$M12D/proj" > "$M12D/plain.json"
m12_json "$(m12_cmd 1500 'echo more >> NOTES.md')" "$M12D/proj" > "$M12D/tail.json"
m12_t0=$SECONDS; ( cd "$M12D/proj" && bash "$M12D/hooks/channel-size-guard.sh" < "$M12D/plain.json" >/dev/null 2>&1 ); m12_rc=$?; m12_dt=$((SECONDS - m12_t0))
if [ "$m12_rc" = 0 ] && [ "$m12_dt" -lt 8 ]; then ok; else bad "M12: a 1,500-line heredoc naming no watched file must be judged in under 8 s (rc=$m12_rc, took ${m12_dt}s)"; fi
refuse_n=$((refuse_n+1))
( cd "$M12D/proj" && bash "$M12D/hooks/channel-size-guard.sh" < "$M12D/tail.json" >/dev/null 2>&1 ); m12_rc=$?
if [ "$m12_rc" = 2 ]; then ok; else bad "M12 control: a long command that ENDS with an append to an over-stop NOTES.md must still be refused (rc=$m12_rc)"; fi
refuse_n=$((refuse_n+1))
m12_json "$(m12_cmd 300 'echo more >> other.md')" "$M12D/proj" > "$M12D/other.json"
( cd "$M12D/proj" && bash "$M12D/hooks/channel-size-guard.sh" < "$M12D/other.json" >/dev/null 2>&1 ); m12_rc=$?
if [ "$m12_rc" = 0 ]; then ok; else bad "M12 control: a long command appending to an unwatched file must pass (rc=$m12_rc)"; fi
pass_n=$((pass_n+1))

# ---- M13: <project>/.claude/CLAUDE.md is the project's rules file ----
M13H="$ATK/m13"; mkdir -p "$M13H/.claude/hooks" "$M13H/projects/with-dot-claude/.claude" "$M13H/projects/bare" "$M13H/projects/plain"
cp "$HOOKS_DIR"/*.md "$M13H/.claude/hooks/" 2>/dev/null;
[ -s "$M13H/.claude/hooks/interview.md" ] || echo "Interview marker m13" > "$M13H/.claude/hooks/interview.md"
printf '## PROCESS RULES (enforced)\n1. x\n' > "$M13H/.claude/CLAUDE.md"; printf '%s\n' "$M13H/projects" > "$M13H/.claude/hooks/project-roots.conf"
echo rules > "$M13H/projects/with-dot-claude/.claude/CLAUDE.md"; echo rules > "$M13H/projects/plain/CLAUDE.md"
m13() { printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$1" | env HOME="$M13H" bash "$HOOKS_DIR/check-claude-md.sh" 2>/dev/null | grep -c 'has no CLAUDE.md yet'; }
if [ "$(m13 "$M13H/projects/with-dot-claude")" = 0 ]; then ok; else bad "M13: a project whose rules live in .claude/CLAUDE.md must NOT get the new-project interview"; fi
refuse_n=$((refuse_n+1))
if [ "$(m13 "$M13H/projects/plain")" = 0 ]; then ok; else bad "M13 control: a project with ./CLAUDE.md gets no interview"; fi
pass_n=$((pass_n+1))
if [ "$(m13 "$M13H/projects/bare")" = 1 ]; then ok; else bad "M13 control: a project with no rules file at all still gets the interview"; fi
pass_n=$((pass_n+1))

# ---- M14: the backup allowlist leaves memory notes out; INSTALL.md says why ----
M14R="$ATK/m14"; mkdir -p "$M14R/projects/-x-y/memory" "$M14R/skills/s"; git init -q "$M14R"; cp "$HOOKS_DIR/dot-claude.gitignore" "$M14R/.gitignore"
echo n > "$M14R/projects/-x-y/memory/note.md"; echo n > "$M14R/projects/-x-y/session.jsonl"; echo n > "$M14R/skills/s/SKILL.md"
if git -C "$M14R" check-ignore -q projects/-x-y/memory/note.md; then ok; else bad "M14: a memory note under projects/ must stay OUT of the backup allowlist"; fi
refuse_n=$((refuse_n+1))
if git -C "$M14R" check-ignore -q projects/-x-y/session.jsonl; then ok; else bad "M14: a session transcript stays out of the allowlist"; fi
refuse_n=$((refuse_n+1))
if ! git -C "$M14R" check-ignore -q skills/s/SKILL.md; then ok; else bad "M14 control: skills/ stays in the allowlist"; fi
pass_n=$((pass_n+1))
if grep -qiE 'memory' "$REPOD2/INSTALL.md" && grep -iE 'memory' "$REPOD2/INSTALL.md" | grep -qiE 'home path|folder names'; then ok; else bad "M14: INSTALL.md must say in one line why memory notes are left out of the backup"; fi
refuse_n=$((refuse_n+1))

# ---- M7: an existing settings.json keeps its file mode through the merge ----
for m7tool in node python3; do
  M7H="$ATK/m7-$m7tool"; mkdir -p "$M7H/.claude"; printf '{"env":{"K":"v"}}\n' > "$M7H/.claude/settings.json"; chmod 600 "$M7H/.claude/settings.json"
  if [ "$m7tool" = python3 ]; then env HOME="$M7H" INSTALL_PRETEND_MISSING=node bash "$REPOD2/install.sh" --yes >/dev/null 2>&1; else env HOME="$M7H" bash "$REPOD2/install.sh" --yes >/dev/null 2>&1; fi
  if [ "$(atk_mode "$M7H/.claude/settings.json")" = 600 ] && [ "$(d2_count "$M7H/.claude/settings.json" SessionStart)" -ge 1 ]; then ok; else bad "M7: a 600 settings.json must stay 600 after the merge ($m7tool merge; got $(atk_mode "$M7H/.claude/settings.json"))"; fi
  refuse_n=$((refuse_n+1))
done
M7C="$ATK/m7-644"; mkdir -p "$M7C/.claude"; printf '{}\n' > "$M7C/.claude/settings.json"; chmod 644 "$M7C/.claude/settings.json"
env HOME="$M7C" bash "$REPOD2/install.sh" --yes >/dev/null 2>&1
if [ "$(atk_mode "$M7C/.claude/settings.json")" = 644 ]; then ok; else bad "M7 control: a 644 settings.json stays 644"; fi
pass_n=$((pass_n+1))

# ---- M8: the installer saves an existing global core.hooksPath and the printed undo restores exactly it ----
m8_run() { local h="$1"; env HOME="$h" python3 - "$h" "$REPOD2/install.sh" "$2" <<'PY'
import os,pty,sys,select,re
home,script,outp=sys.argv[1:4]
pid,fd=pty.fork()
if pid==0:
    os.environ["HOME"]=home
    os.execvp("bash",["bash",script])
buf=b""; answered=0
while True:
    r,_,_=select.select([fd],[],[],0.5)
    if r:
        try: d=os.read(fd,4096)
        except OSError: break
        if not d: break
        buf+=d
    elif len(buf)>answered:
        tail=buf[-400:].decode("utf8","ignore")
        if re.search(r"(\] |: |\? )$",tail):
            os.write(fd,b"y\n" if tail.rstrip().endswith("[y/N]") and "core.hooksPath" in tail else b"\n"); answered=len(buf)
open(outp,"wb").write(buf)
_,st=os.waitpid(pid,0); sys.exit(os.waitstatus_to_exitcode(st))
PY
}
M8A="$ATK/m8a"; mkdir -p "$M8A/company hooks"; env HOME="$M8A" git config --global core.hooksPath "$M8A/company hooks"
m8_run "$M8A" "$ATK/m8a.out" >/dev/null 2>&1
if [ "$(env HOME="$M8A" git config --global core.hooksPath)" = "$M8A/.claude/git-hooks" ]; then ok; else bad "M8 setup: the pty run must have answered yes to the hooksPath step"; fi
refuse_n=$((refuse_n+1))
if [ "$(cat "$M8A/.claude/.setup-prev-hookspath" 2>/dev/null)" = "$M8A/company hooks" ]; then ok; else bad "M8: the previous core.hooksPath must be saved under ~/.claude before it is replaced"; fi
refuse_n=$((refuse_n+1))
m8_undo="$(grep 'To undo:' "$ATK/m8a.out" | tail -1 | sed 's/^.*To undo: //' | tr -d '\r')"
( env HOME="$M8A" bash -c "$m8_undo" >/dev/null 2>&1 )
if [ "$(env HOME="$M8A" git config --global core.hooksPath)" = "$M8A/company hooks" ]; then ok; else bad "M8: the printed undo line must restore the previous value exactly (line was: $m8_undo)"; fi
refuse_n=$((refuse_n+1))
M8B="$ATK/m8b"; mkdir -p "$M8B"
m8_run "$M8B" "$ATK/m8b.out" >/dev/null 2>&1
m8_undo="$(grep 'To undo:' "$ATK/m8b.out" | tail -1 | sed 's/^.*To undo: //' | tr -d '\r')"
( env HOME="$M8B" bash -c "$m8_undo" >/dev/null 2>&1 )
if [ "$(cat "$M8B/.claude/.setup-prev-hookspath" 2>/dev/null)" = unset ] && ! env HOME="$M8B" git config --global core.hooksPath >/dev/null 2>&1; then ok; else bad "M8 control: with no previous value the saved file says unset and the undo unsets"; fi
pass_n=$((pass_n+1))

# ---- M16: `sh install.sh` re-runs itself under bash instead of dying half-way ----
M16H="$ATK/m16"; mkdir -p "$M16H"
env HOME="$M16H" sh "$REPOD2/install.sh" --yes >/dev/null 2>&1; m16rc=$?
if [ "$m16rc" = 0 ] && [ "$(d2_count "$M16H/.claude/settings.json" SessionStart)" -ge 1 ]; then ok; else bad "M16: sh install.sh --yes must finish (rc=$m16rc) with the hooks registered"; fi
refuse_n=$((refuse_n+1))
if command -v zsh >/dev/null 2>&1; then
  M16Z="$ATK/m16z"; mkdir -p "$M16Z"; env HOME="$M16Z" zsh "$REPOD2/install.sh" --yes >/dev/null 2>&1; m16rc=$?
  if [ "$m16rc" = 0 ] && [ "$(d2_count "$M16Z/.claude/settings.json" SessionStart)" -ge 1 ]; then ok; else bad "M16: zsh install.sh --yes must finish (rc=$m16rc) with the hooks registered"; fi
  refuse_n=$((refuse_n+1))
fi

echo "attack fixes (3): the opt-in multi-chat group (refresh 2026-09-30, attack-B B3 M1 M3 M4 M10 M11 M15 M6 M7)"
F3="$T/f3"; mkdir -p "$F3"; F3HK="$F3/hk"; mkdir -p "$F3HK"
cp "$HOOKS_DIR/doorman.sh" "$HOOKS_DIR/stop-state-check.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/clock-in-context.sh" "$F3HK/"
printf 'STATE_FILE state/{role}.md\nmyapp-dev*  dev  850\nmyapp-ops*  ops  850\n' > "$F3HK/state-check.conf"
export -f atk_mode
f3_chk() { local kind="$1" label="$2"; shift 2; if "$@"; then ok; else bad "$label"; fi; if [ "$kind" = refuse ]; then refuse_n=$((refuse_n+1)); else pass_n=$((pass_n+1)); fi; }
f3_has() { grep -q -- "$1" "$2"; }
f3_tp() {   # <file> <K>: a transcript whose newest usage line sums to K thousand tokens
  printf '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"go"}}\n{"type":"assistant","message":{"usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":%d,"output_tokens":5}}}\n' $(( ($2 - 1) * 1000 )) > "$1"
}
f3_zero_line() { printf '{"type":"assistant","message":{"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}\n'; }
f3_door() {   # <cwd> <sid> <transcript> [prompt]: the doorman against $S; stdout $F3/o, stderr $F3/e, rc F3_RC
  dj "$1" "$2" "${4:-hello}" "$3" | STATE_CHECK_STATE_DIR="$S" bash "$F3HK/doorman.sh" > "$F3/o" 2> "$F3/e"; F3_RC=$?
}
f3_stop() {   # <cwd> <sid> <transcript>: the Stop hook against $S; stdout $F3/so, rc F3_SRC
  ssc_json "$1" "$2" false "$3" | STATE_CHECK_STATE_DIR="$S" bash "$F3HK/stop-state-check.sh" > "$F3/so" 2> "$F3/se"; F3_SRC=$?
}
f3_ret() { mkdir -p "$S/retired" "$S/retired-compacts"; echo "2026-01-01 00:00 dev 900k" > "$S/retired/$1"; echo 0 > "$S/retired-compacts/$1"; }
f3_rc() { [ "$F3_RC" = "$1" ]; }
D21="$F3/myapp-dev21"; D22="$F3/myapp-dev22"; D23="$F3/myapp-dev23"; O1="$F3/myapp-ops1"; mkdir -p "$D21" "$D22" "$D23" "$O1"
f3_tp "$F3/tp100" 100; f3_tp "$F3/tp900" 900

echo "  B3 a retired chat's held message reaches the next chat of the same ROLE (its own folder), once, and the inbox copy is marked delivered"
S="$F3/s-b3a"; f3_ret b3c; f3_door "$D21" b3c "$F3/tp100" "deploy the fix to staging"
f3_chk pass "B3 setup: the retired chat's message is held (exit 2)" f3_rc 2
f3_chk pass "B3 pair: before any delivery the inbox copy carries no delivered mark" bash -c "! grep -q 'DELIVERED' '$S/inbox/dev.md'"
f3_door "$D22" b3d "$F3/tp100" "hi, you are the new dev"
f3_chk refuse "B3 a fresh chat of the same role in ANOTHER folder receives the held message" f3_has "deploy the fix to staging" "$F3/o"
f3_chk refuse "B3 the inbox copy is marked delivered, naming the receiving session" bash -c "grep -q 'DELIVERED' '$S/inbox/dev.md' && grep 'DELIVERED' '$S/inbox/dev.md' | grep -q 'b3d'"
f3_door "$D22" b3e "$F3/tp100" "what is next?"
f3_chk pass "B3 pair: a second fresh chat gets nothing (delivered once)" bash -c "! grep -q 'HELD MESSAGE' '$F3/o'"
S="$F3/s-b3b"; f3_ret b3x; f3_door "$D21" b3x "$F3/tp100" "for the dev role only"; f3_door "$O1" b3y "$F3/tp100" "a chat of another role"
f3_chk pass "B3 pair: a chat of ANOTHER role never receives it" bash -c "! grep -q 'HELD MESSAGE' '$F3/o' && [ -f '$S/held/b3x' ]"
S="$F3/s-b3c"; f3_ret b3s; f3_door "$D21" b3s "$F3/tp100" "same chat, next message"; f3_door "$D21" b3s "$F3/tp100" "second message"
f3_chk refuse "B3 the held message delivered to its OWN chat is marked delivered in the inbox too" bash -c "grep -q 'DELIVERED' '$S/inbox/dev.md'"
S="$F3/s-b3d"; f3_door "$D21" b3f "$F3/tp900" "held from a chat that is full but not retired"
f3_chk pass "B3 setup: the full chat's message is held" f3_rc 2
f3_door "$D22" b3g "$F3/tp100" "first message of the new chat"
f3_chk refuse "B3 when delivery cannot happen the new chat is told at its first prompt that a held message is waiting" f3_has "is waiting" "$F3/o"
f3_door "$D22" b3g "$F3/tp100" "second message"
f3_chk pass "B3 pair: it is told only once" bash -c "! grep -q 'is waiting' '$F3/o'"
f3_door "$O1" b3h "$F3/tp100" "another role's first message"
f3_chk pass "B3 pair: a chat of another role is not told" bash -c "! grep -q 'is waiting' '$F3/o'"
S="$F3/s-b3e"; f3_ret b3r; f3_door "$D21" b3r "$F3/tp100" "exactly once please"
( dj "$D22" b3n1 "go" "$F3/tp100" | STATE_CHECK_STATE_DIR="$S" bash "$F3HK/doorman.sh" > "$F3/o1" 2>/dev/null ) &
( dj "$D23" b3n2 "go" "$F3/tp100" | STATE_CHECK_STATE_DIR="$S" bash "$F3HK/doorman.sh" > "$F3/o2" 2>/dev/null ) &
wait
f3_chk refuse "B3 two new chats of the same role starting at once: the held message is delivered exactly once" bash -c "[ \"\$(cat '$F3/o1' '$F3/o2' | grep -c 'HELD MESSAGE')\" = 1 ] && [ \"\$(grep -c 'DELIVERED' '$S/inbox/dev.md')\" = 1 ]"

echo "  M1 an all-zero usage line (an API error) is not a measurement: the end-of-turn check still retires the chat"
S="$F3/s-m1a"; { f3_tp "$F3/tpm1" 900; f3_zero_line >> "$F3/tpm1"; }
f3_stop "$D21" m1a "$F3/tpm1"
f3_chk refuse "M1 a chat at 900k whose last usage line is an API-error zero line is marked retired at turn end" test -f "$S/retired/m1a"
f3_chk refuse "M1 the turn-start size is the real 900k, never 0" bash -c "[ \"\$(head -1 '$S/turn-start/m1a')\" = 900 ]"
S="$F3/s-m1b"; { f3_tp "$F3/tpm1b" 100; f3_zero_line >> "$F3/tpm1b"; }
f3_stop "$D21" m1b "$F3/tpm1b"
f3_chk pass "M1 pair: 100k then a zero line (under the floor) is not retired" bash -c "[ ! -e '$S/retired/m1b' ] && [ \"\$(head -1 '$S/turn-start/m1b')\" = 100 ]"
S="$F3/s-m1c"; f3_ret m1c; f3_door "$D21" m1c "$F3/tpm1" "held with an error line last"
f3_chk pass "M1 the doorman holds the same transcript (900k then a zero line)" f3_rc 2

echo "  M3 the doorman needs jq: the installer registers it only when jq is there, and says so"
F3IH="$F3/inst-nojq"; mkdir -p "$F3IH"; d2_yes "$F3IH" INSTALL_PRETEND_MISSING=jq
f3_chk refuse "M3 with jq missing the doorman is NOT registered (under either event)" bash -c "! grep -q 'doorman.sh' '$F3IH/.claude/settings.json'"
f3_chk pass "M3 pair: with jq missing the end-of-turn check is still registered" bash -c "grep -q 'stop-state-check.sh' '$F3IH/.claude/settings.json'"
F3IH2="$F3/inst-jq"; mkdir -p "$F3IH2"; d2_yes "$F3IH2"
f3_chk pass "M3 pair: with jq present the doorman is registered" bash -c "grep -q 'doorman.sh' '$F3IH2/.claude/settings.json'"
f3_chk refuse "M3 INSTALL.md states the doorman's jq requirement" grep -q 'The doorman needs `jq`' "$HOOKS_DIR/../INSTALL.md"

echo "  M4 the turn snapshot names its repo; a cd during the turn skips the check with a notice"
f3_repo() { local d="$1"; mkdir -p "$d/state"; git -C "$d" init -q -b main; git -C "$d" config core.hooksPath /dev/null
  printf '**Current task:** first\n**Next step:** second\n' > "$d/state/dev.md"; echo "$2" > "$d/README.md"; git -C "$d" add -A; "${ID[@]}" git -C "$d" commit -q -m "init $2"; }
R1="$F3/myapp-dev1"; R2="$F3/myapp-dev2"; f3_repo "$R1" one; f3_repo "$R2" two
S="$F3/s-m4a"; f3_door "$R1" m4a "$F3/tp100" "read only turn"
f3_chk refuse "M4 the snapshot records the repo top-level folder as its fifth field" bash -c "[ \"\$(head -1 '$S/turnsnap/m4a' | cut -f5)\" = \"\$(git -C '$R1' rev-parse --show-toplevel)\" ]"
f3_stop "$R2" m4a "$F3/tp100"
f3_chk refuse "M4 a read-only turn that cd'd into a sibling repo is not blocked" bash -c "! grep -q '\"decision\":\"block\"' '$F3/so'"
f3_chk refuse "M4 ... and leaves a notice that the check was skipped" bash -c "grep -qi 'skipped' '$S/notices/stop-state-check-cwd'"
S="$F3/s-m4b"; f3_door "$R1" m4b "$F3/tp100" "read only turn"; f3_stop "$R1" m4b "$F3/tp100"
f3_chk pass "M4 pair: the same read-only turn ending in its own repo passes with no notice" bash -c "! grep -q '\"decision\":\"block\"' '$F3/so' && [ ! -e '$S/notices/stop-state-check-cwd' ]"
S="$F3/s-m4c"; f3_door "$R1" m4c "$F3/tp100" "edit turn"; echo more >> "$R1/README.md"; f3_stop "$R1" m4c "$F3/tp100"
f3_chk refuse "M4 pair: an edit turn ending in its own repo, state file untouched, is still blocked" bash -c "grep -q '\"decision\":\"block\"' '$F3/so'"
S="$F3/s-m4d"; f3_door "$R1" m4d "$F3/tp100" "edit turn"; echo more >> "$R1/README.md"; f3_stop "$R2" m4d "$F3/tp100"
f3_chk pass "M4 an edit turn that ended in another repo is not judged on that other repo (skipped with a notice)" bash -c "! grep -q '\"decision\":\"block\"' '$F3/so' && [ -s '$S/notices/stop-state-check-cwd' ]"

echo "  M15 the refusal says plainly what to change"
S="$F3/s-m15"; f3_door "$R2" m15 "$F3/tp100" "one more open question"; echo more >> "$R2/README.md"; printf '\nOpen question: x\n' >> "$R2/state/dev.md"; f3_stop "$R2" m15 "$F3/tp100"
f3_chk refuse "M15 the block for an unmoved marker names the FIRST Current task / Next step line to change" bash -c "grep -q 'FIRST line that starts with' '$F3/so' && ! grep -q 'unrelated edit' '$F3/so'"

echo "  M6 the end-of-turn check's two stderr-only notes go through the notice folder"
S="$F3/s-m6a"; f3_stop "$D21" m6a "$F3/tp900"
f3_chk refuse "M6 the retirement note is left as a pending notice" bash -c "grep -q 'RETIRED' '$S/notices/stop-state-check-retired'"
f3_chk refuse "M6 the notice file is private (600) in a private folder (700)" bash -c "[ \"\$(atk_mode '$S/notices/stop-state-check-retired')\" = 600 ] && [ \"\$(atk_mode '$S/notices')\" = 700 ]"
S="$F3/s-m6b"; echo more >> "$R1/README.md"; f3_stop "$R1" m6b "$F3/tp100"
f3_chk refuse "M6 the no-turn-snapshot note is left as a pending notice naming the doorman" bash -c "grep -qi 'doorman' '$S/notices/stop-state-check-nosnap'"
git -C "$R1" checkout -q -- README.md 2>/dev/null

echo "  M7 the doorman's held-prompt files are private"
S="$F3/s-m7"; f3_door "$D21" m7a "$F3/tp900" "a private message"
f3_chk refuse "M7 held/<session> is 600 and its folder 700" bash -c "[ \"\$(atk_mode '$S/held/m7a')\" = 600 ] && [ \"\$(atk_mode '$S/held')\" = 700 ]"
f3_chk refuse "M7 the inbox file is 600 and its folder 700" bash -c "[ \"\$(atk_mode '$S/inbox/dev.md')\" = 600 ] && [ \"\$(atk_mode '$S/inbox')\" = 700 ]"
f3_door "$D21" m7a "$F3/tp900" "the passing message"
f3_chk refuse "M7 delivered/<session> is 600" bash -c "[ \"\$(atk_mode '$S/delivered/m7a')\" = 600 ]"

echo "  M11 the doorman reads the transcript once with a growing tail window"
python3 - "$F3/big" <<'PY'
import sys
line = b'{"type":"assistant","message":{"usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":2000,"output_tokens":5},"content":"' + b"x" * 400 + b'"}}\n'
with open(sys.argv[1], "wb") as f:
    blk = line * 2000
    for _ in range(100): f.write(blk)
    f.write(b'{"type":"assistant","message":{"usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":899000,"output_tokens":5}}}\n')
PY
S="$F3/s-m11a"; m11s=$(date +%s); f3_door "$D21" m11a "$F3/big" "typed words"; m11e=$(date +%s)
f3_chk refuse "M11 a 110 MB transcript at 900k is held (exit 2) in under 3 s (took $((m11e - m11s)) s)" bash -c "[ '$F3_RC' = 2 ] && [ $((m11e - m11s)) -lt 3 ]"
rm -f "$F3/big"
python3 - "$F3/wide" <<'PY'
import sys
usage = b'{"type":"assistant","message":{"usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":899000,"output_tokens":5}}}\n'
tool = b'{"type":"user","message":{"content":"' + b"y" * 1000 + b'"}}\n'
with open(sys.argv[1], "wb") as f:
    f.write(usage); f.write(tool * 12000)      # ~12 MB of tool results after the newest usage line
PY
S="$F3/s-m11b"; f3_door "$D21" m11b "$F3/wide" "typed words"
f3_chk pass "M11 pair: a newest usage line 12 MB from the end (past both windows) is still found and holds" f3_rc 2
rm -f "$F3/wide"
S="$F3/s-m11c"; f3_door "$D21" m11c "$F3/tp100" "typed words"
f3_chk pass "M11 pair: a small chat under the floor passes" f3_rc 0

echo "  M10 provenance: a change that lands between the pre and post hooks is not credited to this session"
M10C="$F3/prov"; mkdir -p "$M10C" "$F3/prov-state"; cp "$HOOKS_DIR/provenance.py" "$M10C/"; printf 'NOTES.md\n' > "$M10C/channel-ceiling.conf"
m10j() { python3 -c 'import json,sys;d=json.loads(sys.argv[5]);print(json.dumps({"tool_name":sys.argv[1],"tool_input":dict(d,file_path=sys.argv[2]),"cwd":sys.argv[3],"session_id":sys.argv[4]}))' "$@"; }
m10p() { printf '%s' "$2" | env PROVENANCE_STATE_DIR="$F3/prov-state" python3 "$M10C/provenance.py" "$1" >/dev/null; }
m10chk() { env PROVENANCE_STATE_DIR="$F3/prov-state" python3 "$M10C/provenance.py" check "$1" "$2" NOTES.md | head -1; }
m10_new() { local d="$F3/$1"; mkdir -p "$d"; git -C "$d" init -q -b main; git -C "$d" config core.hooksPath /dev/null; printf 'alpha\nbeta\n' > "$d/NOTES.md"; git -C "$d" add -A; "${ID[@]}" git -C "$d" commit -q -m init; printf '%s' "$d"; }
M10A="$(m10_new m10a)"; E1='{"old_string":"beta","new_string":"beta edited"}'
m10p pre "$(m10j Edit "$M10A/NOTES.md" "$M10A" m10sa "$E1")"
echo "a foreign append while the permission prompt waits" >> "$M10A/NOTES.md"
python3 -c 'import sys;p=sys.argv[1];s=open(p).read().replace("beta","beta edited",1);open(p,"w").write(s)' "$M10A/NOTES.md"
m10p post "$(m10j Edit "$M10A/NOTES.md" "$M10A" m10sa "$E1")"
f3_chk refuse "M10 an Edit whose result carries another session's append is not credited to this session" bash -c "[ \"$(m10chk "$M10A" m10sa)\" = REFUSE ]"
M10B="$(m10_new m10b)"
m10p pre "$(m10j Edit "$M10B/NOTES.md" "$M10B" m10sb "$E1")"
python3 -c 'import sys;p=sys.argv[1];s=open(p).read().replace("beta","beta edited",1);open(p,"w").write(s)' "$M10B/NOTES.md"
m10p post "$(m10j Edit "$M10B/NOTES.md" "$M10B" m10sb "$E1")"
f3_chk pass "M10 pair: the same Edit with nothing landing in between is credited (commit allowed)" bash -c "[ \"$(m10chk "$M10B" m10sb)\" = OK ]"
M10C2="$(m10_new m10c)"; E2='{"edits":[{"old_string":"alpha","new_string":"alpha 2"},{"old_string":"beta","new_string":"beta 2"}]}'
m10p pre "$(m10j MultiEdit "$M10C2/NOTES.md" "$M10C2" m10sc "$E2")"
printf 'alpha 2\nbeta 2\n' > "$M10C2/NOTES.md"
m10p post "$(m10j MultiEdit "$M10C2/NOTES.md" "$M10C2" m10sc "$E2")"
f3_chk pass "M10 pair: a clean MultiEdit is credited" bash -c "[ \"$(m10chk "$M10C2" m10sc)\" = OK ]"

echo "review fixes (critical)"
RFC="$T/rfc"; mkdir -p "$RFC"
# ---- 1: a stub /usr/bin/python3 (Mac without the Command Line Tools) must not refuse every commit ----
RFC_STUB="$RFC/stub"; mkdir -p "$RFC_STUB"; printf '#!/bin/sh\nexit 1\n' > "$RFC_STUB/python3"; chmod +x "$RFC_STUB/python3"
RFC_REALPY="$(command -v python3)"
RFC_H="$(rb_home rfc1)"; RB_WANT='.'
# the pre-commit hook itself (run directly: git-hooks/commit-msg, outside this fix, has the same stub gap)
rfc1_run() {   # <file content> -> exit code of pre-commit on one staged file, stub preferred python3
  local r; r="$(rb_new)"; printf '%s\n' "$1" > "$r/a.txt"; git -C "$r" add -A >/dev/null 2>&1
  ( cd "$r" && env HOME="$RFC_H" GUARD_PYTHON_PREFERRED="$RFC_STUB/python3" bash "$GIT_HOOKS_DIR/pre-commit" >/dev/null 2>&1 ); echo $?
}
if [ "$(rfc1_run 'honest')" = 0 ]; then ok; else bad "review fix 1: pre-commit with a stub preferred python3 and a working PATH python3 passes honest work"; fi
pass_n=$((pass_n+1))
if [ "$(rfc1_run 'met zebulonquixote')" = 1 ]; then ok; else bad "review fix 1 pair: the same setup still refuses a listed name (the PATH python judged it)"; fi
refuse_n=$((refuse_n+1))
# the same gap in commit-msg (a2): a stub preferred python3 must not refuse every commit message
rfc1m_run() { printf '%s\n' "$1" > "$RFC/msg1m.txt"; env HOME="$RFC_H" GUARD_PYTHON_PREFERRED="$RFC_STUB/python3" bash "$GIT_HOOKS_DIR/commit-msg" "$RFC/msg1m.txt" >/dev/null 2>&1; echo $?; }
if [ "$(rfc1m_run 'fix a typo in the readme')" = 0 ]; then ok; else bad "review fix 1 (commit-msg): a stub preferred python3 and a working PATH python3 pass an honest message"; fi
pass_n=$((pass_n+1))
if [ "$(rfc1m_run 'thanks zebulonquixote')" = 1 ]; then ok; else bad "review fix 1 pair (commit-msg): the same setup still refuses a listed name"; fi
refuse_n=$((refuse_n+1))
# the installer must not offer the machine-wide git hooks when no python3 runs at all (they would refuse every commit)
rfc_pty() { local h="$1" outp="$2"; shift 2; env HOME="$h" "$@" "$RFC_REALPY" - "$h" "$REPOD2/install.sh" "$outp" <<'PY'
import os,pty,sys,select,re
home,script,outp=sys.argv[1:4]
pid,fd=pty.fork()
if pid==0:
    os.environ["HOME"]=home
    os.execvp("bash",["bash",script])
buf=b""; answered=0
while True:
    r,_,_=select.select([fd],[],[],0.5)
    if r:
        try: d=os.read(fd,4096)
        except OSError: break
        if not d: break
        buf+=d
    elif len(buf)>answered:
        tail=buf[-400:].decode("utf8","ignore")
        if re.search(r"(\] |: |\? )$",tail):
            os.write(fd,b"y\n" if tail.rstrip().endswith("[y/N]") and "core.hooksPath" in tail else b"\n"); answered=len(buf)
open(outp,"wb").write(buf)
_,st=os.waitpid(pid,0); sys.exit(os.waitstatus_to_exitcode(st))
PY
}
RFC1A="$RFC/h1a"; mkdir -p "$RFC1A"
rfc_pty "$RFC1A" "$RFC/h1a.out" PATH="$RFC_STUB:$PATH" GUARD_PYTHON_PREFERRED=/nonexistent/python3 >/dev/null 2>&1
if [ -z "$(env HOME="$RFC1A" git config --global core.hooksPath 2>/dev/null)" ]; then ok; else bad "review fix 1: with no python3 that runs, the installer must NOT set the global git hooks path"; fi
refuse_n=$((refuse_n+1))
RFC1B="$RFC/h1b"; mkdir -p "$RFC1B"
rfc_pty "$RFC1B" "$RFC/h1b.out" >/dev/null 2>&1
if [ "$(env HOME="$RFC1B" git config --global core.hooksPath 2>/dev/null)" = "$RFC1B/.claude/git-hooks" ]; then ok; else bad "review fix 1 pair: with a working python3 the installer still sets the global git hooks path when asked"; fi
pass_n=$((pass_n+1))

# ---- 2: gate-guard with jq missing warns and passes; it never refuses on a word inside the text ----
RFC_NOJQ="$RFC/nojq"; mkdir -p "$RFC_NOJQ"
for b in bash cat grep dirname sed env tr cut date mkdir awk python3 touch; do p="$(command -v "$b" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$RFC_NOJQ/$b"; done
RFC2H="$RFC/h2"; mkdir -p "$RFC2H/.claude"
INPUT="$(json_bash 'cd ~/repos/committee-tests && ls')"
expect pass 0 "review fix 2: no jq, a folder name holding 'test' and 'commit' passes" env -i "PATH=$RFC_NOJQ" HOME="$RFC2H" bash "$HOOKS_DIR/gate-guard.sh"
err2="$(printf '%s' "$INPUT" | env -i "PATH=$RFC_NOJQ" HOME="$RFC2H" bash "$HOOKS_DIR/gate-guard.sh" 2>&1 1>/dev/null)"
err2b="$(printf '%s' "$INPUT" | env -i "PATH=$RFC_NOJQ" HOME="$RFC2H" bash "$HOOKS_DIR/gate-guard.sh" 2>&1 1>/dev/null)"
RFC2W="$RFC/h2w"; mkdir -p "$RFC2W/.claude"
err2w="$(printf '%s' "$INPUT" | env -i "PATH=$RFC_NOJQ" HOME="$RFC2W" bash "$HOOKS_DIR/gate-guard.sh" 2>&1 1>/dev/null)"
if printf '%s' "$err2w" | grep -q 'install jq'; then ok; else bad "review fix 2: the first no-jq pass must warn 'install jq' on stderr (got: '$err2w')"; fi
pass_n=$((pass_n+1))
if [ -z "$err2b" ]; then ok; else bad "review fix 2: the warning is given once, not on every command (got: '$err2b')"; fi
pass_n=$((pass_n+1))
INPUT="$(json_bash 'ls -la')"; expect pass 0 "review fix 2: no jq, an unrelated command passes" env -i "PATH=$RFC_NOJQ" HOME="$RFC2H" bash "$HOOKS_DIR/gate-guard.sh"
INPUT="$(json_bash 'npm test | tee out.log && git commit -m x')"; expect refuse 2 "review fix 2 pair: WITH jq a piped gate is still refused" bash "$HOOKS_DIR/gate-guard.sh"
INPUT='not json but says test and commit'; expect refuse 2 "review fix 2 pair: WITH jq, unparseable input carrying gate words still fails closed" bash "$HOOKS_DIR/gate-guard.sh"

# ---- 3: provenance refuses only when the multi-chat recorder is actually running this session ----
RFC3="$RFC/prov"; mkdir -p "$RFC3/state"; cp "$HOOKS_DIR/provenance.py" "$RFC3/"; printf 'NOTES.md\n' > "$RFC3/channel-ceiling.conf"
RFC3R="$RFC/provrepo"; mkdir -p "$RFC3R"; git -C "$RFC3R" init -q -b main; git -C "$RFC3R" config core.hooksPath /dev/null
printf 'a\n' > "$RFC3R/NOTES.md"; git -C "$RFC3R" add -A; "${ID[@]}" git -C "$RFC3R" commit -q -m init
printf 'my own edit made with no recorder installed\n' >> "$RFC3R/NOTES.md"
rfc3chk() { env PROVENANCE_STATE_DIR="$RFC3/state" python3 "$RFC3/provenance.py" check "$RFC3R" "$1" NOTES.md | head -1; }
if [ "$(rfc3chk never-recorded)" = OK ]; then ok; else bad "review fix 3: a session the recorder never saw (multi-chat group not installed) must not be refused on the person's own edit"; fi
pass_n=$((pass_n+1))
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"'"$RFC3R"'","session_id":"recorded"}' | env PROVENANCE_STATE_DIR="$RFC3/state" python3 "$RFC3/provenance.py" pre
if [ "$(rfc3chk recorded)" = REFUSE ]; then ok; else bad "review fix 3 pair: a session the recorder IS recording still refuses a change it did not make"; fi
refuse_n=$((refuse_n+1))

# ---- 4: the installer writes the projects folder as ~/..., not an expanded home path ----
RFC4="$RFC/h4"; mkdir -p "$RFC4"
env HOME="$RFC4" bash "$REPOD2/install.sh" --yes >/dev/null 2>&1
if [ -f "$RFC4/.claude/hooks/project-roots.conf" ] && ! grep -qF "$RFC4" "$RFC4/.claude/hooks/project-roots.conf"; then ok; else bad "review fix 4: project-roots.conf must not hold the expanded home path"; fi
refuse_n=$((refuse_n+1))
rfc4n() { printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$1" | env HOME="$RFC4" bash "$HOOKS_DIR/check-claude-md.sh" 2>/dev/null | grep -c 'has no CLAUDE.md yet'; }
mkdir -p "$RFC4/projects/newone"
if [ "$(rfc4n "$RFC4/projects/newone")" -ge 1 ]; then ok; else bad "review fix 4 pair: the ~/ line the installer writes must still switch the interview on"; fi
pass_n=$((pass_n+1))
printf '%s\n' "$RFC4/projects" > "$RFC4/.claude/hooks/project-roots.conf"
if [ "$(rfc4n "$RFC4/projects/newone")" -ge 1 ]; then ok; else bad "review fix 4 pair: an older, already-expanded value keeps working"; fi
pass_n=$((pass_n+1))

# ---- 5: a secret in settings.json leaves NO copy in the mirror folder ----
RFC5="$RFC/h5"; RFC5M="$RFC/m5"; mkdir -p "$RFC5/.claude/hooks" "$RFC5M"
git -C "$RFC5/.claude" init -q -b main; git -C "$RFC5/.claude" config core.hooksPath /dev/null; git -C "$RFC5/.claude" config user.name Tester; git -C "$RFC5/.claude" config user.email tester@example.com
git -C "$RFC5M" init -q -b main; git -C "$RFC5M" config core.hooksPath /dev/null; git -C "$RFC5M" config user.name Tester; git -C "$RFC5M" config user.email tester@example.com
printf 'AUTHOR=Tester <tester@example.com>\nMIRROR_DIR=%s\n' "$RFC5M" > "$RFC5/.claude/hooks/backup.conf"
echo hello > "$RFC5/.claude/CLAUDE.md"; echo '#!/bin/bash' > "$RFC5/.claude/hooks/check-claude-md.sh"; echo '#!/bin/bash' > "$RFC5/.claude/hooks/auto-backup.sh"
printf '{"env":{"key":"%s"}}' "sk-ant-""zzzzzzzzzz1234567890" > "$RFC5/.claude/settings.json"
git -C "$RFC5/.claude" add -A; git -C "$RFC5/.claude" commit -q -m seed
env HOME="$RFC5" STATE_CHECK_STATE_DIR="$RFC5/state" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
if [ -z "$(ls "$RFC5M" | grep -v '^\.git$')" ]; then ok; else bad "review fix 5: a secret in settings.json must leave NO copy in the mirror folder (found: $(ls "$RFC5M" | tr '\n' ' '))"; fi
refuse_n=$((refuse_n+1))
if [ -s "$RFC5/state/notices/auto-backup" ] && grep -qi 'secret' "$RFC5/state/notices/auto-backup"; then ok; else bad "review fix 5: the notice about the secret is still written"; fi
refuse_n=$((refuse_n+1))
printf '{"name":"clean"}' > "$RFC5/.claude/settings.json"; git -C "$RFC5/.claude" add -A; git -C "$RFC5/.claude" commit -q -m clean
env HOME="$RFC5" STATE_CHECK_STATE_DIR="$RFC5/state" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
if [ -f "$RFC5M/settings-copy.json" ]; then ok; else bad "review fix 5 pair: once the secret is gone the copy is made"; fi
pass_n=$((pass_n+1))

# ---- guard port 2026-10-10 (A): heavy-suite-guard memory check, one spelling, stop-by-name ----
echo "guard port 2026-10-10 (A)"
GPA="$T/gpa"; mkdir -p "$GPA/ok" "$GPA/ml" "$GPA/nolib"
cp "$HOOKS_DIR/heavy-suite-guard.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/override-ledger.sh" "$GPA/ok/"
GPAL="$GPA/ledger.tsv"
# a: run the guard on one command with load L and free memory M (either may be empty = real reading is NOT used: 2 / 100)
gpa() {   # <refuse|pass> <label> <command> [load] [free%] [guard-dir]
  local kind="$1" label="$2" c="$3" l="${4:-2}" m="${5:-100}" d="${6:-$GPA/ok}"
  INPUT="$(json_bash "$c")"
  if [ "$kind" = refuse ]; then expect refuse 2 "$label: $c" env OVERRIDE_LEDGER="$GPAL" HEAVY_SUITE_LOAD_OVERRIDE="$l" HEAVY_SUITE_MEM_OVERRIDE="$m" bash "$d/heavy-suite-guard.sh"
  else expect pass 0 "$label: $c" env OVERRIDE_LEDGER="$GPAL" HEAVY_SUITE_LOAD_OVERRIDE="$l" HEAVY_SUITE_MEM_OVERRIDE="$m" bash "$d/heavy-suite-guard.sh"; fi
}
# ---- P1: the memory check ----
gpa refuse "P1 npm test at 20% free must refuse (memory)" 'npm test' 2 20
gpa pass   "P1 pair: npm test at 50% free passes" 'npm test' 2 50
gpa refuse "P1 npx tsc --noEmit at 20% free must refuse" 'npx tsc --noEmit' 2 20
gpa pass   "P1 pair: npx tsc --version at 20% free is a query and passes" 'npx tsc --version' 2 20
gpa pass   "P1 pair: npx tsc --noEmit at 50% free passes" 'npx tsc --noEmit' 2 50
gpa pass   "P1 pair: tsc is not a load matter: load 50, 50% free passes" 'npx tsc --noEmit' 50 50
gpa refuse "P1 npm run typecheck at 20% free must refuse" 'npm run typecheck' 2 20
gpa refuse "P1 yarn typecheck at 20% free must refuse (one spelling)" 'yarn typecheck' 2 20
gpa refuse "P1 a single-file run is NOT exempt from memory (20% free)" 'npx vitest run a.test.ts' 2 20
gpa pass   "P1 pair: a single-file run at load 50 with 50% free passes (load exemption)" 'npx vitest run a.test.ts' 50 50
gpa refuse "P1 a -t run is NOT exempt from memory (20% free)" 'npm test -- -t "renders"' 2 20
gpa refuse "P1 query in one segment does not exempt the next: load 50" 'node --version && npm test' 50 100
gpa refuse "P1 query in one segment does not exempt the next: 20% free" 'node --version && npm test' 2 20
gpa pass   "P1 pair: the query alone passes" 'node --version' 50 20
gpa pass   "P1 pair: npm test --version is a query, exempt from both" 'npm test --version' 50 20
gpa pass   "P1 an unrelated command passes at 5% free" 'ls -la' 2 5
gpa pass   "P1 prose naming tsc passes at 5% free" 'echo "run npx tsc later" >> DEBT.md' 2 5
gpa refuse "P1 free memory exactly under MIN_FREE (34%) refuses" 'npm test' 2 34
gpa pass   "P1 pair: free memory exactly at MIN_FREE (35%) passes" 'npm test' 2 35
INPUT="$(json_bash 'npm test')"
expect pass 0 "P1 unreadable memory reading fails open" env HEAVY_SUITE_LOAD_OVERRIDE=2 HEAVY_SUITE_MEM_OVERRIDE=unreadable bash "$GPA/ok/heavy-suite-guard.sh"
GPA_NOMP="$GPA/nomp"; mkdir -p "$GPA_NOMP"; for b in bash cat grep dirname sed env tr cut awk jq python3 uptime sysctl tail head; do p="$(command -v "$b" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$GPA_NOMP/$b"; done
expect pass 0 "P1 no memory_pressure on the PATH fails open" env -u HEAVY_SUITE_MEM_OVERRIDE "PATH=$GPA_NOMP" HEAVY_SUITE_LOAD_OVERRIDE=2 bash "$GPA/ok/heavy-suite-guard.sh"
GPA_MP="$GPA/mp"; mkdir -p "$GPA_MP"; cp -P "$GPA_NOMP"/* "$GPA_MP/"
printf '#!/bin/bash\necho "System-wide memory free percentage: 10%%"\n' > "$GPA_MP/memory_pressure"; chmod +x "$GPA_MP/memory_pressure"
expect refuse 2 "P1 pair: a memory_pressure reporting 10% free is read and refuses" env -u HEAVY_SUITE_MEM_OVERRIDE "PATH=$GPA_MP" HEAVY_SUITE_LOAD_OVERRIDE=2 bash "$GPA/ok/heavy-suite-guard.sh"
cp "$HOOKS_DIR/heavy-suite-guard.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/override-ledger.sh" "$GPA/ml/"
printf "MIN_FREE=10\r\n" > "$GPA/ml/heavy-suite.conf"
gpa pass   "P1 conf MIN_FREE=10 (CRLF) lets 20% free pass" 'npm test' 2 20 "$GPA/ml"
gpa refuse "P1 pair: conf MIN_FREE=10 still refuses at 5% free" 'npm test' 2 5 "$GPA/ml"
printf "MEMPATTERN='(^|[;&| ])make +bigbuild([ ;&|]|\$)'\n" >> "$GPA/ml/heavy-suite.conf"
gpa refuse "P1 conf MEMPATTERN adds a runner: make bigbuild at 5% free refuses" 'make bigbuild' 2 5 "$GPA/ml"
gpa pass   "P1 pair: that runner at 50% free passes" 'make bigbuild' 2 50 "$GPA/ml"
gpa pass   "P1 pair: a conf MEMPATTERN replaces the default (tsc no longer memory-checked)" 'npx tsc --noEmit' 2 5 "$GPA/ml"
rm -f "$GPAL"; gpa pass "P1 SUITE_OK=1 waives the memory refusal" 'SUITE_OK=1 npm test' 2 5
if ledger_has "$GPAL" SUITE_OK; then ok; else bad "P1 the SUITE_OK waiver at low memory must be recorded"; fi; pass_n=$((pass_n+1))
# ---- P2: one canonical spelling ----
for c in 'npm t' 'npm run-script test' 'yarn test' 'pnpm vitest' 'npx -y vitest@latest run' 'timeout 600 npm test' 'caffeinate -i npm test' \
         'sudo -u x npm test' 'bash -lc "npm test"' 'eval "npm test"' 'find . -name x -exec npx vitest run \;' 'npm -w web test' \
         'pnpm exec vitest run' 'nice -n 5 npm test' 'FOO="a b" npm test' 'node node_modules/vitest/vitest.mjs run' '(npm test)' 'if true; then npm test; fi'; do
  gpa refuse "P2 load 50 must refuse" "$c" 50 100; done
for c in 'echo npm test' 'grep -n "npm test" README.md' 'git commit -m "npm test"' 'which vitest' 'rg vitest docs/' 'npm tst --help' 'echo bash -lc npm test'; do
  gpa pass "P2 pair, load 50 must allow" "$c" 50 100; done
gpa pass "P2 pair: an escaped pipe is literal text, not a second command" 'grep npm\|test notes.md' 50 100
rm -f "$GPAL"; gpa pass "P2 SUITE_OK=1 in front of a wrapped spelling waives it" 'SUITE_OK=1 timeout 600 npm test' 50 100
if ledger_has "$GPAL" SUITE_OK; then ok; else bad "P2 the waiver of a wrapped spelling must be recorded"; fi; pass_n=$((pass_n+1))
# ---- P3: stop-by-name ----
for c in 'pkill -f vite' 'killall node' 'killall5' 'skill -9 x' 'kill 0' 'kill -9 -1' 'kill -- -123' 'kill -9 -$PGID' 'kill "0"' \
         'kill $(pgrep node)' 'kill "$(lsof -ti :3000)"' 'kill `pgrep node`' 'pids=$(pgrep x); kill $pids' 'pgrep x | xargs kill' \
         'pgrep x | while read p; do kill $p; done' 'fuser -k 3000/tcp' 'npx kill-port 3000' 'launchctl kill TERM gui/1/x' \
         "find . -name '*.pid' -exec kill {} \;" 'bash -c "pkill x"' 'sudo pkill x' 'echo ok && pkill x' 'kill $(echo $(pgrep x))'; do
  gpa refuse "P3 stop-by-name must refuse" "$c" 2 100; done
for c in 'kill 12345' 'kill $PID' 'kill -0 $PID' 'kill %1' 'kill -l' 'kill -9 12345' 'kill $(cat run.pid)' 'kill $(head -n1 run.pid)' 'kill $(< run.pid)' \
         'kill $(jobs -p)' 'cat run.pid | xargs kill' 'pgrep -f vite' 'pkill --help' 'echo "never pkill"' 'git commit -m "no killall here"' \
         'grep -n pkill hooks/heavy-suite-guard.sh' 'echo "the hook refuses \`pkill\`"' 'pgrep x | wc -l'; do
  gpa pass "P3 pair, must allow" "$c" 2 100; done
gpa refuse "P3 comes before the load check: load 2, nothing heavy, still refused" 'pkill x' 2 100
rm -f "$GPAL"; gpa pass "P3 KILL_OK=1 at the segment start waives it" 'KILL_OK=1 pkill x' 2 100
if ledger_has "$GPAL" KILL_OK; then ok; else bad "P3 the KILL_OK waiver must be recorded in the ledger"; fi; pass_n=$((pass_n+1))
gpa refuse "P3 KILL_OK=1 on another segment does not waive this one" 'KILL_OK=1 true && pkill x' 2 100
GPA_BADL="$GPA/badledger"; mkdir -p "$GPA_BADL"; : > "$GPA_BADL/blocker"
INPUT="$(json_bash 'KILL_OK=1 pkill x')"
expect refuse 2 "P3 an unrecordable KILL_OK override is refused" env OVERRIDE_LEDGER="$GPA_BADL/blocker/overrides.tsv" bash "$GPA/ok/heavy-suite-guard.sh"
INPUT="$(json_bash 'pkill x')"
msg="$(printf '%s' "$INPUT" | bash "$GPA/ok/heavy-suite-guard.sh" 2>&1 >/dev/null)"
if printf '%s' "$msg" | grep -q 'kill <PID>' && printf '%s' "$msg" | grep -qi 'Claude app'; then ok; else bad "P3 the refusal must say it can stop the Claude app and name kill <PID> (got: $msg)"; fi; refuse_n=$((refuse_n+1))

# ---- guard port 2026-10-10 (B): piped push/rebase, encoded home path, worktree exception, issue number, replace objects ----
echo "guard port 2026-10-10 (B)"
GPB="$T/gpb"; mkdir -p "$GPB"
GPBL="$GPB/ledger.tsv"
gpb() {   # <refuse|pass> <label> <command>: gate-guard on one command
  local kind="$1" label="$2" c="$3"
  INPUT="$(json_bash "$c")"
  if [ "$kind" = refuse ]; then expect refuse 2 "$label: $c" env OVERRIDE_LEDGER="$GPBL" bash "$HOOKS_DIR/gate-guard.sh"
  else expect pass 0 "$label: $c" env OVERRIDE_LEDGER="$GPBL" bash "$HOOKS_DIR/gate-guard.sh"; fi
}
# ---- P4: a push or rebase piped into a reader ----
for c in 'git push | tail -3' 'git push 2>&1 | grep -v x' 'git -C repo push |& cat' 'git rebase main | head' 'git pull --rebase | tail' \
         'VAR="a b" git push | tail' 'if true; then git push | tail; fi' $'git push \\\n| tail' $'git push \\\n  origin main \\\n  | tail' 'git --no-pager push | tail' \
         'git -c k=v push origin main | tee push.log' 'cd x && git push | tee l' $'echo hi\ngit push | tail' 'git push origin main | wc -l' \
         'git rebase -i main | head' 'git pull --rebase origin main |& tail' 'GATE_OK=1 true && git push | tail' ; do
  gpb refuse "P4 piped push/rebase must refuse" "$c"; done
for c in 'git push' 'git push || echo failed' 'git push --dry-run | tail' 'git push -n | tail' 'set -o pipefail; git push | tail' 'git push | tail; echo ${PIPESTATUS[0]}' \
         'git log | head' 'echo "git push | tail"' 'git pull | tail' 'git pull --rebase=false | tail' 'git push > out.log 2>&1' \
         'git status | head' 'git commit -m "x" | tail' 'git rebase --abort' 'git push && git log | head' 'git diff | git apply' 'echo git push | tail'; do
  gpb pass "P4 pair: must allow" "$c"; done
gpb pass "P4 pair: pipefail set on an earlier line" $'set -eo pipefail\ngit push | tail'
rm -f "$GPBL"; gpb pass "P4 GATE_OK=1 at the segment start waives it" 'GATE_OK=1 git push | tail'
if ledger_has "$GPBL" GATE_OK; then ok; else bad "P4 the GATE_OK waiver of a piped push must be recorded in the ledger"; fi; pass_n=$((pass_n+1))
GPB_BADL="$GPB/badledger"; mkdir -p "$GPB_BADL"; : > "$GPB_BADL/blocker"
INPUT="$(json_bash 'GATE_OK=1 git push | tail')"
expect refuse 2 "P4 an unrecordable GATE_OK override is refused" env OVERRIDE_LEDGER="$GPB_BADL/blocker/overrides.tsv" bash "$HOOKS_DIR/gate-guard.sh"
INPUT="$(json_bash 'git push | tail')"
msg="$(printf '%s' "$INPUT" | bash "$HOOKS_DIR/gate-guard.sh" 2>&1 >/dev/null)"
if printf '%s' "$msg" | grep -q 'hides its exit code' && printf '%s' "$msg" | grep -q 'GATE_OK=1'; then ok; else bad "P4 the refusal must say the pipe hides the exit code and name GATE_OK=1 (got: $msg)"; fi; refuse_n=$((refuse_n+1))

# ---- P8: the encoded home-path form ----
UP="/User""s"; EU="-User""s-"; EH="-hom""e-"
RB_WANT='home path'
rb_case refuse "P8 an encoded home path after a slash" "$RBH" a.txt "see /x/${EU}alice/y"
rb_case refuse "P8 the encoded form at the start of a line" "$RBH" a.txt "${EU}alice-proj-notes"
rb_case refuse "P8 the Linux encoded form" "$RBH" a.txt "${EH}alice-proj"
rb_case refuse "P8 an encoded form in a staged FILE NAME" "$RBH" "proj/${EU}alice-proj/n.md" "harmless body"
rb_case refuse "P8 the slashed form still refuses" "$RBH" a.txt "see ${UP}/alice/x"
rb_case pass "P8 pair: a placeholder account passes" "$RBH" a.txt "${EU}<account>-proj"
rb_case pass "P8 pair: a word that only ENDS in the form passes" "$RBH" a.txt "see${EU}guide and more"
rb_case pass "P8 pair: an excluded name passes (encoded runner)" "$RBH" a.txt "${EU}runner-work"
rb_case pass "P8 pair: an excluded name passes (encoded Linux you)" "$RBH" a.txt "${EH}you-proj"
rb_case pass "P8 pair: the slashed excluded name still passes" "$RBH" a.txt "${UP}/runner/work"
rb_case pass "P8 pair: the form in a file name with a letter before it passes" "$RBH" "proj/my${EU}alice/n.md" "harmless body"
rb_case pass "P8 pair: a bare dash-Users-dash with no name passes" "$RBH" a.txt "${EU} and ${EH}"
RB_WANT='.'

# ---- P9: a worktree of a listed repo counts as the listed repo (names limb only) ----
H9="$(rb_home wt9)"; M9="$(rb_new)"; M9R="$(cd "$M9" && pwd -P)"
env HOME="$H9" "${ID[@]}" git -C "$M9" commit -q --no-verify --allow-empty -m seed >/dev/null 2>&1
git -C "$M9" worktree add -q "$RB/wt9" -b wt9 >/dev/null 2>&1
printf '# listed\n%s\n' "$M9R" > "$H9/.claude/.privacy-name-exceptions.local"
printf 'the guard refuses zebulonquixote\n' > "$RB/wt9/n.txt"
rb_run pass "P9 a listed name in a worktree of a LISTED repo passes" "$RB/wt9" "$H9"
printf 'see %s/alice/x\n' "$UP" > "$RB/wt9/p.txt"; RB_WANT='home path'
rb_run refuse "P9 a home path still binds in a worktree of a listed repo" "$RB/wt9" "$H9"; git -C "$RB/wt9" reset -q; rm "$RB/wt9/p.txt"; RB_WANT='.'
M9B="$(rb_new)"; env HOME="$H9" "${ID[@]}" git -C "$M9B" commit -q --no-verify --allow-empty -m seed >/dev/null 2>&1
git -C "$M9B" worktree add -q "$RB/wt9b" -b wt9b >/dev/null 2>&1
printf 'the guard refuses zebulonquixote\n' > "$RB/wt9b/n.txt"; RB_WANT='name'
rb_run refuse "P9 pair: the same name in a worktree of an UNLISTED repo refuses" "$RB/wt9b" "$H9"; RB_WANT='.'

# ---- P10: the issue number on a push to main (opt-in by hooks/issue-number.conf) ----
P10="$T/p10"; mkdir -p "$P10"; P10L="$P10/ledger.tsv"
p10_home() {   # name [conf lines...] -> a HOME with the ledger script and, when given, the conf
  local h="$P10/home-$1"; shift; mkdir -p "$h/.claude/hooks"; cp "$HOOKS_DIR/override-ledger.sh" "$h/.claude/hooks/"
  if [ "$#" -gt 0 ]; then printf '%s\n' "$@" > "$h/.claude/hooks/issue-number.conf"; fi
  printf '%s' "$h"
}
P10H="$(p10_home on '# the repos that need an issue number' 'o/r')"
p10_repo() {   # name [owner/name of the origin URL, default o/r]: a repo whose remote main already holds a seed commit
  local n="$1" on="${2:-o/r}" r="$P10/$1" b
  b="$P10/srv-$n/$on.git"; mkdir -p "$r" "${b%/*}"; git init -q --bare "$b"
  git -C "$r" init -q -b main; git -C "$r" config core.hooksPath "$GIT_HOOKS_DIR"; git -C "$r" remote add origin "$b"
  echo seed > "$r/seed.txt"; git -C "$r" add -A; "${ID[@]}" git -C "$r" commit -q -m seed
  git -C "$r" push -q --no-verify origin main >/dev/null 2>&1
  printf '%s' "$r"
}
p10_commit() {   # repo path message
  mkdir -p "$(dirname "$1/$2")"; echo "$RANDOM$RANDOM" >> "$1/$2"; git -C "$1" add -A; "${ID[@]}" git -C "$1" commit -q -m "$3"
}
p10_push() {   # <refuse|pass> <label> <repo> <want-regex> [refspec [env...]]
  local kind="$1" label="$2" r="$3" want="$4" spec="${5:-main}"; shift $(( $# < 5 ? $# : 5 ))
  local err rc; err="$(env HOME="${P10_HOME:-$P10H}" OVERRIDE_LEDGER="$P10L" "$@" git -C "$r" push origin "$spec" 2>&1 >/dev/null)"; rc=$?
  if [ "$kind" = refuse ]; then
    if [ "$rc" != 0 ] && printf '%s' "$err" | grep -q 'REFUSED' && printf '%s' "$err" | grep -qE "$want"; then ok; else bad "$label (must refuse for '$want'; rc=$rc err='$err')"; fi
    refuse_n=$((refuse_n+1))
  else
    if [ "$rc" = 0 ]; then ok; else bad "$label (must pass; rc=$rc err='$err')"; fi
    pass_n=$((pass_n+1))
  fi
}
r="$(p10_repo c1)"; p10_commit "$r" src/app.txt "feat: no number"; p10_push refuse "P10 a code commit without #N must refuse" "$r" 'issue number'
r="$(p10_repo c2)"; p10_commit "$r" docs/x.md "docs: a note"; p10_push pass "P10 pair: docs/x.md only passes" "$r" .
r="$(p10_repo c3)"; p10_commit "$r" README.md "docs: readme"; p10_push pass "P10 pair: README.md only passes" "$r" .
r="$(p10_repo c4)"; p10_commit "$r" CLAUDE.md "rules"; p10_push refuse "P10 CLAUDE.md without #N must refuse" "$r" 'issue number'
r="$(p10_repo c4b)"; p10_commit "$r" claude.md "rules"; p10_push refuse "P10 claude.md (lower case) without #N must refuse" "$r" 'issue number'
r="$(p10_repo c4c)"; p10_commit "$r" Notes.MD "notes"; p10_push pass "P10 pair: a root Notes.MD (any case) passes" "$r" .
r="$(p10_repo c4d)"; p10_commit "$r" sub/notes.md "notes"; p10_push refuse "P10 a .md below the root is not a record" "$r" 'issue number'
r="$(p10_repo c5)"; p10_commit "$r" src/app.txt "fix: the thing, fixes #12"; p10_push pass "P10 pair: 'fixes #12' passes" "$r" .
r="$(p10_repo c5b)"; p10_commit "$r" src/app.txt "#7 first words"; p10_push pass "P10 pair: a message starting with #7 passes" "$r" .
r="$(p10_repo c5c)"; p10_commit "$r" src/app.txt "fix: x (#31)"; p10_push pass "P10 pair: (#31) passes" "$r" .
n=0; for m in "fix: C#12" "fix: x#3" 'fix: &#38; entity' "fix: ##3" "fix: #0" "fix: #01a" "fix: a_#4"; do
  n=$((n+1)); r="$(p10_repo cm$n)"; p10_commit "$r" src/app.txt "$m"; p10_push refuse "P10 '$m' does not count as an issue" "$r" 'issue number'
done
r="$(p10_repo d1)"; p10_commit "$r" src/app.txt "feat: no number"; p10_push pass "P10 pair: a push to another branch is not judged" "$r" . main:refs/heads/topic
r="$(p10_repo d2 o/other)"; p10_commit "$r" src/app.txt "feat: no number"; p10_push pass "P10 pair: another repo as the target is not judged" "$r" .
P10_HOME="$(p10_home off)"; r="$(p10_repo d3)"; p10_commit "$r" src/app.txt "feat: no number"; p10_push pass "P10 pair: no conf file, the check never runs" "$r" .
P10_HOME="$(p10_home off2 '# only a comment' '' 'x/y')"; r="$(p10_repo d4)"; p10_commit "$r" src/app.txt "feat: no number"; p10_push pass "P10 pair: a conf without this repo, the check never runs" "$r" .
P10_HOME="$(p10_home crlf $'# c\r' $'O/R\r')"; r="$(p10_repo d5)"; p10_commit "$r" src/app.txt "feat: no number"; p10_push refuse "P10 a conf with CRLF and capitals still binds" "$r" 'issue number'
unset P10_HOME
r="$(p10_repo e1)"; p10_commit "$r" src/app.txt "feat: no number"; rm -f "$P10L"; p10_push pass "P10 ISSUE_OK=1 passes" "$r" . main ISSUE_OK=1
if ledger_has "$P10L" ISSUE_OK; then ok; else bad "P10 the ISSUE_OK waiver must be recorded in the ledger"; fi; pass_n=$((pass_n+1))
r="$(p10_repo e2)"; p10_commit "$r" src/app.txt "feat: no number"; mkdir -p "$P10/badl"; : > "$P10/badl/blocker"
err="$(env HOME="$P10H" OVERRIDE_LEDGER="$P10/badl/blocker/o.tsv" ISSUE_OK=1 git -C "$r" push origin main 2>&1 >/dev/null)"; rc=$?
if [ "$rc" != 0 ] && printf '%s' "$err" | grep -q 'could not be recorded'; then ok; else bad "P10 an unwritable ledger must refuse the ISSUE_OK override (rc=$rc err=$err)"; fi; refuse_n=$((refuse_n+1))
# first push into an empty remote: the root commit is judged (--root)
r="$P10/f1"; b="$P10/srv-f1/o/r.git"; mkdir -p "$r" "${b%/*}"; git init -q --bare "$b"; git -C "$r" init -q -b main; git -C "$r" config core.hooksPath "$GIT_HOOKS_DIR"; git -C "$r" remote add origin "$b"
echo code > "$r/main.txt"; git -C "$r" add -A; "${ID[@]}" git -C "$r" commit -q -m "first"
p10_push refuse "P10 the root commit of a first push is judged (--root)" "$r" 'issue number'
# the hook run by hand: stdin is the ref line, $1 the remote, $2 the target
p10_hook() {   # <refuse|pass> <label> <repo> <want-regex> <stdin-line> <remote-arg> <url-arg>
  local kind="$1" label="$2" r="$3" want="$4" line="$5" a1="$6" a2="$7"
  local err rc; err="$(cd "$r" && printf '%s\n' "$line" | env HOME="${P10_HOME:-$P10H}" OVERRIDE_LEDGER="$P10L" bash "$GIT_HOOKS_DIR/pre-push" "$a1" "$a2" 2>&1 >/dev/null)"; rc=$?
  if [ "$kind" = refuse ]; then
    if [ "$rc" != 0 ] && printf '%s' "$err" | grep -q 'REFUSED' && printf '%s' "$err" | grep -qE "$want"; then ok; else bad "$label (must refuse for '$want'; rc=$rc err='$err')"; fi
    refuse_n=$((refuse_n+1))
  else
    if [ "$rc" = 0 ]; then ok; else bad "$label (must pass; rc=$rc err='$err')"; fi
    pass_n=$((pass_n+1))
  fi
}
r="$(p10_repo g1)"; p10_commit "$r" src/app.txt "feat: no number"; tip="$(git -C "$r" rev-parse main)"; seedsha="$(git -C "$r" rev-parse main~1)"
ZERO40="$(printf '0%.0s' {1..40})"; BOGUS40="$(printf 'a%.0s' {1..40})"
p10_hook refuse "P10 a target spelled in capitals, with a trailing slash and .GIT, is normalised" "$r" 'issue number' "refs/heads/main $tip refs/heads/main $seedsha" origin 'https://example.test/O/R.GIT/'
p10_hook refuse "P10 an scp-style target is read by its last two parts" "$r" 'issue number' "refs/heads/main $tip refs/heads/main $seedsha" origin 'git@example.test:o/r.git'
p10_hook pass "P10 pair: a target one level off (o/r-extra) is not this repo" "$r" . "refs/heads/main $tip refs/heads/main $seedsha" origin 'https://example.test/o/r-extra.git'
git -C "$r" config remote.fake.url 'https://example.test/x/unlisted.git'; git -C "$r" config remote.fake.pushurl 'https://example.test/o/r.git'
p10_hook refuse "P10 a remote NAME is read as its pushurl (listed) even when its url is not" "$r" 'issue number' "refs/heads/main $tip refs/heads/main $seedsha" fake fake
git -C "$r" config remote.fake2.url 'https://example.test/o/r.git'; git -C "$r" config remote.fake2.pushurl 'https://example.test/x/unlisted.git'
p10_hook pass "P10 pair: a remote NAME whose pushurl is unlisted passes though its url is listed" "$r" . "refs/heads/main $tip refs/heads/main $seedsha" fake2 fake2
p10_hook refuse "P10 remote main unknown to this copy refuses, saying fetch first" "$r" 'fetch first' "refs/heads/main $tip refs/heads/main $BOGUS40" origin 'https://example.test/o/r.git'
p10_hook refuse "P10 a commit range git cannot list refuses (fail closed)" "$r" 'could not be listed' "refs/heads/main $BOGUS40 refs/heads/main $seedsha" origin 'https://example.test/o/r.git'
p10_hook pass "P10 pair: deleting main pushes nothing to judge" "$r" . "(delete) $ZERO40 refs/heads/main $seedsha" origin 'https://example.test/o/r.git'
p10_hook pass "P10 pair: remote main unknown but the target is unlisted passes" "$r" . "refs/heads/main $tip refs/heads/main $BOGUS40" origin 'https://example.test/x/unlisted.git'
# a commit whose tree object is gone: rev-list lists it, diff-tree cannot read it
r="$(p10_repo g2)"; p10_commit "$r" src/app.txt "feat: no number"; tip="$(git -C "$r" rev-parse main)"; seedsha="$(git -C "$r" rev-parse main~1)"
tr_sha="$(git -C "$r" rev-parse "main^{tree}")"; rm -f "$r/.git/objects/${tr_sha:0:2}/${tr_sha:2}"
p10_hook refuse "P10 a commit whose paths cannot be read refuses (diff-tree failure, pipefail)" "$r" 'could not be read' "refs/heads/main $tip refs/heads/main $seedsha" origin 'https://example.test/o/r.git'

# ---- P11: a git replace stand-in fools no check of the push ----
r="$(p10_repo h1)"; p10_commit "$r" src/app.txt "feat: no number"
codec="$(git -C "$r" rev-parse main)"; parent="$(git -C "$r" rev-parse main~1)"
blob="$(echo doc | git -C "$r" hash-object -w --stdin)"
standin_tree="$(cd "$r" && export GIT_INDEX_FILE="$r/.git/standin-index" && git read-tree "$parent" && git update-index --add --cacheinfo "100644,$blob,docs/n.md" && git write-tree)"
standin="$("${ID[@]}" git -C "$r" commit-tree -p "$parent" -m "docs only" "$standin_tree")"
git -C "$r" replace "$codec" "$standin" >/dev/null 2>&1
p10_push refuse "P11 a docs-only stand-in (git replace) does not fool the issue-number check" "$r" 'issue number'
AN_B="$(printf '%s%s' anthro pic).com"
r="$(p10_repo h2)"; echo z > "$r/z.txt"; git -C "$r" add -A
env GIT_AUTHOR_NAME=Claude GIT_AUTHOR_EMAIL="noreply@$AN_B" GIT_COMMITTER_NAME=Claude GIT_COMMITTER_EMAIL="noreply@$AN_B" git -C "$r" commit -q --no-verify -m "foreign #1"
foreign="$(git -C "$r" rev-parse main)"
own="$("${ID[@]}" git -C "$r" commit-tree -p "$(git -C "$r" rev-parse main~1)" -m "own #1" "$(git -C "$r" rev-parse "main^{tree}")")"
git -C "$r" replace "$foreign" "$own" >/dev/null 2>&1
P10_HOME="$(p10_home none)"; p10_push refuse "P11 an own-identity stand-in (git replace) does not fool the identity check" "$r" 'Claude/Anthropic'; unset P10_HOME

# ---- guard port 2026-10-10 (C1): shared-folder chats, snapshot after a move, exact tokens, inbox line ----
echo "guard port 2026-10-10 (C1)"
G1="$T/g1"; GH="$G1/hk"; mkdir -p "$GH"
cp "$HOOKS_DIR/stop-state-check.sh" "$HOOKS_DIR/doorman.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/clock-in-context.sh" "$GH/"
# the conf names only the seat folders "g1seat*"; the shared-folder repos below are named so that no row matches them
g1_conf() { { printf 'STATE_FILE state/{role}.md\n'; local l; for l in "$@"; do printf '%s\n' "$l"; done; } > "$GH/state-check.conf"; }
g1_conf 'g1seat*  dev  850'
g1_stop() { c2_sj "$@" | STATE_CHECK_STATE_DIR="$S" bash "$GH/stop-state-check.sh" > "$G1/out" 2> "$G1/err"; }
g1_prompt() {   # <cwd> <sid> [transcript] [prompt]
  dj "$1" "$2" "${4:-hello}" "${3:-}" | STATE_CHECK_STATE_DIR="$S" bash "$GH/doorman.sh" > "$G1/pout" 2> "$G1/perr"; G1_RC=$?
}
g1_shared() {   # <dir> [tsv text]: a repo of chats that share one folder; notes/reviewer.md and notes/builder.md are the state files
  local d="$1" tsv="${2-reviewer	notes/reviewer.md}"
  mkdir -p "$d/notes" "$d/.claude"; git -C "$d" init -q -b main; git -C "$d" config core.hooksPath /dev/null
  echo "reviewer notes" > "$d/notes/reviewer.md"; echo "builder notes" > "$d/notes/builder.md"; echo seed > "$d/README.md"
  [ -n "$tsv" ] && printf '# roles\n\n%s\nbuilder\tnotes/builder.md\n' "$tsv" > "$d/.claude/state-roles.tsv"
  git -C "$d" add -A; "${ID[@]}" git -C "$d" commit -q -m init
}
g1_tr() {   # <file> <title|-> <first-user-text> <edit|none>: a chat transcript
  local f="$1"; : > "$f"
  [ "$2" != - ] && printf '{"type":"custom-title","customTitle":"%s","sessionId":"x"}\n' "$2" >> "$f"
  printf '{"type":"user","message":{"role":"user","content":"%s"}}\n' "$3" >> "$f"
  [ "$4" = edit ] && printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Edit","input":{}}]}}\n' >> "$f"
  return 0
}
g1_blocked() { grep -q '"decision":"block"' "$G1/out"; }
g1_quiet() { [ ! -s "$G1/out" ]; }

echo "  P5 shared-folder chats: .claude/state-roles.tsv, the role from the title or first message"
S="$G1/s5"; R="$G1/shared1"; g1_shared "$R"; g1_tr "$G1/t5a" Reviewer "go" edit
g1_prompt "$R" p5a "$G1/t5a"; echo more >> "$R/README.md"; g1_stop "$R" p5a false "$G1/t5a"
c2_chk refuse "P5 a mapped chat's turn (own Edit, tracked change) with the state file unchanged blocks, naming the file" bash -c "grep -q '\"decision\":\"block\"' '$G1/out' && grep -q 'notes/reviewer.md did not change' '$G1/out' && grep -q 'Heartbeat' '$G1/out'"
c2_chk refuse "P5 the prompt hook wrote the turn snapshot for the mapped chat" test -s "$S/turnsnap/p5a"
g1_stop "$R" p5a true "$G1/t5a"
c2_chk pass "P5 pair: stop_hook_active true: the second stop passes" g1_quiet
git -C "$R" checkout -q -- .
g1_prompt "$R" p5b "$G1/t5a"; echo more >> "$R/README.md"; echo "now at step 2" >> "$R/notes/reviewer.md"; git -C "$R" add -A; "${ID[@]}" git -C "$R" commit -q -m "work and notes"
g1_stop "$R" p5b false "$G1/t5a"
c2_chk pass "P5 pair: the state file changed and committed: passes" g1_quiet
git -C "$R" tag -f base5 >/dev/null 2>&1
g1_tr "$G1/t5c" Reviewer "go" none
g1_prompt "$R" p5c "$G1/t5c"; echo other >> "$R/README.md"; g1_stop "$R" p5c false "$G1/t5c"
c2_chk pass "P5 pair: a change made by ANOTHER chat (no write tool in this transcript) never blocks" g1_quiet
git -C "$R" checkout -q -- .
g1_prompt "$R" p5d "$G1/t5a"; echo more >> "$R/README.md"; echo "unsaved note" >> "$R/notes/reviewer.md"; g1_stop "$R" p5d false "$G1/t5a"
c2_chk refuse "P5 a state file left uncommitted is asked to be committed by path" bash -c "grep -q 'commit it by path (git commit -- notes/reviewer.md)' '$G1/out' && ! grep -q 'did not change' '$G1/out'"
g1_stop "$R" p5d true "$G1/t5a"
c2_chk pass "P5 pair: the uncommitted-file ask also blocks once only" g1_quiet
git -C "$R" checkout -q -- .
g1_tr "$G1/t5e" - "You are the reviewer chat, check the diff" edit
g1_prompt "$R" p5e "$G1/t5e"; echo more >> "$R/README.md"; g1_stop "$R" p5e false "$G1/t5e"
c2_chk refuse "P5 no title: the first user message holding the pattern maps the chat" g1_blocked
git -C "$R" checkout -q -- .
g1_tr "$G1/t5f" - "hello there" edit
g1_prompt "$R" p5f "$G1/t5f"; echo more >> "$R/README.md"; g1_stop "$R" p5f false "$G1/t5f"
c2_chk pass "P5 pair: no title and a first message without any pattern: not mapped, passes" g1_quiet
git -C "$R" checkout -q -- .
g1_tr "$G1/t5g" "the REVIEWER of the week" "go" edit
g1_prompt "$R" p5g "$G1/t5g"; echo more >> "$R/README.md"; g1_stop "$R" p5g false "$G1/t5g"
c2_chk refuse "P5 the pattern is matched case-insensitively inside the title" g1_blocked
git -C "$R" checkout -q -- .
g1_tr "$G1/t5h" Builder "go" edit
g1_prompt "$R" p5h "$G1/t5h"; echo more >> "$R/README.md"; g1_stop "$R" p5h false "$G1/t5h"
c2_chk refuse "P5 a second tsv line maps another chat to its own state file" bash -c "grep -q 'notes/builder.md did not change' '$G1/out'"
git -C "$R" checkout -q -- .
for bad_path in '../x.md' '/etc/x.md'; do
  R2="$G1/shared-bad"; rm -rf "$R2"; g1_shared "$R2" "reviewer	$bad_path"
  g1_prompt "$R2" p5i "$G1/t5a"; echo more >> "$R2/README.md"; g1_stop "$R2" p5i false "$G1/t5a"
  c2_chk pass "P5 a tsv path '$bad_path' is ignored: passes (and no snapshot is written)" bash -c "[ ! -s '$G1/out' ] && [ ! -e '$S/turnsnap/p5i' ]"; rm -f "$S/turnsnap/p5i"
done
R2="$G1/shared-notsv"; g1_shared "$R2" ""
g1_prompt "$R2" p5j "$G1/t5a"; echo more >> "$R2/README.md"; g1_stop "$R2" p5j false "$G1/t5a"
c2_chk pass "P5 pair: a repo with no state-roles.tsv is inert" bash -c "[ ! -s '$G1/out' ] && [ ! -e '$S/turnsnap/p5j' ]"
g1_noconf() { mv "$GH/state-check.conf" "$GH/conf.off"; g1_prompt "$R" p5k "$G1/t5a"; mv "$GH/conf.off" "$GH/state-check.conf"; }
g1_noconf
c2_chk refuse "P5 with no state-check.conf at all a committed mapping still opts the chat in (snapshot written)" test -s "$S/turnsnap/p5k"
git -C "$R" checkout -q -- .
# a folder the conf DOES name keeps the conf's rules even when the repo also carries a mapping
RC="$G1/g1seat1"; c2_repo "$RC"; mkdir -p "$RC/.claude"; printf 'reviewer\tnotes/reviewer.md\n' > "$RC/.claude/state-roles.tsv"; git -C "$RC" add -A; "${ID[@]}" git -C "$RC" commit -q -m map
g1_prompt "$RC" p5l "$G1/t5a"; echo more >> "$RC/README.md"; g1_stop "$RC" p5l false "$G1/t5a"
c2_chk pass "P5 pair: a conf-matched folder is judged by the conf (its own state/dev.md), not by the mapping" bash -c "grep -q 'state/dev.md did not change' '$G1/out'"
# a mapped chat is never retired, held or wrapped up
g1_conf 'g1seat*  dev  5' 'WRAPUP_ROLES *' 'WRAPUP_K 5'
c2_tp "$G1/tp9" 900; cat "$G1/t5a" >> "$G1/tp9"
g1_prompt "$R" p5m "$G1/tp9" "please carry on"
c2_chk refuse "P5 a mapped chat at 900k is not held (rc 0, nothing on stdout)" bash -c "[ '$G1_RC' = 0 ] && [ ! -s '$G1/pout' ] && [ ! -e '$S/held/p5m' ]"
g1_stop "$R" p5m false "$G1/tp9"
c2_chk pass "P5 a mapped chat at 900k is not retired and not wrapped up" bash -c "[ ! -e '$S/retired/p5m' ] && [ ! -e '$S/wrapup-fired/p5m' ] && [ ! -s '$G1/out' ]"
g1_conf 'g1seat*  dev  850'
g1_stop "$R" "" false "$G1/t5a"
c2_chk pass "P5 pair: a Stop with no session id is not judged for a mapped chat" g1_quiet

echo "  P6 a machine prompt rewrites the turn snapshot only after a move to another repo"
S="$G1/s6"; g1_conf 'g1seat*  dev  850'; RA="$G1/g1seat2"; RB="$G1/g1seat3"; c2_repo "$RA"; c2_repo "$RB"
MP='<task-notification>helper finished</task-notification>'
g1_prompt "$RA" m6 "" "$MP"
c2_chk refuse "P6 a machine prompt with no snapshot yet writes one" bash -c "[ \"\$(cut -f5 '$S/turnsnap/m6')\" = '$(git -C "$RA" rev-parse --show-toplevel)' ]"
echo edit >> "$RA/README.md"; before6="$(cat "$S/turnsnap/m6")"
g1_prompt "$RA" m6 "" "$MP"
c2_chk pass "P6 pair: a machine prompt in the SAME repo leaves the snapshot alone" eq "$(cat "$S/turnsnap/m6")" "$before6"
g1_prompt "$RB" m6 "" "$MP"
c2_chk refuse "P6 a machine prompt in ANOTHER repo (the session moved) rewrites it, naming the new repo" bash -c "[ \"\$(cut -f5 '$S/turnsnap/m6')\" = '$(git -C "$RB" rev-parse --show-toplevel)' ]"
g1_prompt "$RB" m6 "" "typed words"
echo edit2 >> "$RB/README.md"; before6b="$(cat "$S/turnsnap/m6")"; g1_prompt "$RB" m6 "" "more typed words"
c2_chk refuse "P6 a typed prompt in the same repo always rewrites (the baseline moves with the edit)" bash -c "[ \"\$(cat '$S/turnsnap/m6')\" != '$before6b' ]"
git -C "$RA" checkout -q -- .; git -C "$RB" checkout -q -- .

echo "  P12 every context threshold compares exact tokens: 399,999 is under 400k, 400,000 is at it"
g1_toks() { printf '{"type":"assistant","message":{"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":%d,"output_tokens":5}}}\n' $(( $2 - 1 )) > "$1"; }
g1_toks "$G1/u399" 399999; g1_toks "$G1/u400" 400000
g1_conf 'g1seat*  dev  400'
R="$G1/g1seat4"; c2_repo "$R"; S="$G1/s12a"
g1_stop "$R" r12a false "$G1/u399"
c2_chk pass "P12 the retire floor 400k: 399,999 tokens is under it (no marker)" test ! -e "$S/retired/r12a"
g1_stop "$R" r12b false "$G1/u400"
c2_chk refuse "P12 the retire floor 400k: 400,000 tokens is at it (marker written)" test -f "$S/retired/r12b"
S="$G1/s12b"; g1_conf 'g1seat*  dev  850' 'WRAPUP_K 400'
g1_prompt "$R" w12a "$G1/u399"; g1_stop "$R" w12a false "$G1/u399"
c2_chk pass "P12 the wrap-up point 400k: 399,999 tokens is under it" g1_quiet
g1_prompt "$R" w12b "$G1/u400"; g1_stop "$R" w12b false "$G1/u400"
c2_chk refuse "P12 the wrap-up point 400k: 400,000 tokens is at it" bash -c "grep -q 'wrap-up point' '$G1/out'"
S="$G1/s12c"; g1_conf 'g1seat*  dev  400'
g1_prompt "$R" d12a "$G1/u399" "hello there"
c2_chk pass "P12 the doorman's cut-off 400k: 399,999 tokens passes" bash -c "[ '$G1_RC' = 0 ] && [ ! -e '$S/held/d12a' ]"
g1_prompt "$R" d12b "$G1/u400" "hello there"
c2_chk refuse "P12 the doorman's cut-off 400k: 400,000 tokens is held (exit 2)" bash -c "[ '$G1_RC' = 2 ] && [ -f '$S/held/d12b' ]"
c1_fire "P12 the context note (default 400k): 400,000 tokens prints it" "$(c1_run "$(c1_in UserPromptSubmit "$G1/u400" 'go on')")" 'open your reply with one line on how full'
c1_quiet "P12 the context note: 399,999 tokens does not (the shown figure rounds to 400k)" "$(c1_run "$(c1_in UserPromptSubmit "$G1/u399" 'go on')")" 'how full'
c1_fire "P12 pair: the shown figure is still the rounded k" "$(c1_run "$(c1_in UserPromptSubmit "$G1/u399" 'go on')")" 'Context used: 400k tokens'
WS="$G1/s12d"; mkdir -p "$WS/wrapup-fired"; echo 400 > "$WS/wrapup-fired/c1s"
c1_fire "P12 the wrap-up words (marker 400): 400,000 tokens switches the note" "$(c1_run "$(c1_in UserPromptSubmit "$G1/u400" 'go on')" STATE_CHECK_STATE_DIR="$WS" CONTEXT_NOTE_K=300)" 'wrapping up: open a fresh chat'
c1_quiet "P12 the wrap-up words (marker 400): 399,999 tokens keeps the plain note" "$(c1_run "$(c1_in UserPromptSubmit "$G1/u399" 'go on')" STATE_CHECK_STATE_DIR="$WS" CONTEXT_NOTE_K=300)" 'wrapping up'

echo "  P13 a delivered held text leaves exactly one inbox line naming both sessions"
S="$G1/s13"; g1_conf 'g1seat*  dev  850'; D1="$G1/g1seat5"; D2="$G1/g1seat6"; mkdir -p "$D1" "$D2"
c2_tp "$G1/tp900" 900
g1_prompt "$D1" old13 "$G1/tp900" "carry me over"
c2_chk pass "P13 pair: before any delivery the inbox holds no DELIVERED line" bash -c "! grep -q DELIVERED '$S/inbox/dev.md'"
mkdir -p "$S/retired" "$S/retired-compacts"; echo "x" > "$S/retired/old13"; echo 0 > "$S/retired-compacts/old13"
c2_tp "$G1/tp100" 100
g1_prompt "$D2" new13 "$G1/tp100" "first words"
c2_chk refuse "P13 the text reached the new chat of the same role" has "carry me over" "$G1/pout"
c2_chk refuse "P13 exactly one DELIVERED line is appended" eq "$(grep -c DELIVERED "$S/inbox/dev.md")" "1"
c2_chk refuse "P13 ... naming the receiving session and the original session" bash -c "l=\$(grep DELIVERED '$S/inbox/dev.md'); case \"\$l\" in *new13*) case \"\$l\" in *old13*) true;; *) false;; esac;; *) false;; esac"
c2_chk refuse "P13 ... and it is written after the held file moved to delivered/" bash -c "[ -f '$S/delivered/old13' ] && [ ! -e '$S/held/old13' ]"
S="$G1/s13b"; g1_prompt "$D1" old13b "$G1/tp900" "second text"; rm -f "$S/inbox/dev.md"
mkdir -p "$S/retired" "$S/retired-compacts"; echo "x" > "$S/retired/old13b"; echo 0 > "$S/retired-compacts/old13b"
g1_prompt "$D2" new13b "$G1/tp100" "first words"
c2_chk refuse "P13 the line is written even when the inbox copy was removed before the delivery" bash -c "[ \"\$(grep -c DELIVERED '$S/inbox/dev.md')\" = 1 ]"

# ---- guard port 2026-10-10 (C2): the wake-up warning (P7) and the installer for it ----
echo "guard port 2026-10-10 (C2): wake-warning.sh (P7) and install.sh"
W="$T/c2w"; mkdir -p "$W"; WNOW=1800000000
w_iso() { python3 -c 'import sys,datetime;print(datetime.datetime.fromtimestamp(int(sys.argv[1]),datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z"))' "$1"; }
w_tr() {   # <file> <tokens> <age-seconds of the newest line>: a user line, then an assistant line with that usage
  local f="$1" tok="$2" age="$3"
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"hi"}}\n' "$(w_iso $((WNOW - age - 60)))" > "$f"
  printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":%d,"output_tokens":5}}}\n' "$(w_iso $((WNOW - age)))" $((tok - 1)) >> "$f"
}
w_in() {   # <sid> <transcript> [prompt] [event]
  python3 -c 'import json,sys;print(json.dumps({"hook_event_name":sys.argv[4],"session_id":sys.argv[1],"transcript_path":sys.argv[2],"prompt":sys.argv[3]}))' "$1" "$2" "${3:-go on}" "${4:-UserPromptSubmit}"
}
w_run() {   # <hook-dir> <state> <json> [ENV=val ...]: stdout -> $W/out, stderr -> $W/err, rc -> W_RC
  local hd="$1" st="$2" js="$3"; shift 3
  printf '%s' "$js" | env STATE_CHECK_STATE_DIR="$st" WAKE_NOW="$WNOW" "$@" bash "$hd/wake-warning.sh" > "$W/out" 2> "$W/err"; W_RC=$?
}
WS="$W/state"; mkdir -p "$WS"
IDLE61=$((61 * 60 + 10)); IDLE59=$((59 * 60 + 10))
w_tr "$W/t61" 250000 $IDLE61
w_run "$HOOKS_DIR" "$WS" "$(w_in w1 "$W/t61")"
c2_chk refuse "P7 idle 61 min with 250k tokens is held (exit 2)" eq "$W_RC" 2
c2_chk refuse "P7 the hold prints nothing on stdout" test ! -s "$W/out"
c2_chk refuse "P7 the hold writes the record of the wake" test -s "$WS/wake-warned/w1"
c2_chk refuse "P7 the message says idle 61 minutes and about 250k tokens" bash -c "grep -q 'idle 61 minutes' '$W/err' && grep -q 'about 250k tokens' '$W/err'"
c2_chk refuse "P7 the message says saved copy expired, the figure, list price and the subscription note" bash -c "grep -q 'saved copy has expired' '$W/err' && grep -q 'about \$1.44 extra at list price' '$W/err' && grep -q 'subscription' '$W/err'"
c2_chk refuse "P7 the message says NOT sent, send again, a fresh chat is cheaper" bash -c "grep -q 'NOT sent' '$W/err' && grep -q 'send it again' '$W/err' && grep -q 'fresh chat is cheaper' '$W/err'"
w_run "$HOOKS_DIR" "$WS" "$(w_in w1 "$W/t61" 'a different text')"
c2_chk pass "P7 pair: the same chat's next message passes" eq "$W_RC" 0
# a later wake (a newer line, still idle over the limit) warns again
printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":249999,"output_tokens":5}}}\n' "$(w_iso $((WNOW - 3700)))" >> "$W/t61"
w_run "$HOOKS_DIR" "$WS" "$(w_in w1 "$W/t61")"
c2_chk refuse "P7 a later wake (a newer line, still idle 61 min) is held again" eq "$W_RC" 2
w_tr "$W/t59" 250000 $IDLE59
w_run "$HOOKS_DIR" "$WS" "$(w_in w2 "$W/t59")"
c2_chk pass "P7 pair: idle 59 min passes" eq "$W_RC" 0
c2_chk pass "P7 pair: idle 59 min leaves no record" test ! -e "$WS/wake-warned/w2"
w_tr "$W/t150" 150000 $IDLE61
w_run "$HOOKS_DIR" "$WS" "$(w_in w3 "$W/t150")"
c2_chk pass "P7 pair: idle 61 min with 150k tokens passes" eq "$W_RC" 0
w_tr "$W/t200" 200000 $IDLE61
w_run "$HOOKS_DIR" "$WS" "$(w_in w3b "$W/t200")"
c2_chk pass "P7 pair: exactly 200,000 tokens is not MORE than the limit: passes" eq "$W_RC" 0
for mp in '<task-notification>done</task-notification>' '[Cross-session delivery notice] hi' '<bash-input>ls</bash-input>' '<<autonomous-loop>>'; do
  w_run "$HOOKS_DIR" "$WS" "$(w_in w4 "$W/t61" "$mp")"
  c2_chk pass "P7 pair: the machine prompt '${mp:0:24}' passes" bash -c "[ '$W_RC' = 0 ] && [ ! -e '$WS/wake-warned/w4' ]"
done
mkdir -p "$W/proj/subagents"; w_tr "$W/proj/subagents/agent-1.jsonl" 250000 $IDLE61
w_run "$HOOKS_DIR" "$WS" "$(w_in w5 "$W/proj/subagents/agent-1.jsonl")"
c2_chk pass "P7 pair: a /subagents/ transcript passes" bash -c "[ '$W_RC' = 0 ] && [ ! -e '$WS/wake-warned/w5' ]"
w_run "$HOOKS_DIR" "$WS" "$(w_in w6 "$W/no-such-transcript")"
c2_chk pass "P7 pair: no transcript passes" eq "$W_RC" 0
w_run "$HOOKS_DIR" "$WS" "$(w_in '' "$W/t61")"
c2_chk pass "P7 pair: no session id passes" eq "$W_RC" 0
w_run "$HOOKS_DIR" "$WS" "$(w_in w6b "$W/t61" go SessionStart)"
c2_chk pass "P7 pair: an event other than UserPromptSubmit passes" eq "$W_RC" 0
# a symlink at the record folder: pass, and nothing written through it
WSL="$W/state-link"; mkdir -p "$WSL" "$W/elsewhere"; ln -s "$W/elsewhere" "$WSL/wake-warned"
w_run "$HOOKS_DIR" "$WSL" "$(w_in w7 "$W/t61")"
c2_chk pass "P7 pair: a symlink at the record folder passes and writes nothing through it" bash -c "[ '$W_RC' = 0 ] && [ -z \"\$(ls -A '$W/elsewhere')\" ]"
# an unwritable record (a folder sits where the record file goes): pass
WSU="$W/state-unw"; mkdir -p "$WSU/wake-warned/w8"
w_run "$HOOKS_DIR" "$WSU" "$(w_in w8 "$W/t61")"
c2_chk pass "P7 pair: an unwritable record passes (the chat is not held on every message)" eq "$W_RC" 0
# a line under 15 s old is the prompt being submitted: the idle time is measured from the line before it
w_tr "$W/tfresh" 250000 5
printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"old"}}\n' "$(w_iso $((WNOW - IDLE61)))" > "$W/tfresh.head"; cat "$W/tfresh" >> "$W/tfresh.head"
python3 - "$W/tfresh.head" "$W/tfresh2" <<'PY'
import sys
L=open(sys.argv[1]).read().splitlines(); L.sort(key=lambda l: l.split('"timestamp":"')[1][:19]); open(sys.argv[2],'w').write("\n".join(L)+"\n")
PY
w_run "$HOOKS_DIR" "$WS" "$(w_in w9 "$W/tfresh2")"
c2_chk pass "P7 pair: the freshest line is only 5 s old and the one before it is 60+ s old: passes" eq "$W_RC" 0
w_tr "$W/t61z" 250000 $IDLE61
printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}}\n' "$(w_iso $((WNOW - IDLE61 + 5)))" >> "$W/t61z"
w_run "$HOOKS_DIR" "$WS" "$(w_in w10 "$W/t61z")"
c2_chk refuse "P7 an all-zero API-error usage line after the big one does not hide the size: held" eq "$W_RC" 2
# the conf (a private copy of the hook folder, so the real folder never gets a live conf)
WH="$W/hk"; mkdir -p "$WH"; cp "$HOOKS_DIR/wake-warning.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/clock-in-context.sh" "$WH/" 2>/dev/null
printf 'WAKE_IDLE_MIN=30\nWAKE_EXCESS_PER_MTOK=10\n' > "$WH/wake-warning.conf"
w_tr "$W/t31" 250000 $((31 * 60 + 10)); w_tr "$W/t29" 250000 $((29 * 60 + 10))
w_run "$WH" "$WS" "$(w_in c1 "$W/t31")"
c2_chk refuse "P7 a conf WAKE_IDLE_MIN=30 makes 31 min held" eq "$W_RC" 2
c2_chk refuse "P7 a conf WAKE_EXCESS_PER_MTOK=10 shows \$2.50 for 250k tokens" has 'about \$2.50 extra' "$W/err"
w_run "$WH" "$WS" "$(w_in c2 "$W/t29")"
c2_chk pass "P7 pair: the same conf, 29 min: passes" eq "$W_RC" 0
w_run "$WH" "$WS" "$(w_in c3 "$W/t31")" WAKE_IDLE_MIN=90
c2_chk pass "P7 pair: an environment WAKE_IDLE_MIN=90 beats the conf's 30: 31 min passes" eq "$W_RC" 0
w_run "$HOOKS_DIR" "$WS" "$(w_in c5 "$W/t61")" WAKE_IDLE_MIN=61
c2_chk refuse "P7 the limit itself counts: idle exactly 61 min with WAKE_IDLE_MIN=61 is held" eq "$W_RC" 2
w_run "$HOOKS_DIR" "$WS" "$(w_in c6 "$W/t61")" WAKE_IDLE_MIN=62
c2_chk pass "P7 pair: idle 61 min with WAKE_IDLE_MIN=62 passes" eq "$W_RC" 0
w_run "$HOOKS_DIR" "$WS" "$(w_in c4 "$W/t31")"
c2_chk pass "P7 pair: with no conf the default 60 applies: 31 min passes" eq "$W_RC" 0
# no guard-lib beside the hook: the built-in reader gives the same answers
WH2="$W/hk2"; mkdir -p "$WH2"; cp "$HOOKS_DIR/wake-warning.sh" "$WH2/" 2>/dev/null
w_run "$WH2" "$WS" "$(w_in n1 "$W/t61")"
c2_chk refuse "P7 without guard-lib.sh the built-in reader still holds a big idle chat" eq "$W_RC" 2
w_run "$WH2" "$WS" "$(w_in n2 "$W/t150")"
c2_chk pass "P7 pair: without guard-lib.sh a 150k chat passes" eq "$W_RC" 0

# ---- the installer for it: a fake HOME, a pty to answer the question ----
REPOW="$(cd "$HOOKS_DIR/.." && pwd -P)"
w_count() { python3 -c 'import json,sys;s=json.load(open(sys.argv[1]));print(sum(1 for g in s.get("hooks",{}).get("UserPromptSubmit",[]) for h in g.get("hooks",[]) if "wake-warning.sh" in h.get("command","")))' "$1" 2>/dev/null; }
cat > "$W/drv.py" <<'PY'
import os,pty,sys,select,re,signal
home,script,outp,mode=sys.argv[1:5]
pid,fd=pty.fork()
if pid==0:
    os.environ["HOME"]=home
    os.execvp("bash",["bash",script])
buf=b""; answered=0; killed=False
while True:
    r,_,_=select.select([fd],[],[],0.5)
    if r:
        try: d=os.read(fd,4096)
        except OSError: break
        if not d: break
        buf+=d
        if mode=="kill" and not killed and b"wake-warning.sh (UserPromptSubmit" in buf:
            os.kill(pid,signal.SIGTERM); killed=True
    elif len(buf)>answered and not killed:
        tail=buf[-400:].decode("utf8","ignore")
        if re.search(r"(\] |: |\? )$",tail):
            yes = mode=="yes" and "wake-up warning" in tail.lower() and tail.rstrip().endswith("[y/N]")
            os.write(fd,b"y\n" if yes else (b"n\n" if tail.rstrip().endswith(("[y/N]","[Y/n]")) else b"\n")); answered=len(buf)
open(outp,"wb").write(buf)
_,st=os.waitpid(pid,0); sys.exit(os.waitstatus_to_exitcode(st))
PY
w_inst() { python3 "$W/drv.py" "$1" "$REPOW/install.sh" "$2" "$3" >/dev/null 2>&1; }
w_files() { ( cd "$1/.claude" 2>/dev/null && find . -type f ! -path './.setup-backup-*' | sort ); }
HW1="$W/home1"; mkdir -p "$HW1"; env HOME="$HW1" bash "$REPOW/install.sh" --yes > "$W/inst1.out" 2>&1
c2_chk refuse "P7 installer --yes: wake-warning.sh is copied and executable" test -x "$HW1/.claude/hooks/wake-warning.sh"
c2_chk refuse "P7 installer --yes: both new conf examples are copied" bash -c "[ -f '$HW1/.claude/hooks/wake-warning.conf.example' ] && [ -f '$HW1/.claude/hooks/issue-number.conf.example' ] && [ -f '$HW1/.claude/hooks/heavy-suite.conf.example' ]"
c2_chk pass "P7 pair: installer --yes does NOT register it (the answer is no)" eq "$(w_count "$HW1/.claude/settings.json")" 0
c2_chk pass "P7 pair: installer --yes writes no live wake-warning.conf" test ! -e "$HW1/.claude/hooks/wake-warning.conf"
HW2="$W/home2"; mkdir -p "$HW2"; w_inst "$HW2" "$W/inst2.out" yes
W_CLEAN_FILES="$(w_files "$HW2")"; W_CLEAN_UPS="$(d2_count "$HW2/.claude/settings.json" UserPromptSubmit)"   # the end state of ONE clean run
c2_chk refuse "P7 installer answering yes registers it once" eq "$(w_count "$HW2/.claude/settings.json")" 1
c2_chk refuse "P7 ... with a timeout of 10" bash -c "python3 -c 'import json,sys;s=json.load(open(sys.argv[1]));print([h.get(\"timeout\") for g in s[\"hooks\"][\"UserPromptSubmit\"] for h in g[\"hooks\"] if \"wake-warning.sh\" in h[\"command\"]])' '$HW2/.claude/settings.json' | grep -q '\[10\]'"
w_inst "$HW2" "$W/inst2b.out" yes
c2_chk pass "P7 pair: a second run answering yes again still leaves it registered once" eq "$(w_count "$HW2/.claude/settings.json")" 1
w_inst "$HW2" "$W/inst2c.out" no
c2_chk pass "P7 pair: a third run answering no keeps the earlier registration (once)" eq "$(w_count "$HW2/.claude/settings.json")" 1
# a run killed (SIGTERM, by its PID) right after the copy step, then run again: the end state of a clean run
HW3="$W/home3"; mkdir -p "$HW3"; w_inst "$HW3" "$W/inst3a.out" kill
c2_chk refuse "P7 killed right after the copy step: the hook file is there (not yet made executable) and nothing is registered yet" bash -c "[ -f '$HW3/.claude/hooks/wake-warning.sh' ] && [ ! -e '$HW3/.claude/settings.json' -o '$(w_count "$HW3/.claude/settings.json")' = 0 ]"
w_inst "$HW3" "$W/inst3b.out" yes
c2_chk refuse "P7 killed then run again (yes): registered once" eq "$(w_count "$HW3/.claude/settings.json")" 1
c2_chk refuse "P7 killed then run again: the same files as a clean run" eq "$(w_files "$HW3")" "$W_CLEAN_FILES"
c2_chk refuse "P7 killed then run again: the same UserPromptSubmit entry count as a clean run" eq "$(d2_count "$HW3/.claude/settings.json" UserPromptSubmit)" "$W_CLEAN_UPS"
{ echo "W-LEFT yes-once files: $(w_files "$HW2" | wc -l | tr -d ' ') UPS-entries: $(d2_count "$HW2/.claude/settings.json" UserPromptSubmit)"; echo "W-LEFT killed-then-rerun files: $(w_files "$HW3" | wc -l | tr -d ' ') UPS-entries: $(d2_count "$HW3/.claude/settings.json" UserPromptSubmit)"; echo "W-LEFT --yes files: $(w_files "$HW1" | wc -l | tr -d ' ') UPS-entries: $(d2_count "$HW1/.claude/settings.json" UserPromptSubmit)"; echo "W-LEFT killed-run (before rerun) tmp leftovers: $(find "$HW3/.claude" -name '*.tmp*' | wc -l | tr -d ' ')"; } > "$W/left.txt"
cp "$W/left.txt" "${WLEFT_OUT:-/dev/null}" 2>/dev/null

# ---- guard port 2026-10-10 (C3): chapter-note.sh (opt-in, Claude desktop app) and its installer step ----
echo "guard port 2026-10-10 (C3): chapter-note.sh"
CH="$T/c3"; mkdir -p "$CH"; CS="$CH/state"
# a transcript builder: P = a typed prompt, N = an assistant text line, B:<cmd> = a Bash tool_use, T:<name> = another tool_use,
# R:<n>:<text>[:err] = the result of the n-th tool_use (is_error when err). Tool ids are t1, t2 ... in order.
cat > "$CH/mk.py" <<'PY'
import json,sys
out=sys.argv[1]; n=0; L=[]
for it in sys.argv[2:]:
    if it=="P": L.append({"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"do it"}})
    elif it=="N": L.append({"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}})
    elif it.startswith("B:") or it.startswith("T:"):
        n+=1
        if it[0]=="B": nm,inp="Bash",{"command":it[2:]}
        else: nm,inp=it[2:],{"file_path":"/x/y"}
        L.append({"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t%d"%n,"name":nm,"input":inp}]}})
    elif it.startswith("R:"):
        _,k,txt,*e=it.split(":",3)
        c={"type":"tool_result","tool_use_id":"t"+k,"content":txt}
        if e and e[0]=="err": c["is_error"]=True
        L.append({"type":"user","message":{"role":"user","content":[c]}})
open(out,"w").write("".join(json.dumps(x)+"\n" for x in L))
PY
ch_mk() { python3 "$CH/mk.py" "$@"; }
ch_run() {   # <event> <sid> <transcript> [env...]: run the hook; stdout -> $CH/out, rc in $CH_RC
  local ev="$1" sid="$2" tp="$3"; shift 3
  printf '{"hook_event_name":"%s","session_id":"%s","transcript_path":"%s"}' "$ev" "$sid" "$tp" | env STATE_CHECK_STATE_DIR="$CS" "$@" bash "$HOOKS_DIR/chapter-note.sh" > "$CH/out" 2> "$CH/err"; CH_RC=$?
}
ch_note() { [ -s "$CS/chapter-notes/$1" ]; }
ch_nonote() { [ ! -e "$CS/chapter-notes/$1" ]; }
ch_stop() { ch_run Stop "$@"; }
ch_rm() { rm -f "$CS/chapter-notes/$1"; }

echo "  P14 first change"
ch_mk "$CH/e1" P "T:Edit" N; ch_stop e1 "$CH/e1"
c2_chk refuse "P14 the first Edit of a session with no chapter call writes a note" ch_note e1
c2_chk refuse "P14 the note says it is the first change, names the tool and asks for a short title" bash -c "grep -q 'Mark a chapter: this session just made its first change\\.' '$CS/chapter-notes/e1' && grep -q 'call the chapter tool (mark_chapter) with a short title' '$CS/chapter-notes/e1'"
c2_chk pass "P14 pair: Stop prints nothing on stdout and exits 0" bash -c "[ '$CH_RC' = 0 ] && [ ! -s '$CH/out' ]"
ch_mk "$CH/e1c" P "T:Edit" N; ch_stop e1c "$CH/e1c"; ch_rm e1c
ch_mk "$CH/e1c2" P "T:Edit" N P "T:Write" N; ch_stop e1c "$CH/e1c2"
c2_chk pass "P14 pair: a later Edit in the same session writes no new note" ch_nonote e1c
ch_mk "$CH/e2" P "T:Edit" "T:mark_chapter" N; ch_stop e2 "$CH/e2"
c2_chk pass "P14 pair: an Edit followed by a chapter call in the same turn: no note" ch_nonote e2
ch_mk "$CH/e2b" P "T:mark_chapter" "B:git push origin main" N; ch_stop e2b "$CH/e2b"
c2_chk refuse "P14 a chapter call BEFORE the push in the turn does not cancel it: note" ch_note e2b
ch_mk "$CH/e2c" P "T:mark_chapter" "T:Edit" N; ch_stop e2c "$CH/e2c"
c2_chk pass "P14 pair: a chapter call before the first Edit of the turn: the session has a chapter, so no first note" ch_nonote e2c
ch_mk "$CH/e3" P "T:mcp__app__mark_chapter" N P "T:Edit" N; ch_stop e3 "$CH/e3"
c2_chk pass "P14 pair: a session that called the (namespaced) chapter tool earlier: no first note" ch_nonote e3
ch_mk "$CH/e3b" P "T:mark_chapter_x" N P "T:Edit" N; ch_stop e3b "$CH/e3b"
c2_chk refuse "P14 a tool whose name only CONTAINS the chapter name is not a chapter call: note" ch_note e3b
ch_mk "$CH/e4" P "B:sed -i s/a/b/ f.txt" N; ch_stop e4 "$CH/e4"
c2_chk refuse "P14 a Bash sed -i counts as a change: note" ch_note e4
ch_mk "$CH/e5" P "B:echo hi > out.txt" N; ch_stop e5 "$CH/e5"
c2_chk refuse "P14 a Bash redirect to a file counts as a change: note" ch_note e5
ch_mk "$CH/e6" P "B:echo hi 2>/dev/null; ls" N; ch_stop e6 "$CH/e6"
c2_chk pass "P14 pair: a redirect to /dev/null is no change" ch_nonote e6
ch_mk "$CH/e7" P "B:git commit -m x" N; ch_stop e7 "$CH/e7"
c2_chk refuse "P14 a git commit counts as the first change: note" ch_note e7
ch_mk "$CH/e8" P "T:Read" "B:ls -la" N; ch_stop e8 "$CH/e8"
c2_chk pass "P14 pair: a read-only turn: no note" ch_nonote e8
ch_mk "$CH/e9" P "B:echo \"git commit\"" N; ch_stop e9 "$CH/e9"
c2_chk pass "P14 pair: the words git commit inside quotes are no commit" ch_nonote e9
ch_mk "$CH/ch10" P "T:Edit" N; ch_stop ch10 "$CH/ch10"; ch_rm ch10; ch_stop ch10 "$CH/ch10"
c2_chk pass "P14 the same trigger seen twice (the same Stop again) gives one note only" ch_nonote ch10

echo "  P14 git push"
ch_mk "$CH/p1" P "B:git push origin main" N; ch_stop p1 "$CH/p1"
c2_chk refuse "P14 git push origin main: note" ch_note p1
c2_chk refuse "P14 the push note says pushed" bash -c "grep -q 'this session just pushed\\.' '$CS/chapter-notes/p1'"
ch_mk "$CH/p1b" P "T:Edit" "B:git push origin main" N; ch_stop p1b "$CH/p1b"
c2_chk refuse "P14 a first change AND a push in one turn: one note saying both" bash -c "grep -q 'made its first change and pushed' '$CS/chapter-notes/p1b'"
ch_rm p1; ch_stop p1 "$CH/p1"
c2_chk pass "P14 pair: the same push seen again: no second note" ch_nonote p1
ch_mk "$CH/p1c" P "B:git push origin main" N P "B:git push origin main" N; ch_stop p1 "$CH/p1c"
c2_chk refuse "P14 a push in a LATER turn is asked again" ch_note p1
for pc in 'git push --dry-run origin main' 'git push -n' 'git push --help' 'echo "git push"' "echo 'git push'" 'git commit -m "git push"' 'git status'; do
  sidp="pn$(printf '%s' "$pc" | cksum | cut -d' ' -f1)"
  ch_mk "$CH/$sidp" P "B:$pc" N; ch_stop "$sidp" "$CH/$sidp"
  case "$pc" in 'git commit'*) c2_chk pass "P14 pair: [$pc] makes no PUSH note (it is a commit: first-change wording only)" bash -c "! grep -q pushed '$CS/chapter-notes/$sidp' 2>/dev/null";;
    *) c2_chk pass "P14 pair: [$pc] makes no note" ch_nonote "$sidp";; esac
done
ch_mk "$CH/ph" P "B:cat <<EOF
git push origin main
EOF" N; ch_stop ph "$CH/ph"
c2_chk pass "P14 pair: a heredoc holding git push is no push" ch_nonote ph
ch_mk "$CH/pr" P "B:git push origin main" "R:1:! [rejected]        main -> main (fetch first)" N; ch_stop pr "$CH/pr"
c2_chk pass "P14 pair: a push whose tool result says rejected: no note" ch_nonote pr
ch_mk "$CH/pe" P "B:git push origin main" "R:1:fatal no remote:err" N; ch_stop pe "$CH/pe"
c2_chk pass "P14 pair: a push whose tool result is an error: no note" ch_nonote pe
ch_mk "$CH/pg" P "B:git push origin main" "R:1:Everything up-to-date" N; ch_stop pg "$CH/pg"
c2_chk refuse "P14 a push whose result is fine: note" ch_note pg
ch_mk "$CH/pb" P "B:bash -c \"git push origin main\"" N; ch_stop pb "$CH/pb"
c2_chk refuse "P14 bash -c \"git push\": note" ch_note pb
ch_mk "$CH/pi" P "B:if true; then git push origin main; fi" N; ch_stop pi "$CH/pi"
c2_chk refuse "P14 if x; then git push; fi: note" ch_note pi
ch_mk "$CH/pc" P "B:git -C repo push" N; ch_stop pc "$CH/pc"
c2_chk refuse "P14 git -C repo push: note" ch_note pc
ch_mk "$CH/pd" P "B:git push origin main" "T:mark_chapter" N; ch_stop pd "$CH/pd"
c2_chk pass "P14 pair: a push followed by a chapter call in the turn: no note" ch_nonote pd
ch_mk "$CH/pl" P "B:git pushd" N; ch_stop pl "$CH/pl"
c2_chk pass "P14 pair: git pushd is not git push" ch_nonote pl

echo "  P14 safety and failing open"
mkdir -p "$CH/elsewhere"; CSL="$CH/state-l1"; mkdir -p "$CSL"; ln -s "$CH/elsewhere" "$CSL/chapter-notes"
printf '{"hook_event_name":"Stop","session_id":"l1","transcript_path":"%s"}' "$CH/e1" | env STATE_CHECK_STATE_DIR="$CSL" bash "$HOOKS_DIR/chapter-note.sh" > "$CH/out" 2>"$CH/err"; rcl=$?
c2_chk refuse "P14 a link at chapter-notes: nothing written through it, exit 0" bash -c "[ $rcl = 0 ] && [ -z \"\$(ls -A '$CH/elsewhere')\" ] && [ ! -s '$CH/out' ]"
CSL2="$CH/state-l2"; mkdir -p "$CSL2/chapter-notes"; ln -s "$CH/elsewhere/x" "$CSL2/chapter-notes/l2"
printf '{"hook_event_name":"Stop","session_id":"l2","transcript_path":"%s"}' "$CH/e1" | env STATE_CHECK_STATE_DIR="$CSL2" bash "$HOOKS_DIR/chapter-note.sh" > "$CH/out" 2>"$CH/err"; rcl=$?
c2_chk refuse "P14 a link at the note path: nothing written through it, exit 0" bash -c "[ $rcl = 0 ] && [ ! -e '$CH/elsewhere/x' ]"
CSL3="$CH/state-l3"; mkdir -p "$CSL3"; ln -s "$CH/elsewhere" "$CSL3/chapters-ask"
printf '{"hook_event_name":"Stop","session_id":"l3","transcript_path":"%s"}' "$CH/e1" | env STATE_CHECK_STATE_DIR="$CSL3" bash "$HOOKS_DIR/chapter-note.sh" > "$CH/out" 2>"$CH/err"; rcl=$?
c2_chk refuse "P14 a link at chapters-ask: no note, nothing written through it, exit 0" bash -c "[ $rcl = 0 ] && [ -z \"\$(ls -A '$CH/elsewhere')\" ] && [ ! -e '$CSL3/chapter-notes/l3' ]"
CSU="$CH/state-u"; mkdir -p "$CSU/chapters-ask/u1"
printf '{"hook_event_name":"Stop","session_id":"u1","transcript_path":"%s"}' "$CH/e1" | env STATE_CHECK_STATE_DIR="$CSU" bash "$HOOKS_DIR/chapter-note.sh" > "$CH/out" 2>"$CH/err"; rcl=$?
c2_chk refuse "P14 an unwritable record (a folder sits at the record path): no note, exit 0" bash -c "[ $rcl = 0 ] && [ ! -e '$CSU/chapter-notes/u1' ]"
CSU2="$CH/state-u2"; mkdir -p "$CSU2"; : > "$CSU2/chapters-ask"
printf '{"hook_event_name":"Stop","session_id":"u2","transcript_path":"%s"}' "$CH/e1" | env STATE_CHECK_STATE_DIR="$CSU2" bash "$HOOKS_DIR/chapter-note.sh" > "$CH/out" 2>"$CH/err"; rcl=$?
c2_chk refuse "P14 a record folder that cannot be made (a file in its place): no note, exit 0" bash -c "[ $rcl = 0 ] && [ ! -e '$CSU2/chapter-notes/u2' ]"
for badsid in '../x' 'a/b' '..'; do
  printf '{"hook_event_name":"Stop","session_id":"%s","transcript_path":"%s"}' "$badsid" "$CH/e1" | env STATE_CHECK_STATE_DIR="$CH/state-bs" bash "$HOOKS_DIR/chapter-note.sh" > "$CH/out" 2>"$CH/err"
  c2_chk pass "P14 pair: the session id [$badsid] is ignored: nothing written" bash -c "[ ! -e '$CH/state-bs' ] && [ ! -e '$CH/x' ]"
done
ch_run Stop ch11 "$CH/no-such-transcript"
c2_chk pass "P14 pair: no transcript: exit 0, no output, no note" bash -c "[ '$CH_RC' = 0 ] && [ ! -s '$CH/out' ] && [ ! -e '$CS/chapter-notes/ch11' ]"
printf '' | bash "$HOOKS_DIR/chapter-note.sh" > "$CH/out" 2>&1; rcn=$?
c2_chk pass "P14 pair: no input: exit 0, no output" bash -c "[ $rcn = 0 ] && [ ! -s '$CH/out' ]"
ch_run SessionStart ch12 "$CH/e1"
c2_chk pass "P14 pair: another event (SessionStart): exit 0, no output, no note" bash -c "[ '$CH_RC' = 0 ] && [ ! -s '$CH/out' ] && [ ! -e '$CS/chapter-notes/ch12' ]"
ch_run PreToolUse ch12 "$CH/e1"
c2_chk pass "P14 pair: another event (PreToolUse): no note" ch_nonote ch12
ch_mk "$CH/ch13" T:Edit; ch_stop ch13 "$CH/ch13"
c2_chk pass "P14 pair: a transcript with no typed prompt: no note" ch_nonote ch13
ch_mk "$CH/ch14" P "T:Edit" N; ch_stop ch14 "$CH/ch14"
c2_chk pass "P14 pair: Stop output is empty and the exit code 0 even when a note was written" bash -c "[ '$CH_RC' = 0 ] && [ ! -s '$CH/out' ] && [ -s '$CS/chapter-notes/ch14' ]"

echo "  P14 delivery on UserPromptSubmit"
ch_run UserPromptSubmit e1c "$CH/e1"
c2_chk pass "P14 pair: UserPromptSubmit with no note waiting: empty output, exit 0" bash -c "[ '$CH_RC' = 0 ] && [ ! -s '$CH/out' ]"
ch_run UserPromptSubmit ch14 "$CH/ch14"
c2_chk refuse "P14 UserPromptSubmit with a note waiting prints it" has 'Mark a chapter: this session just made its first change' "$CH/out"
c2_chk refuse "P14 ... and removes it" ch_nonote ch14
ch_run UserPromptSubmit ch14 "$CH/ch14"
c2_chk pass "P14 pair: the second UserPromptSubmit prints nothing (the note is shown once)" bash -c "[ '$CH_RC' = 0 ] && [ ! -s '$CH/out' ]"
mkdir -p "$CS/chapter-notes"; ln -s "$CH/ch14" "$CS/chapter-notes/lk"
ch_run UserPromptSubmit lk "$CH/ch14"
c2_chk pass "P14 pair: a link at the note path is never read" bash -c "[ ! -s '$CH/out' ]"

echo "  P14 the chapter tool name"
ch_mk "$CH/t1" P "T:Edit" "T:set_title" N; ch_stop t1 "$CH/t1" CHAPTER_TOOL=set_title
c2_chk pass "P14 pair: CHAPTER_TOOL=set_title: a set_title call after the Edit: no note" ch_nonote t1
ch_mk "$CH/t2" P "T:Edit" "T:mark_chapter" N; ch_stop t2 "$CH/t2" CHAPTER_TOOL=set_title
c2_chk refuse "P14 CHAPTER_TOOL=set_title: mark_chapter is no longer the chapter tool: note, and it names set_title" bash -c "grep -q '(set_title)' '$CS/chapter-notes/t2'"
HK3="$CH/hk"; mkdir -p "$HK3"; cp "$HOOKS_DIR/chapter-note.sh" "$HK3/"; printf 'CHAPTER_TOOL=set_title\n' > "$HK3/chapter-note.conf"
printf '{"hook_event_name":"Stop","session_id":"t3","transcript_path":"%s"}' "$CH/t1" | env STATE_CHECK_STATE_DIR="$CS" bash "$HK3/chapter-note.sh" >/dev/null 2>&1
c2_chk pass "P14 pair: a conf CHAPTER_TOOL=set_title is read: set_title call, no note" ch_nonote t3
printf '{"hook_event_name":"Stop","session_id":"t4","transcript_path":"%s"}' "$CH/t2" | env STATE_CHECK_STATE_DIR="$CS" bash "$HK3/chapter-note.sh" >/dev/null 2>&1
c2_chk refuse "P14 a conf CHAPTER_TOOL=set_title: only mark_chapter called, so a note" ch_note t4
printf '{"hook_event_name":"Stop","session_id":"t5","transcript_path":"%s"}' "$CH/t2" | env STATE_CHECK_STATE_DIR="$CS" CHAPTER_TOOL=mark_chapter bash "$HK3/chapter-note.sh" >/dev/null 2>&1
c2_chk pass "P14 pair: an environment CHAPTER_TOOL beats the conf" ch_nonote t5

echo "  P14 installer"
c3_count() { python3 -c 'import json,sys;s=json.load(open(sys.argv[1]));print(sum(1 for g in s.get("hooks",{}).get(sys.argv[2],[]) for h in g.get("hooks",[]) if "chapter-note.sh" in h.get("command","")))' "$1" "$2" 2>/dev/null; }
cat > "$CH/drv.py" <<'PY'
import os,pty,sys,select,re
home,script,outp,mode=sys.argv[1:5]
pid,fd=pty.fork()
if pid==0:
    os.environ["HOME"]=home
    os.execvp("bash",["bash",script])
buf=b""; answered=0
while True:
    r,_,_=select.select([fd],[],[],0.5)
    if r:
        try: d=os.read(fd,4096)
        except OSError: break
        if not d: break
        buf+=d
    elif len(buf)>answered:
        tail=buf[-400:].decode("utf8","ignore")
        if re.search(r"(\] |: |\? )$",tail):
            yes = mode=="yes" and "chapter note" in tail.lower() and tail.rstrip().endswith("[y/N]")
            os.write(fd,b"y\n" if yes else (b"n\n" if tail.rstrip().endswith(("[y/N]","[Y/n]")) else b"\n")); answered=len(buf)
open(outp,"wb").write(buf)
_,st=os.waitpid(pid,0); sys.exit(os.waitstatus_to_exitcode(st))
PY
c3_inst() { python3 "$CH/drv.py" "$1" "$REPOW/install.sh" "$2" "$3" >/dev/null 2>&1; }
HC1="$CH/home1"; mkdir -p "$HC1"; env HOME="$HC1" bash "$REPOW/install.sh" --yes > "$CH/inst1.out" 2>&1
c2_chk refuse "P14 installer --yes: chapter-note.sh is copied and executable" test -x "$HC1/.claude/hooks/chapter-note.sh"
c2_chk pass "P14 pair: installer --yes does not register it (Stop)" eq "$(c3_count "$HC1/.claude/settings.json" Stop)" 0
c2_chk pass "P14 pair: installer --yes does not register it (UserPromptSubmit)" eq "$(c3_count "$HC1/.claude/settings.json" UserPromptSubmit)" 0
HC2="$CH/home2"; mkdir -p "$HC2"; c3_inst "$HC2" "$CH/inst2.out" yes
c2_chk refuse "P14 installer answering yes registers it once on Stop" eq "$(c3_count "$HC2/.claude/settings.json" Stop)" 1
c2_chk refuse "P14 ... and once on UserPromptSubmit" eq "$(c3_count "$HC2/.claude/settings.json" UserPromptSubmit)" 1
c2_chk refuse "P14 ... both with a timeout of 10" bash -c "python3 -c 'import json,sys;s=json.load(open(sys.argv[1]));print(sorted(h.get(\"timeout\") for e in (\"Stop\",\"UserPromptSubmit\") for g in s[\"hooks\"][e] for h in g[\"hooks\"] if \"chapter-note.sh\" in h[\"command\"]))' '$HC2/.claude/settings.json' | grep -q '\[10, 10\]'"
c2_chk refuse "P14 the question says it is for the Claude desktop app" bash -c "grep -q 'Claude desktop app' '$CH/inst2.out'"
c3_inst "$HC2" "$CH/inst2b.out" yes
c2_chk pass "P14 pair: a second run answering yes: still once on Stop" eq "$(c3_count "$HC2/.claude/settings.json" Stop)" 1
c2_chk pass "P14 pair: a second run answering yes: still once on UserPromptSubmit" eq "$(c3_count "$HC2/.claude/settings.json" UserPromptSubmit)" 1
c3_inst "$HC2" "$CH/inst2c.out" no
c2_chk pass "P14 pair: a third run answering no keeps both registrations (once each)" eq "$(c3_count "$HC2/.claude/settings.json" Stop)$(c3_count "$HC2/.claude/settings.json" UserPromptSubmit)" 11
c2_chk pass "P14 pair: the wake-up warning was answered no in the yes run, so only this hook was added to UserPromptSubmit by the question" eq "$(w_count "$HC2/.claude/settings.json")" 0

echo "RESULT: $pass passed, $fail failed ($refuse_n must-refuse cases, $pass_n must-pass cases)"
[ "$fail" = 0 ]
