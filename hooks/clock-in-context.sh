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
# 3. AWAY DETECTOR: if your own last TYPED message in the transcript is older than
#    AWAY_MINUTES (default 20 minutes), you likely stepped away and did not watch the last
#    stretch of work. The hook injects a note telling the model to invoke the summarize skill
#    and re-summarize what happened rather than assume you saw it. Measured from YOUR last
#    message, never from the model's own reply. It fires only on a UserPromptSubmit that YOU
#    typed: a helper's hand-back, a task notification, a message from another session, the
#    output of a `!` command, a scheduled-loop sentinel and a notice-only prompt are MACHINE
#    text (the classifier below) — they neither fire it nor count as "your previous message".
#    On a return it also prints ONE line counting the override words honoured since that
#    previous message (from the override ledger; nothing when none).
#    Reads transcript_path and prompt from the hook's stdin JSON; missing or unparseable input
#    simply skips this block, and a missing prompt field counts as typed.
# 4. CONTEXT LINE: a rough "Context used: Nk tokens" line, so a long session can see how
#    close it is to needing a hand-off. N = (cache_read + cache_creation + input tokens) of
#    the NEWEST assistant transcript line whose usage is not all zero (an API-error line
#    carries all-zero usage and is not a measurement), divided by 1000 and rounded. The WHOLE
#    transcript is read, never a byte-limited tail: a tool result over 200 KB pushes the real
#    usage line out of any fixed window. After a compaction (a compact-boundary line newer than
#    the last usage line) the number is UNKNOWN, not stale, so nothing prints. Silent with no
#    transcript, an unreadable one, or no usage line — never blocks, never writes to stderr.
# 5. FULLNESS NOTE (typed prompt only, never a machine prompt, never a helper's own transcript):
#    once the context passes CONTEXT_NOTE_K (default 400) thousand tokens, one line asks the
#    reply to open with how full the chat is; when the chat has also been idle CONTEXT_STALE_MIN
#    (default 60) minutes or more — you AND the model — it adds "this wake re-read the whole
#    chat" (the prompt cache lives about an hour). Both numbers are illustrative defaults.
#    WRAP-UP WORDS (read-only; only where the opt-in multi-chat group is installed): once hooks/
#    stop-state-check.sh has written $STATE/wrapup-fired/<session_id> (its first line is the wrap-up
#    point in thousands of tokens), the fullness line is REPLACED by the wrap-up words for as long as
#    the context stays at or over that point — unless $STATE/open/<session_id> exists (a later prompt
#    hook's own wrap-up note already says it). This file never writes the marker and knows no roles
#    or thresholds: no group installed, no marker, nothing changes. An unattended run needs no check
#    here — the Stop hook writes no marker while one is on. $STATE = STATE_CHECK_STATE_DIR, default
#    ~/.claude/state/state-check.
# 6. BACKUP WATCHDOG (typed prompt only, and only where hooks/backup.conf exists — the backup
#    is opt-in): one line when the settings repo has changes uncommitted for over
#    WATCHDOG_MINUTES (default 60; the OLDEST changed file's age) or commits not pushed.
#    Silent when clean and pushed, or not a git repo. WATCHDOG_CLAUDE_DIR (default ~/.claude).
# The machine-prompt CLASSIFIER is callable by another hook without running this one:
#     printf '%s' "$text" | bash clock-in-context.sh --classify-prompt     # exit 0 machine, 1 typed
# This file is the classifier's single home (cic_is_machine_text, cic_is_notice_only,
# cic_is_machine_prompt, below).
# No jq required — bash/sed/grep/awk only; jq is used for the prompt when it is there.
# Portable: the epoch and date helpers try BSD (macOS) then GNU (Linux); no `tail -r`, no
# `stat -f`. Test seams: CIC_NO_JQ=1 forces the no-jq prompt reader; OVERRIDE_LEDGER (path).
# Tests: hooks/test-hooks.sh (section 1 and "refresh 2026-09-29 (c1)").

