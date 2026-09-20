#!/bin/bash
# stop-state-check.sh — Stop hook, paired with doorman.sh (same UserPromptSubmit-side
# hook, same config file). Two independent jobs, each gated on hooks/state-check.conf
# matching the session's working-directory NAME to a role:
#
# (1) RETIRE: once the session's context is at or over that role's configured floor (in
#     thousands of tokens), write state/retired/<session_id> and append a note to
#     state/inbox/<role>.md naming the worktree and any uncommitted TRACKED files. This
#     never blocks the turn — it just leaves the marker doorman.sh checks on the session's
#     NEXT message. Written once per session id (idempotent): re-running an already-retired
#     session neither rewrites the marker nor re-appends to the inbox.
# (2) THE STATE FILE: a turn that CHANGED tracked files may not end unless the role's state
#     file (state-check.conf's STATE_FILE pattern, with {role} substituted) is among them,
#     and its "Current task:" / "Next step:" lines are filled AND actually touched by this
#     turn's diff — printed as a block decision so the file gets written now. Appending a
#     blank line to the state file is not a handover. Never blocks twice in a row
#     (stop_hook_active). Untracked files never count as "changed" — a file git doesn't
#     know about yet is not "the paper trail".
#     "CHANGED" means changed DURING this turn, not "dirty right now": a read-only turn in
#     a tree someone left dirty an hour ago has nothing to write down. The comparison is
#     against the TURN SNAPSHOT hooks/doorman.sh writes when the prompt arrives. With no
#     snapshot (doorman.sh not registered, or a turn that began before it was) this job
#     WARNS instead of blocking — refusing to end a turn on a guess is worse than missing
#     one. Register doorman.sh to get the real check.
#     This job needs no session id; only job (1) does, because only a marker file is keyed
#     by one.
#
# No hooks/state-check.conf at all, or the working directory's basename matches no line in
# it: BOTH jobs are off for this session — the safe default for a single-session project
# with nothing to track. Fails OPEN (exit 0) outside a git repo, or with no readable
# transcript/cwd.
#
# Config: hooks/state-check.conf (see hooks/state-check.conf.example; shared with
# doorman.sh). Test seam: STATE_CHECK_STATE_DIR (where retired/ and inbox/ are written).
# Tests: hooks/test-hooks.sh.
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
# job (1), the marker file that is keyed by it. Job (2) needs no id and keeps running.
case "$sid" in *'/'*|..*) sid="";; esac
active=$(printf '%s' "$input" | /usr/bin/grep -oE '"stop_hook_active"[[:space:]]*:[[:space:]]*(true|false)' | /usr/bin/grep -oE 'true|false' | head -1)
[ -n "$cwd" ] || cwd="$PWD"
base=$(basename "$cwd")

# ---- role + floor lookup (hooks/state-check.conf; see .conf.example) ----
CONF="$(dirname "$0")/state-check.conf"
STATE_FILE_PATTERN="docs/state/{role}.md"
role=""; floor_k=""
if [ -f "$CONF" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue;; esac
    case "$line" in
      STATE_FILE\ *) STATE_FILE_PATTERN="${line#STATE_FILE }"; continue;;
    esac
    set -- $line
    pat="$1"; r="$2"; fk="$3"
    case "$fk" in ''|*[!0-9]*) continue;; esac   # a non-numeric floor: skip this line, not the file
    [ -n "$pat" ] && [ -n "$r" ] || continue
    case "$base" in $pat) role="$r"; floor_k="$fk"; break;; esac
  done < "$CONF"
