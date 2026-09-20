#!/bin/bash
# doorman.sh — UserPromptSubmit hook, paired with stop-state-check.sh (same
# hooks/state-check.conf). Refuses a new prompt (exit 2; the prompt text saved to the
# role's inbox) when:
#   - stop-state-check.sh already marked this session RETIRED at its context floor, or
#   - the session has been idle DOORMAN_IDLE_MIN minutes or more (default 40) AND its
#     context is DOORMAN_CTX_K thousand tokens or more (default 200).
# "Idle" is measured from the newest transcript line on EITHER side, not just the human's:
# a session that is still working — still producing assistant messages — must never refuse
# the next prompt just because the person reading along has been quiet. Only a session that
# has ITSELF gone quiet, as well as the person, counts as idle.
# A prompt beginning "wake anyway" always passes, forcing this session open regardless.
#
# Applies only when the session's working-directory basename matches a line in
# hooks/state-check.conf (role = the name that line gives it). No conf file, or no match:
# inert — the safe default for a single-session project with no roles to track.
# Fails OPEN with a log line when the transcript cannot be read — a cost guard, not a
# safety guard.
#
# Config: hooks/state-check.conf (see hooks/state-check.conf.example; shared with
# stop-state-check.sh). Test seam: STATE_CHECK_STATE_DIR (where retired/ and inbox/ live),
# DOORMAN_NOW (epoch seconds), DOORMAN_IDLE_MIN, DOORMAN_CTX_K.
# Tests: hooks/test-hooks.sh.
input=$(cat 2>/dev/null); [ -z "$input" ] && exit 0
field() { printf '%s' "$input" | /usr/bin/sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
tp=$(field transcript_path); cwd=$(field cwd); sid=$(field session_id)
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd="$PWD"
base=$(basename "$cwd")

# ---- role lookup (hooks/state-check.conf; see .conf.example — shared with stop-state-check.sh) ----
CONF="$(dirname "$0")/state-check.conf"
role=""
if [ -f "$CONF" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*|STATE_FILE\ *) continue;; esac
    set -- $line
    pat="$1"; r="$2"
    [ -n "$pat" ] && [ -n "$r" ] || continue
    case "$base" in $pat) role="$r"; break;; esac
  done < "$CONF"
fi
[ -n "$role" ] || exit 0   # no config, or this folder matches nothing in it: inert

STATE="${STATE_CHECK_STATE_DIR:-$HOME/.claude/state/state-check}"
IDLE_MIN="${DOORMAN_IDLE_MIN:-40}"; CTX_K="${DOORMAN_CTX_K:-200}"
now_s="${DOORMAN_NOW:-$(date +%s)}"
if printf '%s' "$prompt" | grep -qiE '^[[:space:]]*wake anyway'; then exit 0; fi
refuse() {
  mkdir -p "$STATE/inbox"
  printf '\n## %s — to the %s (session %s; %s)\n\n%s\n' "$(date '+%Y-%m-%d %H:%M')" "$role" "${sid:-?}" "$1" "$prompt" >> "$STATE/inbox/$role.md"
  printf 'DOORMAN: this %s is %s. Your message is saved in %s/inbox/%s.md. Open a fresh %s; to force this one, start the message with "wake anyway".\n' "$role" "$1" "$STATE" "$role" "$role" >&2
  exit 2
}
if [ -n "$sid" ] && [ -e "$STATE/retired/$sid" ]; then refuse "marked RETIRED at its context floor ($(head -1 "$STATE/retired/$sid" 2>/dev/null))"; fi
if [ -z "$tp" ] || [ ! -r "$tp" ]; then echo "doorman: no readable transcript — passing (fail open)"; exit 0; fi
ctx_line=$(/usr/bin/tail -c 200000 "$tp" | /usr/bin/grep -E '"type"[[:space:]]*:[[:space:]]*"assistant"' | /usr/bin/grep 'cache_read_input_tokens' | /usr/bin/tail -1)
ctx_k=0
if [ -n "$ctx_line" ]; then
  cf() { printf '%s' "$ctx_line" | /usr/bin/grep -oE "\"$1\"[[:space:]]*:[[:space:]]*[0-9]+" | /usr/bin/tail -1 | /usr/bin/sed -E 's/.*:[[:space:]]*([0-9]+)/\1/'; }
  ci=$(cf input_tokens); cc=$(cf cache_creation_input_tokens); cr=$(cf cache_read_input_tokens)
  ctx_k=$(( (${ci:-0} + ${cc:-0} + ${cr:-0} + 500) / 1000 ))
fi
to_epoch() { local e; e=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$1" "+%s" 2>/dev/null); case "$e" in ''|*[!0-9]*) printf '' ;; *) printf '%s' "$e" ;; esac; }
hs=$(/usr/bin/grep -E '"type"[[:space:]]*:[[:space:]]*"user"' "$tp" | /usr/bin/grep -v '"tool_result"' | /usr/bin/grep -oE '"timestamp"[[:space:]]*:[[:space:]]*"[^"]*"' | /usr/bin/sed 's/.*"\([^"]*\)"[[:space:]]*$/\1/' | cut -c1-19 | tail -2)
n=$(printf '%s\n' "$hs" | /usr/bin/grep -c .); gap_min=""
if [ "$n" -ge 1 ]; then
  newest_s=$(to_epoch "$(printf '%s\n' "$hs" | tail -1)"); ref=""
  # The newest "user" line may just be the prompt now being submitted — within 15s of
  # "now" — in which case the PREVIOUS one is the real reference point for idle time.
  if [ -n "$newest_s" ] && [ $((now_s - newest_s)) -le 15 ]; then [ "$n" -ge 2 ] && ref=$(to_epoch "$(printf '%s\n' "$hs" | head -1)"); else ref="$newest_s"; fi
  [ -n "$ref" ] && gap_min=$(( (now_s - ref) / 60 ))
fi
# The caution: idle is the gap since the newest line of EITHER side. A session still
# producing assistant messages is not idle just because the human has been silent.
as_line=$(/usr/bin/grep -E '"type"[[:space:]]*:[[:space:]]*"assistant"' "$tp" | /usr/bin/grep -oE '"timestamp"[[:space:]]*:[[:space:]]*"[^"]*"' | /usr/bin/sed 's/.*"\([^"]*\)"[[:space:]]*$/\1/' | cut -c1-19 | tail -1)
assistant_gap_min=""
if [ -n "$as_line" ]; then
  as_s=$(to_epoch "$as_line")
  [ -n "$as_s" ] && assistant_gap_min=$(( (now_s - as_s) / 60 ))
fi
if [ -n "$gap_min" ] && [ "$gap_min" -ge "$IDLE_MIN" ] && [ "$ctx_k" -ge "$CTX_K" ]; then
  if [ -z "$assistant_gap_min" ] || [ "$assistant_gap_min" -ge "$IDLE_MIN" ]; then
    refuse "stale and heavy (idle $gap_min min, context ${ctx_k}k)"
  fi
fi
exit 0