# --- the classifier: machine text versus the owner's own typed prompt -------------------
# Every test here is bounded, because a long paste once outran the prompt hook's timeout. The
# prefix test reads only the first 4,096 characters and trims leading whitespace with a plain
# pattern (an extglob +(...) trim is quadratic in bash: about 2 s at 4 KB and minutes at 100 KB);
# the notice-only test refuses to look at anything over 16 KB (a real notice is a few hundred
# characters). Limit: 4,096 or more leading whitespace characters before a machine prefix are
# not seen.
CIC_FRAME='[Cross-session delivery notice] '
cic_is_machine_text() {  # $1 = a prompt/message text (its start is enough); exit 0 = machine
  local _h="${1:0:4096}" _lead t
  _lead="${_h%%[!$' \t\r\n']*}"; t="${_h#"$_lead"}"
  case "$t" in
    '<task-notification>'*|'<agent-message'*|'<cross-session-message'*|'Another Claude session sent a message'*|'<bash-input>'*|'<<autonomous-loop'*) return 0 ;;
  esac
  return 1
}
cic_is_notice_only() {  # $1 = a prompt text; exit 0 only when EVERY non-blank line starts with the notice frame
  local _l _n=0
  [ "${#1}" -gt 16384 ] && return 1
  while IFS= read -r _l || [ -n "$_l" ]; do
    _l="${_l%$'\r'}"
    case "$_l" in *[![:space:]]*) ;; *) continue ;; esac
    case "$_l" in "$CIC_FRAME"*) _n=$((_n+1)) ;; *) return 1 ;; esac
  done <<<"$1"
  [ "$_n" -ge 1 ]
}
cic_is_machine_prompt() { cic_is_machine_text "$1" || cic_is_notice_only "$1"; }
if [ "${1:-}" = "--classify-prompt" ]; then
  _cls_text=$(cat 2>/dev/null)
  cic_is_machine_prompt "$_cls_text"
  exit $?
fi

