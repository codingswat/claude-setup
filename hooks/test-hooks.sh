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
for c in 'git reset --hard HEAD~1' 'git reset HEAD~1 --hard' 'git reset abc1234 --hard' 'git reset --quiet HEAD~1 --hard' 'git reset origin/main --hard' 'cd /x && git reset HEAD~1 --hard' 'git -c core.pager=cat reset --hard' 'git --no-pager reset --hard' 'git -C /some/path reset --hard' 'git clean -fd' 'git clean -f' 'git branch -D feature' 'git branch -Df feature' 'git branch --delete --force feature' 'git checkout .' 'git checkout -- .' 'git checkout -f main' 'git checkout main .' 'git restore .' 'git restore -s HEAD -- .' 'git restore --staged --worktree .' 'git push --force origin main' 'git push -f origin main' 'git push --force-with-lease' 'git push origin --delete feature' 'git push origin -d feature' 'git push origin :feature' 'git filter-branch --all' 'cd "/x y" && git reset --hard' 'git commit -m "GITGUARD=1 later" && git reset --hard' 'echo GITGUARD=1; git reset --hard'; do
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
echo "see /home/bob/project" > "$pr/h.txt"; if ptry; then bad "privacy: an absolute /home/<name>/ path must be refused"; else ok; git -C "$pr" reset -q; rm "$pr/h.txt"; fi
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
echo "WORKDIR /home/node/app" > "$pr2/Dockerfile"
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
echo 'DATABASE_URL=postgres://u:p4ss@host/db' >> "$SH/.claude/CLAUDE.md"
env HOME="$SH" bash "$HOOKS_DIR/auto-backup.sh" >/dev/null 2>&1
afterS="$(git -C "$SH/.claude" log --oneline 2>/dev/null | wc -l | tr -d ' ')"
if [ "$afterS" = "$beforeS" ]; then ok; else bad "a password inside a URL (DATABASE_URL=postgres://u:p4ss@host/db) must NOT be committed"; fi
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
for c in 'npm test | tee out.log' 'npm run typecheck | grep -q PASS' 'vitest run | tail -20' 'npx playwright test; git commit -am "x"' 'while ! grep -q READY build.log; do sleep 2; done' 'until tail -1 build.log | grep -q DONE; do sleep 1; done'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "must refuse: $c" bash "$HOOKS_DIR/gate-guard.sh"; done
NLGATE=$'npm test\ngit push'
INPUT="$(json_bash "$NLGATE")"; expect refuse 2 "a bare newline joining a gate to a push must refuse" bash "$HOOKS_DIR/gate-guard.sh"
for c in 'npm test && git commit -am "x"' 'npm test && git push' 'ls -la' 'GATE_OK=1 npm test | tee out.log' 'git commit -m "ran npm test and it passed"' 'while ! curl -sf localhost:3000/health; do sleep 2; done' 'npx vitest run src/foo.test.ts && echo done'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "must allow: $c" bash "$HOOKS_DIR/gate-guard.sh"; done
GGCONF="$T/gg-conf"; mkdir -p "$GGCONF"; cp "$HOOKS_DIR/gate-guard.sh" "$HOOKS_DIR/guard-lib.sh" "$HOOKS_DIR/override-ledger.sh" "$GGCONF/"
printf 'pytest\ngo test\n' > "$GGCONF/gate-guard.conf"
INPUT="$(json_bash 'pytest | tee out.log')"; expect refuse 2 "conf-added gate 'pytest' piped must refuse" bash "$GGCONF/gate-guard.sh"
INPUT="$(json_bash 'go test | tee out.log')"; expect refuse 2 "conf-added gate 'go test' piped must refuse" bash "$GGCONF/gate-guard.sh"
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
rm -f "$WL"; INPUT="$(json_bash 'GATE_OK=1 npm test | tee out.log')"; printf '%s' "$INPUT" | env OVERRIDE_LEDGER="$WL" bash "$HOOKS_DIR/gate-guard.sh" >/dev/null 2>&1
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
SCD="$T/state-check-conf"; mkdir -p "$SCD"; cp "$HOOKS_DIR/stop-state-check.sh" "$SCD/"
printf 'STATE_FILE state/{role}.md\nmyapp-dev*  dev  5\n' > "$SCD/state-check.conf"
scr="$T/myapp-dev1"; mkdir -p "$scr/state"; git -C "$scr" init -q -b main; git -C "$scr" config core.hooksPath /dev/null
echo seed > "$scr/README.md"; git -C "$scr" add -A; "${ID[@]}" git -C "$scr" commit -q -m init
ssc_json() { python3 -c 'import json,sys;print(json.dumps({"cwd":sys.argv[1],"session_id":sys.argv[2],"stop_hook_active":sys.argv[3]=="true","transcript_path":sys.argv[4]}))' "$1" "$2" "$3" "$4"; }
# The state-file job only blocks when it can see that THIS turn changed something — the
# turn snapshot hooks/doorman.sh writes when the prompt arrives (see section 29's M12).
# Taken here with the tree still clean, so the change below is this turn's.
mkdir -p "$T/ssc-state/turnsnap"; git -C "$scr" status --porcelain --untracked-files=no > "$T/ssc-state/turnsnap/sidX"
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
outss3="$(ssc_json "$scr" sidRET25 false "$TP25" | STATE_CHECK_STATE_DIR="$T/ssc-state" bash "$SCD/stop-state-check.sh")"
if printf '%s' "$outss3" | grep -q 'RETIRED at 8k'; then ok; else bad "stop-state-check.sh: context over the role's floor must RETIRE the session; got '$outss3'"; fi
pass_n=$((pass_n+1))
[ -f "$T/ssc-state/retired/sidRET25" ] && ok || bad "stop-state-check.sh: retirement must write state/retired/<session_id>"
pass_n=$((pass_n+1))

