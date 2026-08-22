#!/bin/bash
# Stop hook — automates PROCESS RULE 11.
# At the end of every turn, in any session:
#   1. If anything tracked under ~/.claude changed, commit it to a private
#      backup repo and push. The commit message names the changed files so
#      history can answer "what changed when".
#   2. Refresh readable copies in a mirror folder and commit+push those too —
#      Cowork sessions can't see ~/.claude, so the copies are how the rules
#      stay visible there.
# Push failures never block the turn from ending, and a commit that could not
# be pushed is retried implicitly next turn. Nothing is ever merged INTO
# ~/.claude automatically — see push_with_heal() for why.
#
# ============================ READ BEFORE COPYING ============================
# This script runs `git add -A` in ~/.claude and PUSHES WITHOUT SHOWING A DIFF.
# It is only safe because ~/.claude/.gitignore is a strict ALLOWLIST (ignore
# everything, re-include named files) — shipped next to this script as
# `dot-claude.gitignore`. Install that allowlist FIRST, or `git add -A` will
# sweep up credentials (~/.claude/.credentials.json), shell history, and full
# session transcripts and push them to your backup repo. Also: (1) keep the
# backup repo PRIVATE — AND the mirror repo, which receives a copy of
# settings.json — both hold your AI's standing instructions; (2) know the
# trade-off: anything that writes into ~/.claude gets committed with no human
# review, so a malicious instruction that reaches your config would be
# preserved too. Convenience and safety pull in opposite directions here;
# this setup chooses convenience WITH the allowlist as the boundary.
# =============================================================================

# Settings come from ~/.claude/hooks/backup.conf, written by install.sh:
#   AUTHOR=your-handle <you@example.com>     # required
#   MIRROR_DIR=/some/folder                  # optional; empty = skip step 2
# No conf file means this hook is NOT configured, and it does nothing at all.
# That is the safe default: an unconfigured backup hook must never guess at a
# repo to push your config into.
#
# The conf is PARSED, never sourced. It is read at the end of every single
# turn, so anything able to write into it would otherwise get shell execution
# for free — including a value that merely happens to contain a backtick.
CLAUDE_DIR="$HOME/.claude"
CONF="$CLAUDE_DIR/hooks/backup.conf"

[ -f "$CONF" ] || exit 0
AUTHOR=""; MIRROR_DIR=""
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  case "$line" in *=*) ;; *) continue ;; esac
  key=${line%%=*}
  val=${line#*=}
  case "$key" in
    AUTHOR)     AUTHOR="$val" ;;
    MIRROR_DIR) MIRROR_DIR="$val" ;;
  esac
done < "$CONF"
if [ -z "$AUTHOR" ]; then
  warn "hooks/backup.conf exists but no AUTHOR line could be read from it (it must be exactly 'AUTHOR=Name <email>', no spaces around the '='). Backups are NOT running — tell the user."
  exit 0
fi

# The value is no longer shell-expanded, so expand a leading ~/ or $HOME/ here.
case "$MIRROR_DIR" in
  '~/'*)     MIRROR_DIR="$HOME/${MIRROR_DIR#\~/}" ;;
  '$HOME/'*) MIRROR_DIR="$HOME/${MIRROR_DIR#\$HOME/}" ;;
esac

warn() { printf 'auto-backup hook: %s\n' "$1"; }

# Push. On failure, report — never merge the remote's version in.
# $1 = human label for the repo, used in messages.
push_with_heal() {
  git push -q 2>/dev/null && return 0
  if ! git fetch -q 2>/dev/null; then
    warn "$1: commit saved locally but the remote is unreachable (offline?); will retry next turn"
    return 1
  fi
  # Deliberately NOT auto-merging. This repo holds hooks and settings, so
  # pulling whatever the remote gained would run someone else's code in the
  # next session — turning "somebody can write to your backup repo" into
  # unattended execution on this machine. The local commit is already safe.
  ahead=$(git rev-list --count HEAD..@{u} 2>/dev/null)
  if [ -n "$ahead" ] && [ "$ahead" != "0" ]; then
    warn "$1: the remote has $ahead commit(s) this machine doesn't have, so the push was refused. NOT merging them automatically — this repo contains hooks and settings, and pulling them in would run that code in the next session. Your work is committed locally and safe. Tell the user, show them what changed (git -C \"$PWD\" diff HEAD..@{u}), and let them decide."
    return 1
  fi
  warn "$1: the push failed for a reason other than the remote being ahead. The commit is safe locally — tell the user plainly and offer to look."
  return 1
}

