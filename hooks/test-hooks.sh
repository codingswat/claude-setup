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
CONFDIR="$T/confdir-bdg"; mkdir -p "$CONFDIR"; cp "$HOOKS_DIR/block-dangerous-git.sh" "$CONFDIR/"
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
# NOTE: PATTERN's own vitest clause matches "npx vitest run" as soon as "run" appears,
# regardless of a trailing filename — only a bare "vitest"/"npx vitest" with NO "run" is
# exempted by naming a specific test file (see the extra check below PATTERN).
for c in 'npm run typecheck' 'ls' 'SUITE_OK=1 npm test' 'git commit -m "ran npm test and it passed"' 'npx vitest src/foo.test.ts'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "load 12 must allow: $c" env HEAVY_SUITE_LOAD_OVERRIDE=12 bash "$HOOKS_DIR/heavy-suite-guard.sh"; done
INPUT="$(json_bash 'npm test')"; expect pass 0 "load 2 must allow: npm test" env HEAVY_SUITE_LOAD_OVERRIDE=2 bash "$HOOKS_DIR/heavy-suite-guard.sh"
# custom conf: a command outside the default pattern, and a lower MAX_LOAD
CDIR="$T/confhook"; mkdir -p "$CDIR"; cp "$HOOKS_DIR/heavy-suite-guard.sh" "$CDIR/"
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

echo "RESULT: $pass passed, $fail failed ($refuse_n must-refuse cases, $pass_n must-pass cases)"
[ "$fail" = 0 ]
