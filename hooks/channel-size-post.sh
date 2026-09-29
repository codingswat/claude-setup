#!/bin/bash
# channel-size-post.sh — PostToolUse hook on Write|Edit|MultiEdit|Bash, the companion to
# hooks/channel-size-guard.sh (the PreToolUse half) and reading the SAME config file,
# hooks/channel-ceiling.conf.
#
# Why a second half exists. The pre hook has to judge a write BEFORE it happens, from the
# tool call alone — and a shell can grow a file in more ways than any pattern can name: a
# filename held in a variable (`f=NOTES.md; echo x >> $f`), `perl -pi`, an open file
# descriptor, `cat … > tmp && mv tmp NOTES.md`, or an Edit that replaces three words with
# one word 100,000 characters long. Rather than refuse every shell command it cannot read,
# the pre hook refuses only visible growth, and this hook MEASURES THE FILE ON DISK once
# the call is done. It cannot undo the write — a PostToolUse hook never can — but the file
# can no longer grow unnoticed, and the next visible append is refused by the pre hook.
#
# Two measures, because one is not enough:
#   - the band's own unit (words or lines), the same number the pre hook refuses on;
#   - BYTES, against a ceiling derived from that hard stop (40 bytes per word, 400 per
#     line — far more than any real prose, so it only fires on something genuinely huge).
#     A file can sit under a word ceiling and still be enormous: one 100,000-character
#     "word", a pasted base64 blob, a minified paste. A `bytes` line in the conf is used
#     as an exact ceiling if you write one.
# A conf pattern with a slash matches the file's repo-relative path, one without matches the bare
# name — the same reading as channel-size-guard.sh (A28; the header there says it in full).
# Never blocks and never changes anything. A file over its stop makes it exit 2 with the reason on
# stderr: for a PostToolUse hook Claude Code shows that to the model (the tool has already run, so
# nothing is undone or blocked) — at exit 0 the message went nowhere (refresh 2026-09-29 M6). Anything
# else, including no jq, no conf file, or no file it can resolve: silent, exit 0.
# Conf lines are split with globbing OFF (`set -f`) so `*/NOTES.md` stays a pattern (M5).
# Tests: hooks/test-hooks.sh (section 29, "attack fixes (2)" M5/M6).
set -f
WARNED=0
command -v jq >/dev/null 2>&1 || exit 0
input="$(cat 2>/dev/null)"; [ -z "$input" ] && exit 0
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
CONF="$(dirname "$0")/channel-ceiling.conf"
[ -f "$CONF" ] || exit 0

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
rel_path() { # $1 file path -> its repo-relative path (lower-cased), or nothing when it is not inside a git work tree
  local d top base
  d="$(dirname "$1")"; d="$(cd "$d" 2>/dev/null && pwd -P)" || return 0
  top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$top" ] || return 0
  top="$(cd "$top" 2>/dev/null && pwd -P)" || return 0
  base="$(basename "$1")"
  lower "${d#"$top"}/$base" | sed 's#^/##'
}
bands_for() { # $1 basename, $2 (optional) full path -> zero or more "unit band hardstop" lines
  [ -f "$CONF" ] || return
  local lb full="$2" rel="" relset=0; lb="$(lower "$1")"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*|LIMIT=*) continue ;; esac
    set -- $line
    local pat="$1" unit="$2" band="$3" stop="$4"
    [ -n "$unit" ] && [ -n "$band" ] && [ -n "$stop" ] || continue
    local lp; lp="$(lower "$pat")"
    case "$lp" in
      */*)
        if [ "$relset" = 0 ]; then rel=""; [ -n "$full" ] && rel="$(rel_path "$full")"; relset=1; fi
        if [ -n "$rel" ]; then case "$rel" in $lp) echo "$unit $band $stop" ;; esac
        else case "$lb" in ${lp##*/}) echo "$unit $band $stop" ;; esac; fi ;;
      *) case "$lb" in $lp) echo "$unit $band $stop" ;; esac ;;
    esac
  done < "$CONF"
}
all_watched_basenames() {
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*|LIMIT=*) continue ;; esac
    set -- $line
    [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ] && printf '%s\n' "${1##*/}"
  done < "$CONF" | sort -u
}
measure() { # unit file
  [ -f "$2" ] || { echo 0; return; }
  case "$1" in
    words) wc -w < "$2" | tr -d ' ' ;;
    lines) wc -l < "$2" | tr -d ' ' ;;
    bytes) wc -c < "$2" | tr -d ' ' ;;
    *)     echo 0 ;;
  esac
}
byte_ceiling() { # unit stop -> the derived byte ceiling for that band
  case "$1" in
    words) echo $(( $2 * 40 )) ;;
    lines) echo $(( $2 * 400 )) ;;
    bytes) echo "$2" ;;
    *)     echo 0 ;;
  esac
}
loud() { # file current unit stop band
  echo "channel-size-guard (after the write): WARNING — $1 is now $2 $3, over its HARD STOP ($4 $3). This hook runs AFTER the write, so nothing was undone: sweep it down to $5 $3 now (move the resolved entries to an archive). Until you do, the next visible append to it is refused." >&2
  WARNED=1
}
loud_bytes() { # file bytes ceiling unit stop
  echo "channel-size-guard (after the write): WARNING — $1 is now $2 bytes, over the byte ceiling ($3, derived from its $5-$4 hard stop). A file can sit under a word count and still be enormous — one huge 'word', a pasted blob. Sweep it now; this hook runs after the write and undoes nothing." >&2
  WARNED=1
}

