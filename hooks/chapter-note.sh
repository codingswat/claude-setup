#!/bin/bash
# chapter-note.sh - Stop + UserPromptSubmit hook, OPT-IN (the installer asks; the default answer is no).
# FOR THE CLAUDE DESKTOP APP: it has a chapter tool (mark_chapter) that titles a phase of work in the
# session list. This hook nudges the model to call it at the right moments. It does nothing useful
# in a client that has no such tool. It NEVER blocks and never prints a Stop decision.
#
# One script, two events (any other event, or no input: exit 0, no output):
#   Stop              may write ONE note to $STATE/chapter-notes/<session_id>, when the turn that just
#                     ended (read from the transcript, from the last typed prompt on)
#                       (a) is the session's FIRST turn that changed files (Edit/Write/MultiEdit/
#                           NotebookEdit, or a Bash command with `sed -i`, a `>`/`>>` redirect to a
#                           file other than /dev/*, `tee`, `cp`, `mv`, `git apply`) or made a git commit
#                           (commit, merge, cherry-pick, revert), and the session has never called the
#                           chapter tool; or
#                       (b) ran `git push` (not --dry-run, -n, --help; not one whose tool result is an
#                           error or says "rejected" with no ref updated, and not one that only says
#                           "Everything up-to-date": nothing was pushed). A push of two refs with one
#                           rejected still counts: the other went.
#                     No note when a chapter-tool call comes after the turn's last trigger.
#   UserPromptSubmit  prints a waiting note once on stdout (so it reaches the model with your next
#                     message) and removes it. A link is never read.
# What counts as a command: `git` at a command start (line start, after ; & | ( && ||, after
# if/then/elif/else/do/while/until, inside bash|sh|zsh -c "..."), global options (-C dir, -c k=v,
# --no-pager ...) allowed before the verb. A git word inside quotes, a heredoc body or a commit
# message never counts; `command git` counts. The transcript is read by guard-lib.sh's turn_scan, the
# one reader shared with stop-state-check.sh (the turn starts at the last TYPED prompt, never at a task
# notification, an isMeta line or a slash-command wrapper). Not covered: eval, xargs, a function wrapper,
# a variable as the command, env/time/nice prefixes, { ...; } groups, an interpreter's file write other
# than a -c/-e body that names open/write.
# The same trigger never gives two notes: $STATE/chapters-ask/<session_id> records "first" and
# "push:<prompt line>:<push line>", written and read back BEFORE the note is written.
# FAILS OPEN everywhere: no input, no session id (or one holding / or ..), no transcript, no guard-lib.sh, a link or
# non-plain file at a record or note path, an unwritable record = nothing happens, exit 0.
# Stated gap: when wake-warning.sh holds a prompt at the same moment, that prompt may swallow a note.
# Config: CHAPTER_TOOL, the chapter tool's name (default mark_chapter); a tool_use whose name ENDS with
#   it counts (the app namespaces its tools). An environment variable wins over hooks/chapter-note.conf
#   (one KEY=VALUE line, read as text, never executed).
# Test seams: STATE_CHECK_STATE_DIR (the doorman's state folder; default ~/.claude/state/state-check).
# Tests: hooks/test-hooks.sh "guard port 2026-10-10 (C3)".
input=$(cat 2>/dev/null); [ -z "$input" ] && exit 0
field() { printf '%s' "$input" | /usr/bin/sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
event=$(field hook_event_name); sid=$(field session_id)
case "$event" in Stop|UserPromptSubmit) ;; *) exit 0;; esac
case "$sid" in ''|*/*|*..*) exit 0;; esac
STATE="${STATE_CHECK_STATE_DIR:-$HOME/.claude/state/state-check}"
umask 077

# ---- UserPromptSubmit: hand over the waiting note, once ----
if [ "$event" = "UserPromptSubmit" ]; then
  nf="$STATE/chapter-notes/$sid"
  if [ ! -L "$STATE/chapter-notes" ] && [ ! -L "$nf" ] && [ -f "$nf" ]; then
    /bin/cat "$nf" 2>/dev/null
    /bin/rm -f "$nf" 2>/dev/null
  fi
  exit 0
fi

# ---- Stop ----
tp=$(field transcript_path)
[ -n "$tp" ] && [ -f "$tp" ] && [ -r "$tp" ] || exit 0
here="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
CT="${CHAPTER_TOOL:-}"
if [ -z "$CT" ] && [ -r "$here/chapter-note.conf" ]; then
  CT=$(/usr/bin/sed -n "s/^[[:space:]]*CHAPTER_TOOL[[:space:]]*=[[:space:]]*['\"]\{0,1\}\([A-Za-z0-9_.-][A-Za-z0-9_.-]*\)['\"]\{0,1\}[[:space:]]*\$/\1/p" "$here/chapter-note.conf" 2>/dev/null | /usr/bin/tail -1)
fi
case "$CT" in ''|*[!A-Za-z0-9_.-]*) CT=mark_chapter;; esac

rec="$STATE/chapters-ask/$sid"
if [ -L "$STATE/chapters-ask" ] || [ -L "$rec" ] || { [ -e "$rec" ] && [ ! -f "$rec" ]; } \
   || [ -L "$STATE/chapter-notes" ] || [ -L "$STATE/chapter-notes/$sid" ] || { [ -e "$STATE/chapter-notes/$sid" ] && [ ! -f "$STATE/chapter-notes/$sid" ]; }; then
  echo "chapter-note: skipped ($STATE/chapters-ask or chapter-notes is a link, or this session's record or note is not a plain file)" >&2
  exit 0
fi

# The transcript is read by guard-lib.sh's turn_scan (the one reader shared with stop-state-check.sh):
# it sets TS_PL (the last typed prompt), TS_MC (the turn's last chapter-tool call), TS_PU (its last
# counted push), TS_ED (its last change) and TS_ANY (any chapter-tool call at all, in the part read).
# A missing guard-lib.sh = nothing happens.
[ -r "$here/guard-lib.sh" ] && . "$here/guard-lib.sh" 2>/dev/null
command -v turn_scan >/dev/null 2>&1 || exit 0
turn_scan "$tp" "$CT" || exit 0
q_pl=$TS_PL; q_mc=$TS_MC; q_pu=$TS_PU; q_ed=$TS_ED; q_any=$TS_ANY
[ "${q_pl:-0}" -gt 0 ] 2>/dev/null || exit 0

# "any chapter call in the session" is only needed when a change was seen and "first" is not yet recorded:
# a cheap fixed-string test over the whole file, then the exact one
if [ "${q_ed:-0}" -gt 0 ] && [ "${q_any:-0}" = 0 ] && ! /usr/bin/grep -aqxF first "$rec" 2>/dev/null \
   && /usr/bin/grep -aqF "$CT" "$tp" 2>/dev/null && /usr/bin/grep -aqE "\"name\"[[:space:]]*:[[:space:]]*\"[^\"]*$CT\"" "$tp" 2>/dev/null; then q_any=1; fi

trig=""; keys=""; what=""
if [ "${q_pu:-0}" -gt 0 ] && ! /usr/bin/grep -aqxF "push:$q_pl:$q_pu" "$rec" 2>/dev/null; then
  trig="$q_pu"; keys="push:$q_pl:$q_pu"; what="pushed"
fi
if [ "${q_ed:-0}" -gt 0 ] && [ "${q_any:-0}" = 0 ] && ! /usr/bin/grep -aqxF first "$rec" 2>/dev/null; then
  keys="${keys:+$keys
}first"
  what="${what:+made its first change and }${what:-made its first change}"
  if [ -z "$trig" ] || [ "$q_ed" -gt "$trig" ]; then trig="$q_ed"; fi
fi
[ -n "$trig" ] || exit 0
# a chapter call after the turn's last trigger already did the job
if [ "${q_mc:-0}" != 0 ] && [ "$q_mc" -gt "$trig" ]; then exit 0; fi

# record first, and read it back; only then write the note (else a record that cannot be kept would
# note the same turn again every time)
mkdir -p "$STATE/chapters-ask" "$STATE/chapter-notes" 2>/dev/null
{ printf '%s\n' "$keys" >> "$rec"; } 2>/dev/null
ok=1
while IFS= read -r k; do /usr/bin/grep -aqxF "$k" "$rec" 2>/dev/null || ok=0; done <<EOF_K
$keys
EOF_K
if [ "$ok" != 1 ]; then
  echo "chapter-note: skipped (cannot record it under $STATE/chapters-ask)" >&2
  exit 0
fi
{ printf 'Mark a chapter: this session just %s. If this starts a new phase of work, call the chapter tool (%s) with a short title.\n' "$what" "$CT" > "$STATE/chapter-notes/$sid"; } 2>/dev/null
exit 0
