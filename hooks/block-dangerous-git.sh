#!/bin/bash
# PreToolUse hook on Bash. Refuses, BEFORE they run, git commands that throw away work or
# rewrite shared history without an explicit go-ahead: reset --hard, clean -f/--force,
# branch -D (force delete), checkout/restore that wipes the whole tree, force-push
# (`--force`, `-f`, `--force-with-lease`, and a leading `+` on a refspec — `git push origin
# +main` / `+HEAD:main` mean the same thing as `--force` and are refused the same way),
# deleting a remote branch, and history rewrites (filter-branch/filter-repo). Plain
# `git push` is always allowed.
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
# The mirror image is refused instead of judged: a plain `git` whose ARGUMENT comes from a
# variable or a substitution (`R=reset; git $R --hard`, `git push origin $F`). There the
# arguments are exactly what cannot be read, so nothing is left to decide on — the command
# is refused and a plain spelling asked for. A substitution inside a quoted message or
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
# Both jq and python3 parse the command below, and hooks/guard-lib.sh normalises it; if any
# of the three is missing this guard cannot read what it is being asked to run, so it
# refuses rather than silently letting an unparsed (and therefore unmatched) command
# through. Hook input that is empty or is not valid JSON is refused for the same reason —
# the one exception is a well-formed call for a tool other than Bash, which carries no
# command to judge. Fail closed, like git-hooks/pre-commit.
# Tests: hooks/test-hooks.sh.
missing=""
command -v jq >/dev/null 2>&1 || missing="jq"
command -v python3 >/dev/null 2>&1 || missing="${missing:+$missing and }python3"
if [ -n "$missing" ]; then
  echo "block-dangerous-git: REFUSED — $missing not found, so this guard cannot parse the command (fail closed, not open)." >&2
  exit 2
fi
GUARD_LIB="$(dirname "$0")/guard-lib.sh"
if [ ! -r "$GUARD_LIB" ]; then
  echo "block-dangerous-git: REFUSED — hooks/guard-lib.sh is missing next to this hook, so the command cannot be normalised before matching (fail closed, not open). Reinstall the hooks (install.sh copies hooks/*.sh)." >&2
  exit 2
fi
. "$GUARD_LIB"
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
norm="$(printf '%s' "$rawcmd" | python3 -c "$GUARD_PY_COMMON"'
raw=sys.stdin.read()
# The wrapper check runs BEFORE unwrap: unwrap lifts an inline literal out of
# `eval "…"` / `sh -c "…"`, but there is nothing to lift out of `eval "$cmd"`.
pre=normalize_ws(strip_messages(strip_heredocs(raw)))
wrapsub="1" if wrapped_substitution(pre) else "0"
s=clean(raw)
recs=[]
for seg in segments(s):
    m=strip_quotechars(seg).replace("\n", " ")
    q=blank_quoted(seg).replace("\n", " ")
    flag="1" if override_at_start(q, "GITGUARD") else "0"
    asub="1" if substituted_args(q, "git") else "0"
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
  "${W}git${G} +push${A} +(--force|-f|--force-with-lease|--delete|-d)${E}"
  "${W}git${G} +push${A} +:[A-Za-z]"
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

matched=""; matched_hidden=0; stash_hit=0; argsub_hit=0
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
  if [ "$flag" = 1 ]; then
    # An approved segment, recorded with WHAT it bypassed — and ONLY when it bypassed
    # something. An override standing in front of a segment where nothing was going to be
    # refused waives nothing, so it writes no ledger line: `GITGUARD=1 true; git push
    # --force` used to log "no dangerous pattern matched" and then refuse the push, so the
    # record of approvals held a line for an act that was never approved and never ran.
    if [ "$segstash" = 1 ]; then why="git stash in a checkout listed in block-dangerous-git.conf"
    elif [ "$segargsub" = 1 ]; then why="a git argument produced by a substitution"
    elif [ -n "$segmatch" ]; then why="$segmatch"
    else continue; fi
    guard_log_override GITGUARD "$rawcmd" "$why" || { guard_refuse_unrecorded "block-dangerous-git" "GITGUARD=1"; exit 2; }
    continue
  fi
  if [ -n "$segmatch" ]; then matched="$segmatch"; matched_hidden="$hidden"; break; fi
  if [ "$segstash" = 1 ]; then stash_hit=1; break; fi
  if [ "$segargsub" = 1 ]; then argsub_hit=1; break; fi
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
  echo "block-dangerous-git: REFUSED — an ARGUMENT of this git command comes from a variable or a substitution (\`\$R\`, \`\${R}\`, \`\$(…)\`, backticks), so what git will be told to do cannot be read before it runs: \`R=reset; git \$R --hard\` is a hard reset no pattern can see. Write the git command plainly: git <subcommand> <arguments> … A substitution inside a quoted message or value (git commit -m \"\$msg\" f.ts, git log --author=\"\$me\") is fine and is not what this refuses. Once approved: GITGUARD=1 <command>" >&2
  exit 2
fi
if [ "$stash_hit" = 1 ]; then
  echo "block-dangerous-git: REFUSED — \`git stash\` in a checkout listed in block-dangerous-git.conf hides every session's uncommitted work, not just yours. Commit your own paths instead; \`git stash list\`/\`show\` are allowed. Deliberate, approved stash: GITGUARD=1 <command>" >&2
  exit 2
fi
exit 0
