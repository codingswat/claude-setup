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
# A bare `vitest`/`vitest run` or direct `playwright test` (no `npx`) that names no
# specific test file is always treated as heavy too, on top of PATTERN — see the checks
# below; this never narrows what PATTERN already refuses, only widens it.
# Deliberate override: start the command (or the segment after ; && |) with `SUITE_OK=1 `.
# Every use is logged by hooks/override-ledger.sh, if present (a missing ledger script
# never blocks this guard).
# Test seam: HEAVY_SUITE_LOAD_OVERRIDE=<load> stands in for the real `uptime` reading.
# Both jq and python3 parse the command below; if either is missing this guard cannot
# read what it's being asked to run, so it refuses rather than silently letting an
# unparsed (and therefore unmatched) heavy suite through. Fail closed, like
# git-hooks/pre-commit.
# Tests: hooks/test-hooks.sh.
missing=""
command -v jq >/dev/null 2>&1 || missing="jq"
command -v python3 >/dev/null 2>&1 || missing="${missing:+$missing and }python3"
if [ -n "$missing" ]; then
  echo "heavy-suite-guard: REFUSED — $missing not found, so this guard cannot parse the command (fail closed, not open)." >&2
  exit 2
fi
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0
if printf '%s' "$cmd" | grep -qE '(^|[;&|] *)SUITE_OK=1 '; then
  L="$(dirname "$0")/override-ledger.sh"; [ -f "$L" ] && bash "$L" SUITE_OK "$cmd"
  exit 0
fi

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
heavy=0
printf '%s' "$cmd" | grep -qE "$PATTERN" && heavy=1
# Extra, always-on safety net alongside PATTERN (never narrower than it, only wider):
# a bare `vitest`/`vitest run`, with or without `npx`, that does NOT name a specific
# test file (no .ts/.tsx/.js/.mjs token) runs the whole suite even though PATTERN's own
# vitest clause requires the word "run" — catch that case too. A command naming its own
# test file stays exempt, matching the "targeted runs are never refused" contract above.
if printf '%s' "$cmd" | grep -qE '(^|[;&| ])(npx +)?vitest( +run)?([ ;&|]|$)' \
   && ! printf '%s' "$cmd" | grep -qE '\.(m?ts|tsx|m?js)([ ;&|]|$)'; then heavy=1; fi
# `playwright test` run directly, without `npx`, is also a full suite.
printf '%s' "$cmd" | grep -qE '(^|[;&| ])(npx +)?playwright +test([ ;&|]|$)' && heavy=1
[ "$heavy" = 1 ] || exit 0

# Portable 1-minute load: macOS has no /proc/loadavg, Linux has no `sysctl vm.loadavg`;
# `uptime`'s wording (macOS "load averages:" vs Linux "load average:") is the last resort.
read_load() {
  local out
  if out="$(sysctl -n vm.loadavg 2>/dev/null)" && [ -n "$out" ]; then
    printf '%s' "$out" | sed -E 's/^\{? *([0-9.]+).*/\1/'; return
  fi
  if [ -r /proc/loadavg ]; then
    awk '{print $1}' /proc/loadavg; return
  fi
  uptime | sed -E 's/.*load averages?: *([0-9.]+).*/\1/'
}
load="${HEAVY_SUITE_LOAD_OVERRIDE:-$(read_load)}"
if awk -v l="$load" -v m="$MAX_LOAD" 'BEGIN{exit !(l+0>=m+0)}'; then
  echo "heavy-suite-guard: REFUSED — 1-minute load is $load (limit $MAX_LOAD): another heavy suite looks like it is already running. Wait and retry; single-file/targeted runs are exempt. Deliberate override: SUITE_OK=1 <command>" >&2
  exit 2
fi
exit 0
