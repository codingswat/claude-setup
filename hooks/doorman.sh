#!/bin/bash
# doorman.sh — the opt-in prompt hook of the multi-chat group (UserPromptSubmit, registered by
# install.sh's multi-chat question; also read on SessionStart when registered there), paired with
# stop-state-check.sh (same hooks/state-check.conf). Applies only when the session's git TOPLEVEL
# folder name matches a line in hooks/state-check.conf (see guard-lib.sh's state_conf_read): no conf
# file, no match, or no guard-lib.sh beside this hook = inert, the safe default for a single-session
# project with no roles to track. A cost guard, not a safety guard: every doubt fails OPEN.
#
# THE HOLD. The only trigger is the chat's context: the newest usage line at or over the conf row's
# floor (its third column, thousands of tokens; the same number stop-state-check.sh retires at), or a
# RETIRED marker written by stop-state-check.sh (honoured only with its companion
# $STATE/retired-compacts/<sid>, and never through a symlink). There is no idle-time trigger and no
# "wake anyway" escape. A held prompt exits 2 with the refusal on stderr and NOTHING on stdout; the
# text is saved twice: appended to $STATE/inbox/<role>.md and written, stamped (time, folder,
# text), to $STATE/held/<session> (written whole under a temporary name, then renamed).
# THE PASS. The owner's NEXT typed message in that session passes and carries the held text
# (stdout, labelled with its stamped time): $STATE/open/<session> is written first, then the held file
# is renamed into $STATE/delivered/ (a rename is atomic, so two prompts can never both take it), then
# the text is printed. From then on every typed prompt of that session passes (the
# open marker is read first, so a RETIRED chat is never locked out) and is told to wrap up. A body
# of 12 characters or fewer (a one-letter pick) is delivered with a line telling the chat to
# confirm it before acting. A fresh chat of the same ROLE (its folder name and the conf's aliases, not
# necessarily the same folder: each seat has its own worktree) receives another chat's held text only
# once that other chat is retired (live marker), once (the same rename), and the inbox copy is then
# marked DELIVERED (session and time) so a later holder does not act on it twice. While the held chat is
# only full (not yet retired) a fresh chat of that role is told once, at its first typed prompt, that a
# held message is waiting. The compaction rule and the marker file names are the shared contract with
# clock-in-context.sh, which reads open/<session>.
# NEEDS jq to read the typed prompt (the installer registers this hook only when jq is present); without
# it the hook still writes the turn snapshot, then does nothing and says so on stderr.
# PRIVACY: every file written here is created private (umask 077: files 600, folders 700).
# COMPACTION. A compact boundary in the transcript AFTER its newest usage line means the context
# size is unknown: nothing is held that turn, and the chat is told it was compacted (with the
# wrap-up words when its role is in WRAPUP_ROLES). A later compaction than the count recorded in
# retired-compacts/<session> clears the retired marker. The same notice is printed on a
# SessionStart whose "source" is "compact". UNVERIFIED: no real "source":"compact" payload has
# been seen; the branch reads the field defensively and a payload without it changes nothing. An
# unreadable transcript or an unreadable usage line is also "unknown": never a hold.
# MACHINE PROMPTS (task notices, agent hand-backs, peer messages, shell input, fired scheduled
# prompts) are never held, never the passing message and never counted. They are recognised by the
# ONE classifier, `bash clock-in-context.sh --classify-prompt` (exit 0 machine, 1 typed; anything
# else, or the script missing, reads as "cannot tell": never hold), plus the cron registry
# $STATE/crons/<session> that stop-state-check.sh writes (an exact-match lookup, needs jq).
#
# It also writes, at every prompt, what hooks/stop-state-check.sh reads at the end of the turn:
#   - the TURN SNAPSHOT $STATE/turnsnap/<key>, one line of five tab-separated fields — HEAD,
#     the state file's hash, a hash of `git diff HEAD` (the content of every tracked change),
#     a hash of the state file's two first marker lines ("none" for what is absent), and the repo's
#     top-level folder (so the end-of-turn check judges THAT repo, never one the turn cd'd into) — so
#     that hook can tell a turn that CHANGED something (a commit-only turn, a second edit of an
#     already-dirty file) from a read-only turn in a tree that was already dirty. Hashes come
#     from git itself (portable: no shasum). Untracked files never enter it. The format is
#     pinned by the round-trip case in hooks/test-hooks.sh (c2a): stop-state-check.sh compares
#     against these very fields.
#   - the context size $STATE/turn-start/<sid> (thousands of tokens, from the newest usage line; read once
#     with a growing tail window by guard-lib.sh's stc_ctx_read, an all-zero API-error line skipped),
#     the base the helper tell measures growth from.
# It also SHOWS the helper tell $STATE/tell/<sid> that stop-state-check.sh left (one line on
# stdout, which reaches the model), and deletes it — but only on a prompt that PASSES: a held
# prompt (exit 2) leaves it for the next one that does. Symlinked state files are never followed.
#
# Crash safety (each step leaves the text on disk; tests: hooks/test-hooks.sh, c2b): killed before
# the inbox line = nothing saved, and a killed hook is not a refusal, so the prompt is simply
# delivered as typed; after the inbox line, before held/ = the inbox copy only; after held/ = the
# next typed prompt carries it; after the open marker, before the rename = the same (held/ is read
# before the marker); between the rename and the print = the text sits in delivered/, the chat is
# not held again, and it is never shown twice; after the print = complete.
#
# Config: hooks/state-check.conf (see hooks/state-check.conf.example; shared with
# stop-state-check.sh). Test seam: STATE_CHECK_STATE_DIR (where the marker folders live).
# Tests: hooks/test-hooks.sh.
input=$(cat 2>/dev/null); [ -z "$input" ] && exit 0
field() { printf '%s' "$input" | /usr/bin/sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
tp=$(field transcript_path); cwd=$(field cwd); sid=$(field session_id)
event=$(field hook_event_name); source_=$(field source)
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
umask 077   # every file this hook writes holds the person's own words (held text, inbox): private (600, folders 700)

# ---- the shared words, and the SessionStart half of the compaction rule ----
WRAPUP_WORDS='wrapping up — open a fresh chat for new work.'
role_wrapped() {  # is this role in WRAPUP_ROLES ("*" = every role)?
  local _roles _r
  _roles=$(printf ' %s ' "$STC_WRAPUP_ROLES" | tr 'A-Z\t' 'a-z ')
  _r=$(printf '%s' "$role" | tr 'A-Z' 'a-z')
  case "$_roles" in *" * "*|*" $_r "*) return 0 ;; *) return 1 ;; esac
}
compact_notice() {
  printf 'This chat was compacted — its earlier history was summarized and the measured context is unknown.\n'
  if role_wrapped; then printf '%s\n' "$WRAPUP_WORDS"; fi
}
# The SessionStart half of the compaction rule (see the header: unverified against a real payload).
# It runs before the turn snapshot, the tell and every marker: a session start is not a turn.
if [ "$event" = "SessionStart" ]; then
  [ "$source_" = "compact" ] && compact_notice
  exit 0
