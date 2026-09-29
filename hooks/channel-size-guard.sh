#!/bin/bash
# channel-size-guard.sh — PreToolUse hook on Write|Edit|MultiEdit|Bash. A shared file several
# people or sessions append to (running notes, a decision log, a changelog) grows forever
# unless something watches it. This refuses further GROWTH once such a file crosses a hard
# stop — checked live, on every edit, not only at commit time. Shrinking edits (a sweep)
# always pass, even over the hard stop. It prints NOTHING while an edit is allowed: stderr on
# an exit-0 hook is not something the model reads, so a "you are over the band" note went
# nowhere (refresh 2026-09-29 A29; channel-size-post.sh's warning therefore exits 2 with its
# reason on stderr, which Claude Code shows the model after the tool has run). The conf's `band` column is
# still the SWEEP-DOWN TARGET the post hook's message names, and an edit that ends at or
# under the band always passes.
#
# Config: hooks/channel-ceiling.conf (see hooks/channel-ceiling.conf.example) — the SAME
# file git-hooks/pre-commit reads for its per-commit insertion ceiling. Each line beyond
# `LIMIT=...` is: <repo-relative glob pattern> [<unit> <band> <hard-stop>]. This guard only
# looks at the last three fields (unit is "words" or "lines"); a line with none of them just
# adds its pattern to pre-commit's list and is otherwise ignored here. A pattern WITHOUT a
# slash matches by BASENAME (`NOTES.md` watches any file called NOTES.md). A pattern WITH a
# slash matches the file's REPO-RELATIVE path (`docs/plans/NOTES.md` watches that file only,
# `*/NOTES.md` any nested one) — the same reading hooks/provenance.py gives a pattern.
# Where the file is not inside a git work tree there is no repo path to compare, so the bare
# file name is tried against the pattern's own basename instead (refresh 2026-09-29 A28).
# No conf file, or a file with no unit/band/stop columns at all: this guard does nothing —
# the safe default for a repo with no shared files.
#
# Coverage for Bash, deliberately NARROW: only growth this hook can actually SEE in the
# command text is refused —
#   - an append redirect (`>> NOTES.md`),
#   - `tee -a … NOTES.md`,
#   - `cat <one or more files> > NOTES.md` (a concatenation INTO the file),
#   - a python `open('NOTES.md','a')` anywhere in the command, a heredoc body included
#     (refresh 2026-09-29 A26, the one form the live setup also refuses that is pure growth).
# Everything else a shell can do to a file passes: `sed -i`, `cp`, `: >`, `dd`, a python
# `open(...,'w')`, `cat tmp > NOTES.md`'s truncating cousins, a filename held in a variable.
# (The live setup also judges `>` heredocs, `tee` without -a, `sed -i`, `cp` and `dd of=`;
# those are NOT ported: each can be a sweep, and section 29's M8 cases pin them as allowed.)
# When a command names several files, the target is the first token whose BASENAME is the
# watched name — `tee -a proof-notes.md NOTES.md` judges NOTES.md (A27).
# Most of those are how a SWEEP is actually written, and refusing them refused the very
# fix the guard asks for. What catches the rest is hooks/channel-size-post.sh, the
# PostToolUse companion: it re-measures the file on disk AFTER the call and says loudly
# that it is over — it cannot undo a write, but nothing gets past it unnoticed.
# The file name is matched with a word boundary on BOTH sides, so `RELEASE-NOTES.md` is
# not a `NOTES.md`.
# Write/Edit/MultiEdit are judged on the content the tool is about to write: a Write on
# the larger of the file and its new content, an Edit/MultiEdit on the file's current size
# PLUS the call's own delta (new minus old, summed across a MultiEdit's edits) — what the
# file will hold after the call, never what it holds now.
# Growth is measured in the band's OWN unit — words via `wc -w`, lines via `wc -l`, bytes
# via `wc -c` (a `bytes` band is the exact ceiling hooks/channel-size-post.sh also reads;
# without one it derives a generous byte bound from the words/lines stop); a relative Bash path is resolved against the hook JSON's `.cwd` when given, and
# left unchecked (noted, not refused) when `.cwd` is absent, rather than refused on a guess;
# the basename compare is case-insensitive.
# Cost: a Bash command is judged once, not once per line — a command that names no watched file
# is let through after ONE grep, and a segment with no `>` or `tee` is skipped without spawning
# anything (a 1,500-line heredoc used to cost minutes). Tests: "attack fixes (2)" M12.
# Conf lines are split with globbing OFF (`set -f`): a pattern like `*/NOTES.md` must reach the
# case-match below as text, never be expanded against the folder the hook runs in. Tests: M5.
# Tests: hooks/test-hooks.sh (sections 22 and 29).
set -f
input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
CONF="$(dirname "$0")/channel-ceiling.conf"

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
bands_for() { # $1 basename, $2 (optional) full path -> zero or more "unit band hardstop" lines from channel-ceiling.conf
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
all_watched_basenames() { # every basename channel-ceiling.conf gives a unit/band/stop to
  [ -f "$CONF" ] || return
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*|LIMIT=*) continue ;; esac
    set -- $line
    [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ] && printf '%s\n' "${1##*/}"
  done < "$CONF" | sort -u
}
# A band names its own unit: words, lines, or bytes. `bytes` used to fall through to the
# line count here, so a byte hard stop measured the wrong quantity and never refused —
# hooks/channel-size-post.sh honoured it and this hook did not.
measure() { [ -f "$2" ] || { echo 0; return; }
  case "$1" in words) wc -w < "$2" | tr -d ' ' ;; bytes) wc -c < "$2" | tr -d ' ' ;; *) wc -l < "$2" | tr -d ' ' ;; esac; }