# Short list of changed paths for the commit message (capped for sanity).
changed_files() {
  git status --porcelain 2>/dev/null | awk '{printf "%s ", $NF}' | cut -c1-120
}

# Is $1 the ROOT of a git repo — not merely inside one?
#
# This distinction is the whole safety boundary. `rev-parse
# --is-inside-work-tree` walks UP the tree, so if $HOME itself is a git repo
# (the common dotfiles setup) it answers "true" for ~/.claude. `git add -A`
# then stages the ENTIRE home directory, and the ~/.claude/.gitignore
# allowlist cannot help: a .gitignore only governs its own subtree, so
# ~/.ssh/id_rsa and ~/.aws/credentials sit completely outside its reach.
is_repo_root() {
  local top
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -n "$top" ] || return 1
  [ "$(cd "$top" 2>/dev/null && pwd -P)" = "$(cd "$1" 2>/dev/null && pwd -P)" ]
}

# --- 1. private backup repo ------------------------------------------------
if is_repo_root "$CLAUDE_DIR"; then
  cd "$CLAUDE_DIR" || exit 0
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    files=$(changed_files)
    git add -A
    if git commit -q -m "auto-backup: ${files:-config changed}" --author="$AUTHOR"; then
      push_with_heal "config backup repo"
    else
      warn "commit in ~/.claude failed — back up manually per rule 11"
    fi
  fi
elif git -C "$CLAUDE_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  warn "~/.claude is not its own git repository — it sits inside a larger one ($(git -C "$CLAUDE_DIR" rev-parse --show-toplevel 2>/dev/null)). REFUSING to back up: committing from here would stage that whole repository, and the ~/.claude/.gitignore allowlist cannot protect files outside ~/.claude. Tell the user; they need ~/.claude to be its own repo."
else
  warn "~/.claude is not a git repository — the config backup cannot run; tell the user"
fi

# --- 2. readable copies (optional) -----------------------------------------
# Only runs when MIRROR_DIR is set in backup.conf. The mirror may be a plain
# folder inside a larger repo, not a repo of its own — ask git rather than
# checking for a .git directory.
if [ -z "$MIRROR_DIR" ]; then
  exit 0
elif git -C "$MIRROR_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  cp "$CLAUDE_DIR/CLAUDE.md"             "$MIRROR_DIR/global-copy.md"       2>/dev/null
  cp "$CLAUDE_DIR/hooks/check-claude-md.sh" "$MIRROR_DIR/hook-copy.sh"      2>/dev/null
  cp "$CLAUDE_DIR/settings.json"         "$MIRROR_DIR/settings-copy.json"   2>/dev/null
  cp "$CLAUDE_DIR/hooks/auto-backup.sh"  "$MIRROR_DIR/auto-backup-copy.sh"  2>/dev/null
  cd "$MIRROR_DIR" || exit 0
  if [ -n "$(git status --porcelain -- global-copy.md hook-copy.sh settings-copy.json auto-backup-copy.sh 2>/dev/null)" ]; then
    files=$(git status --porcelain -- global-copy.md hook-copy.sh settings-copy.json auto-backup-copy.sh | awk '{printf "%s ", $NF}')
    git add global-copy.md hook-copy.sh settings-copy.json auto-backup-copy.sh
    # Pathspec is mandatory: a bare `git commit` commits the whole index, so
    # anything the user had staged in this repo would be swept into a commit
    # whose message names only these four files — and then pushed.
    if git commit -q -m "auto-refresh copies: ${files:-readable copies}" --author="$AUTHOR" \
         -- global-copy.md hook-copy.sh settings-copy.json auto-backup-copy.sh; then
      push_with_heal "mirror repo"
    else
      warn "commit of readable copies failed — refresh manually per rule 11"
    fi
  fi
else
  warn "$MIRROR_DIR is not inside a git repository — readable copies not refreshed; tell the user"
fi

exit 0
