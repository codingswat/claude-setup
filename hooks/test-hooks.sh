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
ID=(env GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.com GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.com)

echo "1 clock-in-context.sh"
out="$(bash "$HOOKS_DIR/clock-in-context.sh" </dev/null)"
if printf '%s' "$out" | grep -qE '^Clock \(this machine\): [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$'; then ok; else bad "clock line format: '$out'"; fi
pass_n=$((pass_n+1))
if printf '%s' "$out" | grep -q '^HOW TO TALK TO ME (enforced)'; then ok; else bad "the reply-format card must be injected on every turn"; fi
pass_n=$((pass_n+1))
for sec in 'Problem' 'Story' 'Result' 'Needs my input'; do
  if printf '%s' "$out" | grep -q "\*\*$sec\*\*"; then ok; else bad "card section missing: $sec"; fi
  pass_n=$((pass_n+1))
done
out="$(CARD_FILE="$T/no-card.md" bash "$HOOKS_DIR/clock-in-context.sh" </dev/null)"
if printf '%s' "$out" | grep -q '^WARNING: .*could not be injected' && printf '%s' "$out" | grep -q '^Clock (this machine): '; then ok; else bad "missing card file: loud WARNING and the clock kept"; fi
pass_n=$((pass_n+1))
if printf '%s' "$out" | grep -q 'YOU ARE RETURNING'; then bad "no transcript: away notice must NOT fire"; else ok; fi
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
away_out() { printf '{"session_id":"t","transcript_path":%s,"cwd":"/tmp"}' "$(jstr "$1")" | env "${@:2}" bash "$HOOKS_DIR/clock-in-context.sh" 2>/dev/null; }
fires() { printf '%s' "$1" | grep -qE "^YOU ARE RETURNING after ($2) minutes"; }
quiet() { ! printf '%s' "$1" | grep -q 'YOU ARE RETURNING'; }
TR="$T/transcript.jsonl"
mk_tr "$TR" human:30 assistant:29 tool:29 assistant:28; out="$(away_out "$TR")"
if fires "$out" '29|30|31'; then ok; else bad "away 30 min ago, model done 28 min ago: MUST fire: '$out'"; fi
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
for c in 'git reset --hard HEAD~1' 'git reset HEAD~1 --hard' 'git clean -fd' 'git clean -f' 'git branch -D feature' 'git branch --delete --force feature' 'git checkout .' 'git checkout -f main' 'git restore .' 'git restore --staged --worktree .' 'git push --force origin main' 'git push -f origin main' 'git push origin --delete feature' 'git push origin :feature' 'git filter-branch --all'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "must refuse: $c" bash "$HOOKS_DIR/block-dangerous-git.sh"; done
for c in 'git push origin main' 'git push' 'git branch -d feature' 'git checkout main' 'git checkout -b feature' 'git restore file.ts' 'git reset --soft HEAD~1' 'git reset file.ts' 'GITGUARD=1 git reset HEAD~1 --hard' 'git commit -m "never run git reset --hard here"' 'git clean -n' 'git push origin HEAD:main'; do
  INPUT="$(json_bash "$c")"; expect pass 0 "must allow: $c" bash "$HOOKS_DIR/block-dangerous-git.sh"; done

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
expect_c pass 0 "staged file: SWEEP=1 override passes" 'SWEEP=1 git commit -m "deliberate sweep"'
git -C "$r" reset -q
expect_c pass 0 "index emptied: bare commit passes again" 'git commit -m "x"'

echo "4 heavy-suite-guard.sh"
for c in 'npm test' 'npm run test' 'npm run e2e' 'npx vitest run' 'npx playwright test -c apps/web/playwright.config.ts'; do
  INPUT="$(json_bash "$c")"; expect refuse 2 "load 12 must refuse: $c" env HEAVY_SUITE_LOAD_OVERRIDE=12 bash "$HOOKS_DIR/heavy-suite-guard.sh"; done
for c in 'npm run typecheck' 'ls' 'SUITE_OK=1 npm test' 'git commit -m "ran npm test and it passed"'; do
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
repo="$T/repo"; mkdir -p "$repo"; git -C "$repo" init -q -b main; git -C "$repo" config core.hooksPath "$GIT_HOOKS_DIR"
commit_try() { git -C "$repo" add -A; env HOME="$FAKE_HOME" "$@" git -C "$repo" commit -q -m "test" >/dev/null 2>&1; }
ID_OTHER=(env GIT_AUTHOR_NAME="Someone Else" GIT_AUTHOR_EMAIL=someone@example.com GIT_COMMITTER_NAME="Someone Else" GIT_COMMITTER_EMAIL=someone@example.com)
echo "a" > "$repo/a.txt"; if commit_try "${ID[@]}"; then ok; else bad "matching identity (backup.conf set) must commit"; fi
pass_n=$((pass_n+1))
echo "b" > "$repo/b.txt"; if commit_try "${ID_OTHER[@]}"; then bad "a non-matching identity (backup.conf set) must be refused"; else ok; git -C "$repo" reset -q; rm -f "$repo/b.txt"; fi
refuse_n=$((refuse_n+1))
# no backup.conf at all: any identity passes (skip silently)
NOAUTH_HOME="$T/fakehome-noauth"; mkdir -p "$NOAUTH_HOME/.claude/hooks"
commit_try_noauth() { git -C "$repo" add -A; env HOME="$NOAUTH_HOME" "$@" git -C "$repo" commit -q -m "test" >/dev/null 2>&1; }
echo "c" > "$repo/c.txt"; if commit_try_noauth "${ID_OTHER[@]}"; then ok; else bad "no backup.conf: any identity must pass (skip silently)"; fi
pass_n=$((pass_n+1))

# (c) privacy
pr="$T/privrepo"; mkdir -p "$pr"; git -C "$pr" init -q -b main; git -C "$pr" config core.hooksPath "$GIT_HOOKS_DIR"
printf '[guard names, one per line]\nZebulonQuixote\n' > "$FAKE_HOME/.claude/redaction-names.local"
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
NOLIST_HOME="$T/fakehome-nolist"; mkdir -p "$NOLIST_HOME/.claude/hooks"
pn="$T/privnone"; mkdir -p "$pn"; git -C "$pn" init -q -b main; git -C "$pn" config core.hooksPath "$GIT_HOOKS_DIR"
echo "zebulonquixote mentioned here" > "$pn/a.txt"; git -C "$pn" add -A
if env HOME="$NOLIST_HOME" "${ID[@]}" git -C "$pn" commit -q -m t >/dev/null 2>&1; then ok; else bad "privacy: with no redaction-names.local, only the path check runs, so this must pass"; fi
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

echo "RESULT: $pass passed, $fail failed ($refuse_n must-refuse cases, $pass_n must-pass cases)"
[ "$fail" = 0 ]
