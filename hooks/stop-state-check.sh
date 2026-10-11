#!/bin/bash
# stop-state-check.sh — Stop hook, paired with doorman.sh (same UserPromptSubmit-side
# hook, same config file). Jobs, each gated on hooks/state-check.conf matching the session's
# folder to a role (the git TOPLEVEL folder's name, so a chat opened in a subfolder of a
# seat's folder matches too):
#
# (1) RETIRE: once the session's context is at or over that role's configured floor (in
#     thousands of tokens), write state/retired/<session_id> (plus its companion
#     state/retired-compacts/<session_id>, the count of compact boundaries at that moment;
#     a marker without its companion counts as absent and is written again) and append a
#     note to state/inbox/<role>.md naming the worktree and any uncommitted TRACKED files.
#     This never blocks the turn — it just leaves the marker doorman.sh checks on the
#     session's NEXT message. Written once per session id (idempotent). The one-line
#     RETIRED sentence goes to STDERR, never stdout: a Stop hook's stdout is read as a
#     decision only when the WHOLE of it starts with "{", so a sentence printed first
#     silently dropped the state-file block below on the same turn.
# (2) THE STATE FILE: a turn that CHANGED the repo may not end unless the role's state
#     file (state-check.conf's STATE_FILE pattern, with {role} substituted) changed too, and
#     its FIRST "**Current task:**" and FIRST "**Next step:**" lines are filled AND differ
#     from what they were when the turn began — printed as a block decision so the file gets
#     written now. A prose mention of a marker, or a second marker line appended below the
#     real one, is not the line moving. Never blocks twice in a row (stop_hook_active).
#     Untracked files never count as "changed".
#     "CHANGED" means changed DURING this turn, not "dirty right now": the comparison is
#     against the TURN SNAPSHOT hooks/doorman.sh writes when the prompt arrives — four
#     tab-separated fields: HEAD, the state file's hash, a hash of `git diff HEAD` (the
#     CONTENT of every tracked change, so a second edit to an already-dirty file is seen),
#     a hash of the state file's two marker lines, and the repo's top-level folder. When the
#     Stop is in a DIFFERENT repo than the snapshot's (a `cd` during the turn) the check is
#     skipped with a notice, never judged on the wrong repo. A turn that only COMMITTED moves HEAD
#     and is caught; a turn that changed nothing passes even in a tree left dirty an hour
#     ago. With no snapshot (doorman.sh not registered, or a turn that began before it was)
#     this job WARNS instead of blocking — refusing to end a turn on a guess is worse than
#     missing one. A snapshot that is a symlink is never followed (skipped, one stderr note).
#     This job needs no session id; only the marker-file jobs do, because those files are
#     keyed by one. State file and every git call are resolved from the git toplevel.
# (3) THE WRAP-UP: at the FIRST Stop past WRAPUP_K thousand tokens (conf key, default 600,
#     illustrative) in a role listed in WRAPUP_ROLES (default: the dev seats; "*" = every role),
#     block once, after job (2) had nothing to say (one Stop output, never two JSON objects),
#     telling the seat to finish the task in hand, land it, update the state file and say it is
#     ready to retire. Never on the forced second stop, never while an unattended run is on
#     (guard-lib.sh's unattended_run_active), once per session ($STATE/wrapup-fired/<sid>,
#     which also tells clock-in-context.sh to swap its fullness line for the wrap-up words).
# (4) THE HELPER TELL: a turn that grew the context by TELL_GROWTH_K thousand tokens or more, compared in exact tokens (default
#     30, illustrative) with no Agent/Workflow launched leaves one line in $STATE/tell/<sid>;
#     doorman.sh shows it at the next passing prompt, then deletes it. Roles in
#     TELL_EXEMPT_ROLES never get it. The growth is measured from $STATE/turn-start/<sid>
#     (the context size doorman.sh wrote at the prompt, and this hook rewrites at every Stop).
# (5) SCHEDULED PROMPTS: the session's cron/loop prompts, from the Stop input's
#     session_crons[].prompt, are written to $STATE/crons/<sid> (needs jq; without jq this is
#     skipped silently) so a later prompt hook can tell a fired schedule from a typed message.
#     Rewritten at every Stop; an empty list removes the file.
# Every state file this hook writes is skipped when its path (or its folder) is a symlink.
# Notes that would only reach a stderr nobody reads (the retirement, "no turn snapshot", a skipped check)
# are also left as a pending notice in $STATE/notices/<source>, shown at the next typed prompt.
#
# SHARED-FOLDER CHATS (opt-in per repo): a folder the conf does not name may still hold several chats that
# share it. A repo opts in by COMMITTING `.claude/state-roles.tsv` at its git top, tracked (an untracked or ignored file does not count) (`<pattern><TAB><state file path
# from the top>`; see state-check.conf.example); guard-lib.sh's hook_state_role reads the chat's role from its
# title or first message. Such a chat gets job (2) only, with a lighter rule: a turn whose OWN transcript wrote one
# of the tracked files that changed (or a folder holding one), or committed (git commit/merge/cherry-pick/revert, with or without -C/-c
# options), or wrote something whose target cannot be read (sed -i, a quoted or variable redirect target, git
# apply, an interpreter body that writes), and that did not change its state file, is blocked once (a Heartbeat
# line is asked); a state file with uncommitted changes is asked to be committed by path. Another chat's edit in
# the same folder never blocks, and neither does this chat's write to a file outside the changed set (a /tmp
# file). What this chat wrote is read by guard-lib.sh's turn_scan (also used by chapter-note.sh) from the last
# TYPED prompt on: a mid-turn task notification, an isMeta skill body or a slash-command wrapper does not move
# the start. Not covered: a write through eval, xargs, a function or a variable as the command; a path written
# as a shell glob or a quoted word counts as unreadable (this chat's); a queued owner message that the app
# writes as a typed user line starts a new turn like any prompt.
# No retirement, wrap-up or helper tell for these chats. Every threshold above compares the EXACT token count
# (399,999 is under 400k); the "k" figure in a message is only the rounded display.
# No hooks/state-check.conf at all, or the folder matches no line in it and no repo mapping: EVERY job is off for
# this session — the safe default for a single-session project with nothing to track. Fails OPEN
# (exit 0) outside a git repo, with no readable transcript/cwd, or when hooks/guard-lib.sh (the
# shared conf reader) is missing (one stderr note).
#
# Config: hooks/state-check.conf (see hooks/state-check.conf.example; shared with
# doorman.sh). Test seam: STATE_CHECK_STATE_DIR (where the marker folders are written).
# Portable: no `shasum`, `stat -f` or `tail -r`; every hash comes from git itself.
# Tests: hooks/test-hooks.sh (sections 25, 29, "refresh 2026-09-29 (c2a)" and "attack fixes (3)").
input=$(cat 2>/dev/null); [ -z "$input" ] && exit 0
field() { printf '%s' "$input" | /usr/bin/sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
json_esc() {
  local s
  s=$(printf '%s' "$1" | /usr/bin/sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}
tp=$(field transcript_path); cwd=$(field cwd); sid=$(field session_id)
# An empty or traversal-shaped session id must touch no path below — but it only disables
# the jobs keyed by it (the marker files). Job (2) needs no id and keeps running.
case "$sid" in *'/'*|..*) sid="";; esac
active=$(printf '%s' "$input" | /usr/bin/grep -oE '"stop_hook_active"[[:space:]]*:[[:space:]]*(true|false)' | /usr/bin/grep -oE 'true|false' | head -1)
[ -n "$cwd" ] || cwd="$PWD"

# ---- role + floor lookup: guard-lib.sh's state_conf_read (hooks/state-check.conf) ----
_lib="$(dirname "$0")/guard-lib.sh"
# shellcheck disable=SC1090
[ -r "$_lib" ] && . "$_lib" 2>/dev/null
if ! command -v state_conf_read >/dev/null 2>&1; then
  echo "stop-state-check: guard-lib.sh (the shared conf reader) is missing beside this hook — doing nothing." >&2
  exit 0
fi
CONF="$(dirname "$0")/state-check.conf"
# A folder the conf does not name may still belong to a repo that opted in with a committed
# .claude/state-roles.tsv (guard-lib.sh's hook_state_role: chats sharing ONE folder, the role read from the
# session's title or first message). mapped_sf is set only then, and only job (2) runs for such a chat.
mapped_sf=""
if state_conf_read "$cwd" "$CONF"; then
  role="$STC_ROLE"; floor_k=$((10#$STC_FLOOR_K)); sf="${STC_STATE_FILE//'{role}'/$role}"
elif [ -n "$sid" ] && command -v hook_state_role >/dev/null 2>&1 && _m=$(hook_state_role "$cwd" "$tp" 2>/dev/null); then
  role="${_m%%$'\t'*}"; mapped_sf="${_m#*$'\t'}"; floor_k=0; sf="$mapped_sf"
else
  exit 0   # no config, or this folder matches nothing in it and no repo mapping: inert
fi
top="$STC_TOP"; base="$STC_BASE"
STATE="${STATE_CHECK_STATE_DIR:-$HOME/.claude/state/state-check}"

# safe_state_file <dir> <name> — true only when neither the folder nor the file is a symlink.
safe_state_file() { [ ! -L "$STATE/$1" ] && [ ! -L "$STATE/$1/$2" ]; }
# ssc_notice <source> <text> — a stderr line at exit 0 reaches nobody, so the note also goes into the kit's notice
# folder ($STATE/notices/<source>, private): clock-in-context.sh shows it at the next typed prompt, then deletes
# it. One file per source; a later note of the same source replaces the earlier one.
ssc_notice() {
  [ ! -L "$STATE/notices" ] && [ ! -L "$STATE/notices/$1" ] || return 0
  ( umask 077; mkdir -p "$STATE/notices" && printf '%s\n' "$2" > "$STATE/notices/$1" ) 2>/dev/null
  return 0
}

# ---- (5) register the session's scheduled prompts (needs jq; silently skipped without it) ----
if [ -n "$sid" ] && command -v jq >/dev/null 2>&1 && safe_state_file crons "$sid"; then
  _cron_lines=$(printf '%s' "$input" | jq -c '(.session_crons // [])[]?.prompt | select(type=="string") | gsub("^\\s+|\\s+$";"") | select(length>0)' 2>/dev/null)
  if [ -n "$_cron_lines" ]; then
    mkdir -p "$STATE/crons" 2>/dev/null && printf '%s\n' "$_cron_lines" > "$STATE/crons/$sid" 2>/dev/null
  else
    rm -f "$STATE/crons/$sid" 2>/dev/null
  fi
fi

# ---- (1) retire past the floor, and (4) the helper tell ----
ctx_k=""; ctx_tok=""
if [ -z "$mapped_sf" ] && [ -n "$tp" ] && [ -r "$tp" ] && [ -n "$sid" ]; then
  # ONE windowed read (guard-lib.sh's stc_ctx_read): the newest usage line whose counters are not all zero
  # (an API-error answer is not a measurement), found from the end of the file, widened only as far as needed.
  stc_ctx_read "$tp"
  if [ "$STC_CTX_TOT" -gt 0 ]; then
    ctx_k=$(( (STC_CTX_TOT + 500) / 1000 ))   # the figure shown; every threshold below compares ctx_tok, the exact tokens
    ctx_tok=$STC_CTX_TOT

    # (4) the helper tell. Growth = ctx_k now minus the size doorman.sh wrote at the prompt.
    # "A helper launched this turn" = an Agent or Workflow tool_use after the last top-level
    # user line whose "origin" kind is human or peer (a tool result is also a top-level user
    # line but carries no origin). No such prompt line found: the turn's start cannot be
    # located, so no tell rather than scanning the whole file (one old Agent call would silence
    # every later turn). The tell never goes to stdout (see the header): it is a file.
    snap_start="$STATE/turn-start/$sid"
    if [ -f "$snap_start" ] && ! [ -L "$snap_start" ] && ! [ -L "$STATE/turn-start" ]; then
      start_k=$(head -1 "$snap_start" 2>/dev/null)
      case "$start_k" in ''|*[!0-9]*) start_k="";; esac
      tell_exempt=0
      _exempt_lc=$(printf ' %s ' "$STC_TELL_EXEMPT" | tr 'A-Z\t' 'a-z ')
      case "$_exempt_lc" in *" $(printf '%s' "$role" | tr 'A-Z' 'a-z') "*) tell_exempt=1;; esac
      if [ -n "$start_k" ] && [ "$tell_exempt" = 0 ]; then
        # exact tokens, as every other threshold: the exact size doorman.sh wrote beside the rounded one
        # (turn-start-tok/<sid>) when it agrees with it, else the rounded figure
        start_tok=$((10#$start_k * 1000))
        if [ -f "$STATE/turn-start-tok/$sid" ] && ! [ -L "$STATE/turn-start-tok/$sid" ] && ! [ -L "$STATE/turn-start-tok" ]; then
          _st=$(head -1 "$STATE/turn-start-tok/$sid" 2>/dev/null)
          case "$_st" in ''|*[!0-9]*) ;; *) [ $(( (10#$_st + 500) / 1000 )) -eq $((10#$start_k)) ] && start_tok=$((10#$_st));; esac
        fi
        growth_tok=$(( ctx_tok - start_tok )); growth_k=$(( (growth_tok + 500) / 1000 ))
        if [ "$growth_tok" -ge "$((STC_TELL_K * 1000))" ]; then
          last_prompt_line=$(/usr/bin/grep -nE '"type"[[:space:]]*:[[:space:]]*"user".*"origin"[[:space:]]*:[[:space:]]*\{[[:space:]]*"kind"[[:space:]]*:[[:space:]]*"(human|peer)"' "$tp" 2>/dev/null | /usr/bin/tail -1 | /usr/bin/cut -d: -f1)
          if [ -n "$last_prompt_line" ]; then
            agent_count=$(/usr/bin/tail -n "+$((last_prompt_line+1))" "$tp" 2>/dev/null | /usr/bin/grep '"type":"tool_use"' 2>/dev/null | /usr/bin/grep -cE '"name"[[:space:]]*:[[:space:]]*"(Agent|Workflow)"' 2>/dev/null)
            [ -n "$agent_count" ] || agent_count=0
            if [ "$agent_count" = 0 ] && safe_state_file tell "$sid"; then
              mkdir -p "$STATE/tell" 2>/dev/null
              printf '%s\n' "$growth_k" > "$STATE/tell/$sid" 2>/dev/null
            fi
          fi
        fi
      fi
    fi
    # Rewrite the turn-start size with THIS turn's end size (a turn that began without a prompt
    # hook — a wake, a peer message — is still measured from where the last turn ended).
    if [ ! -L "$snap_start" ] && [ ! -L "$STATE/turn-start" ]; then
      mkdir -p "$STATE/turn-start" 2>/dev/null
      printf '%s\n' "$ctx_k" > "$snap_start" 2>/dev/null
    fi
    if [ ! -L "$STATE/turn-start-tok" ] && [ ! -L "$STATE/turn-start-tok/$sid" ]; then
      mkdir -p "$STATE/turn-start-tok" 2>/dev/null
      printf '%s\n' "$ctx_tok" > "$STATE/turn-start-tok/$sid" 2>/dev/null
    fi

    # (1) retire.
    if [ "$ctx_tok" -ge "$((floor_k * 1000))" ]; then
      mkdir -p "$STATE/retired"
      # Idempotent: an already-retired sid with its companion is neither rewritten nor re-appended
      # to the inbox. A marker without a companion counts as absent; a symlinked companion is
      # removed and written as a real file, never written through.
      if [ ! -e "$STATE/retired/$sid" ] || [ ! -e "$STATE/retired-compacts/$sid" ] || [ -L "$STATE/retired-compacts/$sid" ]; then
        if [ ! -L "$STATE/retired-compacts" ]; then
          mkdir -p "$STATE/retired-compacts" 2>/dev/null
          [ -L "$STATE/retired-compacts/$sid" ] && rm -f "$STATE/retired-compacts/$sid" 2>/dev/null
          { /usr/bin/grep -F compact_boundary "$tp" 2>/dev/null | /usr/bin/grep -cE '"subtype"[[:space:]]*:[[:space:]]*"compact_boundary"' 2>/dev/null || true; } | head -1 > "$STATE/retired-compacts/$sid" 2>/dev/null
        fi
        _retired_now=1
        dirty_files=""; gitrc=1
        if command -v git >/dev/null 2>&1; then
          _dirtyraw="$STATE/.dirty-tmp.$$"
          git -c core.quotepath=false -C "$top" status --porcelain -z --untracked-files=no > "$_dirtyraw" 2>/dev/null
          gitrc=$?
          if [ "$gitrc" = 0 ]; then
            # Parse the NUL-separated entries directly — never load the whole blob into a
            # bash variable (bash truncates on an embedded NUL). A rename (code starting
            # with R) is two NUL fields: new path, then old path — written as "old -> new".
            entries=()
            while IFS= read -r -d '' _tok; do entries+=("$_tok"); done < "$_dirtyraw"
            _i=0; _n=${#entries[@]}
            while [ "$_i" -lt "$_n" ]; do
              _tok="${entries[$_i]}"; _code="${_tok:0:1}"; _path="${_tok:3}"
              case "$_code" in
                R)
                  _i=$((_i+1)); _oldpath="${entries[$_i]}"
                  dirty_files="${dirty_files}${dirty_files:+$'\n'}${_oldpath} -> ${_path}"
                  ;;
                *)
                  dirty_files="${dirty_files}${dirty_files:+$'\n'}${_path}"
                  ;;
              esac
              _i=$((_i+1))
            done
          fi
          rm -f "$_dirtyraw"
        fi
        {
          printf '%s %s %sk\n' "$(date '+%Y-%m-%d %H:%M')" "$role" "$ctx_k"
          printf 'worktree %s\n' "$top"
          if [ "$gitrc" != 0 ]; then
            printf 'dirty list unavailable (git failed)\n'
          elif [ -n "$dirty_files" ]; then
            printf '%s\n' "$dirty_files"
          fi
        } > "$STATE/retired/$sid"
        # A symlinked inbox file, or a symlinked inbox/ folder, is never followed: it could point at
        # /dev/stdout and put this record on stdout ahead of a decision JSON. Skipped with a note.
        inbox_path="$STATE/inbox/$role.md"
        if [ -L "$STATE/inbox" ] || [ -L "$inbox_path" ]; then
          echo "stop-state-check: inbox path is a symlink; skipping the retirement inbox record" >&2
        elif [ "$gitrc" != 0 ]; then
          mkdir -p "$STATE/inbox"
          printf '\n## %s — to the %s (session %s; RETIRED, dirty list unavailable)\n\nWorktree %s: dirty list unavailable (git failed)\n' \
            "$(date '+%Y-%m-%d %H:%M')" "$role" "${sid:-?}" "$top" >> "$inbox_path"
        elif [ -n "$dirty_files" ]; then
          mkdir -p "$STATE/inbox"
          printf '\n## %s — to the %s (session %s; RETIRED with uncommitted tracked changes)\n\nFiles in %s:\n%s\n' \
            "$(date '+%Y-%m-%d %H:%M')" "$role" "${sid:-?}" "$top" "$dirty_files" >> "$inbox_path"
        fi
      fi
      # STDERR, not stdout (see the header): stdout is reserved for a decision JSON. On exit 0 this
      # only reaches the debug log; the doorman's refusal at the next message is what the seat sees.
      echo "stop-state-check: this $role is RETIRED at ${ctx_k}k (floor ${floor_k}k) — a fresh $role should start from $sf and the inbox." >&2
      [ "${_retired_now:-0}" = 1 ] && ssc_notice stop-state-check-retired "stop-state-check hook: this $role chat is RETIRED at ${ctx_k}k (its floor is ${floor_k}k) — its next message is held and passed on to a fresh $role chat, which should start from $sf and the inbox."
    fi
  fi
fi

# ---- (3) the wrap-up: called ONLY where job (2) has decided not to print its own block ----
# Prints the ONE wrap-up block (returns 0) the first time this fires for the session; every other
# time (already fired, a role not listed, under the point, the forced second stop, an unattended
# run) it prints nothing and returns 1.
maybe_stop_wrapup() {
  [ "$active" = "true" ] && return 1
  [ -n "$sid" ] || return 1
  [ -n "$ctx_tok" ] && [ "$ctx_tok" -ge "$((STC_WRAPUP_K * 1000))" ] || return 1
  local _roles _r
  _roles=$(printf ' %s ' "$STC_WRAPUP_ROLES" | tr 'A-Z\t' 'a-z ')
  _r=$(printf '%s' "$role" | tr 'A-Z' 'a-z')
  case "$_roles" in *" * "*|*" $_r "*) ;; *) return 1 ;; esac
  unattended_run_active "$CONF" && return 1
  { [ -e "$STATE/wrapup-fired/$sid" ] || [ -L "$STATE/wrapup-fired/$sid" ] || [ -L "$STATE/wrapup-fired" ]; } && return 1
  mkdir -p "$STATE/wrapup-fired" 2>/dev/null
  printf '%s\n' "$STC_WRAPUP_K" > "$STATE/wrapup-fired/$sid" 2>/dev/null
  local wreason="stop-state-check: this $role is past its ${STC_WRAPUP_K}k wrap-up point — finish the task in hand, land it, update $sf, and say it is ready to retire."
  printf '{"decision":"block","reason":"%s"}\n' "$(json_esc "$wreason")"
  return 0
}
# Every "job (2) has nothing to block" exit goes through here.
pass_exit() { maybe_stop_wrapup; exit 0; }

# ---- (2) the state file ----
git -C "$top" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
case "$sid" in
  '') snapkey="nosid-$(printf '%s' "$base" | tr -c 'A-Za-z0-9._-' '_')" ;;
  *)  snapkey="$sid" ;;