input=$(cat 2>/dev/null)
tp=$(printf '%s' "$input" | /usr/bin/sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
event=$(printf '%s' "$input" | /usr/bin/sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
sid=$(printf '%s' "$input" | /usr/bin/sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
printf 'Clock (this machine): %s (%s for file entries)\n' "$(date '+%Y-%m-%d %l:%M %p' | tr -s ' ')" "$(date '+%H:%M')"

# The current prompt, classified once. Only a UserPromptSubmit has one; a missing or empty
# prompt field counts as TYPED (the safe side: the away detector may fire, never the reverse).
_cur_machine=0; _cur_prompt=""
if [ "$event" = "UserPromptSubmit" ]; then
  if [ "${CIC_NO_JQ:-0}" != 1 ] && command -v jq >/dev/null 2>&1; then
    _cur_prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)
  else
    # No jq: cut the prompt value out of the JSON with awk — the first 16,500 characters, up to the
    # first unescaped quote, with \n \t \r \" \\ undone. Enough for both bounded tests above.
    _cur_prompt=$(printf '%s' "$input" | /usr/bin/awk 'BEGIN{RS="\001"} {
      if (match($0, /"prompt"[ \t\r\n]*:[ \t\r\n]*"/)) {
        s=substr($0, RSTART+RLENGTH, 16500); out=""; n=length(s); i=1
        while (i<=n) { c=substr(s,i,1)
          if (c=="\\") { d=substr(s,i+1,1); if (d=="n") out=out "\n"; else if (d=="t") out=out "\t"; else if (d!="r") out=out d; i+=2; continue }
          if (c=="\"") break
          out=out c; i++ }
        printf "%s", out } }' 2>/dev/null)
  fi
  cic_is_machine_prompt "$_cur_prompt" && _cur_machine=1
fi
typed_prompt=0
[ "$event" = "UserPromptSubmit" ] && [ "$_cur_machine" = 0 ] && typed_prompt=1
helper=0
case "$tp" in */subagents/*) helper=1 ;; esac

# Context line: the newest assistant usage block that is not all zero, and whether a compaction came
# after it. Read from the END of the transcript in growing windows (256 KB, then 8 MB, then the whole
# file): the newest non-zero usage line, and every line after it, always sit inside the first window
# that holds one, so the answer is the same as a whole-file read — but a normal chat costs almost
# nothing, and a tool result over 200 KB (which pushed the usage line out of the old fixed 200 KB
# tail) just widens the window. A window's first line may be cut, so it is dropped. One awk pass over
# the few lines that can matter prints "<total tokens> <last usage line no.> <last compact line no.>"
# (numbers within the window); only the newest 64 usage lines are measured, so 64 API-error lines in
# a row would read as unknown. The three counters are read from the LAST occurrence in the line.
cic_ctx_window() {  # $1 = bytes of the file's end to read; 0 = the whole file
  { if [ "$1" -gt 0 ]; then /usr/bin/tail -c "$1" "$tp" 2>/dev/null | /usr/bin/sed 1d; else /bin/cat "$tp" 2>/dev/null; fi; } \
    | /usr/bin/grep -E 'cache_read_input_tokens|"subtype"[[:space:]]*:[[:space:]]*"compact_boundary"' 2>/dev/null | /usr/bin/awk '
    function lastnum(s, key,   re, r, v) { re="\"" key "\"[ \t]*:[ \t]*[0-9]+"; v=0
      while (match(s, re)) { r=substr(s,RSTART,RLENGTH); sub(/.*:[ \t]*/,"",r); v=r+0; s=substr(s,RSTART+RLENGTH) }
      return v }
    { l=$0; ln=NR
      if (index(l,"compact_boundary") && l ~ /"type"[ \t]*:[ \t]*"system"/ && l ~ /"subtype"[ \t]*:[ \t]*"compact_boundary"/) cln=ln
      # keep only the newest 64 usage-bearing lines; they are measured at the END, newest first
      if (index(l,"cache_read_input_tokens") && (index(l,"\"type\":\"assistant\"") || l ~ /"type"[ \t]*:[ \t]*"assistant"/)) { n++; ring[n%64]=l; rln[n%64]=ln } }
    END { for (k=n; k>0 && k>n-64; k--) { l=ring[k%64]
            t=lastnum(l,"input_tokens")+lastnum(l,"cache_creation_input_tokens")+lastnum(l,"cache_read_input_tokens")
            if (t>0) { tot=t; uln=rln[k%64]; break } }
          printf "%d %d %d\n", tot+0, uln+0, cln+0 }' 2>/dev/null
}
ctx_k=""; compact_after=0
if [ -n "$tp" ] && [ -r "$tp" ]; then
  _size=$(/usr/bin/wc -c < "$tp" 2>/dev/null | tr -d ' ')
  for _w in 262144 8388608 0; do
    if [ "$_w" -gt 0 ] && [ "${_size:-0}" -le "$_w" ]; then _w=0; fi
    read -r _ctx_tot _ctx_uln _ctx_cln <<<"$(cic_ctx_window "$_w")"
    case "$_ctx_tot$_ctx_uln$_ctx_cln" in ''|*[!0-9]*) _ctx_tot=0; _ctx_uln=0; _ctx_cln=0 ;; esac
    [ "$_w" = 0 ] && break
    { [ "$_ctx_tot" -gt 0 ] || [ "$_ctx_cln" -gt 0 ]; } && break
  done
  if [ "$_ctx_cln" -gt "$_ctx_uln" ]; then
    compact_after=1
  elif [ "$_ctx_tot" -gt 0 ]; then
    ctx_k=$(( (_ctx_tot + 500) / 1000 ))
    printf 'Context used: %sk tokens (rough, last step)\n' "$ctx_k"
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
# epoch seconds -> LOCAL "YYYY-MM-DD HH:MM", the override ledger's own stamp (override-ledger.sh
# writes `date '+%Y-%m-%d %H:%M'`, local time). GNU `date -d @N` first (BSD date has no -d and
# fails), then BSD `date -r N`; the answer must have the ledger's shape or nothing is returned.
epoch_to_local() {
  local e="$1" s
  s=$(date -d "@$e" '+%Y-%m-%d %H:%M' 2>/dev/null)
  case "$s" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9][0-9]:[0-9][0-9]) ;; *) s=$(date -r "$e" '+%Y-%m-%d %H:%M' 2>/dev/null) ;; esac
  case "$s" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9][0-9]:[0-9][0-9]) printf '%s' "$s" ;; esac
}
gap_min=""; ref=""; now_s=$(date +%s)
if [ "$typed_prompt" = 1 ] && [ -n "$tp" ] && [ -f "$tp" ]; then
  # Your own messages are top-level "type":"user" lines that hold no tool_result (tool
  # results are also "user" lines and carry a promptId too, so the id cannot be the marker),
  # minus every MACHINE line (the classifier above). One awk pass lists them NEWEST FIRST as
  # "<timestamp>TAB<start of the content>"; the walk below stops at the second typed one, so a
  # run of machine lines of any length between two messages cannot push the previous one out.
  # Timestamps are ISO-8601 UTC ("...Z"). The prompt being submitted is already in the file
  # when this hook runs, so a line under 15 s old is skipped and the gap is measured from
  # the previous message instead.
  _hs_raw=$(/usr/bin/grep -E '"type"[[:space:]]*:[[:space:]]*"user"' "$tp" 2>/dev/null | /usr/bin/grep -v '"tool_result"' | /usr/bin/awk '
    { ts="-"; if (match($0, /"timestamp"[ \t]*:[ \t]*"/)) ts=substr($0, RSTART+RLENGTH, 19)
      c=""; if (match($0, /"content"[ \t]*:[ \t]*"/)) { c=substr($0, RSTART+RLENGTH, 4200)
        if (substr(c,1,32)=="[Cross-session delivery notice] ") c=substr($0, RSTART+RLENGTH, 16400) }
      a[NR]=ts "\t" c }
    END { for (i=NR; i>0; i--) print a[i] }' 2>/dev/null)
  _t1=""; _t2=""
  while IFS=$'\t' read -r _uts _uc; do
    case "$_uts" in ''|-) continue ;; esac
    cic_is_machine_text "$_uc" && continue
    if [ "${_uc:0:32}" = "$CIC_FRAME" ]; then
      _ucu="${_uc//\\n/$'\n'}"; _ucu="${_ucu//\\r/}"   # JSON newlines -> real ones, only for a frame-led line
      cic_is_notice_only "$_ucu" && continue
    fi
    if [ -z "$_t1" ]; then _t1="$_uts"; else _t2="$_uts"; break; fi
  done <<<"$_hs_raw"
  if [ -n "$_t1" ]; then
    newest_s=$(to_epoch "$_t1")
    if [ -n "$newest_s" ] && [ $((now_s - newest_s)) -le 15 ]; then
      [ -n "$_t2" ] && ref=$(to_epoch "$_t2")
    else
      ref="$newest_s"
    fi
    [ -n "$ref" ] && gap_min=$(( (now_s - ref) / 60 ))
  fi
fi
returning=0
if [ "$typed_prompt" = 1 ] && [ -n "$gap_min" ] && [ "$gap_min" -ge "$AWAY_MINUTES" ]; then
  printf 'YOU ARE RETURNING after %s minutes away. You did NOT watch what happened. This reply is a COLD START: invoke the summarize skill; summarize what the problem was in one line, whether it is fixed, and what is needed from you. No history, no "as you saw", no codes.\n' "$gap_min"
  returning=1
  # The override words honoured since your previous typed message, by name, from the ledger
  # (override-ledger.sh). Ledger stamps are whole local minutes, so the compare is at minute
  # resolution: an override in the very minute of your previous message counts.
  _ovL="${OVERRIDE_LEDGER:-$HOME/.claude/ledgers/overrides.tsv}"
  if [ -n "$ref" ] && [ -r "$_ovL" ]; then
    _refts=$(epoch_to_local "$ref")
    if [ -n "$_refts" ]; then
      _ov_summary=$(/usr/bin/awk -F'\t' -v r="$_refts" '
        $1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]$/ && $3 != "" && $1 >= r { c[$3]++ }
        END { for (k in c) printf "%d\t%s\n", c[k], k }' "$_ovL" 2>/dev/null | sort -k1,1nr -k2 \
        | /usr/bin/awk -F'\t' '{ printf "%s%s %s", (NR>1 ? ", " : ""), $2, $1 }')
      [ -n "$_ov_summary" ] && printf 'Overrides while you were away: %s\n' "$_ov_summary"
    fi
  fi
fi

# Backup watchdog: one line on your typed prompt when the settings repo has been dirty for over
# WATCHDOG_MINUTES or holds commits the remote does not have. `find -mmin` reads the file age
# (BSD and GNU alike, no `stat`). Silent unless the backup is set up (hooks/backup.conf).
cic_backup_watchdog() {
  local wd="${WATCHDOG_CLAUDE_DIR:-$HOME/.claude}" mins="${WATCHDOG_MINUTES:-60}" reason="" entry st p ahead
  case "$mins" in ''|*[!0-9]*) mins=60 ;; esac
  [ -f "$wd/hooks/backup.conf" ] || return 0
  git -C "$wd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  while IFS= read -r -d '' entry; do
    st="${entry:0:2}"; p="${entry:3}"
    case "$st" in R*|C*) IFS= read -r -d '' _old_p ;; esac   # a rename or copy carries its old path as a second field
    [ -e "$wd/$p" ] || continue
    if [ -n "$(find "$wd/$p" -maxdepth 0 -mmin "+$mins" 2>/dev/null)" ]; then reason="uncommitted changes for over $mins minutes"; break; fi
  done < <(git -C "$wd" status --porcelain -z 2>/dev/null)
  if [ -z "$reason" ]; then
    ahead=$(git -C "$wd" rev-list --count '@{u}..HEAD' 2>/dev/null)
    case "$ahead" in ''|*[!0-9]*|0) ;; *) reason="commits not pushed to its remote" ;; esac
  fi
  [ -n "$reason" ] && printf 'WATCHDOG: the settings repo has %s — the settings backup may be stuck (a secret scan, being offline, a clash, or a lock); check it.\n' "$reason"
  return 0
}
[ "$typed_prompt" = 1 ] && cic_backup_watchdog

