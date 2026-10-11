#!/bin/bash
# PreToolUse hook on Bash. Refuses, BEFORE they run, git commands that throw away work or
# rewrite shared history without an explicit go-ahead: reset --hard, clean -f/--force,
# branch -D (force delete), checkout/restore that wipes the whole tree, force-push
# (`--force`, `-f`, `--force-with-lease`, and a leading `+` on a refspec — `git push origin
# +main` / `+HEAD:main` mean the same thing as `--force` and are refused the same way),
# deleting a remote branch that is not fully merged (or the default branch, or one that cannot
# be checked), and history rewrites (filter-branch/filter-repo). Plain `git push` is always
# allowed.
# Also refused, on any git command: `--no-verify` and `-c core.hooksPath=...` (they switch off
# every other hook); and the going-public stop: `gh repo create ... --public`, `gh repo edit
# ... --visibility public` and `npm publish` without `--dry-run`. Both are read on the copy
# with quoted content blanked, so a message or printf that only NAMES them passes.
# `git push origin --delete <b>` / `-d <b>` / `:<b>` (any flag order, EVERY named branch) is
# judged, not refused blindly: `git cherry origin/<default> origin/<b>` after a quiet fetch of
# the branch, bounded to 10 seconds. THIS GUARD THEREFORE TOUCHES THE NETWORK, only on such a
# delete. Fully merged: passes. Unmerged, the default branch itself, or unreadable (fetch
# failed, no such branch, another remote, a variable name): refused, GITGUARD=1 approves.
# OUT OF SCOPE, stated plainly: `git commit --amend` and `git rebase` are NOT matched by
# this guard, even though both rewrite history — they rewrite only local, unpushed commits
# until a push happens, and that push is where this guard's force-push patterns apply.
# Global git flags between `git` and the subcommand (-c k=v, -C path, --no-pager) are
# tolerated, so they cannot be used to slip a banned command past the match. Argument
# matching never crosses ; & |, so a later command on the same line cannot trigger a
# refusal that belongs to an earlier one.
# HOW THE COMMAND IS READ (hooks/guard-lib.sh, shared with the other Bash guards): commit
# messages and heredoc bodies are dropped first, so a message that merely MENTIONS a banned
# command is not refused; `bash|sh|zsh -c "…"` and `eval "…"` are unwrapped, so a wrapper
# is not a hiding place; tabs, escaped newlines and stray backslashes become spaces and the
# quote CHARACTERS are dropped, so `git reset "--hard"`, `git<TAB>reset<TAB>--hard`,
# `gi\t reset --hard` and a command continued over two lines all match the same pattern.
# Every pattern ends at a space, a line end, or one of ; & | ) > < — so a trailing
# character (`git reset --hard;`, `(git reset --hard)`, `git reset --hard>log`) cannot
# defeat it.
# A command word the guard cannot see — `$GIT reset --hard`, `${G} push --force`,
# `$(which git) clean -f` — is judged by its ARGUMENTS: the hidden word is replaced by
# `git` and the same patterns run again, so the shape still decides. `$(which git) status`
# and `$TOOLS/lint.sh --fix` are unaffected.
# The mirror image is refused instead of judged: a plain `git` whose SUBCOMMAND comes from a
# variable or a substitution (`R=reset; git $R --hard`), or whose ARGUMENT does, after a
# mutating subcommand (`git push origin $F`, `git reset $M`). There the arguments are exactly
# what cannot be read, so nothing is left to decide on — the command is refused and a plain
# spelling asked for. A variable in a read-only command (`git diff HEAD -- $paths`, `git -C
# $W/repo status`, `git log -$n`) is an honest read and passes. A substitution inside a quoted message or
# value is NOT that: `git commit -m "$msg" f.ts` and `git log --author="$me"` still pass,
# because the check reads the copy with quoted content blanked.
# Refused for the same reason, before any of the above: `eval`, `sh -c`, `bash -c` handed
# an argument that is itself a substitution or a bare variable (`eval "$cmd"`). A wrapper
# around an inline literal is unwrapped and judged as usual (`sh -c 'git reset --hard'` is
# still refused, `bash -c 'ls -la'` still passes), but text that does not exist until the
# shell runs it cannot be unwrapped, and GITGUARD=1 does not waive it: there is nothing to
# approve until the command is readable.
# Deliberate, approved run: start the SEGMENT that would be refused with `GITGUARD=1 ` —
# `echo x && GITGUARD=1 git reset --hard` approves the reset, while
# `git push --force && GITGUARD=1 true` approves only the `true` and the force-push is
# still refused. The word is read on text with quoted strings removed, so the token inside
# a message or a quoted argument does not disarm the guard. Every HONOURED use is written
# to hooks/override-ledger.sh with the pattern it bypassed; if that line CANNOT be written
# (no ledger script, unwritable path) the override is REFUSED, not honoured. An override
# standing in front of a segment that was never going to be refused waives nothing and
# writes NO line — the ledger records approvals, not the typing of the word.
# Optional extra check, OFF by default: in a checkout shared by more than one session
# (a shared dev box, a pair-programming worktree), `git stash` hides EVERY session's
# uncommitted work, not just the caller's. List the repos where that applies in
# hooks/block-dangerous-git.conf (see hooks/block-dangerous-git.conf.example) — one
# substring/regex per line, matched against `git config remote.origin.url`. No file (or
# no match) means this check never fires — the safe default for a solo checkout.
# `git stash list`/`show` always pass, and a session alone in its own linked git
# worktree is exempt (its stash cannot touch another worktree's files).
# Both jq and python3 (guard-lib.sh's GUARD_PY: /usr/bin/python3 if present, else the first on
# PATH, so a broken shim earlier on PATH cannot refuse every call) parse the command below, and
# hooks/guard-lib.sh normalises it; if any of the three is missing this guard cannot read what it is being asked to run, so it
# refuses rather than silently letting an unparsed (and therefore unmatched) command
# through. Hook input that is empty or is not valid JSON is refused for the same reason —
# the one exception is a well-formed call for a tool other than Bash, which carries no
# command to judge. Fail closed, like git-hooks/pre-commit.
# Tests: hooks/test-hooks.sh (`refresh 2026-09-29 (a)` for the off-switch, going-public, delete and python3 rows).
GUARD_LIB="$(dirname "$0")/guard-lib.sh"
if [ ! -r "$GUARD_LIB" ]; then
  echo "block-dangerous-git: REFUSED — hooks/guard-lib.sh is missing next to this hook, so the command cannot be normalised before matching (fail closed, not open). Reinstall the hooks (install.sh copies hooks/*.sh)." >&2
  exit 2
