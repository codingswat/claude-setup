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
#                           file, or `tee`) or made a `git commit`, and the session has never called
#                           the chapter tool; or
#                       (b) ran `git push` (not --dry-run, -n, --help; not one whose tool result is an
#                           error or says "rejected").
#                     No note when a chapter-tool call comes after the turn's last trigger.
#   UserPromptSubmit  prints a waiting note once on stdout (so it reaches the model with your next
#                     message) and removes it. A link is never read.
# What counts as a command: `git` at a command start (line start, after ; & | ( && ||, after
# if/then/elif/else/do/while/until, inside bash|sh|zsh -c "..."), global options (-C dir, -c k=v,
# --no-pager ...) allowed before the verb. A git word inside quotes, a heredoc body or a commit
# message never counts. Not covered: eval, xargs, a function wrapper, a variable as the command,
# env/time/nice prefixes, { ...; } groups.
# The same trigger never gives two notes: $STATE/chapters-ask/<session_id> records "first" and
# "push:<prompt line>:<push line>", written and read back BEFORE the note is written.
# FAILS OPEN everywhere: no input, no session id (or one holding / or ..), no transcript, a link or
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

# One awk pass over the transcript. It prints five transcript line numbers (0 = none):
#   <last typed prompt> <last chapter-tool call of the turn> <last counted push of the turn>
#   <last change of the turn> <any chapter-tool call at all, in the part read>
# Only the Bash tool input's "command" is read. A push whose tool_result is an error or says
# "rejected]" does not count.
awk_prog='
function endswith(s, t) { return length(s) >= length(t) && substr(s, length(s) - length(t) + 1) == t }
function unesc(v) {
  gsub(/\\\\/, "\001", v); gsub(/\\n/, "\n", v); gsub(/\\t/, "\t", v); gsub(/\\r/, "", v); gsub(/\\"/, "\"", v)
  return v
}
function nohd(t,   n, a, i, o, tag, m, pre) {   # drop heredoc bodies
  n = split(t, a, "\n"); o = ""; tag = ""
  for (i = 1; i <= n; i++) {
    if (tag != "") { if (a[i] ~ ("^[ \t]*" tag "[ \t]*$")) tag = ""; continue }
    o = o a[i] "\n"
    if (match(a[i], /<<-?[ \t]*["\047\\]?[A-Za-z_][A-Za-z0-9_]*/)) {
      pre = (RSTART > 1) ? substr(a[i], RSTART - 1, 1) : ""
      if (pre != "<") { m = substr(a[i], RSTART, RLENGTH); sub(/^<<-?[ \t]*["\047\\]?/, "", m); tag = m }
    }
  }
  return o
}
function gitcmd(t, verb, skipdry,   re, c, seg, k) {   # is there a `git ... <verb>` at a command start?
  re = "(^|[;&|(])[[:space:]]*(" KW "[[:space:]]+)*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(/[^[:space:]]*/)?git[[:space:]]+(" OPT "[[:space:]]+)*" verb
  while (match(t, re)) {
    c = substr(t, RSTART + RLENGTH, 1); seg = substr(t, RSTART + RLENGTH + 1); t = seg
    if (c ~ /[A-Za-z0-9_-]/) continue
    if (skipdry) {
      k = match(seg, /[;&|]/); if (k > 0) seg = substr(seg, 1, k - 1)
      seg = c seg
      if (seg ~ /(^|[[:space:]])(--dry-run|--help)([[:space:]=]|$)/ || seg ~ /(^|[[:space:]])-[A-Za-z]*n[A-Za-z]*([[:space:]]|$)/) continue
    }
    return 1
  }
  return 0
}
# one left-to-right quote strip: a double-quoted string may hold a backslash-escaped character (the
# backslash is \001 by now), so an escaped quote does not end it; a single-quoted one holds none
function stripq(t) { gsub(/"([^"\001]|\001.)*"|\047[^\047]*\047/, "Q", t); return t }
# `bash|sh|zsh [-opts] -c "body"` at a command start runs its body: the body replaces the wrapper
function unwrap(t,   re, n, b, pre, post) {
  re = "(^|[;&|(\n])[[:space:]]*(/[^[:space:]]*/)?(bash|sh|zsh)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*c[[:space:]]+(\"([^\"\001]|\001.)*\"|\047[^\047]*\047)"
  for (n = 0; n < 6 && match(t, re); n++) {
    b = substr(t, RSTART, RLENGTH); pre = substr(t, 1, RSTART - 1); post = substr(t, RSTART + RLENGTH)
    sub(/^[^"\047]*[ \t]-[A-Za-z]*c[ \t]+/, "", b)
    if (substr(b, 1, 1) == "\"") { b = substr(b, 2, length(b) - 2); gsub(/\001"/, "\"", b); gsub(/\001\$/, "$", b) } else b = substr(b, 2, length(b) - 2)
    t = pre ";" b ";" post
  }
  return t
}
function bashedit(t,   u) {   # sed -i, tee, or a > / >> redirect to a file (not /dev/null)
  u = stripq(t); gsub(/\001/, "_", u); gsub(/[0-9&]?>>?[ \t]*\/dev\/null/, "", u)
  if (u ~ /(^|[[:space:];&|(])sed[[:space:]]+([^;&|]*[[:space:]])?(-[A-Za-z]*i|--in-place)/) return 1
  if (u ~ /(^|[[:space:];&|(])tee([[:space:]]|$)/) return 1
  if (u ~ /(^|[^0-9&>])>>?[[:space:]]*[^[:space:]&>]/) return 1
  return 0
}
BEGIN {
  Q1 = "\"[^\"]*\""; Q2 = "\047[^\047]*\047"; ARG = "(" Q1 "|" Q2 "|[^[:space:]]+)"
  OPT = "(-C[[:space:]]+" ARG "|-c[[:space:]]+" ARG "|-[Pp]|--[A-Za-z-]+(=" ARG ")?)"
  KW = "(if|then|elif|else|do|while|until)"
  PRE = "\"type\"[[:space:]]*:[[:space:]]*\"user\".*\"origin\"[[:space:]]*:[[:space:]]*\\{[[:space:]]*\"kind\"[[:space:]]*:[[:space:]]*\"(human|peer)\""
}
{
  line = $0
  if (part && NR == 1) next   # a window cut from the middle of the file starts inside a line
  if (index(line, "\"origin\"") && line ~ PRE) { pl = NR; mc = 0; ed = 0; pn = 0; delete pushes; delete bad; delete seen; cur = ""; curpush = 0; next }
  if (index(line, "\"tool_result\"")) {
    if (pl && (line ~ /"is_error"[[:space:]]*:[[:space:]]*true/ || index(line, "rejected]"))) {
      tid = ""; if (match(line, /"tool_use_id"[[:space:]]*:[[:space:]]*"[^"]*"/)) { tid = substr(line, RSTART, RLENGTH); sub(/^"tool_use_id"[[:space:]]*:[[:space:]]*"/, "", tid); sub(/"$/, "", tid) }
      if (tid in pushes) bad[pushes[tid]] = 1
      else if (!(tid in seen) && curpush) bad[cur] = 1
    }
    next
  }
  if (!index(line, "\"tool_use\"")) next
  if (!match(line, /"type"[[:space:]]*:[[:space:]]*"tool_use"/)) next
  s = substr(line, RSTART); nm = ""; id = ""
  if (match(s, /"name"[[:space:]]*:[[:space:]]*"[^"]*"/)) { nm = substr(s, RSTART, RLENGTH); sub(/^"name"[[:space:]]*:[[:space:]]*"/, "", nm); sub(/"$/, "", nm) }
  if (match(s, /"id"[[:space:]]*:[[:space:]]*"[^"]*"/)) { id = substr(s, RSTART, RLENGTH); sub(/^"id"[[:space:]]*:[[:space:]]*"/, "", id); sub(/"$/, "", id) }
  if (id != "") seen[id] = 1
  cur = NR; curpush = 0
  if (endswith(nm, CT)) { any = 1; if (pl) mc = NR; next }
  if (!pl) next
  if (nm == "Edit" || nm == "Write" || nm == "MultiEdit" || nm == "NotebookEdit") { ed = NR; next }
  if (nm == "Bash") {
    if (!match(s, /"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"/)) next
    cmd = substr(s, RSTART, RLENGTH); sub(/^"command"[[:space:]]*:[[:space:]]*"/, "", cmd); sub(/"$/, "", cmd)
    cmd = nohd(unesc(cmd)); gsub(/\001[ \t]*\n/, " ", cmd)
    if (bashedit(cmd)) ed = NR
    cmd = stripq(unwrap(cmd)); gsub(/\001/, "_", cmd); gsub(/\n/, ";", cmd)
    if (gitcmd(cmd, "commit", 0)) ed = NR
    if (gitcmd(cmd, "push", 1)) { pn++; pl_at[pn] = NR; curpush = 1; if (id != "") pushes[id] = NR }
  }
}
END {
  pu = 0
  for (k = pn; k >= 1; k--) if (!(pl_at[k] in bad)) { pu = pl_at[k]; break }
  off = total - NR   # a window numbers its lines from 1: shift to whole-file numbers so the record keys never move
  print (pl ? pl + off : 0), (mc ? mc + off : 0), (pu ? pu + off : 0), (ed ? ed + off : 0), any + 0
}'

# Read only the CURRENT turn: the file last 1 MB, then 8 MB, then 64 MB, then the whole file, stopping at the
# first window that holds the last typed prompt.
size=$(/usr/bin/wc -c < "$tp" 2>/dev/null | tr -d ' '); total=$(/usr/bin/wc -l < "$tp" 2>/dev/null | tr -d ' ')
[ -n "$(/usr/bin/tail -c 1 "$tp" 2>/dev/null)" ] && total=$((${total:-0} + 1))
out=""
for win in 1048576 8388608 67108864 0; do
  if [ "$win" = 0 ] || [ "${size:-0}" -le "$win" ]; then
    out=$(LC_ALL=C /usr/bin/awk -v part=0 -v total="${total:-0}" -v CT="$CT" "$awk_prog" < "$tp" 2>/dev/null); break
  fi
  out=$(/usr/bin/tail -c "$win" "$tp" 2>/dev/null | LC_ALL=C /usr/bin/awk -v part=1 -v total="${total:-0}" -v CT="$CT" "$awk_prog" 2>/dev/null)
  [ "${out%% *}" != 0 ] && [ -n "$out" ] && break
done
read -r q_pl q_mc q_pu q_ed q_any <<< "$out"
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
