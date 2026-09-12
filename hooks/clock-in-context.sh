#!/bin/bash
# Runs on SessionStart and on EVERY user prompt (see settings.json). Never blocks anything
# — it only prints text that gets added to the model's context.
# 1. Clock: prints this machine's current date and time, so a running session can stamp
#    things with the real clock instead of assuming continuity from earlier in the chat.
# 2. THE CARD: injects hooks/owner-card.md on every prompt, so the reply format you asked
#    for stays in view even in a very long conversation — a rule stated once early on tends
#    to lose out to whatever is most recent in context.
# 3. AWAY DETECTOR: if your own last message in the transcript is older than AWAY_MINUTES
#    (default 20 minutes), you likely stepped away and did not watch the last stretch of
#    work. The hook injects a note telling the model to re-summarize what happened rather
#    than assume you saw it. Measured from YOUR last message, never from the model's own
#    reply — a model that finishes work 2 minutes ago is irrelevant if you left an hour ago.
#    Reads transcript_path from the hook's stdin JSON; missing or unparseable input simply
#    skips this block.
# No jq — bash/sed/grep only, so it runs with zero extra dependencies.
# Tests: hooks/test-hooks.sh.
input=$(cat 2>/dev/null)
printf 'Clock (this machine): %s\n' "$(date '+%Y-%m-%d %H:%M')"

AWAY_MINUTES="${AWAY_MINUTES:-20}"
# Portable ISO-8601-UTC ("YYYY-MM-DDTHH:MM:SS", no trailing Z) -> epoch seconds.
# BSD `date -j -f` (macOS) first; GNU `date -d` (Linux, no -j/-f) as the fallback —
# GNU needs the Z put back so it reads the string as UTC, same as BSD's `-u`.
to_epoch() {
  local raw="$1" e
  e=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$raw" "+%s" 2>/dev/null)
  case "$e" in ''|*[!0-9]*) e="" ;; esac
  if [ -z "$e" ]; then
    e=$(date -u -d "${raw}Z" "+%s" 2>/dev/null)
    case "$e" in ''|*[!0-9]*) e="" ;; esac
  fi
  printf '%s' "$e"
}
tp=$(printf '%s' "$input" | /usr/bin/sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
gap_min=""
if [ -n "$tp" ] && [ -f "$tp" ]; then
  # Your own messages are top-level "type":"user" lines that hold no tool_result (tool
  # results are also "user" lines and carry a promptId too, so the id cannot be the marker).
  # Timestamps are ISO-8601 UTC ("...Z"). The prompt being submitted is already in the file
  # when this hook runs, so a line under 15 s old is skipped and the gap is measured from
  # the previous message instead.
  hs=$(/usr/bin/grep -E '"type"[[:space:]]*:[[:space:]]*"user"' "$tp" 2>/dev/null | /usr/bin/grep -v '"tool_result"' \
       | /usr/bin/grep -oE '"timestamp"[[:space:]]*:[[:space:]]*"[^"]*"' | /usr/bin/sed 's/.*"\([^"]*\)"[[:space:]]*$/\1/' | cut -c1-19 | tail -2)
  n=$(printf '%s\n' "$hs" | /usr/bin/grep -c .)
  if [ "$n" -ge 1 ]; then
    newest_s=$(to_epoch "$(printf '%s\n' "$hs" | tail -1)"); now_s=$(date +%s); ref=""
    if [ -n "$newest_s" ] && [ $((now_s - newest_s)) -le 15 ]; then
      [ "$n" -ge 2 ] && ref=$(to_epoch "$(printf '%s\n' "$hs" | head -1)")
    else
      ref="$newest_s"
    fi
    [ -n "$ref" ] && gap_min=$(( (now_s - ref) / 60 ))
  fi
fi
if [ -n "$gap_min" ] && [ "$gap_min" -ge "$AWAY_MINUTES" ]; then
  printf 'YOU ARE RETURNING after %s minutes away. You did NOT watch what happened. This reply is a COLD START: summarize what the problem was in one line, whether it is fixed, and what is needed from you. No history, no "as you saw", no codes.\n' "$gap_min"
fi

# The card is ONE file so every reader sees the same text; edit it to your own taste.
CARD_FILE="${CARD_FILE:-$(dirname "$0")/owner-card.md}"
if [ -s "$CARD_FILE" ]; then
  cat "$CARD_FILE"
else
  printf 'WARNING: %s is missing or empty, so the reply-format card could not be injected. Say so at the start of the reply.\n' "$CARD_FILE"
fi