echo "25c hooks/stop-state-check.sh: no hooks/state-check.conf at all is INERT"
SCD2="$T/state-check-noconf"; mkdir -p "$SCD2"; cp "$HOOKS_DIR/stop-state-check.sh" "$SCD2/"
scr2="$T/myapp-dev2"; mkdir -p "$scr2"; git -C "$scr2" init -q -b main; git -C "$scr2" config core.hooksPath /dev/null
echo seed > "$scr2/README.md"; git -C "$scr2" add -A; "${ID[@]}" git -C "$scr2" commit -q -m init
echo more >> "$scr2/README.md"
outss4="$(ssc_json "$scr2" sidNC false "" | bash "$SCD2/stop-state-check.sh")"
if [ -z "$outss4" ]; then ok; else bad "stop-state-check.sh: no conf file must be INERT (no block); got '$outss4'"; fi
pass_n=$((pass_n+1))

echo "26 hooks/doorman.sh: refuses a RETIRED session and a genuinely idle+heavy one; passes a fresh one"
DCD="$T/doorman-conf"; mkdir -p "$DCD"; cp "$HOOKS_DIR/doorman.sh" "$DCD/"
printf 'myapp-dev*  dev  850\n' > "$DCD/state-check.conf"
dm="$T/myapp-dev3"; mkdir -p "$dm"
dj() { python3 -c 'import json,sys;print(json.dumps({"cwd":sys.argv[1],"session_id":sys.argv[2],"prompt":sys.argv[3],"transcript_path":sys.argv[4]}))' "$1" "$2" "$3" "$4"; }

mkdir -p "$T/doorman-state/retired"; echo "2026-01-01 00:00 dev 900k" > "$T/doorman-state/retired/sidDM-A"
dj "$dm" sidDM-A hello "" | STATE_CHECK_STATE_DIR="$T/doorman-state" bash "$DCD/doorman.sh" >/dev/null 2>&1
rcA=$?
if [ "$rcA" = 2 ]; then ok; else bad "doorman.sh: a session already marked RETIRED must be REFUSED (exit 2), got $rcA"; fi
refuse_n=$((refuse_n+1))

dj "$dm" sidDM-B hello "" | STATE_CHECK_STATE_DIR="$T/doorman-state" bash "$DCD/doorman.sh" >/dev/null 2>&1
rcB=$?
if [ "$rcB" = 0 ]; then ok; else bad "doorman.sh: a fresh session with no transcript must PASS (fail open), got $rcB"; fi
pass_n=$((pass_n+1))

echo "26b hooks/doorman.sh: 'idle' means the SESSION stopped working, never that the owner was merely silent"
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
if [ "$rcD" = 2 ]; then ok; else bad "doorman.sh: BOTH sides quiet 70min with high context must REFUSE (genuinely idle), got $rcD"; fi
refuse_n=$((refuse_n+1))

