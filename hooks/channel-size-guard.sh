#!/bin/bash
# channel-size-guard.sh — PreToolUse hook on Write|Edit|MultiEdit|Bash. A shared file several
# people or sessions append to (running notes, a decision log, a changelog) grows forever
# unless something watches it. This warns once such a file crosses a "sweep it soon" band,
# and refuses further GROWTH once it crosses a hard stop — checked live, on every edit, not
# only at commit time. Shrinking edits (a sweep) always pass, even over the hard stop.
#
# Config: hooks/channel-ceiling.conf (see hooks/channel-ceiling.conf.example) — the SAME
# file git-hooks/pre-commit reads for its per-commit insertion ceiling. Each line beyond
# `LIMIT=...` is: <repo-relative glob pattern> [<unit> <band> <hard-stop>]. This guard only
# looks at the last three fields (unit is "words" or "lines"); a line with none of them just
# adds its pattern to pre-commit's list and is otherwise ignored here. Matched by BASENAME
# (a pattern's own basename, so `*/NOTES.md` still watches any `NOTES.md`), because a Write/
# Edit/MultiEdit call doesn't know the file's git-relative path and a Bash command may only
# name the file, not its full path. No conf file, or a file with no unit/band/stop columns
# at all: this guard does nothing — the safe default for a repo with no shared files.
#
# Coverage for Bash, deliberately NARROW: only growth this hook can actually SEE in the
# command text is refused —
#   - an append redirect (`>> NOTES.md`),
#   - `tee -a … NOTES.md`,
#   - `cat <one or more files> > NOTES.md` (a concatenation INTO the file).
# Everything else a shell can do to a file passes: `sed -i`, `cp`, `: >`, `dd`, a python
# `open(...)`, `cat tmp > NOTES.md`'s truncating cousins, a filename held in a variable.
# Most of those are how a SWEEP is actually written, and refusing them refused the very
# fix the guard asks for. What catches the rest is hooks/channel-size-post.sh, the
# PostToolUse companion: it re-measures the file on disk AFTER the call and says loudly
# that it is over — it cannot undo a write, but nothing gets past it unnoticed.
# The file name is matched with a word boundary on BOTH sides, so `RELEASE-NOTES.md` is
# not a `NOTES.md`.
# Write/Edit/MultiEdit are judged on the content the tool is about to write.
# Growth is measured in the band's OWN unit (words via `wc -w`, lines via `wc -l`), never
# bytes; a relative Bash path is resolved against the hook JSON's `.cwd` when given, and
# left unchecked (noted, not refused) when `.cwd` is absent, rather than refused on a guess;
# the basename compare is case-insensitive.
# Tests: hooks/test-hooks.sh (sections 22 and 29).
input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
CONF="$(dirname "$0")/channel-ceiling.conf"

bands_for() { # $1 basename -> zero or more "unit band hardstop" lines from channel-ceiling.conf
  [ -f "$CONF" ] || return
  local lb; lb="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*|LIMIT=*) continue ;; esac
    set -- $line
    local pat="$1" unit="$2" band="$3" stop="$4"
    [ -n "$unit" ] && [ -n "$band" ] && [ -n "$stop" ] || continue
    local patbase; patbase="$(printf '%s' "${pat##*/}" | tr '[:upper:]' '[:lower:]')"
    case "$lb" in $patbase) echo "$unit $band $stop" ;; esac
  done < "$CONF"
}
all_watched_basenames() { # every basename channel-ceiling.conf gives a unit/band/stop to
  [ -f "$CONF" ] || return
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*|LIMIT=*) continue ;; esac
    set -- $line
    [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ] && printf '%s\n' "${1##*/}"
  done < "$CONF" | sort -u
}
measure() { [ -f "$2" ] || { echo 0; return; }; if [ "$1" = words ]; then wc -w < "$2" | tr -d ' '; else wc -l < "$2" | tr -d ' '; fi; }
count_str() { if [ "$1" = words ]; then printf '%s' "$2" | wc -w | tr -d ' '; else printf '%s' "$2" | wc -l | tr -d ' '; fi; }
refuse() { echo "channel-size-guard: REFUSED — $1 is over its HARD STOP ($2 $3, stop $4). Only a shrinking edit (a sweep) may touch it now." >&2; exit 2; }
warn()   { echo "channel-size-guard: NOTE — $1 is over its band ($2 $3, band $4): the edit is allowed; sweep it to an archive soon." >&2; }