esac
SNAP="$STATE/turnsnap/$snapkey"
snap_ok=0
if [ -L "$SNAP" ] || [ -L "$STATE/turnsnap" ]; then
  echo "stop-state-check: the turn snapshot path is a symlink; not following it" >&2
elif [ -f "$SNAP" ]; then
  snap_line=$(head -1 "$SNAP" 2>/dev/null)
  case "$snap_line" in *$'\t'*$'\t'*$'\t'*) snap_ok=1 ;; esac   # anything not four fields is an old-format file: no snapshot
  IFS=$'\t' read -r snap_head snap_sf snap_tree snap_mk snap_top <<<"$snap_line"
fi
# A cd during the turn: the snapshot was taken in ANOTHER repo than the one this Stop is in (a snapshot without
# the repo field, from an older doorman, is judged as before). Judging the wrong repo would block a read-only
# turn or pass a real change, so the check is skipped, with a notice.
if [ "$snap_ok" = 1 ] && [ -n "$snap_top" ] && [ "$snap_top" != "$top" ]; then
  echo "stop-state-check: this turn started in $snap_top but ended in $top — the state-file check is skipped." >&2
  ssc_notice stop-state-check-cwd "stop-state-check hook: the state-file check was skipped for the last turn — it started in $(basename "$snap_top") but ended in $base (a cd), so no repo was judged. If the turn changed files in $(basename "$snap_top"), update its state file by hand."
  pass_exit