echo "26c hooks/doorman.sh: no hooks/state-check.conf at all is INERT"
DCD2="$T/doorman-noconf"; mkdir -p "$DCD2"; cp "$HOOKS_DIR/doorman.sh" "$DCD2/"
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
INPUT="$(json_bash 'npm test | tee out.log')"; expect refuse 2 "F1 pair: conf present, a built-in gate piped must still refuse" bash "$G28/gate-guard.sh"
INPUT="$(json_bash 'pytest | tee out.log')"; expect refuse 2 "F1 pair: conf present, a conf-added gate piped must still refuse" bash "$G28/gate-guard.sh"

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
rm -f "$OL28"; INPUT="$(json_bash "git commit -m 'x; GATE_OK=1 y' && npm test | tee out.log")"
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
for c in 'npx tsc --noEmit | head -1' 'vitest run | head -3'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "F10 pair, must refuse: $c" bash "$HOOKS_DIR/gate-guard.sh"; done

# --- 11 gate-guard with jq but no python3: inert and loud, never a blanket refusal ------
NOPY28="$T/h28-nopy-bin"; mkdir -p "$NOPY28"
for b in bash cat grep jq dirname sed env tr cut date mkdir awk; do p="$(command -v "$b" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$NOPY28/$b"; done
INPUT="$(json_bash 'ls -la')"; expect pass 0 "F11 jq present, python3 missing: an unrelated command must pass" env -i "PATH=$NOPY28" bash "$HOOKS_DIR/gate-guard.sh"
err28="$(printf '%s' "$INPUT" | env -i "PATH=$NOPY28" bash "$HOOKS_DIR/gate-guard.sh" 2>&1 1>/dev/null)"
if printf '%s' "$err28" | grep -q 'python3'; then ok; else bad "F11 the python3-missing pass must say so on stderr (got: '$err28')"; fi; pass_n=$((pass_n+1))
INPUT="$(json_bash 'ls -la')"; expect pass 0 "F11 pair: with python3 present an unrelated command still passes" bash "$HOOKS_DIR/gate-guard.sh"
INPUT="$(json_bash 'npm test | tee out.log')"; expect refuse 2 "F11 pair: with python3 present a piped gate is still refused" bash "$HOOKS_DIR/gate-guard.sh"

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
SCD29="$T/state-check-29"; mkdir -p "$SCD29"; cp "$HOOKS_DIR/stop-state-check.sh" "$SCD29/"
printf 'STATE_FILE state/{role}.md\nmyapp-dev*  dev  5\n' > "$SCD29/state-check.conf"
S29="$T/ssc29-state"
sr29="$T/myapp-dev29"; mkdir -p "$sr29/state"; git -C "$sr29" init -q -b main; git -C "$sr29" config core.hooksPath /dev/null
printf '**Current task:** first\n**Next step:** second\n' > "$sr29/state/dev.md"
echo seed > "$sr29/README.md"; git -C "$sr29" add -A; "${ID[@]}" git -C "$sr29" commit -q -m init
snap29() { mkdir -p "$S29/turnsnap"; git -C "$sr29" status --porcelain --untracked-files=no > "$S29/turnsnap/$1"; }
run29() { ssc_json "$sr29" "$1" false "" | STATE_CHECK_STATE_DIR="$S29" bash "$SCD29/stop-state-check.sh"; }
snap29 sid29a
echo more >> "$sr29/README.md"
printf '   \n' >> "$sr29/state/dev.md"
o29a="$(run29 sid29a)"
if printf '%s' "$o29a" | grep -q '"decision":"block"'; then ok; else bad "M10 a whitespace-only append to the state file must still BLOCK (got: $o29a)"; fi
refuse_n=$((refuse_n+1))
printf '**Next step:** land the fix\n' >> "$sr29/state/dev.md"
o29b="$(run29 sid29a)"
if printf '%s' "$o29b" | grep -q '"decision":"block"'; then bad "M10 pair: a real Next step update must be ALLOWED (got: $o29b)"; else ok; fi
pass_n=$((pass_n+1))
git -C "$sr29" add -A; "${ID[@]}" git -C "$sr29" commit -q -m land
echo dirt >> "$sr29/README.md"          # dirty from a PREVIOUS turn
snap29 sid29b                            # this turn starts in the already-dirty tree
o29c="$(run29 sid29b)"
if printf '%s' "$o29c" | grep -q '"decision":"block"'; then bad "M12 a read-only turn in an already-dirty tree must NOT block (got: $o29c)"; else ok; fi
pass_n=$((pass_n+1))
mkdir -p "$S29/turnsnap"; : > "$S29/turnsnap/sid29c"
o29d="$(run29 sid29c)"
if printf '%s' "$o29d" | grep -q '"decision":"block"'; then ok; else bad "M12 pair: a turn that started CLEAN and left the tree dirty must BLOCK (got: $o29d)"; fi
refuse_n=$((refuse_n+1))
rm -f "$S29/turnsnap/sid29d"
o29e="$(run29 sid29d)"
if printf '%s' "$o29e" | grep -q '"decision":"block"'; then bad "M12 with no turn snapshot the gate must WARN, not block (got: $o29e)"; else ok; fi
pass_n=$((pass_n+1))
if printf '%s' "$o29e" | grep -qi 'doorman'; then ok; else bad "M12 the no-snapshot note must name doorman.sh (got: $o29e)"; fi
pass_n=$((pass_n+1))
: > "$S29/turnsnap/nosid-myapp-dev29"
o29f="$(ssc_json "$sr29" "" false "" | STATE_CHECK_STATE_DIR="$S29" bash "$SCD29/stop-state-check.sh")"
if printf '%s' "$o29f" | grep -q '"decision":"block"'; then ok; else bad "M14 an empty session_id must not switch the state-file job off (got: $o29f)"; fi
refuse_n=$((refuse_n+1))
TP29="$T/ssc29-transcript.jsonl"
printf '{"type":"assistant","timestamp":"2026-01-01T00:00:00Z","message":{"usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":9000,"output_tokens":10}}}\n' > "$TP29"
ssc_json "$sr29" "" false "$TP29" | STATE_CHECK_STATE_DIR="$S29" bash "$SCD29/stop-state-check.sh" >/dev/null 2>&1
n29ret="$(ls "$S29/retired" 2>/dev/null | wc -l | tr -d ' ')"
if [ "$n29ret" = "0" ]; then ok; else bad "M14 pair: with no session id no retirement marker may be written (got $n29ret)"; fi
pass_n=$((pass_n+1))
DCDS="$T/doorman-snap-conf"; mkdir -p "$DCDS"; cp "$HOOKS_DIR/doorman.sh" "$DCDS/"
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
DCD29="$T/doorman29"; mkdir -p "$DCD29"; cp "$HOOKS_DIR/doorman.sh" "$DCD29/"
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
if [ "$rc29b" = 2 ]; then ok; else bad "M13 pair: the newest tool result 70 min old must still REFUSE (got $rc29b)"; fi
refuse_n=$((refuse_n+1))
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
expect refuse 2 "D1 python3 present but failing: block-dangerous-git must REFUSE" env PATH="$PYBAD30:$PATH" bash "$HOOKS_DIR/block-dangerous-git.sh"
expect refuse 2 "D1 a python3 that exits 0 printing nothing must REFUSE too" env PATH="$PYQ30:$PATH" bash "$HOOKS_DIR/block-dangerous-git.sh"
err30="$(printf '%s' "$INPUT" | env PATH="$PYBAD30:$PATH" bash "$HOOKS_DIR/block-dangerous-git.sh" 2>&1 1>/dev/null)"
if printf '%s' "$err30" | grep -qi 'parse'; then ok; else bad "D1 the refusal must say the guard could not parse its input (got: '$err30')"; fi
refuse_n=$((refuse_n+1))
INPUT="$(json_bash 'npm test')"
expect refuse 2 "D1 python3 present but failing: heavy-suite-guard must REFUSE" env PATH="$PYBAD30:$PATH" HEAVY_SUITE_LOAD_OVERRIDE=25 bash "$HOOKS_DIR/heavy-suite-guard.sh"
ex30 refuse 2 "D1 python3 present but failing: commit-pathspec-guard must REFUSE" 'git commit --all -m x' env PATH="$PYBAD30:$PATH" bash "$HOOKS_DIR/commit-pathspec-guard.sh"
ex30 refuse 2 "D1 a silent python3 must not let a sweep through either" 'git commit --all -m x' env PATH="$PYQ30:$PATH" bash "$HOOKS_DIR/commit-pathspec-guard.sh"
INPUT="$(json_bash 'npm test | tee out.log')"
expect refuse 2 "D1 gate-guard with a failing python3 stays closed" env PATH="$PYBAD30:$PATH" bash "$HOOKS_DIR/gate-guard.sh"
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
INPUT="$(json_bash 'npx${IFS}tsc${IFS}--noEmit | head')"
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
rm -f "$OL30"; INPUT="$(json_bash 'GATE_OK=1 true && npm test | tee out.log')"
expect refuse 2 "D3 GATE_OK on another segment must not disarm gate-guard" env OVERRIDE_LEDGER="$OL30" bash "$HOOKS_DIR/gate-guard.sh"
rm -f "$OL30"; INPUT="$(json_bash 'GATE_OK=1 npm test | tee out.log')"
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

echo "RESULT: $pass passed, $fail failed ($refuse_n must-refuse cases, $pass_n must-pass cases)"
[ "$fail" = 0 ]
