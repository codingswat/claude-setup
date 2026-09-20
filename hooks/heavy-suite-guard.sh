#!/bin/bash
# PreToolUse hook on Bash. A full test suite can take minutes and pin the CPU; running two
# at once on the same machine makes both slower and their results less trustworthy. When
# the 1-minute load average is already at or above MAX_LOAD, something else looks like it
# is running one — so refuse this one and say wait.
# WHAT COUNTS AS HEAVY, per command segment (split on ; & | and newlines, so one segment's
# words never make another segment heavy): `npm|yarn|pnpm test`, `npm|yarn|pnpm run test`,
# a `run test:<something>` script, `run e2e`, `vitest run`, `playwright test` — with or
# without `npx`, and a bare `vitest` with no named test file too.
# WHAT IS EXEMPT, in the same segment: a named `*.test.*` / `*.spec.*` file (a single-file
# run), a `-t` / `--testNamePattern` selector (one named test), and `--version`,
# `--list` or `--help` (a query, not a run). These are the targeted runs the guard has
# always promised never to refuse — `npm test -- src/a.test.ts` and
# `vitest run -t "renders the card"` are not the thing that pins a machine.
# HOW THE COMMAND IS READ (hooks/guard-lib.sh, shared with the other Bash guards): commit
# messages and heredoc bodies are dropped, `bash|sh|zsh -c "…"` and `eval "…"` are
# unwrapped (a wrapper is not a hiding place), quoted text is blanked (so prose such as
# `echo "run npm test later" >> DEBT.md` is not a test run), and redirections (`>`, `<`)
# count as separators, so `npm test>log` is the same command as `npm test > log`.
# The command pattern and the load threshold come from hooks/heavy-suite.conf, next to
# this script (see hooks/heavy-suite.conf.example for the format: PATTERN='...' as an
# extended regex, MAX_LOAD=10); a conf saved with Windows line endings (CRLF) is read the
# same as a Unix one — a stray carriage return used to leave PATTERN unmatchable, which
# silently disabled the guard. No conf file: the built-in default above applies.
# Deliberate override: start the command with `SUITE_OK=1 ` — the START only, judged on
# text with quoted strings removed, so the word inside a commit message can no longer
# disarm the guard. Every use is written to hooks/override-ledger.sh; if that line CANNOT
# be written (no ledger script, unwritable path) the override is REFUSED, not honoured.
# Test seam: HEAVY_SUITE_LOAD_OVERRIDE=<load> stands in for the real `uptime` reading.
# jq, python3 and hooks/guard-lib.sh all parse the command below; if any is missing this
# guard cannot read what it is being asked to run, so it refuses rather than silently
# letting an unparsed (and therefore unmatched) heavy suite through. Fail closed, like
# git-hooks/pre-commit.
# Tests: hooks/test-hooks.sh.
missing=""
command -v jq >/dev/null 2>&1 || missing="jq"
command -v python3 >/dev/null 2>&1 || missing="${missing:+$missing and }python3"
if [ -n "$missing" ]; then
  echo "heavy-suite-guard: REFUSED — $missing not found, so this guard cannot parse the command (fail closed, not open)." >&2
  exit 2
fi
GUARD_LIB="$(dirname "$0")/guard-lib.sh"
if [ ! -r "$GUARD_LIB" ]; then
  echo "heavy-suite-guard: REFUSED — hooks/guard-lib.sh is missing next to this hook, so the command cannot be normalised before matching (fail closed, not open). Reinstall the hooks (install.sh copies hooks/*.sh)." >&2
  exit 2
fi
. "$GUARD_LIB"
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0

CONF="$(dirname "$0")/heavy-suite.conf"
PATTERN='(^|[;&| ])(npm|yarn|pnpm) +(test|run +(test(:[A-Za-z0-9_.:-]+)?|e2e))([ ;&|]|$)|(^|[;&| ])(npx +)?(vitest +run|playwright +test)([ ;&|]|$)'
MAX_LOAD=10
if [ -f "$CONF" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"                       # a conf saved with CRLF must still bind
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in
      PATTERN=*) v="${line#PATTERN=}"; v="${v%\'}"; v="${v#\'}"; PATTERN="$v" ;;
      MAX_LOAD=*) MAX_LOAD="${line#MAX_LOAD=}" ;;
    esac
  done < "$CONF"
fi

# The matching copy: messages and heredocs dropped, wrappers unwrapped, whitespace
# normalised, quoted text blanked, redirections turned into separators.
cmd="$(printf '%s' "$cmd" | python3 -c "$GUARD_PY_COMMON"'
s = blank_quoted(clean(sys.stdin.read()))
sys.stdout.write(re.sub(r"[<>]", " ", s))')"

targeted() {   # a single-file run, one named test, or a --version/--list/--help query
  printf '%s' "$1" | grep -qE '(^| )[^ ]+\.(test|spec)\.[A-Za-z0-9]+( |$)' && return 0
  printf '%s' "$1" | grep -qE '(^| )(-t|--testNamePattern)([ =]|$)' && return 0
  printf '%s' "$1" | grep -qE '(^| )(--version|--list|--help)( |$)' && return 0
  return 1
}
heavy=0
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  targeted "$seg" && continue
  printf '%s' "$seg" | grep -qE "$PATTERN" && { heavy=1; break; }
  # Always-on safety net alongside PATTERN (never narrower, only wider): a bare
  # `vitest`/`npx vitest` naming no test file still runs the whole suite.
  printf '%s' "$seg" | grep -qE '(^|[;&| ])(npx +)?vitest( +run)?([ ;&|]|$)' && { heavy=1; break; }
  printf '%s' "$seg" | grep -qE '(^|[;&| ])(npx +)?playwright +test([ ;&|]|$)' && { heavy=1; break; }
done <<< "$(printf '%s' "$cmd" | tr ';&|\n' '\n\n\n\n')"

# An approved override, recorded with what it bypassed.
if printf '%s' "$cmd" | python3 -c "$GUARD_PY_COMMON"'
sys.exit(0 if override_at_start(sys.stdin.read(), "SUITE_OK") else 1)'; then
  guard_log_override SUITE_OK "$(printf '%s' "$input" | jq -r '.tool_input.command // empty')" "heavy suite, load check skipped" \
    || { guard_refuse_unrecorded "heavy-suite-guard" "SUITE_OK=1"; exit 2; }
  exit 0
fi
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
  echo "heavy-suite-guard: REFUSED — 1-minute load is $load (limit $MAX_LOAD): another heavy suite looks like it is already running. Wait and retry; single-file, -t and --version/--list runs are exempt. Deliberate override: SUITE_OK=1 <command>" >&2
  exit 2
fi
exit 0