fi
. "$GUARD_LIB"
missing=""
command -v jq >/dev/null 2>&1 || missing="jq"
[ -n "$GUARD_PY" ] && [ -x "$GUARD_PY" ] || missing="${missing:+$missing and }python3"
if [ -n "$missing" ]; then
  echo "block-dangerous-git: REFUSED — $missing not found, so this guard cannot parse the command (fail closed, not open)." >&2
  exit 2
fi
input="$(cat)"
if [ -z "$input" ] || ! printf '%s' "$input" | jq -e . >/dev/null 2>&1; then
  echo "block-dangerous-git: REFUSED — the hook input is empty or is not valid JSON, so the command cannot be read (fail closed, not open)." >&2
  exit 2
fi
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
[ -n "$tool" ] && [ "$tool" != "Bash" ] && exit 0   # a Write/Edit call carries no command
rawcmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
if [ -z "$rawcmd" ]; then
  echo "block-dangerous-git: REFUSED — a Bash tool call with no readable command (fail closed, not open)." >&2
  exit 2
fi
# Three whole-command copies — cmdn normalised with quotes intact (path extraction),
# cmdm with the quote characters dropped, cmdq with the quoted CONTENT blanked — followed
# by one RECORD PER SEGMENT (; && || | & and newlines, split outside quotes), because both
# the match and the override that could waive it belong to one segment, never to the line:
#   <override here 0|1> TAB <match copy> TAB <hidden-command-word copy> TAB <blanked copy>
norm="$(printf '%s' "$rawcmd" | "$GUARD_PY" -I -c "$GUARD_PY_COMMON"'
raw=sys.stdin.read()
# The subcommands this guard judges by their ARGUMENTS: a variable after one of these cannot be
# read (`git push origin $F`), while a variable in a read-only command (`git diff -- $paths`) is fine.
_MUTATING=("push","reset","clean","branch","checkout","restore","filter-branch","filter-repo")
# The wrapper check runs BEFORE unwrap: unwrap lifts an inline literal out of
# `eval "…"` / `sh -c "…"`, but there is nothing to lift out of `eval "$cmd"`.
pre=normalize_ws(strip_messages(strip_heredocs(raw)))
wrapsub="1" if wrapped_substitution(pre) else "0"
s=clean(raw)
recs=[]
assigned={}
for seg in segments(s):
    # A variable given a plain value EARLIER IN THE SAME COMMAND (`B=feature; git push origin $B`)
    # is read as that value, on segments that start with git or a variable command word.
    note_assignments(seg, assigned)
    if re.match(r"\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:git\b|\$)", seg):
        seg=resolve_assigned(seg, assigned)
    m=strip_quotechars(seg).replace("\n", " ")
    q=blank_quoted(seg).replace("\n", " ")
    flag="1" if override_at_start(q, "GITGUARD") else "0"
    asub="1" if substituted_args(q, "git", _MUTATING) else "0"
    recs.append(flag + "\t" + m + "\t" + hidden_cmdword(m, "git") + "\t" + q + "\t" + asub)