fi


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
  # Five fields, the format stop-state-check.sh reads (see the header): the fifth names the repo. The same commands run there.
  _s_head=$(git -C "$top" rev-parse HEAD 2>/dev/null); _s_head="${_s_head:-none}"
  _s_tree=$(git -C "$top" diff --no-ext-diff --no-textconv HEAD 2>/dev/null | git -C "$top" hash-object --stdin 2>/dev/null); _s_tree="${_s_tree:-none}"
  _s_sf=none; _s_mk=none
  if [ -f "$top/$sf" ]; then
    _s_sf=$(git -C "$top" hash-object -- "$top/$sf" 2>/dev/null); _s_sf="${_s_sf:-none}"
    _s_mk=$({ /usr/bin/grep -m1 -E '^\*\*Current task:\*\*' "$top/$sf" 2>/dev/null; /usr/bin/grep -m1 -E '^\*\*Next step:\*\*' "$top/$sf" 2>/dev/null; } | git -C "$top" hash-object --stdin 2>/dev/null); _s_mk="${_s_mk:-none}"
  fi
  mkdir -p "$STATE/turnsnap" 2>/dev/null \
    && printf '%s\t%s\t%s\t%s\t%s\n' "$_s_head" "$_s_sf" "$_s_tree" "$_s_mk" "$top" > "$STATE/turnsnap/$(snapkey)" 2>/dev/null