# Pending notices: a Stop-time hook (the backup) cannot speak to the model or the person at exit 0,
# so it leaves a small plain-text file in $STATE_CHECK_STATE_DIR/notices/ (default
# ~/.claude/state/state-check/notices/) — format documented in hooks/auto-backup.sh, note_pending().
# The next TYPED prompt prints each one (up to 2,000 bytes) and deletes it, so it is said exactly once.
# Tests: hooks/test-hooks.sh "attack fixes (2)" M6.
cic_pending_notices() {
  local _nd="${STATE_CHECK_STATE_DIR:-$HOME/.claude/state/state-check}/notices" _f
  [ -d "$_nd" ] && [ ! -L "$_nd" ] || return 0
  for _f in "$_nd"/*; do
    [ -f "$_f" ] && [ ! -L "$_f" ] || continue
    printf 'PENDING NOTICE from a background hook (%s) — tell the user about it at the start of your reply:\n' "$(basename "$_f")"
    head -c 2000 "$_f" 2>/dev/null
    rm -f "$_f" 2>/dev/null
  done
  return 0
}
[ "$typed_prompt" = 1 ] && cic_pending_notices

# Fullness note: the context is over CONTEXT_NOTE_K thousand tokens. Typed prompts only, never a
# helper's own transcript. The re-read line needs BOTH you and the model idle CONTEXT_STALE_MIN
# minutes: a chat that was working while you were silent has a warm cache.
CONTEXT_NOTE_K="${CONTEXT_NOTE_K:-400}"; case "$CONTEXT_NOTE_K" in ''|*[!0-9]*) CONTEXT_NOTE_K=400 ;; esac
CONTEXT_STALE_MIN="${CONTEXT_STALE_MIN:-60}"; case "$CONTEXT_STALE_MIN" in ''|*[!0-9]*) CONTEXT_STALE_MIN=60 ;; esac
if [ "$typed_prompt" = 1 ] && [ "$helper" = 0 ] && [ -n "$ctx_k" ] && [ "$ctx_k" -ge "$((10#$CONTEXT_NOTE_K))" ]; then
  note="This chat has used about ${ctx_k}k tokens of context — open your reply with one line on how full this chat is."
  # The wrap-up words replace it once the Stop hook's marker says the wrap-up point was reached (read-only).
  _wu=0
  case "$sid" in ''|*/*|..*) ;; *)
    _STC="${STATE_CHECK_STATE_DIR:-$HOME/.claude/state/state-check}"
    if [ -f "$_STC/wrapup-fired/$sid" ] && [ ! -L "$_STC/wrapup-fired/$sid" ] && [ ! -L "$_STC/wrapup-fired" ] && [ ! -e "$_STC/open/$sid" ]; then
      _wuk=$(head -1 "$_STC/wrapup-fired/$sid" 2>/dev/null)
      case "$_wuk" in ''|*[!0-9]*) ;; *) [ "$ctx_k" -ge "$((10#$_wuk))" ] && _wu=1 ;; esac
    fi ;;
  esac
  if [ "$_wu" = 1 ]; then
    note="This chat has used about ${ctx_k}k tokens of context and is past its wrap-up point — wrapping up: open a fresh chat for new work."
  elif [ -n "$gap_min" ] && [ "$gap_min" -ge "$((10#$CONTEXT_STALE_MIN))" ]; then
    # the newest assistant line's time: the last 1 MB first, the whole file only when that holds none
    _as=""
    for _w in 1048576 0; do
      _as=$({ if [ "$_w" -gt 0 ]; then /usr/bin/tail -c "$_w" "$tp" 2>/dev/null; else /bin/cat "$tp" 2>/dev/null; fi; } | /usr/bin/grep -E '"type"[[:space:]]*:[[:space:]]*"assistant"' 2>/dev/null | /usr/bin/grep -oE '"timestamp"[[:space:]]*:[[:space:]]*"[^"]*"' | /usr/bin/sed 's/.*"\([^"]*\)"[[:space:]]*$/\1/' | cut -c1-19 | tail -1)
      [ -n "$_as" ] && break
    done
    _as_s=""; [ -n "$_as" ] && _as_s=$(to_epoch "$_as")
    if [ -z "$_as_s" ] || [ $(( (now_s - _as_s) / 60 )) -ge "$((10#$CONTEXT_STALE_MIN))" ]; then
      note="$note This wake is $((10#$CONTEXT_STALE_MIN)) minutes or more since the chat's last line — treat it as a re-read: this wake re-read the whole chat."
    fi
  fi
  printf '%s\n' "$note"
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