sys.stdout.write(s + "\x01" + strip_quotechars(s) + "\x01" + blank_quoted(s) + "\x01" + wrapsub + "\x01" + "\n".join(recs))')"
guard_parsed "block-dangerous-git" python3 $? "$norm" "$rawcmd"
SEP=$'\001'
cmdn="${norm%%$SEP*}"; rest="${norm#*$SEP}"; cmdm="${rest%%$SEP*}"
rest2="${rest#*$SEP}"; cmdq="${rest2%%$SEP*}"
rest3="${rest2#*$SEP}"; wrapsub="${rest3%%$SEP*}"; segrecs="${rest3#*$SEP}"
if [ "$wrapsub" = 1 ]; then
  echo "block-dangerous-git: REFUSED — this command hands \`eval\`, \`sh -c\` or \`bash -c\` an argument that does not exist until the shell runs it (\`eval \"\$cmd\"\`, \`sh -c \"\$(cat run.sh)\"\`). There is no text for this guard to read, so \`git reset --hard\` inside that variable would pass unseen. Write the git command plainly: git <subcommand> … — or put it in a script file and run that. GITGUARD=1 does NOT waive this one; there is nothing to approve until the command is readable." >&2
  exit 2
fi

W='(^|[^a-zA-Z0-9_./-])'                           # `git` as a whole word
G='( +-[^ ;&|]+( +[^-;&| ][^ ;&|]*)?)*'            # optional global flags, each with one optional value
A='( +[^ ;&|]+)*'                                  # optional arguments, never across ; & |
E='([ ;&|)<>]|$)'                                  # the flag ENDS here: no trailing character defeats it
patterns=(
  "${W}git${G} +reset${A} +--hard${E}"
  "${W}git${G} +clean${A} +(-[a-zA-Z]*f[a-zA-Z]*|--force)${E}"
  "${W}git${G} +branch${A} +(-[a-zA-Z]*D[a-zA-Z]*|--delete +--force|--force +--delete)${E}"
  "${W}git${G} +checkout${A} +\\.${E}"
  "${W}git${G} +checkout${A} +(-f|--force)${E}"
  "${W}git${G} +restore${A} +\\.${E}"
  "${W}git${G} +push${A} +(--force(-with-lease|-if-includes)?(=[^ ;&|]*)?|-[a-zA-Z]*f[a-zA-Z]*)${E}"
  "${W}git${G} +push${A} +\\+[A-Za-z0-9]"
  "${W}git${G} +(filter-branch|filter-repo)${E}"
)
# ---- the judgement, segment by segment ----
# A pattern is looked for twice: on the segment as written, then (only if that found
# nothing) on the copy where a hidden command word has been replaced by `git`.
STASH_CONF="$(dirname "$0")/block-dangerous-git.conf"
seg_is_stash() {   # $1 = the segment with quoted content blanked
  [ -s "$STASH_CONF" ] || return 1
  printf '%s' "$1" | grep -qE "${W}git${G} +stash( |\$|[;&|)])" || return 1
  printf '%s' "$1" | grep -qE "${W}git${G} +stash +(list|show)( |\$|[;&|)])" && return 1
  repo="$(printf '%s' "$input" | jq -r '.cwd // empty')"; [ -z "$repo" ] && repo="$PWD"
  # The repo is the LAST `cd` before the stash (a leading "(" is ignored), or a
  # `git -C` target, else the session cwd.
  before="$(printf '%s' "$cmdn" | sed -E 's/git( +-[^ ;&|]+( +[^-;&| ][^ ;&|]*)?)* +stash.*$//')"
  cdpath="$(printf '%s' "$before" | grep -oE '(^|[;&|(] *)cd +("[^"]+"|[^ ;&|)]+)' | tail -1 | sed -E 's/^.*cd +//; s/^"//; s/"$//')"; [ -n "$cdpath" ] && repo="$cdpath"
  cpath="$(printf '%s' "$cmdn" | grep -oE "${W}git +-C +(\"[^\"]+\"|[^ ;&|]+)" | head -1 | sed -E 's/.*-C +//; s/^"//; s/"$//')"; [ -n "$cpath" ] && repo="$cpath"
  # A linked worktree stashes only its own working directory — no other session's files
  # are touched — so it is exempt regardless of what block-dangerous-git.conf lists.
  gd="$(git -C "$repo" rev-parse --path-format=absolute --git-dir 2>/dev/null)"; gc="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  if [ -n "$gd" ] && [ "$(cd "$gd" 2>/dev/null && pwd -P)" != "$(cd "$gc" 2>/dev/null && pwd -P)" ]; then return 1; fi
  origin="$(git -C "$repo" config --get remote.origin.url 2>/dev/null)"
  while IFS= read -r pat || [ -n "$pat" ]; do
    pat="${pat%$'\r'}"                      # a conf saved with CRLF must still match
    case "$pat" in ''|'#'*) continue ;; esac
    if printf '%s' "$origin" | grep -qE "$pat"; then return 0; fi
  done < "$STASH_CONF"
  return 1
}

