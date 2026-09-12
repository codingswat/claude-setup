#!/bin/bash
# PreToolUse hook on Bash. Refuses, BEFORE they run, git commands that throw away work or
# rewrite shared history without an explicit go-ahead: reset --hard, clean -f, branch -D
# (force delete), checkout/restore that wipes the whole tree, force-push, deleting a
# remote branch, and history rewrites (filter-branch/filter-repo). Plain `git push` is
# always allowed.
# Global git flags between `git` and the subcommand (-c k=v, -C path, --no-pager) are
# tolerated, so they cannot be used to slip a banned command past the match. Argument
# matching never crosses ; & |, so a later command on the same line cannot trigger a
# refusal that belongs to an earlier one.
# Commit messages and heredoc bodies are stripped out before matching, so a message that
# merely MENTIONS a banned command is not refused.
# Deliberate, approved run: start the command (or the segment after ; && |) with
# `GITGUARD=1 ` — only that position counts, so the token inside a message or a quoted
# argument does not disarm the guard.
# Tests: hooks/test-hooks.sh.
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0
printf '%s' "$cmd" | grep -qE '(^|[;&|] *)GITGUARD=1 ' && exit 0
# Match on what is INVOKED, not on quoted text: drop commit messages (-m/--message args)
# and heredoc bodies first, so a message or pasted block that names a banned command does
# not trigger a false refusal.
cmd="$(printf '%s' "$cmd" | python3 -c '
import re,sys
s=sys.stdin.read()
s=re.sub(r"<<-?\s*[\x27\"]?(\w+)[\x27\"]?[^\n]*\n.*?\n\1(?=\n|$)", " HEREDOC ", s, flags=re.S)
s=re.sub(r"(-m|--message)(=|\s+)(\"(?:[^\"\\\\]|\\\\.)*\"|\x27[^\x27]*\x27)", r"\1 MSG", s, flags=re.S)
sys.stdout.write(s)')"
W='(^|[^a-zA-Z0-9_./-])'                          # `git` as a whole word
G='( +-[^ ;&|]+( +[^-;&| ][^ ;&|]*)?)*'            # optional global flags, each with one optional value
A='( +[^ ;&|]+)*'                                  # optional arguments, never across ; & |
patterns=(
  "${W}git${G} +reset${A} +--hard( |\$)"
  "${W}git${G} +clean +-[a-zA-Z]*f"
  "${W}git${G} +branch${A} +(-[a-zA-Z]*D[a-zA-Z]*|--delete +--force|--force +--delete)( |\$)"
  "${W}git${G} +checkout${A} +\\.( |\$)"
  "${W}git${G} +checkout${A} +(-f|--force)( |\$)"
  "${W}git${G} +restore${A} +\\.( |\$)"
  "${W}git${G} +push${A} +(--force|-f|--force-with-lease|--delete|-d)( |\$)"
  "${W}git${G} +push${A} +:[A-Za-z]"
  "${W}git${G} +(filter-branch|filter-repo)( |\$)"
)
for p in "${patterns[@]}"; do
  if printf '%s' "$cmd" | grep -qE "$p"; then
    echo "block-dangerous-git: REFUSED — the command matches '$p' (irreversible git actions need an explicit yes). Name the target, scope and consequence, get the go-ahead, then run it as: GITGUARD=1 <command>" >&2
    exit 2
  fi
done
exit 0
