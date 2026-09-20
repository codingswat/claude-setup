#!/bin/bash
# doorman.sh — UserPromptSubmit hook, paired with stop-state-check.sh (same
# hooks/state-check.conf). Refuses a new prompt (exit 2; the prompt text saved to the
# role's inbox) when:
#   - stop-state-check.sh already marked this session RETIRED at its context floor, or
#   - the session has been idle DOORMAN_IDLE_MIN minutes or more (default 40) AND its
#     context is DOORMAN_CTX_K thousand tokens or more (default 200).
# "Idle" is measured from the newest transcript line of ANY kind — your message, a model
# reply, or a TOOL RESULT. A session forty minutes into one long tool call is working, not
# idle, and its tool results are the proof; a session still producing assistant messages
# must never be refused just because the person reading along has been quiet. Only a
# session where nothing at all has happened counts as idle.
# A prompt beginning "wake anyway" always passes, forcing this session open regardless.
# It also writes the TURN SNAPSHOT that hooks/stop-state-check.sh reads at the end of the
# turn — what the tracked tree looked like when this prompt arrived — so that hook can tell
# a turn that CHANGED something from a read-only turn in a tree that was already dirty.
#
# Applies only when the session's working-directory basename matches a line in
# hooks/state-check.conf (role = the name that line gives it). No conf file, or no match:
# inert — the safe default for a single-session project with no roles to track.
# Fails OPEN with a log line when the transcript cannot be read, or when a user/assistant
# line in it carries no timestamp at all — an undatable line might be seconds old, and a
# cost guard must never turn "I cannot tell" into "you are idle". This is a cost guard, not
# a safety guard.
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

# The turn snapshot stop-state-check.sh reads. Same key in both scripts: the session id
# when there is one, otherwise the working folder's own name (sanitised), so a session
# without an id still gets a snapshot of its own rather than none at all.
snapkey() {
  case "$sid" in
    ''|*/*|..*) printf 'nosid-%s' "$(printf '%s' "$base" | tr -c 'A-Za-z0-9._-' '_')" ;;
    *)          printf '%s' "$sid" ;;
  esac
}
if command -v git >/dev/null 2>&1 && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  mkdir -p "$STATE/turnsnap" 2>/dev/null \
    && git -C "$cwd" status --porcelain --untracked-files=no 2>/dev/null > "$STATE/turnsnap/$(snapkey)"
fi
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
iso_of() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%S 2>/dev/null; }

# ACTIVITY = the newest timestamp on ANY user or assistant line, a tool result included.
# A user/assistant line with no timestamp makes the whole question unanswerable, so the
# hook passes (the header promises fail open, and an undatable line might be seconds old).
ua=$(/usr/bin/grep -E '"type"[[:space:]]*:[[:space:]]*"(user|assistant)"' "$tp")
n_ua=$(printf '%s\n' "$ua" | /usr/bin/grep -c .)
n_ts=$(printf '%s\n' "$ua" | /usr/bin/grep -c '"timestamp"')
if [ "$n_ua" -eq 0 ]; then echo "doorman: no user or assistant lines in the transcript — passing (fail open)"; exit 0; fi
if [ "$n_ts" -lt "$n_ua" ]; then echo "doorman: a transcript line carries no timestamp, so idle time cannot be judged — passing (fail open)"; exit 0; fi
# The newest line is usually the prompt being submitted right now; anything within 15s of
# "now" is therefore not evidence of idleness. Timestamps are UTC and fixed width, so the
# newest one is simply the last in sort order.
cut_iso=$(iso_of $((now_s - 15)))
last_iso=$(printf '%s\n' "$ua" \
  | /usr/bin/grep -oE '"timestamp"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | /usr/bin/sed 's/.*"\([^"]*\)"[[:space:]]*$/\1/' | cut -c1-19 \
  | /usr/bin/grep -E '^[0-9]{4}-' | awk -v c="$cut_iso" 'c == "" || $0 < c' | sort | tail -1)
[ -n "$last_iso" ] || exit 0          # everything just happened: not idle
last_s=$(to_epoch "$last_iso")
[ -n "$last_s" ] || { echo "doorman: the newest transcript timestamp could not be read — passing (fail open)"; exit 0; }
gap_min=$(( (now_s - last_s) / 60 ))
if [ "$gap_min" -ge "$IDLE_MIN" ] && [ "$ctx_k" -ge "$CTX_K" ]; then
  refuse "stale and heavy (idle $gap_min min, context ${ctx_k}k)"
fi
exit 0
