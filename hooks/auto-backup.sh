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

warn() { printf 'auto-backup hook: %s\n' "$1"; }

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

# NUL-safe walk of `git status --porcelain --untracked-files=all -z`: a path with a
# space (or any byte) is not split by whitespace, and a new DIRECTORY does not collapse
# to one `?? dir/` entry (nothing inside it would ever be scanned). For a rename/copy
# entry (status starts with R or C) porcelain -z emits the NEW path as this field and
# the OLD path as the NEXT NUL-delimited field — read and discard it so it isn't
# mistaken for a separate changed file; the new path is what gets scanned/listed.
porcelain_paths() {
  git status --porcelain --untracked-files=all -z 2>/dev/null | {
    local entry status path old
    while IFS= read -r -d '' entry; do
      status="${entry:0:2}"; path="${entry:3}"
      case "$status" in R*|C*) IFS= read -r -d '' old ;; esac
      printf '%s\n' "$path"
    done
  }
}

# Short list of changed paths for the commit message (capped for sanity).
changed_files() {
  porcelain_paths | tr '\n' ' ' | cut -c1-120
}

# Secret scan: refuse to commit or push while a changed file contains — or is NAMED with —
# something that looks like a live secret (an API key, a token, a private key). Fails
# closed: the backup does not run until the secret is gone, and the next turn retries
# automatically once it's removed.
#
# Two escapes, because a check that holds every backup for ever over a line of
# documentation is worse than no check:
#   - a PLACEHOLDER value — one containing `your-`, `example`, `xxxx`, or wrapped in
#     `<`/`>` — never blocks. A doc showing the SHAPE of a key is not a key.
#   - `# pragma: allow-secret` anywhere on the same line marks a deliberate fixture (a
#     test string, a regex example) and skips that line.
# When the scan does block, the message names the blocking FILE and repeats the pragma, on
# every turn, so the way out is never something you have to go and look up.
#
# Limits, stated plainly: the scan is LINE BY LINE, so a secret split across two lines is
# not caught, and neither is a base64- or otherwise encoded one. It is a catcher of
# accidents, not a defence against someone deliberately hiding a key in your config.
SECRET_RE='sk-ant-[A-Za-z0-9_-]{10,}|sk-proj-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|Bearer [A-Za-z0-9._-]{20,}|_TOKEN=[^ ]{16,}|_KEY=[^ ]{16,}|_SECRET=[^ ]{16,}|://[^/ :]+:[^@ ]+@|-----BEGIN [A-Z ]*PRIVATE KEY'
SECRET_HINT="If a line is a placeholder or a test fixture, put '# pragma: allow-secret' on it (a value containing your-, example, xxxx or <…> is ignored already)."
is_placeholder() {   # $1 = the matched text, not the whole line
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    *your-*|*example*|*xxxx*|*'<'*|*'>'*) return 0 ;;
  esac
  return 1
}
# One file -> prints a line number per REAL hit (placeholders and pragma lines dropped).
file_secret_lines() {
  local f="$1" ln m full
  grep -noaE "$SECRET_RE" "$f" 2>/dev/null | while IFS=: read -r ln m; do
    case "$ln" in ''|*[!0-9]*) continue ;; esac
    is_placeholder "$m" && continue
    full="$(sed -n "${ln}p" "$f" 2>/dev/null)"
    case "$full" in *'pragma: allow-secret'*) continue ;; esac
    printf '%s\n' "$ln"
  done
}
# A path can BE the secret: `ghp_…​.md` as a filename has no matching line inside it.
path_has_secret() {
  printf '%s' "$1" | grep -qE "$SECRET_RE" && ! is_placeholder "$1"
}
# Scans a fixed list of file paths (used for the mirror copies, which are never inside
# `git status`). Returns matching paths, one per line.
files_have_secret() {
  local hits="" f
  for f in "$@"; do
    if path_has_secret "$f" || { [ -f "$f" ] && [ -n "$(file_secret_lines "$f")" ]; }; then
      hits="${hits:+$hits$'\n'}$f"
    fi
  done
  printf '%s' "$hits"
}
secret_scan() {
  local hits
  hits=$(porcelain_paths | while IFS= read -r f; do
    if path_has_secret "$f"; then printf '%s\n' "$f"; continue; fi
    [ -f "$f" ] || continue
    [ -n "$(file_secret_lines "$f")" ] && printf '%s\n' "$f"
  done)
  if [ -n "$hits" ]; then
    warn "$1: possible secret in: $hits — NOT committed, NOT pushed. Remove it; the next turn backs up normally once it's gone. $SECRET_HINT"
    return 1
  fi
  return 0
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
    secret_scan "config backup repo" || exit 0   # also skips the mirror copies below
    files=$(changed_files)
    # Two sessions can end at the same instant and race for .git/index.lock.
    # The loser must not dump raw git stderr into the transcript or claim the
    # backup is broken: the winner commits everything, including this turn's
    # changes, so the correct report is "it is being handled".
    err=$(git add -A 2>&1) && err=$(git commit -q -m "auto-backup: ${files:-config changed}" --author="$AUTHOR" 2>&1)
    rc=$?
    if [ "$rc" = "0" ]; then
      push_with_heal "config backup repo"
    elif printf '%s' "$err" | grep -q 'index.lock'; then
      warn "another session is backing up right now; this turn's changes go into that commit — nothing to do"
    else
      warn "the commit in ~/.claude failed and the config is NOT backed up. git said: $(printf '%s' "$err" | head -2 | tr '\n' ' '). Tell the user plainly."
    fi
  fi
  # A clean tree with no NEW changes this turn still retries a push left over from a
  # turn whose push failed (offline, remote rejected, etc.) — otherwise that commit
  # sits local until the next dirty turn. `@{u}..HEAD` errors (exit nonzero, empty
  # output) when there is no upstream; that is tolerated, not treated as an ahead count.
  ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null)
  if [ -n "$ahead" ] && [ "$ahead" -gt 0 ] 2>/dev/null; then
    push_with_heal "config backup repo"
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
  # settings.json legitimately carries an `env` block, which is where a live API key would
  # sit — scan the four copies too, same as the config repo above, before they are staged.
  mirror_hits="$(files_have_secret "$MIRROR_DIR/global-copy.md" "$MIRROR_DIR/hook-copy.sh" "$MIRROR_DIR/settings-copy.json" "$MIRROR_DIR/auto-backup-copy.sh")"
  if [ -n "$mirror_hits" ]; then
    warn "mirror repo: possible secret in: $mirror_hits — NOT committed, NOT pushed. Remove it from the source; the next turn refreshes normally once it's gone. $SECRET_HINT"
    exit 0
  fi
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