# seg_is_offswitch $1 = the segment with quoted CONTENT blanked — `--no-verify` and
# `-c core.hooksPath=...` on ANY git command switch off every OTHER hook downstream
# (pre-commit, commit-msg, pre-push). Read on the blanked copy, so a printf/echo/grep that
# merely NAMES the flag is not the flag.
seg_is_offswitch() {
  printf '%s' "$1" | grep -qE "${W}git${A} +--no-verify${E}" && return 0
  printf '%s' "$1" | grep -qE "${W}git${A} +-c +core\\.hooksPath=" && return 0
  return 1
}

# seg_is_going_public $1 = the segment with quoted CONTENT blanked (a --title/--body value, a
# printf string or a commit message that only NAMES the command is not the command).
# `gh repo create ... --public`, `gh repo edit ... --visibility public` (or `=public`) and
# `npm publish` without `--dry-run` make something public, and that cannot be undone. Sets
# GOPUB_WHY to the matched shape for the ledger and the refusal. `--private`, `gh repo view`,
# `npm help publish` and `npm publish --dry-run` never match.
GOPUB_WHY=""
seg_is_going_public() {
  GOPUB_WHY=""
  if printf '%s' "$1" | grep -qE "${W}gh${A} +repo${A} +create${A} +--public${E}"; then
    GOPUB_WHY="gh repo create --public"; return 0
  fi
  if printf '%s' "$1" | grep -qE "${W}gh${A} +repo${A} +edit${A} +--visibility(=| +)public${E}"; then
    GOPUB_WHY="gh repo edit --visibility public"; return 0
  fi
  if printf '%s' "$1" | grep -qE "${W}npm${A} +help${A} +publish${E}"; then
    return 1
  fi
  if printf '%s' "$1" | grep -qE "${W}npm${A} +publish${E}" && ! printf '%s' "$1" | grep -qE "${W}--dry-run(${E}|=)"; then
    GOPUB_WHY="npm publish"; return 0
  fi
  return 1
}