fi
# The helper tell (see the header): read now, shown and deleted only when this prompt PASSES.
tell_k=""; tell_path=""; waiting_note=""
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
  if [ "$rc" = 0 ] && [ -n "$waiting_note" ]; then
    printf '%s\n' "$waiting_note"
    [ ! -L "$STATE/told" ] && mkdir -p "$STATE/told" 2>/dev/null && [ ! -L "$STATE/told/$safe_sid" ] && : > "$STATE/told/$safe_sid" 2>/dev/null
  fi
  exit "$rc"
}
trap doorman_finish EXIT

# ---- the shared words and small helpers ----
safe_sid=""; case "$sid" in ''|*/*|..*|*..*) : ;; *) safe_sid="$sid" ;; esac
# marker_live SID — a RETIRED marker counts only with its retired-compacts companion (an old marker
# without one is stale), and a symlinked companion or folder is not honoured.
marker_live() {
  [ -f "$STATE/retired/$1" ] && [ ! -L "$STATE/retired/$1" ] && [ ! -L "$STATE/retired" ] \
    && [ -f "$STATE/retired-compacts/$1" ] && [ ! -L "$STATE/retired-compacts/$1" ] && [ ! -L "$STATE/retired-compacts" ]
}
# ---- the machine-prompt test ----
# The one classifier (clock-in-context.sh --classify-prompt), then the cron registry.
if [ -z "$prompt" ] && ! command -v jq >/dev/null 2>&1; then
  echo "doorman: jq is not installed — this hook cannot read the typed prompt and does nothing (install jq)." >&2
fi
[ -n "$prompt" ] || exit 0                       # nothing typed (or no jq to read it): nothing to hold or carry
machine=0
_cls="$(dirname "$0")/clock-in-context.sh"
if [ -r "$_cls" ]; then
  printf '%s' "$prompt" | bash "$_cls" --classify-prompt >/dev/null 2>&1; _crc=$?
  case "$_crc" in
    0) machine=1 ;;
    1) machine=0 ;;
    *) echo "doorman: the prompt classifier failed (exit $_crc) — passing (fail open)." >&2; machine=1 ;;
  esac
else
  echo "doorman: clock-in-context.sh (the prompt classifier) is missing beside this hook — passing (fail open)." >&2
  machine=1
fi
if [ "$machine" = 0 ] && [ -n "$safe_sid" ] && [ -f "$STATE/crons/$safe_sid" ] && [ ! -L "$STATE/crons/$safe_sid" ] && [ ! -L "$STATE/crons" ] && command -v jq >/dev/null 2>&1; then
  _lead="${prompt%%[!$' \t\r\n']*}"; _trim="${prompt#"$_lead"}"
  _tail="${_trim##*[!$' \t\r\n']}"; _trim="${_trim%"$_tail"}"
  _json=$(printf '%s' "$_trim" | jq -Rs . 2>/dev/null)
  if [ -n "$_json" ] && grep -qxF -- "$_json" "$STATE/crons/$safe_sid" 2>/dev/null; then machine=1; fi
fi

# ---- the context: one windowed read (guard-lib.sh's stc_ctx_read), all-zero usage lines skipped ----
# The newest non-zero usage line and the newest compact boundary come from ONE read of the transcript's
# end (256 KB, widened to 8 MB, then the whole file, only until they are found): a long chat costs
# milliseconds per prompt, not seconds. An API-error line with every counter 0 is not a measurement.
ctx_k=""; compact_after=0
if [ -n "$tp" ] && [ -r "$tp" ]; then
  stc_ctx_read "$tp"
  # A compact boundary after the newest usage line = the size is stale: unknown.
  if [ "$STC_CTX_CLN" -gt "$STC_CTX_ULN" ]; then
    compact_after=1
  elif [ "$STC_CTX_TOT" -gt 0 ]; then
    ctx_k=$(( (STC_CTX_TOT + 500) / 1000 ))
  fi
  # The size this turn starts from, for the helper tell (never through a symlink).
  if [ -n "$ctx_k" ] && [ -n "$safe_sid" ] && [ ! -L "$STATE/turn-start" ] && [ ! -L "$STATE/turn-start/$safe_sid" ]; then
    mkdir -p "$STATE/turn-start" 2>/dev/null
    printf '%s\n' "$ctx_k" > "$STATE/turn-start/$safe_sid" 2>/dev/null
  fi
fi

# Machine prompts: never held, never the passing message. (The tell above still shows on rc 0.)
[ "$machine" = 1 ] && exit 0

# ---- delivery helpers ----
# claim_held FILE KEY — take a held file by renaming it into delivered/<KEY>; sets HELD_TIME and
# HELD_TEXT from the claimed copy. Fails (returns 1) when someone else already took it.
claim_held() {
  [ -L "$STATE/delivered" ] && return 1
  mkdir -p "$STATE/delivered" 2>/dev/null || return 1
  mv -f "$1" "$STATE/delivered/$2" 2>/dev/null || return 1
  HELD_TIME=$(sed -n '1p' "$STATE/delivered/$2" 2>/dev/null)
  HELD_TEXT=$(tail -n +3 "$STATE/delivered/$2" 2>/dev/null)
}
show_held() {  # $1 = label ("" or "held for the previous chat")
  local _l _t
  _l="${HELD_TEXT%%[!$' \t\r\n']*}"; _t="${HELD_TEXT#"$_l"}"
  _l="${_t##*[!$' \t\r\n']}"; _t="${_t%"$_l"}"
  if [ -n "$1" ]; then printf 'HELD MESSAGE delivered (%s at %s): %s\n' "$1" "${HELD_TIME:-?}" "$HELD_TEXT"
  else printf 'HELD MESSAGE delivered (held at %s): %s\n' "${HELD_TIME:-?}" "$HELD_TEXT"; fi
  if [ "${#_t}" -le 12 ]; then
    printf 'This is a short pick ("%s") — confirm this answer with the owner before acting on it.\n' "$_t"
  fi
}
# mark_delivered ROLE HELD-SESSION — say under the inbox copy that its text was delivered (to this session,
# now), so a later holder who reads the inbox does not act on it a second time. Never through a symlink.
mark_delivered() {
  [ -f "$STATE/inbox/$1.md" ] && [ ! -L "$STATE/inbox" ] && [ ! -L "$STATE/inbox/$1.md" ] || return 0
  printf '\n## %s — DELIVERED: the message held for session %s was delivered to session %s (folder %s) — do not act on it again\n' \
    "$(date '+%Y-%m-%d %H:%M')" "$2" "${sid:-?}" "$top" >> "$STATE/inbox/$1.md" 2>/dev/null
}
WRAP_NOTE='This chat is past its context cut-off — wrap up the task in hand and hand over to a fresh chat.'

# ---- 1. THE PASS: this session has text held for it ----
if [ -n "$safe_sid" ] && [ -f "$STATE/held/$safe_sid" ] && [ ! -L "$STATE/held/$safe_sid" ] && [ ! -L "$STATE/held" ]; then
  # The open marker goes FIRST: a kill after it and before the rename leaves the held file, which this
  # very branch delivers on the next prompt (it is checked before the marker); a kill after the rename
  # leaves the marker, so the chat is never held twice and the text sits in delivered/.
  [ ! -L "$STATE/open" ] && mkdir -p "$STATE/open" 2>/dev/null && [ ! -L "$STATE/open/$safe_sid" ] && : > "$STATE/open/$safe_sid" 2>/dev/null
  if claim_held "$STATE/held/$safe_sid" "$safe_sid"; then
    mark_delivered "$role" "$safe_sid"
    show_held ""
    printf '%s\n' "$WRAP_NOTE"
  fi
  exit 0
fi
# ---- 2. already passed once: every later typed prompt passes and is told to wrap up ----
if [ -n "$safe_sid" ] && [ -f "$STATE/open/$safe_sid" ] && [ ! -L "$STATE/open/$safe_sid" ] && [ ! -L "$STATE/open" ]; then
  printf '%s\n' "$WRAP_NOTE"
  exit 0
fi
# ---- 3. a fresh chat of the same ROLE receives a RETIRED chat's held text, once ----
# Same role, not same folder: each seat works in its own worktree, so the next holder is in another folder.
# The held chat's role is read from its folder by the conf (state_conf_read, in a subshell so this chat's own
# settings are untouched; works after the folder is gone). A chat that is only FULL (not retired yet) keeps its
# text: the fresh chat of that role is told once, at its first typed prompt, that a held message is waiting.
if [ -n "$safe_sid" ] && [ -d "$STATE/held" ] && [ ! -L "$STATE/held" ]; then
  for _hf in "$STATE/held"/*; do
    [ -f "$_hf" ] && [ ! -L "$_hf" ] || continue
    _osid="${_hf##*/}"
    [ "$_osid" = "$safe_sid" ] && continue
    _htop=$(sed -n '2p' "$_hf" 2>/dev/null); _hrole=""
    if [ "$_htop" = "$top" ]; then _hrole="$role"
    elif [ -n "$_htop" ]; then _hrole=$( ( state_conf_read "$_htop" "$CONF" && printf '%s' "$STC_ROLE" ) 2>/dev/null ); fi
    [ -n "$_hrole" ] && [ "$_hrole" = "$role" ] || continue
    if marker_live "$_osid"; then
      if claim_held "$_hf" "$_osid"; then mark_delivered "$_hrole" "$_osid"; show_held "held for the previous chat"; exit 0; fi
    elif [ ! -e "$STATE/told/$safe_sid" ] && [ ! -L "$STATE/told/$safe_sid" ]; then
      waiting_note="A message held for another $role chat (session $_osid, held at $(sed -n '1p' "$_hf" 2>/dev/null)) is waiting: it is saved in $STATE/inbox/$_hrole.md and will be delivered when that chat is retired. Tell the owner."
    fi
  done
