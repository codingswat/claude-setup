#!/bin/bash
# PreToolUse hook on Bash. A full test suite can take minutes and pin the CPU; running two
# at once on the same machine makes both slower and their results less trustworthy. When
# the 1-minute load average is already at or above MAX_LOAD, something else looks like it
# is running one — so refuse this one and say wait. Targeted single-file or single-test
# runs are not matched by the default pattern, so they are never refused.
# The command pattern and the load threshold come from hooks/heavy-suite.conf, next to
# this script (see hooks/heavy-suite.conf.example for the format: PATTERN='...' as an
# extended regex, MAX_LOAD=10). No conf file: falls back to a built-in default matching
# `npm test`, `npm run test`, `npm run e2e`, `vitest run`, `playwright test`, MAX_LOAD=10.
# Deliberate override: start the command (or the segment after ; && |) with `SUITE_OK=1 `.
# Test seam: HEAVY_SUITE_LOAD_OVERRIDE=<load> stands in for the real `uptime` reading.
# Tests: hooks/test-hooks.sh.
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0
printf '%s' "$cmd" | grep -qE '(^|[;&|] *)SUITE_OK=1 ' && exit 0

CONF="$(dirname "$0")/heavy-suite.conf"
PATTERN='(^|[;&| ])(npm +test|npm +run +(test|e2e)|npx +vitest +run|npx +playwright +test)([ ;&|]|$)'
MAX_LOAD=10
if [ -f "$CONF" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in
      PATTERN=*) v="${line#PATTERN=}"; v="${v%\'}"; v="${v#\'}"; PATTERN="$v" ;;
      MAX_LOAD=*) MAX_LOAD="${line#MAX_LOAD=}" ;;
    esac
  done < "$CONF"
fi

# Match on what is INVOKED, not on quoted text: drop commit messages (-m/--message args)
# and heredoc bodies first, so a word inside a message or a pasted block cannot trigger a
# false refusal.
cmd="$(printf '%s' "$cmd" | python3 -c '
import re,sys
s=sys.stdin.read()
s=re.sub(r"<<-?\s*[\x27\"]?(\w+)[\x27\"]?[^\n]*\n.*?\n\1(?=\n|$)", " HEREDOC ", s, flags=re.S)
s=re.sub(r"(-m|--message)(=|\s+)(\"(?:[^\"\\\\]|\\\\.)*\"|\x27[^\x27]*\x27)", r"\1 MSG", s, flags=re.S)
sys.stdout.write(s)')"
printf '%s' "$cmd" | grep -qE "$PATTERN" || exit 0

load="${HEAVY_SUITE_LOAD_OVERRIDE:-$(uptime | sed -E 's/.*load averages?: *([0-9.]+).*/\1/')}"
if awk -v l="$load" -v m="$MAX_LOAD" 'BEGIN{exit !(l+0>=m+0)}'; then
  echo "heavy-suite-guard: REFUSED — 1-minute load is $load (limit $MAX_LOAD): another heavy suite looks like it is already running. Wait and retry; single-file/targeted runs are exempt. Deliberate override: SUITE_OK=1 <command>" >&2
  exit 2
fi
exit 0