fi
# A mapped chat shares its folder with others: with no snapshot it is never judged (the folder holds their dirt).
[ -n "$mapped_sf" ] && [ "$snap_ok" != 1 ] && exit 0
changed=$(git -C "$top" status --porcelain --untracked-files=no 2>/dev/null | /usr/bin/grep -c .)

if [ "$snap_ok" = 1 ]; then
  cur_head=$(git -C "$top" rev-parse HEAD 2>/dev/null); cur_head="${cur_head:-none}"
  cur_tree=$(git -C "$top" diff --no-ext-diff --no-textconv HEAD 2>/dev/null | git -C "$top" hash-object --stdin 2>/dev/null); cur_tree="${cur_tree:-none}"
  cur_sf=none; cur_mk=none
  if [ -f "$top/$sf" ]; then
    cur_sf=$(git -C "$top" hash-object -- "$top/$sf" 2>/dev/null); cur_sf="${cur_sf:-none}"
    cur_mk=$({ /usr/bin/grep -m1 -E '^\*\*Current task:\*\*' "$top/$sf" 2>/dev/null; /usr/bin/grep -m1 -E '^\*\*Next step:\*\*' "$top/$sf" 2>/dev/null; } | git -C "$top" hash-object --stdin 2>/dev/null); cur_mk="${cur_mk:-none}"
  fi
  # Nothing moved this turn (HEAD and every tracked change's content): pass, whatever was dirty before.
  if [ "$cur_head" = "$snap_head" ] && [ "$cur_tree" = "$snap_tree" ]; then pass_exit; fi
  # A mapped (shared-folder) chat: the state file must change (blocks once), and a state file with uncommitted
  # changes is asked to be committed by path. The Current task / Next step lines are not asked of it. The folder is
  # shared, so a change is THIS chat's only when its own transcript, after the turn's last real user entry (a user
  # line that is not a tool result), holds a file-writing tool use or a Bash git commit/merge/cherry-pick/revert:
  # another chat's edit in the same folder never blocks.
  if [ -n "$mapped_sf" ]; then
    turn_scan "$tp" "" || exit 0
    [ "${TS_PL:-0}" -gt 0 ] || exit 0
    _m_own=0
    { [ "${TS_COMMIT:-0}" -gt 0 ] || [ "${TS_UNREAD:-0}" = 1 ]; } && _m_own=1
    if [ "$_m_own" = 0 ] && [ -n "$TS_PATHS" ]; then
      # hold only when a written path is one of the tracked paths that changed (dirty now, or moved by a commit since the snapshot)
      _m_chg=$(git -C "$top" -c core.quotepath=false diff --no-ext-diff --no-textconv --name-only HEAD 2>/dev/null)
      if [ -n "$snap_head" ] && [ "$snap_head" != "$cur_head" ] && git -C "$top" rev-parse --verify -q "$snap_head^{commit}" >/dev/null 2>&1; then
        _m_chg="$_m_chg
