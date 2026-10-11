#!/bin/bash
# wake-warning.sh - UserPromptSubmit hook, OPT-IN (the installer asks; the default answer is no).
# A big chat that has sat idle has lost its saved copy (the prompt cache lasts about an hour), so
# your first message into it re-reads the whole chat at full price. This hook holds that first
# message ONCE (exit 2, a plain-words warning on stderr, nothing on stdout) when ALL of these hold:
#   - the event is UserPromptSubmit, the transcript is a main chat's (no /subagents/ in its path),
#     and the prompt is one you typed (not a task notification, a message from another session, a
#     `!` shell line, a scheduled-loop sentinel or a delivery notice);
#   - the chat's newest line (either role; a line under 15 s old is skipped, because the prompt
#     being submitted is already in the file) is WAKE_IDLE_MIN (60) minutes old or more;
#   - the chat holds MORE than WAKE_CTX_TOKENS (200000) tokens: input + cache-creation + cache-read
#     of the newest assistant line whose usage is not all zero (the same reader the doorman uses).
# THE PASS: the warning records the newest line's time in $STATE/wake-warned/<session_id>. While the
# chat's newest line is still that line (the next message is the same wake), the next message of any
# text goes through. A later wake, after a newer line, is warned again.
# FAILS OPEN everywhere: no transcript, no timestamp, no session id, no jq, no guard-lib.sh, an unreadable usage line,
# a record folder or record file that is a link or cannot be written (or does not read back) = pass, nothing held.
# A chat compacted after its last usage line has an unknown size = pass.
# Config: hooks/wake-warning.conf (copy wake-warning.conf.example), KEY=VALUE lines (a trailing ` # comment`
#   is ignored), never executed:
#   WAKE_IDLE_MIN, WAKE_CTX_TOKENS, WAKE_EXCESS_PER_MTOK. An environment variable of the same name wins.
# Test seams: WAKE_NOW (epoch seconds), STATE_CHECK_STATE_DIR (the doorman's state folder; default
#   ~/.claude/state/state-check), and the three keys above. Tests: hooks/test-hooks.sh "guard port
#   2026-10-10 (C2)".
input=$(cat 2>/dev/null); [ -z "$input" ] && exit 0
event=$(printf '%s' "$input" | /usr/bin/sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ "$event" = "UserPromptSubmit" ] || exit 0
tp=$(printf '%s' "$input" | /usr/bin/sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
sid=$(printf '%s' "$input" | /usr/bin/sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
case "$sid" in ''|*/*|*..*) exit 0;; esac
case "$tp" in */subagents/*) exit 0;; esac
[ -n "$tp" ] && [ -f "$tp" ] && [ -r "$tp" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0   # the typed prompt is read with jq; without it nothing is held

here="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
# the conf: KEY=VALUE lines read as text (never sourced); only an unset environment key takes the conf's value
conf_val() {  # $1 = key
  [ -r "$here/wake-warning.conf" ] || return 0
  /usr/bin/sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*['\"]\{0,1\}\([0-9][0-9.]*\)['\"]\{0,1\}[[:space:]]*\(#.*\)\{0,1\}\$/\1/p" "$here/wake-warning.conf" 2>/dev/null | /usr/bin/tail -1
}
IDLE_MIN="${WAKE_IDLE_MIN:-$(conf_val WAKE_IDLE_MIN)}"
CTX_MIN="${WAKE_CTX_TOKENS:-$(conf_val WAKE_CTX_TOKENS)}"
PRICE="${WAKE_EXCESS_PER_MTOK:-$(conf_val WAKE_EXCESS_PER_MTOK)}"
case "$IDLE_MIN" in ''|*[!0-9]*) IDLE_MIN=60;; esac
case "$CTX_MIN" in ''|*[!0-9]*) CTX_MIN=200000;; esac
case "$PRICE" in ''|*[!0-9.]*|*.*.*|.) PRICE=5.75;; esac

# machine prompts always pass: only a typed message is held
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)
head_p="${prompt:0:300}"; head_p="${head_p#"${head_p%%[![:space:]]*}"}"
case "$head_p" in
  '<task-notification'*|'<agent-message'*|'<cross-session-message'*|'Another Claude session sent a message'*|'<bash-input>'*|'<<autonomous-loop'*|'[Cross-session delivery notice]'*) exit 0;;
esac
if [ -r "$here/clock-in-context.sh" ] && printf '%s' "$prompt" | /bin/bash "$here/clock-in-context.sh" --classify-prompt >/dev/null 2>&1; then exit 0; fi

# the context size: the doorman's windowed reader (guard-lib.sh, which the installer requires); a missing
# library passes
[ -r "$here/guard-lib.sh" ] && . "$here/guard-lib.sh" 2>/dev/null
command -v stc_ctx_read >/dev/null 2>&1 || exit 0
stc_ctx_read "$tp"
tokens="${STC_CTX_TOT:-0}"
case "$tokens" in ''|*[!0-9]*) exit 0;; esac
[ "$tokens" -gt "$CTX_MIN" ] || exit 0
[ "${STC_CTX_CLN:-0}" -gt "${STC_CTX_ULN:-0}" ] && exit 0   # compacted since: size unknown

# ISO-8601 UTC -> epoch seconds: BSD date first, then GNU
to_epoch() {
  local e
  e=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$1" "+%s" 2>/dev/null)
  case "$e" in ''|*[!0-9]*) e=$(date -u -d "${1}Z" "+%s" 2>/dev/null);; esac
  case "$e" in ''|*[!0-9]*) return 1;; esac
  printf '%s' "$e"
}
# the newest line's time: the timestamps of the file's last 3 MB, newest first, the first one not under 15 s old
NOW="${WAKE_NOW:-$(date +%s)}"
case "$NOW" in ''|*[!0-9]*) exit 0;; esac
newest=""
while IFS= read -r ts; do
  e=$(to_epoch "$ts") || continue
  if [ $((NOW - e)) -gt 15 ]; then newest="$e"; break; fi
done < <(/usr/bin/tail -c 3000000 "$tp" 2>/dev/null | /usr/bin/grep -oE '"timestamp"[[:space:]]*:[[:space:]]*"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}' | /usr/bin/sed -E 's/.*"([0-9T:-]+)$/\1/' | /usr/bin/awk '{a[NR]=$0} END{for(i=NR;i>0;i--) print a[i]}')
[ -n "$newest" ] || exit 0
idle=$(( (NOW - newest) / 60 ))
[ "$idle" -ge "$IDLE_MIN" ] || exit 0

STATE="${STATE_CHECK_STATE_DIR:-$HOME/.claude/state/state-check}"
mk="$STATE/wake-warned/$sid"
# the same wake already warned: this message goes through
if [ -f "$mk" ] && [ ! -L "$mk" ] && [ "$(head -1 "$mk" 2>/dev/null)" = "$newest" ]; then exit 0; fi
[ -L "$STATE/wake-warned" ] && exit 0
[ -L "$mk" ] && exit 0   # a link AT the record file: never written through (the target would be overwritten)
umask 077
mkdir -p "$STATE/wake-warned" 2>/dev/null
{ printf '%s\n' "$newest" > "$mk"; } 2>/dev/null
# hold only when the record was written and reads back (else this chat would be held on every message)
[ -f "$mk" ] && [ ! -L "$mk" ] && [ "$(head -1 "$mk" 2>/dev/null)" = "$newest" ] || exit 0
cost=$(awk -v t="$tokens" -v p="$PRICE" 'BEGIN{printf "%.2f", t*p/1000000}')
printf 'WAKE-UP WARNING: this chat has been idle %s minutes and holds about %sk tokens. Its saved copy has expired, so this message re-reads all of it: about $%s extra at list price (on a subscription it counts against your usage limit instead). Your message is NOT sent. To go ahead, send it again. For new work, a fresh chat is cheaper.\n' "$idle" "$(( (tokens + 500) / 1000 ))" "$cost" >&2
exit 2