# resolve_repo_path PATH — `~` and `~/x` are expanded against this guard's own $HOME; a
# `$VAR` / `${VAR}` is looked up from an earlier `VAR=value` IN THE SAME COMMAND TEXT (the only
# place a hook can read a variable's value: it never runs the shell). Printed EMPTY when it
# cannot fully resolve, so the caller falls back to the payload cwd rather than treating a
# literal, nonexistent "$R" as a folder.
resolve_repo_path() {
  local p="$1" vn val rest
  case "$p" in
    "~") printf '%s' "$HOME"; return ;;
    "~/"*) printf '%s/%s' "$HOME" "${p:2}"; return ;;
  esac
  if [[ "$p" == \$* ]]; then
    vn="$(printf '%s' "$p" | sed -E 's/^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?.*/\1/')"
    val="$(printf '%s' "$cmdn" | grep -oE "(^|[;& ])${vn}=[^;&]*" | tail -1 | sed -E "s/^.*${vn}=//")"
    val="$(printf '%s' "$val" | sed -E 's/^"//; s/"$//')"
    [ -z "$val" ] && return
    case "$p" in
      "\${$vn}"*) rest="${p#\$\{$vn\}}" ;;
      *) rest="${p#\$$vn}" ;;
    esac
    printf '%s%s' "$val" "$rest"
    return
  fi
  printf '%s' "$p"
}
# default_ref REPO — the branch origin treats as its default, so a repo whose default is
# "master" is not hardcoded to main; "main" when neither can be read.
default_ref() {
  local repo="$1" ref
  ref="$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -n "$ref" ]; then printf '%s' "${ref#origin/}"; return; fi
  if git -C "$repo" show-ref -q --verify refs/remotes/origin/master 2>/dev/null && ! git -C "$repo" show-ref -q --verify refs/remotes/origin/main 2>/dev/null; then printf 'master'; return; fi
  printf 'main'
}
# seg_delete_verdict $1 = the segment with quoted CONTENT blanked (only DETECTS the shape, so
# a title or message naming `git push origin --delete x` is not one); $2 = the same segment
# with the quote CHARACTERS dropped (PARSES the remote and branches). Prints one word:
#   none     — not a push --delete/-d/:branch at all
#   clean    — every named branch holds nothing origin's default branch lacks (`git cherry`
#              shows no `+` line): PASSES with no override
#   dirty    — some branch has commits the default branch lacks, or IS the default branch:
#              refused, GITGUARD=1 approves
#   noremote — the fetch failed or origin does not have the branch, so `git cherry` cannot be
#              read: refused, GITGUARD=1 approves
#   other    — a remote other than origin, or no branch name that can be read (a variable):
#              refused, GITGUARD=1 approves
# Any flag order and EVERY named branch are judged. Each branch is first fetched quietly,
# bounded to 10 seconds (this hook does touch the network, once per named branch, only on a
# push --delete): the local origin/<b> can be stale. The repo is the last `cd` before the push
# or a `git -C` target, else the session cwd.
seg_delete_verdict() {
  printf '%s' "$1" | grep -qE "${W}git${G} +push${A} +(--delete|-d)${E}" || \
  printf '%s' "$1" | grep -qE "${W}git${G} +push${A} +:[A-Za-z]" || { echo "none"; return; }
  local toks=() t branches=() remote="" inpush=0 b n
  read -r -a toks <<<"$2"
  for t in "${toks[@]}"; do
    if [ "$inpush" = 1 ]; then
      case "$t" in
        --delete|-d) : ;;
        -*) : ;;
        :*) branches+=("${t#:}") ;;
        *) if [ -z "$remote" ]; then remote="$t"; else branches+=("$t"); fi ;;
      esac
    fi
    [ "$t" = "push" ] && inpush=1
  done
  for ((n=0; n<${#branches[@]}; n++)); do branches[$n]="${branches[$n]#refs/heads/}"; done
  if [ ${#branches[@]} -eq 0 ] || [ "$remote" != "origin" ]; then echo "other"; return; fi
  local repo before cdpath cpath resolved dref cherry_out rc fpid wpid frc
  repo="$(printf '%s' "$input" | jq -r '.cwd // empty')"; [ -z "$repo" ] && repo="$PWD"
  before="$(printf '%s' "$cmdn" | sed -E 's/git( +-[^ ;&|]+( +[^-;&| ][^ ;&|]*)?)* +push.*$//')"
  cdpath="$(printf '%s' "$before" | grep -oE '(^|[;&|(] *)cd +("[^"]+"|[^ ;&|)]+)' | tail -1 | sed -E 's/^.*cd +//; s/^"//; s/"$//')"
  if [ -n "$cdpath" ]; then resolved="$(resolve_repo_path "$cdpath")"; [ -n "$resolved" ] && repo="$resolved"; fi
  cpath="$(printf '%s' "$cmdn" | grep -oE "${W}git +-C +(\"[^\"]+\"|[^ ;&|]+)" | head -1 | sed -E 's/.*-C +//; s/^"//; s/"$//')"
  if [ -n "$cpath" ]; then resolved="$(resolve_repo_path "$cpath")"; [ -n "$resolved" ] && repo="$resolved"; fi
  dref="$(default_ref "$repo")"
  for b in "${branches[@]}"; do
    # The default branch is trivially "merged into itself": `git cherry` would call it clean.
    if [ "$b" = "$dref" ]; then echo "dirty"; return; fi
    # macOS has no timeout(1): a background fetch and a 10-second watchdog.
    GIT_TERMINAL_PROMPT=0 git -C "$repo" fetch -q origin "$b" >/dev/null 2>&1 & fpid=$!
    ( sleep 10; kill -TERM "$fpid" 2>/dev/null ) >/dev/null 2>&1 & wpid=$!
    wait "$fpid" 2>/dev/null; frc=$?; kill "$wpid" 2>/dev/null; wait "$wpid" 2>/dev/null
    if [ "$frc" != 0 ]; then echo "noremote"; return; fi
    cherry_out="$(git -C "$repo" cherry "origin/$dref" "origin/$b" 2>/dev/null)"; rc=$?
    if [ "$rc" != 0 ]; then echo "noremote"; return; fi
    if printf '%s\n' "$cherry_out" | grep -q '^+'; then echo "dirty"; return; fi
  done
  echo "clean"
}

matched=""; matched_hidden=0; stash_hit=0; argsub_hit=0; offswitch_hit=0; gopub_hit=0; gopub_why=""; segdel_hit=0; segdel_hit_state=""
while IFS=$'\t' read -r flag mseg sseg qseg asub; do
  [ -n "$flag" ] || continue
  segmatch=""; hidden=0
  for p in "${patterns[@]}"; do
    if printf '%s' "$mseg" | grep -qE "$p"; then segmatch="$p"; break; fi
  done
  if [ -z "$segmatch" ] && [ "$sseg" != "$mseg" ]; then
    for p in "${patterns[@]}"; do
      if printf '%s' "$sseg" | grep -qE "$p"; then segmatch="$p"; hidden=1; break; fi
    done
  fi
  segstash=0
  if [ -z "$segmatch" ] && seg_is_stash "$qseg"; then segstash=1; fi
  segargsub=0
  if [ -z "$segmatch" ] && [ "$segstash" = 0 ] && [ "$asub" = 1 ]; then segargsub=1; fi
  segoff=0
  if [ -z "$segmatch" ] && [ "$segstash" = 0 ] && [ "$segargsub" = 0 ] && seg_is_offswitch "$qseg"; then segoff=1; fi
  seggopub=0; segwhy=""
  if [ -z "$segmatch" ] && [ "$segstash" = 0 ] && [ "$segargsub" = 0 ] && [ "$segoff" = 0 ] && seg_is_going_public "$qseg"; then seggopub=1; segwhy="$GOPUB_WHY"; fi
  segdel_state="none"
  if [ -z "$segmatch" ] && [ "$segstash" = 0 ] && [ "$segargsub" = 0 ] && [ "$segoff" = 0 ] && [ "$seggopub" = 0 ]; then
    segdel_state="$(seg_delete_verdict "$qseg" "$mseg")"
    # A command word hidden in a variable (`$(which git) push origin --delete b`) is judged by its
    # arguments, as everywhere else in this guard: read the hidden-word copy too.
    if [ "$segdel_state" = "none" ] && [ "$sseg" != "$mseg" ]; then segdel_state="$(seg_delete_verdict "$sseg" "$sseg")"; fi
  fi
  segdel=0
  if [ "$segdel_state" = "dirty" ] || [ "$segdel_state" = "other" ] || [ "$segdel_state" = "noremote" ]; then segdel=1; fi
  if [ "$flag" = 1 ]; then
    # An approved segment, recorded with WHAT it bypassed — and ONLY when it bypassed
    # something. An override standing in front of a segment where nothing was going to be
    # refused waives nothing, so it writes no ledger line: `GITGUARD=1 true; git push
    # --force` used to log "no dangerous pattern matched" and then refuse the push, so the
    # record of approvals held a line for an act that was never approved and never ran.
    if [ "$segstash" = 1 ]; then why="git stash in a checkout listed in block-dangerous-git.conf"
    elif [ "$segargsub" = 1 ]; then why="a git argument produced by a substitution"
    elif [ "$segoff" = 1 ]; then why="the --no-verify / core.hooksPath off-switch"
    elif [ "$seggopub" = 1 ]; then why="the going-public stop ($segwhy)"
    elif [ "$segdel" = 1 ] && [ "$segdel_state" = "dirty" ]; then why="git push --delete on a branch not fully merged into origin's default branch (git cherry showed unmerged commits, or it is the default branch)"
    elif [ "$segdel" = 1 ] && [ "$segdel_state" = "noremote" ]; then why="git push --delete/-d, a fetch failed or origin lacks the branch, so git cherry could not be read"
    elif [ "$segdel" = 1 ]; then why="git push --delete/-d on a remote other than origin, or an unreadable branch name"
    elif [ -n "$segmatch" ]; then why="$segmatch"
    else continue; fi
    guard_log_override GITGUARD "$rawcmd" "$why" || { guard_refuse_unrecorded "block-dangerous-git" "GITGUARD=1"; exit 2; }
    continue
  fi
  if [ -n "$segmatch" ]; then matched="$segmatch"; matched_hidden="$hidden"; break; fi
  if [ "$segstash" = 1 ]; then stash_hit=1; break; fi
  if [ "$segargsub" = 1 ]; then argsub_hit=1; break; fi
  if [ "$segoff" = 1 ]; then offswitch_hit=1; break; fi
  if [ "$seggopub" = 1 ]; then gopub_hit=1; gopub_why="$segwhy"; break; fi
  if [ "$segdel" = 1 ]; then segdel_hit=1; segdel_hit_state="$segdel_state"; break; fi
done <<<"$segrecs"

if [ -n "$matched" ] && [ "$matched_hidden" = 1 ]; then
  echo "block-dangerous-git: REFUSED — this command's own name comes from a variable or a substitution (\`\$GIT\`, \`\${G}\`, \`\$(…)\`), and what follows it matches '$matched' (irreversible git actions need an explicit yes). A guard cannot see which binary that will be, so it is judged on the arguments. Write the command plainly: git <subcommand> … — or, once approved: GITGUARD=1 <command>" >&2
  exit 2
fi
if [ -n "$matched" ]; then
  echo "block-dangerous-git: REFUSED — the command matches '$matched' (irreversible git actions need an explicit yes). Name the target, scope and consequence, get the go-ahead, then run it as: GITGUARD=1 <command>" >&2
  exit 2
fi
if [ "$argsub_hit" = 1 ]; then
  echo "block-dangerous-git: REFUSED — an ARGUMENT of this git command comes from a variable or a substitution (\`\$R\`, \`\${R}\`, \`\$(…)\`, backticks), so what git will be told to do cannot be read before it runs: \`R=reset; git \$R --hard\` is a hard reset no pattern can see. Write the value out: git push origin feature-x instead of git push origin \$B (or set it earlier in the SAME command: B=feature-x; git push origin \$B — a plain value assigned there is read). A variable whose value comes from \$(…) or an earlier command cannot be read. A substitution inside a quoted message or value (git commit -m \"\$msg\" f.ts, git log --author=\"\$me\") is fine and is not what this refuses. Once approved: GITGUARD=1 <command>" >&2
  exit 2
fi
if [ "$offswitch_hit" = 1 ]; then
  echo "block-dangerous-git: REFUSED — this command carries \`--no-verify\` or \`-c core.hooksPath=...\`, the git flags that turn off every OTHER hook downstream (pre-commit, commit-msg, pre-push). Run it without the flag, or, once approved: GITGUARD=1 <command>" >&2
  exit 2
fi
if [ "$gopub_hit" = 1 ]; then
  echo "block-dangerous-git: REFUSED — \`$gopub_why\` makes this public, and that cannot be undone. Going public needs, in order: a privacy check (no real name, path or secret anywhere in the repo or its history), a security review, a fresh-eyes review by someone who did not build it, and your explicit yes. Once all four are done: GITGUARD=1 <command>" >&2
  exit 2
fi
if [ "$segdel_hit" = 1 ]; then
  if [ "$segdel_hit_state" = "dirty" ]; then
    echo "block-dangerous-git: REFUSED — \`git push origin --delete/-d\` on a branch that is NOT fully merged into origin's default branch (\`git cherry\` shows commits unique to it), or on the default branch itself. Deleting it cannot be undone. Once approved: GITGUARD=1 <command>" >&2
  elif [ "$segdel_hit_state" = "noremote" ]; then
    echo "block-dangerous-git: REFUSED — \`git push origin --delete/-d\` names a branch origin does not have, or the check fetch failed (\`git cherry\` could not be read), so whether it is safe to delete cannot be judged. Once approved: GITGUARD=1 <command>" >&2
  else
    echo "block-dangerous-git: REFUSED — \`git push --delete/-d\` on a remote other than \`origin\`, or with a branch name this guard could not read (a variable), so it cannot be judged. Once approved: GITGUARD=1 <command>" >&2
  fi
  exit 2
fi
if [ "$stash_hit" = 1 ]; then
  echo "block-dangerous-git: REFUSED — \`git stash\` in a checkout listed in block-dangerous-git.conf hides every session's uncommitted work, not just yours. Commit your own paths instead; \`git stash list\`/\`show\` are allowed. Deliberate, approved stash: GITGUARD=1 <command>" >&2
  exit 2
fi
exit 0