case "$tool" in
  Write|Edit|MultiEdit)
    f="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
    [ -z "$f" ] && exit 0
    b="$(basename "$f")"; bands="$(bands_for "$b")"
    [ -z "$bands" ] && exit 0
    # More than one band can apply to the same file (e.g. both a word count and a line
    # count) — a note or a refusal from EITHER fires.
    while IFS=' ' read -r unit band limit; do
      [ -z "$unit" ] && continue
      cur="$(measure "$unit" "$f")"
      if [ "$tool" = Write ]; then
        wnew="$(printf '%s' "$input" | jq -r '.tool_input.content' | { if [ "$unit" = words ]; then wc -w; else wc -l; fi; } | tr -d ' ')"
        # judged on the LARGER of the file's current size and the content about to be
        # written — a small write onto a big file (a genuine sweep) still passes.
        [ "$wnew" -gt "$cur" ] && cur="$wnew"
      fi
      [ "$cur" -le "$band" ] && continue
      if [ "$cur" -le "$limit" ]; then warn "$b" "$cur" "$unit" "$band"; continue; fi
      if [ "$tool" = Edit ]; then
        old_s="$(printf '%s' "$input" | jq -r '.tool_input.old_string // ""')"
        new_s="$(printf '%s' "$input" | jq -r '.tool_input.new_string // ""')"
        old_n="$(count_str "$unit" "$old_s")"; new_n="$(count_str "$unit" "$new_s")"
        [ $(( new_n - old_n )) -lt 0 ] && continue
      elif [ "$tool" = Write ]; then
        [ "$wnew" -lt "$cur" ] && continue
      elif [ "$tool" = MultiEdit ]; then
        delta=0
        while IFS= read -r ed; do
          [ -z "$ed" ] && continue
          eo="$(printf '%s' "$ed" | jq -r '.old_string // ""')"; en="$(printf '%s' "$ed" | jq -r '.new_string // ""')"
          eon="$(count_str "$unit" "$eo")"; enn="$(count_str "$unit" "$en")"
          delta=$(( delta + enn - eon ))
        done <<<"$(printf '%s' "$input" | jq -c '.tool_input.edits[]')"
        [ "$delta" -lt 0 ] && continue
      fi
      refuse "$b" "$cur" "$unit" "$limit"
    done <<<"$bands"
    exit 0 ;;
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
    names="$(all_watched_basenames)"
    [ -z "$names" ] && exit 0
    # One segment per command: a growth form only counts against the file it actually
    # writes to, so `cat NOTES.md >> other.md` reads NOTES.md and is not growth.
    segs="${cmd//&&/$'\n'}"; segs="${segs//||/$'\n'}"; segs="${segs//|/$'\n'}"; segs="${segs//;/$'\n'}"
    while IFS= read -r seg; do
      [ -z "$seg" ] && continue
      for b in $names; do
        bre="$(printf '%s' "$b" | sed 's/\./\\./g')"
        nb="(^|[^A-Za-z0-9_.-])${bre}([^A-Za-z0-9_.-]|\$)"
        target=""
        case "$seg" in
          *'>>'*) t="${seg##*>>}"
                  printf '%s' "$t" | grep -qiE "$nb" && target="$t" ;;
        esac
        if [ -z "$target" ] \
           && printf '%s' "$seg" | grep -qE '(^|[[:space:]])tee([[:space:]]|$)' \
           && printf '%s' "$seg" | grep -qE '(^|[[:space:]])-a([[:space:]]|$)' \
           && printf '%s' "$seg" | grep -qiE "$nb"; then target="$seg"; fi
        if [ -z "$target" ] \
           && printf '%s' "$seg" | grep -qE '^[[:space:]]*cat[[:space:]]+[^>[:space:]]' \
           && printf '%s' "$seg" | grep -q '>'; then
          t="${seg##*>}"
          printf '%s' "$t" | grep -qiE "$nb" && target="$t"
        fi
        [ -n "$target" ] || continue
        f="$(printf '%s' "$target" | grep -oiE "'[^']*${bre}'|\"[^\"]*${bre}\"|[^ '\"]*${bre}" | head -1 | sed -e "s/^['\"]//" -e "s/['\"]\$//")"
        [ -n "$f" ] || continue
        case "$f" in
          /*) resolved="$f" ;;
          *)
            cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
            if [ -n "$cwd" ]; then resolved="$cwd/$f"
            else
              echo "channel-size-guard: NOTE — $b's path in this Bash command ($f) is relative and no cwd was given; size not checked, allowed. hooks/channel-size-post.sh re-measures it after the write." >&2
              continue
            fi ;;
        esac
        while IFS=' ' read -r unit band limit; do
          [ -z "$unit" ] && continue
          cur="$(measure "$unit" "$resolved")"
          [ "$cur" -gt "$limit" ] && refuse "$b" "$cur" "$unit" "$limit"
          [ "$cur" -gt "$band" ] && warn "$b" "$cur" "$unit" "$band"
        done <<<"$(bands_for "$b")"
      done
    done <<<"$segs"
    ;;
esac
exit 0