$(git -C "$top" -c core.quotepath=false diff --no-ext-diff --no-textconv --name-only "$snap_head" HEAD 2>/dev/null)"
      fi
      _m_topp=$(cd "$top" 2>/dev/null && pwd -P); _m_cwdp=$(cd "$cwd" 2>/dev/null && pwd -P); _m_rel=""; _m_nl=$'\n'
      case "$_m_cwdp/" in "$_m_topp/"*) _m_rel="${_m_cwdp#"$_m_topp"}"; _m_rel="${_m_rel#/}";; esac
      while IFS= read -r _m_p; do
        [ -n "$_m_p" ] || continue
        case "$_m_p" in /*) _m_d=$(cd "${_m_p%/*}" 2>/dev/null && pwd -P) && [ -n "$_m_d" ] && _m_p="${_m_d%/}/${_m_p##*/}";; esac   # resolve links in the folder part
        case "$_m_p" in
          "$top"/*) _m_p="${_m_p#"$top"/}";;
          "$_m_topp"/*) _m_p="${_m_p#"$_m_topp"/}";;
          /*) continue;;
          *) [ -n "$_m_rel" ] && _m_p="$_m_rel/${_m_p#./}" || _m_p="${_m_p#./}";;
        esac
        _m_p="${_m_p%/}"
        [ -n "$_m_p" ] || continue
        # a changed line that IS the path, or starts with the path and a slash (a folder holding it): read from the
        # start of the line, so a write to ocs is not one inside docs/ (test-hooks.sh "kit follow-up 2026-10-11" K1)
        case "$_m_nl$_m_chg$_m_nl" in *"$_m_nl$_m_p$_m_nl"*|*"$_m_nl$_m_p/"*) _m_own=1; break;; esac
      done <<EOF_P
$TS_PATHS
EOF_P
    fi
    [ "$_m_own" = 1 ] || exit 0
    _m_ask=""
    if [ "$cur_sf" = "$snap_sf" ]; then
      _m_ask="this turn changed tracked files in $base but $sf did not change since the turn started. Files are memory: rewrite $sf now (under 200 words: current task, next step, open questions, what must not be repeated) with a Heartbeat: line holding the current time."
    fi
    if [ -n "$(git -C "$top" status --porcelain --untracked-files=all -- "$sf" 2>/dev/null)" ]; then
      _m_ask="${_m_ask:+$_m_ask }$sf has uncommitted changes, and work that is not in the repo can be lost: commit it by path (git commit -- $sf)."
    fi
    [ -n "$_m_ask" ] || exit 0
    [ "$active" = "true" ] && { echo "stop-state-check: the mapped state file is still not saved; not blocking twice." >&2; exit 0; }
    printf '{"decision":"block","reason":"%s"}\n' "$(json_esc "stop-state-check: $_m_ask Then stop.")"
    exit 0
  fi
  if [ "$cur_sf" = "$snap_sf" ]; then
    [ "$active" = "true" ] && { maybe_stop_wrapup; echo "stop-state-check: the state file is still untouched; not blocking twice."; exit 0; }
    reason="stop-state-check: this turn changed the repo (a commit and/or the working tree) in $base but $sf did not change since the turn started. Rewrite $sf now (under 200 words — current task, next step, open questions, what must not be repeated), then stop."
    printf '{"decision":"block","reason":"%s"}\n' "$(json_esc "$reason")"
    exit 0
  fi
  # The resume half: a fresh seat picks up from the FIRST two marker lines, so a state file that
  # changed but left either empty is not a state file. -m1: the first occurrence is the canonical one.
  ct=$(/usr/bin/grep -m1 -E '^\*\*Current task:\*\*[[:space:]]*[^[:space:]]' "$top/$sf" 2>/dev/null)
  ns=$(/usr/bin/grep -m1 -E '^\*\*Next step:\*\*[[:space:]]*[^[:space:]]' "$top/$sf" 2>/dev/null)
  if [ -n "$ct" ] && [ -n "$ns" ]; then
    # Filled is not enough: the two first lines must be what CHANGED since the turn began. Compared
    # by their hash in the snapshot, so a prose mention or an appended duplicate marker line, which
    # leave the first lines alone, do not count.
    if [ "$cur_mk" != "$snap_mk" ]; then pass_exit; fi
    [ "$active" = "true" ] && { maybe_stop_wrapup; echo "stop-state-check: the state file changed but neither required line moved; not blocking twice."; exit 0; }
    reason3="stop-state-check: $sf changed, but its two marker lines did not. Change the wording of the FIRST line that starts with **Current task:** or of the FIRST line that starts with **Next step:** so it says where this turn got to (notes added elsewhere in the file, or a whitespace edit, do not count), then stop."
    printf '{"decision":"block","reason":"%s"}\n' "$(json_esc "$reason3")"
    exit 0
  fi
  [ "$active" = "true" ] && { maybe_stop_wrapup; echo "stop-state-check: the state file's Current task / Next step is still unfilled; not blocking twice."; exit 0; }
  reason2="stop-state-check: $sf changed but is missing a filled **Current task:** or **Next step:** line — a resuming seat cannot pick up from it. Fill both (under 200 words total), then stop."
  printf '{"decision":"block","reason":"%s"}\n' "$(json_esc "$reason2")"
  exit 0
fi

# --- no usable turn snapshot: warn, never block on a guess ---
[ "$changed" -gt 0 ] || pass_exit
_nosnap="stop-state-check: NOTE — the tree holds $changed changed tracked file(s), but there is no turn snapshot for this session, so this turn may only have READ them. hooks/doorman.sh writes that snapshot on UserPromptSubmit; register it (install.sh's multi-chat group) to turn this note back into a real check."
maybe_stop_wrapup || { echo "$_nosnap"; ssc_notice stop-state-check-nosnap "$_nosnap"; }
exit 0