check_file() { # absolute or cwd-relative path
  local f="$1" b cur stop bc
  [ -n "$f" ] || return
  [ -f "$f" ] || return
  b="$(basename "$f")"
  while IFS=' ' read -r unit band stop; do
    [ -z "$unit" ] && continue
    cur="$(measure "$unit" "$f")"
    [ "$cur" -gt "$stop" ] && loud "$b" "$cur" "$unit" "$stop" "$band"
    bc="$(byte_ceiling "$unit" "$stop")"
    if [ "$bc" -gt 0 ] && [ "$unit" != bytes ]; then
      cur="$(measure bytes "$f")"
      [ "$cur" -gt "$bc" ] && loud_bytes "$b" "$cur" "$bc" "$stop" "$unit"
    fi
  done <<<"$(bands_for "$b" "$f")"
}

case "$tool" in
  Write|Edit|MultiEdit)
    check_file "$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')" ;;
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
    names="$(all_watched_basenames)"
    [ -z "$names" ] && exit 0
    for b in $names; do
      bre="$(printf '%s' "$b" | sed 's/\./\\./g')"
      printf '%s' "$cmd" | grep -qiE "(^|[^A-Za-z0-9_.-])${bre}([^A-Za-z0-9_.-]|\$)" || continue
      # Every spelling of the name in the command is measured: a `mv tmp NOTES.md` and a
      # `cp NOTES.md sub/NOTES.md` both name a file worth re-measuring. The plain name in
      # the working folder is always measured too, because the command may only have named
      # it through a variable (`f=NOTES.md; echo x >> $f`) and the path it wrote cannot be
      # recovered from the text.
      cands="$(printf '%s' "$cmd" | grep -oiE "'[^']*${bre}'|\"[^\"]*${bre}\"|[^ '\"=><|;&]*${bre}")"
      [ -n "$cwd" ] && cands="$cands
$b"
      resolved=""
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        f="$(printf '%s' "$f" | sed -e "s/^['\"]//" -e "s/['\"]\$//")"
        case "$f" in
          /*) resolved="$resolved$f
" ;;
          *)  [ -n "$cwd" ] && resolved="$resolved$cwd/$f
" ;;
        esac
      done <<<"$cands"
      while IFS= read -r f; do
        [ -n "$f" ] && check_file "$f"
      done <<<"$(printf '%s' "$resolved" | sort -u)"
    done ;;
esac
[ "$WARNED" = 1 ] && exit 2
exit 0
