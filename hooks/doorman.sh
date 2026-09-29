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
# It also writes, at every prompt, what hooks/stop-state-check.sh reads at the end of the turn:
#   - the TURN SNAPSHOT $STATE/turnsnap/<key>, one line of four tab-separated fields — HEAD,
#     the state file's hash, a hash of `git diff HEAD` (the content of every tracked change),
#     and a hash of the state file's two first marker lines ("none" for what is absent) — so
#     that hook can tell a turn that CHANGED something (a commit-only turn, a second edit of an
#     already-dirty file) from a read-only turn in a tree that was already dirty. Hashes come
#     from git itself (portable: no shasum). Untracked files never enter it. The format is
#     pinned by the round-trip case in hooks/test-hooks.sh (c2a): stop-state-check.sh compares
#     against these very fields.
#   - the context size $STATE/turn-start/<sid> (thousands of tokens, from the newest usage line),
#     the base the helper tell measures growth from.
# It also SHOWS the helper tell $STATE/tell/<sid> that stop-state-check.sh left (one line on
# stdout, which reaches the model), and deletes it — but only on a prompt that PASSES: a held
# prompt (exit 2) leaves it for the next one that does. Symlinked state files are never followed.
#
# Applies only when the session's git TOPLEVEL folder name matches a line in
# hooks/state-check.conf (role = the name that line gives it; see guard-lib.sh's state_conf_read).
# No conf file, no match, or no guard-lib.sh beside this hook: inert — the safe default for a
# single-session project with no roles to track.
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

# ---- role lookup: guard-lib.sh's state_conf_read (hooks/state-check.conf; shared with stop-state-check.sh) ----
_lib="$(dirname "$0")/guard-lib.sh"
# shellcheck disable=SC1090
[ -r "$_lib" ] && . "$_lib" 2>/dev/null
if ! command -v state_conf_read >/dev/null 2>&1; then
  echo "doorman: guard-lib.sh (the shared conf reader) is missing beside this hook — doing nothing." >&2
  exit 0
fi
CONF="$(dirname "$0")/state-check.conf"
state_conf_read "$cwd" "$CONF" || exit 0   # no config, or this folder matches nothing in it: inert
role="$STC_ROLE"; top="$STC_TOP"; base="$STC_BASE"
sf="${STC_STATE_FILE//'{role}'/$role}"

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
if command -v git >/dev/null 2>&1 && git -C "$top" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
   && [ ! -L "$STATE/turnsnap" ] && [ ! -L "$STATE/turnsnap/$(snapkey)" ]; then
  # Four fields, the format stop-state-check.sh reads (see the header). The same commands run there.
  _s_head=$(git -C "$top" rev-parse HEAD 2>/dev/null); _s_head="${_s_head:-none}"
  _s_tree=$(git -C "$top" diff --no-ext-diff --no-textconv HEAD 2>/dev/null | git -C "$top" hash-object --stdin 2>/dev/null); _s_tree="${_s_tree:-none}"
  _s_sf=none; _s_mk=none
  if [ -f "$top/$sf" ]; then
    _s_sf=$(git -C "$top" hash-object -- "$top/$sf" 2>/dev/null); _s_sf="${_s_sf:-none}"
    _s_mk=$({ /usr/bin/grep -m1 -E '^\*\*Current task:\*\*' "$top/$sf" 2>/dev/null; /usr/bin/grep -m1 -E '^\*\*Next step:\*\*' "$top/$sf" 2>/dev/null; } | git -C "$top" hash-object --stdin 2>/dev/null); _s_mk="${_s_mk:-none}"
  fi
  mkdir -p "$STATE/turnsnap" 2>/dev/null \
    && printf '%s\t%s\t%s\t%s\n' "$_s_head" "$_s_sf" "$_s_tree" "$_s_mk" > "$STATE/turnsnap/$(snapkey)" 2>/dev/null
fi
# The helper tell (see the header): read now, shown and deleted only when this prompt PASSES.
tell_k=""; tell_path=""
case "$sid" in
  ''|*/*|..*) : ;;
  *) tell_path="$STATE/tell/$sid"
     if [ -f "$tell_path" ] && [ ! -L "$tell_path" ] && [ ! -L "$STATE/tell" ]; then
       tell_k=$(head -1 "$tell_path" 2>/dev/null)
       case "$tell_k" in ''|*[!0-9]*) tell_k="" ;; esac
     fi ;;
esac
doorman_finish() {
  local rc=$?
  trap - EXIT
  if [ "$rc" = 0 ] && [ -n "$tell_k" ]; then
    printf 'helper tell: your last turn grew the context by %sk tokens with no helper launched — long reads, test runs and searches belong to a subagent (a short-lived helper chat that reports back).\n' "$tell_k"
    rm -f "$tell_path" 2>/dev/null
  fi
  exit "$rc"
}
trap doorman_finish EXIT
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
  # The size this turn starts from, for the helper tell (never through a symlink).
  case "$sid" in
    ''|*/*|..*) : ;;
    *) if [ ! -L "$STATE/turn-start" ] && [ ! -L "$STATE/turn-start/$sid" ]; then
         mkdir -p "$STATE/turn-start" 2>/dev/null
         printf '%s\n' "$ctx_k" > "$STATE/turn-start/$sid" 2>/dev/null
       fi ;;
  esac
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