fi

# ---- 4. compaction: a later compaction than the retirement's clears the marker; unknown context never holds ----
if [ -n "$safe_sid" ] && marker_live "$safe_sid" && [ -n "$tp" ] && [ -r "$tp" ]; then
  _now=$(/usr/bin/grep -F compact_boundary "$tp" 2>/dev/null | /usr/bin/grep -cE '"subtype"[[:space:]]*:[[:space:]]*"compact_boundary"' 2>/dev/null); _now="${_now:-0}"
  _then=$(head -1 "$STATE/retired-compacts/$safe_sid" 2>/dev/null); case "$_then" in ''|*[!0-9]*) _then=0 ;; esac
  if [ "$_now" -gt "$_then" ] 2>/dev/null; then rm -f "$STATE/retired/$safe_sid" "$STATE/retired-compacts/$safe_sid" 2>/dev/null; fi
fi
if [ "$compact_after" = 1 ]; then compact_notice; exit 0; fi

# ---- 5. the hold: retired, or the context at or over the conf row's floor ----
state_word=""; reason=""
if [ -n "$safe_sid" ] && marker_live "$safe_sid"; then
  state_word=retired; reason="marked RETIRED at its context floor"
elif [ -n "$ctx_k" ] && [ -n "$STC_FLOOR_K" ] && [ "$ctx_k" -ge "$((10#$STC_FLOOR_K))" ]; then
  state_word=full; reason="context ${ctx_k}k at or over its ${STC_FLOOR_K}k floor"
