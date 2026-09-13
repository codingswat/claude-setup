#!/bin/bash
# Runs on SessionStart and on EVERY user prompt (see settings.json). Never blocks anything
# — it only prints text that gets added to the model's context.
# 1. Clock: prints this machine's current date and time, in 12-hour form with the 24-hour
#    form beside it "for file entries" (a file entry that carries a time — a note, a log
#    line — is stamped in the unambiguous 24-hour form; the 12-hour form is just for a
#    human glancing at the reply).
# 2. THE CARD, injected only when it matters: on SessionStart, on a turn where the away
#    detector below fires (you're returning after a gap), or with CARD_ALWAYS=1 (an escape
#    hatch back to the old every-turn behaviour). Every other prompt gets ONE reminder line
#    instead of the full card — a quick reply is one line then "Needs my input", and the
#    full card is for a decision, a closed task, or a returning you. `hook_event_name` on
#    the hook's stdin JSON ("SessionStart" / "UserPromptSubmit" / ...) is a real field on
#    every hook call.
# 3. AWAY DETECTOR: if your own last message in the transcript is older than AWAY_MINUTES
#    (default 20 minutes), you likely stepped away and did not watch the last stretch of
#    work. The hook injects a note telling the model to re-summarize what happened rather
#    than assume you saw it. Measured from YOUR last message, never from the model's own
#    reply — a model that finishes work 2 minutes ago is irrelevant if you left an hour ago.
#    Reads transcript_path from the hook's stdin JSON; missing or unparseable input simply
#    skips this block.
# 4. CONTEXT LINE: a rough "Context used: Nk tokens" line, so a long session can see how
#    close it is to needing a hand-off. N = (cache_read + cache_creation + input tokens) of
#    the LAST assistant transcript line that carries a usage block, divided by 1000 and
#    rounded. Silent with no transcript, an unreadable one, or no assistant usage line —
#    never blocks, never writes to stderr.
# No jq — bash/sed/grep only, so it runs with zero extra dependencies.
# Tests: hooks/test-hooks.sh.
input=$(cat 2>/dev/null)
tp=$(printf '%s' "$input" | /usr/bin/sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
event=$(printf '%s' "$input" | /usr/bin/sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
printf 'Clock (this machine): %s (%s for file entries)\n' "$(date '+%Y-%m-%d %l:%M %p' | tr -s ' ')" "$(date '+%H:%M')"

# Context line: the last assistant usage block in the transcript, if there is one.
# `tail -c 200000` keeps the cost to one small pipeline even on a multi-megabyte transcript.
if [ -n "$tp" ] && [ -r "$tp" ]; then
  ctx_line=$(/usr/bin/tail -c 200000 "$tp" 2>/dev/null \
    | /usr/bin/grep -E '"type"[[:space:]]*:[[:space:]]*"assistant"' 2>/dev/null \
    | /usr/bin/grep 'cache_read_input_tokens' 2>/dev/null | /usr/bin/tail -1)
  if [ -n "$ctx_line" ]; then
    ctx_field() { printf '%s' "$ctx_line" | /usr/bin/grep -oE "\"$1\"[[:space:]]*:[[:space:]]*[0-9]+" | /usr/bin/tail -1 | /usr/bin/sed -E 's/.*:[[:space:]]*([0-9]+)/\1/'; }
    ci=$(ctx_field input_tokens); cc=$(ctx_field cache_creation_input_tokens); cr=$(ctx_field cache_read_input_tokens)
    [ -n "$ci" ] || ci=0; [ -n "$cc" ] || cc=0; [ -n "$cr" ] || cr=0
    printf 'Context used: %sk tokens (rough, last step)\n' "$(( (ci + cc + cr + 500) / 1000 ))"
  fi
fi

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
returning=0
if [ -n "$gap_min" ] && [ "$gap_min" -ge "$AWAY_MINUTES" ]; then
  printf 'YOU ARE RETURNING after %s minutes away. You did NOT watch what happened. This reply is a COLD START: summarize what the problem was in one line, whether it is fixed, and what is needed from you. No history, no "as you saw", no codes.\n' "$gap_min"
  returning=1
fi

# The card is ONE file so every reader sees the same text; edit it to your own taste.
# Full card only when it matters: SessionStart, a returning turn, or CARD_ALWAYS=1.
# Everything else gets the one-line reminder below instead.
full_card=0
[ "$event" = "SessionStart" ] && full_card=1
[ "$returning" = 1 ] && full_card=1
[ "${CARD_ALWAYS:-0}" = 1 ] && full_card=1
CARD_FILE="${CARD_FILE:-$(dirname "$0")/owner-card.md}"
if [ "$full_card" = 1 ]; then
  if [ -s "$CARD_FILE" ]; then
    cat "$CARD_FILE"
  else
    printf 'WARNING: %s is missing or empty, so the reply-format card could not be injected. Say so at the start of the reply.\n' "$CARD_FILE"
  fi
else
  printf 'Card: a quick reply is one line then "Needs my input:"; a decision, a closed task, or you returning gets the full card (see hooks/owner-card.md).\n'
fi