fi
[ -n "$role" ] || exit 0   # no config, or this folder matches nothing in it: inert
floor_k=$((10#$floor_k))
sf="${STATE_FILE_PATTERN//'{role}'/$role}"
STATE="${STATE_CHECK_STATE_DIR:-$HOME/.claude/state/state-check}"

# ---- (1) retire past the floor ----
if [ -n "$tp" ] && [ -r "$tp" ] && [ -n "$sid" ]; then
  # The whole transcript is scanned (not just a tail) so one long tool result earlier in
  # the file can never push the real, most-recent usage line out of a byte-limited window.
  ctx_line=$(/usr/bin/grep -E '"type"[[:space:]]*:[[:space:]]*"assistant"' "$tp" 2>/dev/null | /usr/bin/grep 'cache_read_input_tokens' 2>/dev/null | /usr/bin/tail -1)
  if [ -n "$ctx_line" ]; then
    cf() { printf '%s' "$ctx_line" | /usr/bin/grep -oE "\"$1\"[[:space:]]*:[[:space:]]*[0-9]+" | /usr/bin/tail -1 | /usr/bin/sed -E 's/.*:[[:space:]]*([0-9]+)/\1/'; }
    ci=$(cf input_tokens); cc=$(cf cache_creation_input_tokens); cr=$(cf cache_read_input_tokens)
    ctx_k=$(( (${ci:-0} + ${cc:-0} + ${cr:-0} + 500) / 1000 ))
    if [ "$ctx_k" -ge "$floor_k" ]; then
      mkdir -p "$STATE/retired"
      if [ ! -e "$STATE/retired/$sid" ]; then
        dirty_files=""; gitrc=1
        if command -v git >/dev/null 2>&1; then
          _dirtyraw="$STATE/.dirty-tmp.$$"
          git -c core.quotepath=false -C "$cwd" status --porcelain -z --untracked-files=no > "$_dirtyraw" 2>/dev/null
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
          printf 'worktree %s\n' "$cwd"
          if [ "$gitrc" != 0 ]; then
            printf 'dirty list unavailable (git failed)\n'
          elif [ -n "$dirty_files" ]; then
            printf '%s\n' "$dirty_files"
          fi
        } > "$STATE/retired/$sid"
        if [ "$gitrc" != 0 ]; then
          mkdir -p "$STATE/inbox"
          printf '\n## %s — to the %s (session %s; RETIRED, dirty list unavailable)\n\nWorktree %s: dirty list unavailable (git failed)\n' \
            "$(date '+%Y-%m-%d %H:%M')" "$role" "${sid:-?}" "$cwd" >> "$STATE/inbox/$role.md"
        elif [ -n "$dirty_files" ]; then
          mkdir -p "$STATE/inbox"
          printf '\n## %s — to the %s (session %s; RETIRED with uncommitted tracked changes)\n\nFiles in %s:\n%s\n' \
            "$(date '+%Y-%m-%d %H:%M')" "$role" "${sid:-?}" "$cwd" "$dirty_files" >> "$STATE/inbox/$role.md"
        fi
      fi
      echo "stop-state-check: this $role is RETIRED at ${ctx_k}k (floor ${floor_k}k) — a fresh $role should start from $sf and the inbox."
    fi
  fi
fi

# ---- (2) the state file ----
git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
now_state=$(git -C "$cwd" status --porcelain --untracked-files=no 2>/dev/null)
changed=$(printf '%s\n' "$now_state" | /usr/bin/grep -c .)
[ "$changed" -gt 0 ] || exit 0
# Did THIS turn change anything? The snapshot doorman.sh took when the prompt arrived says
# what the tree looked like then; identical now means the turn only read.
case "$sid" in
  '') snapkey="nosid-$(printf '%s' "$base" | tr -c 'A-Za-z0-9._-' '_')" ;;
  *)  snapkey="$sid" ;;
esac
SNAP="$STATE/turnsnap/$snapkey"
if [ -f "$SNAP" ]; then
  if [ "$(cat "$SNAP" 2>/dev/null)" = "$now_state" ]; then exit 0; fi
else
  echo "stop-state-check: NOTE — the tree holds $changed changed tracked file(s), but there is no turn snapshot for this session, so this turn may only have READ them. hooks/doorman.sh writes that snapshot on UserPromptSubmit; register it (install.sh's multi-chat group) to turn this note back into a real check."
  exit 0
fi
if [ -n "$(git -C "$cwd" status --porcelain --untracked-files=all -- "$sf" 2>/dev/null)" ]; then
  ct=$(/usr/bin/grep -E '^\*\*Current task:\*\*[[:space:]]*[^[:space:]]' "$cwd/$sf" 2>/dev/null)
  ns=$(/usr/bin/grep -E '^\*\*Next step:\*\*[[:space:]]*[^[:space:]]' "$cwd/$sf" 2>/dev/null)
  if [ -n "$ct" ] && [ -n "$ns" ]; then
    # Filled is not enough: the two lines must be what CHANGED. Appending a blank line to
    # a state file written three turns ago is not a handover. An untracked (brand-new)
    # state file has no diff to read, and its whole content is new, so it passes here.
    touched=yes
    if git -C "$cwd" ls-files --error-unmatch -- "$sf" >/dev/null 2>&1; then
      if [ -z "$(git -C "$cwd" diff HEAD -- "$sf" 2>/dev/null | /usr/bin/grep -E '^[+-]' | /usr/bin/grep -vE '^(\+\+\+|---)' | /usr/bin/grep -E '\*\*(Current task|Next step):\*\*')" ]; then
        touched=no
      fi
    fi
    if [ "$touched" = yes ]; then exit 0; fi
    [ "$active" = "true" ] && { echo "stop-state-check: the state file changed but neither required line moved; not blocking twice."; exit 0; }
    reason3="stop-state-check: $sf was touched but neither its **Current task:** nor its **Next step:** line changed this turn — whitespace is not a handover. Rewrite both to say where this turn actually got to, then stop."
    printf '{"decision":"block","reason":"%s"}\n' "$(json_esc "$reason3")"
    exit 0
  fi
  [ "$active" = "true" ] && { echo "stop-state-check: the state file's Current task / Next step is still unfilled; not blocking twice."; exit 0; }
  reason2="stop-state-check: $sf changed but is missing a filled **Current task:** or **Next step:** line — a resuming seat cannot pick up from it. Fill both (under 200 words total), then stop."
  printf '{"decision":"block","reason":"%s"}\n' "$(json_esc "$reason2")"
  exit 0
fi
[ "$active" = "true" ] && { echo "stop-state-check: the state file is still untouched; not blocking twice."; exit 0; }
reason="stop-state-check: this turn leaves $changed changed tracked file(s) in $base but $sf is untouched. Rewrite $sf now (under 200 words — current task, next step, open questions, what must not be repeated), then stop."
printf '{"decision":"block","reason":"%s"}\n' "$(json_esc "$reason")"
exit 0