fi
if [ -n "$state_word" ] && [ -n "$safe_sid" ] && [ ! -L "$STATE/held" ]; then
  stamp="$(date '+%Y-%m-%d %H:%M')"
  mkdir -p "$STATE/inbox" 2>/dev/null
  printf '\n## %s — to the %s (session %s; folder %s; %s)\n\n%s\n' "$stamp" "$role" "$sid" "$top" "$reason" "$prompt" >> "$STATE/inbox/$role.md" 2>/dev/null
  # Written whole under a temporary (dot) name, then renamed: a kill in between never leaves a half file
  # under held/<session>. If the copy cannot be made the prompt PASSES (never a refusal that loses the text).
  if mkdir -p "$STATE/held" 2>/dev/null \
     && printf '%s\n%s\n%s' "$stamp" "$top" "$prompt" > "$STATE/held/.$safe_sid.$$" 2>/dev/null \
     && mv -f "$STATE/held/.$safe_sid.$$" "$STATE/held/$safe_sid" 2>/dev/null; then
    printf 'DOORMAN: this chat is %s (%s). Your message is saved — don'"'"'t retype: your next message carries this one.\n' "$state_word" "$reason" >&2
    exit 2
  fi
  rm -f "$STATE/held/.$safe_sid.$$" 2>/dev/null
  echo "doorman: the held copy could not be written — passing (fail open)." >&2
fi
exit 0