count_str() { case "$1" in
    words) printf '%s' "$2" | wc -w | tr -d ' ' ;;
    bytes) printf '%s' "$2" | wc -c | tr -d ' ' ;;
    *)     printf '%s' "$2" | wc -l | tr -d ' ' ;; esac; }
refuse() { echo "channel-size-guard: REFUSED — $1 is over its HARD STOP ($2 $3, stop $4). Only a shrinking edit (a sweep) may touch it now." >&2; exit 2; }

case "$tool" in
  Write|Edit|MultiEdit)
    f="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
    [ -z "$f" ] && exit 0
    b="$(basename "$f")"; bands="$(bands_for "$b" "$f")"
    [ -z "$bands" ] && exit 0
    # More than one band can apply to the same file (e.g. both a word count and a line
    # count) — a refusal from EITHER fires.
    while IFS=' ' read -r unit band limit; do
      [ -z "$unit" ] && continue
      cur="$(measure "$unit" "$f")"
      # An Edit/MultiEdit's own DELTA, in the band's unit. It is worked out BEFORE the
      # band and stop compare, because those must judge what the file will hold AFTER the
      # call: comparing the file's CURRENT size alone made a 601-byte insertion into a
      # 1500-byte file with a 2000-byte stop a mere warning, and the file landed at 2100 —
      # past the stop the guard exists to hold.
      delta=0
      if [ "$tool" = Edit ]; then
        old_s="$(printf '%s' "$input" | jq -r '.tool_input.old_string // ""')"
        new_s="$(printf '%s' "$input" | jq -r '.tool_input.new_string // ""')"
        delta=$(( $(count_str "$unit" "$new_s") - $(count_str "$unit" "$old_s") ))
      elif [ "$tool" = MultiEdit ]; then
        while IFS= read -r ed; do
          [ -z "$ed" ] && continue
          eo="$(printf '%s' "$ed" | jq -r '.old_string // ""')"; en="$(printf '%s' "$ed" | jq -r '.new_string // ""')"
          eon="$(count_str "$unit" "$eo")"; enn="$(count_str "$unit" "$en")"
          delta=$(( delta + enn - eon ))
        done <<<"$(printf '%s' "$input" | jq -c '.tool_input.edits[]')"
      fi
      proj="$cur"
      if [ "$tool" = Write ]; then
        # if/elif, not a case: bash 3.2 (the macOS system bash) misparses a case pattern
        # inside $( … ) and the count came back as the script text itself.
        wnew="$(printf '%s' "$input" | jq -r '.tool_input.content' | { if [ "$unit" = words ]; then wc -w; elif [ "$unit" = bytes ]; then wc -c; else wc -l; fi; } | tr -d ' ')"
        # judged on the LARGER of the file's current size and the content about to be
        # written — a small write onto a big file (a genuine sweep) still passes.
        [ "$wnew" -gt "$cur" ] && proj="$wnew"
      elif [ "$delta" -gt 0 ]; then
        proj=$(( cur + delta ))
      fi
      [ "$proj" -le "$band" ] && continue
      [ "$proj" -le "$limit" ] && continue   # over the band, under the hard stop: allowed, and silent (A29)
      if [ "$tool" = Write ]; then
        [ "$wnew" -lt "$proj" ] && continue
      else
        [ "$delta" -lt 0 ] && continue
      fi
      refuse "$b" "$proj" "$unit" "$limit"
    done <<<"$bands"
    exit 0 ;;
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
    names="$(all_watched_basenames)"
    [ -z "$names" ] && exit 0
    # One grep for the whole command: no watched name anywhere in it means nothing below can fire.
    names_re="$(printf '%s' "$names" | sed 's/\./\\./g' | paste -sd'|' -)"
    printf '%s' "$cmd" | grep -qiE "$names_re" || exit 0
    # judge <watched basename> <text that holds the target's name>: the target is the first
    # token whose BASENAME is the watched name (a whole name: not `proof-notes.md`, not
    # `NOTES.md.bak` — A27); resolved against the hook JSON's .cwd when relative; refused when
    # the file is over its hard stop. Growth is judged on the file's current size.
    judge() {
      local b="$1" text="$2" bre lb f cand resolved cwd unit band limit cur
      bre="$(printf '%s' "$b" | sed 's/\./\\./g')"; lb="$(lower "$b")"
      f=""
      while IFS= read -r cand; do
        cand="$(printf '%s' "$cand" | sed -e "s/^['\"]//" -e "s/['\"]\$//")"
        [ "$(lower "$(basename "$cand")")" = "$lb" ] && { f="$cand"; break; }
      done <<<"$(printf '%s' "$text" | grep -oiE "'[^']*${bre}[^']*'|\"[^\"]*${bre}[^\"]*\""; printf '%s' "$text" | grep -oiE "[^ '\"<>=(),\`]*${bre}[^ '\"<>=(),\`]*")"
      [ -n "$f" ] || return 0
      case "$f" in
        /*) resolved="$f" ;;
        *)
          cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
          if [ -n "$cwd" ]; then resolved="$cwd/$f"
          else
            echo "channel-size-guard: NOTE — $b's path in this Bash command ($f) is relative and no cwd was given; size not checked, allowed. hooks/channel-size-post.sh re-measures it after the write." >&2
            return 0
          fi ;;
      esac
      while IFS=' ' read -r unit band limit; do
        [ -z "$unit" ] && continue
        cur="$(measure "$unit" "$resolved")"
        [ "$cur" -gt "$limit" ] && refuse "$b" "$cur" "$unit" "$limit"
      done <<<"$(bands_for "$b" "$resolved")"
      return 0
    }
    # A26: a python open(<name>, 'a') anywhere in the command (a heredoc body is part of the same
    # string) is an append the segment split below cannot see, since a heredoc holds `;` and `|`.
    if printf '%s' "$cmd" | grep -qiE 'python[0-9.]*[[:space:]]' && printf '%s' "$cmd" | grep -q 'open(' \
       && printf '%s' "$cmd" | grep -qE "['\"]a['\"]"; then
      for b in $names; do
        bre="$(printf '%s' "$b" | sed 's/\./\\./g')"
        printf '%s' "$cmd" | grep -qiE "(^|[^A-Za-z0-9_.-])${bre}([^A-Za-z0-9_.-]|\$)" && judge "$b" "$cmd"
      done
    fi
    # One segment per command: a growth form only counts against the file it actually
    # writes to, so `cat NOTES.md >> other.md` reads NOTES.md and is not growth.
    segs="${cmd//&&/$'\n'}"; segs="${segs//||/$'\n'}"; segs="${segs//|/$'\n'}"; segs="${segs//;/$'\n'}"
    while IFS= read -r seg; do
      [ -z "$seg" ] && continue
      # every growth form below needs a `>` or a `tee`; skip the rest with no process spawned
      case "$seg" in *'>'*|*tee*) ;; *) continue ;; esac
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
        judge "$b" "$target"
      done
    done <<<"$segs"
    ;;
esac
exit 0
