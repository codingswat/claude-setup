#!/bin/bash
# Two-sided tests for git-hooks/pre-commit's root CLAUDE.md word cap (section (3) in that
# file's own header comment). Re-run after any edit to that section:
#   bash hooks/test-rules-cap.sh
#
# Two capped cases, judged on the STAGED blob, path exactly "CLAUDE.md" at a repo root
# (never */CLAUDE.md in a subfolder):
#   - a project rules file (repo toplevel != $HOME/.claude)                  -> 5750 words
#   - the global rules file (repo toplevel == $HOME/.claude — a config-backup repo whose
#     toplevel IS $HOME/.claude)                                            -> 4000 words
# RULES_CAP_OK=1 skips both cases.
#
# Test seam for the global-file branch: a THROWAWAY repo at $FAKE_HOME/.claude, committed
# with HOME=$FAKE_HOME passed to git — this exercises the hook's "$toplevel = $HOME/.claude"
# comparison without ever touching a real ~/.claude repo. Every git write below is inside
# $T (mktemp -d); no add/commit/push/stash/reset/checkout/clean/branch runs anywhere else.
GIT_HOOKS_DIR="${GIT_HOOKS_DIR:-$(cd "$(dirname "$0")/../git-hooks" && pwd -P)}"
pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { fail=$((fail+1)); echo "  FAIL: $1"; }

T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export OVERRIDE_LEDGER="$T/overrides.tsv"   # RULES_CAP_OK=1 writes here, never a real ledger
# pwd -P resolves macOS's /var -> /private/var symlink so $T matches what
# `git rev-parse --show-toplevel` reports (git resolves symlinks; a literal-string $T would
# otherwise never equal it in the HOME=$FAKE_HOME comparison below — the real $HOME has no
# such symlink, so production is unaffected).

# A suite-wide HOME with its own placeholder names list, so pre-commit's privacy check
# (which fails CLOSED with no ~/.claude/.redaction-names.local at all) never interferes
# with these word-cap-only tests; every commit below explicitly overrides HOME to one of
# the two throwaway homes set up here.
export HOME="$T/suite-home"; mkdir -p "$HOME/.claude"
printf '# suite placeholder, never matches real content\n' > "$HOME/.claude/.redaction-names.local"
AUTHOR_ENV=(GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.com GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.com)

mkwords() { python3 -c "import sys; print(' '.join(['w']*int(sys.argv[1])))" "$1"; }

# try_commit REPO [env-assignments...] -- stages everything, commits, plus any extra env
# assignments (e.g. HOME=..., RULES_CAP_OK=1). Sets RC and ERR (stderr only).
try_commit() {
  local repo="$1"; shift
  git -C "$repo" add -A >/dev/null 2>&1
  ERR="$(env "$@" "${AUTHOR_ENV[@]}" git -C "$repo" commit -q -m test 2>&1 1>/dev/null)"
  RC=$?
  git -C "$repo" reset -q >/dev/null 2>&1
}

# ---- project repo: toplevel != $HOME/.claude -> cap 5750 ----
repo="$T/proj"; mkdir -p "$repo"; git -C "$repo" init -q -b main; git -C "$repo" config core.hooksPath "$GIT_HOOKS_DIR"

echo "1 project CLAUDE.md: must-fire at 5751 words"
mkwords 5751 > "$repo/CLAUDE.md"
try_commit "$repo"
if [ "$RC" != 0 ] && printf '%s' "$ERR" | grep -q 'CLAUDE.md is 5751 words' && printf '%s' "$ERR" | grep -q 'capped at 5750'; then ok; else bad "5751-word root CLAUDE.md must be REFUSED with the cap message; RC=$RC ERR='$ERR'"; fi

echo "2 project CLAUDE.md: must-not-fire at 5750 words"
mkwords 5750 > "$repo/CLAUDE.md"
try_commit "$repo"
if [ "$RC" = 0 ]; then ok; else bad "5750-word root CLAUDE.md must pass; RC=$RC ERR='$ERR'"; fi

echo "3 sub/CLAUDE.md (not repo root): must-not-fire at 6000 words"
mkdir -p "$repo/sub"
mkwords 6000 > "$repo/sub/CLAUDE.md"
try_commit "$repo"
if [ "$RC" = 0 ]; then ok; else bad "a 6000-word sub/CLAUDE.md must pass (only the repo-root file is capped); RC=$RC ERR='$ERR'"; fi
rm -f "$repo/sub/CLAUDE.md"; try_commit "$repo"   # clean up the addition so it doesn't linger staged

echo "4 RULES_CAP_OK=1 skips the project cap"
mkwords 5751 > "$repo/CLAUDE.md"
try_commit "$repo" RULES_CAP_OK=1
if [ "$RC" = 0 ]; then ok; else bad "RULES_CAP_OK=1 with 5751 words must pass; RC=$RC ERR='$ERR'"; fi
mkwords 5750 > "$repo/CLAUDE.md"; try_commit "$repo"   # put the repo back under cap

# ---- global repo: toplevel == $HOME/.claude -> cap 4000 (test seam: FAKE_HOME) ----
FAKE_HOME="$T/fakehome"; mkdir -p "$FAKE_HOME"; FAKE_HOME="$(cd "$FAKE_HOME" && pwd -P)"
grepo="$FAKE_HOME/.claude"
mkdir -p "$grepo"; git -C "$grepo" init -q -b main; git -C "$grepo" config core.hooksPath "$GIT_HOOKS_DIR"
printf '# suite placeholder, never matches real content\n' > "$grepo/.redaction-names.local"

echo "5 global CLAUDE.md (toplevel == \$HOME/.claude): must-fire at 4001 words"
mkwords 4001 > "$grepo/CLAUDE.md"
try_commit "$grepo" HOME="$FAKE_HOME"
if [ "$RC" != 0 ] && printf '%s' "$ERR" | grep -q 'CLAUDE.md is 4001 words' && printf '%s' "$ERR" | grep -q 'capped at 4000'; then ok; else bad "4001-word global CLAUDE.md must be REFUSED with the cap message; RC=$RC ERR='$ERR'"; fi

echo "6 global CLAUDE.md: must-not-fire at 4000 words"
mkwords 4000 > "$grepo/CLAUDE.md"
try_commit "$grepo" HOME="$FAKE_HOME"
if [ "$RC" = 0 ]; then ok; else bad "4000-word global CLAUDE.md must pass; RC=$RC ERR='$ERR'"; fi

echo
echo "test-rules-cap.sh: $pass passed, $fail failed"
[ "$fail" = "0" ] || exit 1
