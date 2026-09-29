#!/bin/bash
# PreToolUse hook on Bash. A full test suite can take minutes and pin the CPU; running two
# at once on the same machine makes both slower and their results less trustworthy. When
# the 1-minute load average is already at or above MAX_LOAD, something else looks like it
# is running one — so refuse this one and say wait.
# WHAT COUNTS AS HEAVY, per command segment (split on ; & | and newlines, so one segment's
# words never make another segment heavy): `npm|yarn|pnpm test`, `npm|yarn|pnpm run test`,
# a `run test:<something>` script, `run e2e`, `vitest run`, `playwright test` — with or
# without `npx`, and a bare `vitest` with no named test file too; the runner reached by path
# (`node node_modules/.bin/vitest run`, `./node_modules/.bin/vitest run`) and npm/yarn/pnpm with
# a `--prefix`/`--workspace`/`-w`/`-C` flag in front of the script (`npm --prefix apps/web test`).
# The command must stand at the segment's COMMAND POSITION (leading `VAR=val` words, `time`/
# `sudo`/`env`-style wrappers, `(` and `if`/`do`-style keywords peeled off): a runner named as
# an ARGUMENT — `rg vitest docs/`, `which vitest`, `echo npm test >> notes` — is not a run.
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
# Deliberate override: start the SEGMENT that would be refused with `SUITE_OK=1 ` —
# `cd apps/web && SUITE_OK=1 npm test` approves that run, while `SUITE_OK=1 true && npm
# test` approves only the `true`. Judged on text with quoted strings removed, so the word
# inside a commit message can no longer disarm the guard. A command word hidden in a
# variable (`T=npm; $T test`) is judged by its arguments, with `npm` standing in for the
# name the guard cannot see. Every use is written to hooks/override-ledger.sh; if that line CANNOT
# be written (no ledger script, unwritable path) the override is REFUSED, not honoured.
# Test seam: HEAVY_SUITE_LOAD_OVERRIDE=<load> stands in for the real `uptime` reading.
# jq, python3 and hooks/guard-lib.sh all parse the command below; if any is missing this
# guard cannot read what it is being asked to run, so it refuses rather than silently
# letting an unparsed (and therefore unmatched) heavy suite through. Fail closed, like
# git-hooks/pre-commit.
# Tests: hooks/test-hooks.sh (`refresh 2026-09-29 (a)` for the command position, the runner by path, the busy wording and the python3 choice).
GUARD_LIB="$(dirname "$0")/guard-lib.sh"
if [ ! -r "$GUARD_LIB" ]; then
  echo "heavy-suite-guard: REFUSED — hooks/guard-lib.sh is missing next to this hook, so the command cannot be normalised before matching (fail closed, not open). Reinstall the hooks (install.sh copies hooks/*.sh)." >&2
  exit 2
fi
. "$GUARD_LIB"
missing=""
command -v jq >/dev/null 2>&1 || missing="jq"
[ -n "$GUARD_PY" ] && [ -x "$GUARD_PY" ] || missing="${missing:+$missing and }python3"
if [ -n "$missing" ]; then
  echo "heavy-suite-guard: REFUSED — $missing not found, so this guard cannot parse the command (fail closed, not open)." >&2
  exit 2
fi
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
guard_parsed "heavy-suite-guard" jq $? "$cmd" ""      # a jq that runs but fails reads nothing
[ -z "$cmd" ] && exit 0
rawcmd="$cmd"

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

# One record per command segment — messages and heredocs dropped, wrappers unwrapped,
# whitespace (and `${IFS}`) normalised, quoted text blanked, redirections turned into
# separators — as: <override at the start of THIS segment 0|1> TAB <segment> TAB <the same
# segment with a hidden command word replaced by `npm`> TAB <segment at its command position>
# TAB <the hidden-word copy at its command position>. The last two are what PATTERN is matched
# against: leading `VAR=val` words, `time`/`nice`/`env`/`sudo`-style wrappers, `(`, `!` and
# `if`/`then`/`do`-style keywords are peeled off, so `rg vitest docs/` is a search and not a run.
segrecs="$(printf '%s' "$cmd" | "$GUARD_PY" -c "$GUARD_PY_COMMON"'
s = blank_quoted(clean(sys.stdin.read()))
s = re.sub(r"[<>]", " ", s)
_PEEL = re.compile(r"^\s*(?:[({!]+|(?:[A-Za-z_][A-Za-z0-9_]*=\S*|(?:if|then|else|elif|do|while|until|time|nohup|exec|command|sudo|env|nice)(?:\s+-\S+(?:\s+\d+)?)*)(?=\s|$))")
def at_command(seg):
    prev = None
    while prev != seg:
        prev = seg
        seg = _PEEL.sub("", seg, count=1)
    return seg.strip().rstrip(")} ")
out=[]
for seg in segments(s):
    seg = seg.replace("\n", " ")
    flag = "1" if override_at_start(seg, "SUITE_OK") else "0"
    hid = hidden_cmdword(seg, "npm")
    out.append(flag + "\t" + seg + "\t" + hid + "\t" + at_command(seg) + "\t" + at_command(hid))
sys.stdout.write("\n".join(out))')"
guard_parsed "heavy-suite-guard" python3 $? "$segrecs" "$rawcmd"

targeted() {   # a single-file run, one named test, or a --version/--list/--help query
  printf '%s' "$1" | grep -qE '(^| )[^ ]+\.(test|spec)\.[A-Za-z0-9]+( |$)' && return 0
  printf '%s' "$1" | grep -qE '(^| )(-t|--testNamePattern)([ =]|$)' && return 0
  printf '%s' "$1" | grep -qE '(^| )(--version|--list|--help)( |$)' && return 0
  return 1
}
is_heavy() {   # $1 a segment AT ITS COMMAND POSITION: PATTERN, then the always-on safety net beside it
  # PATTERN is anchored: a runner word that is another command's ARGUMENT (`rg vitest docs/`,
  # `which vitest`, `echo npm test`) is not a run.
  printf '%s' "$1" | grep -qE "^($PATTERN)" && return 0
  # Always-on safety net alongside PATTERN (never narrower, only wider): a bare
  # `vitest`/`npx vitest` naming no test file still runs the whole suite; the runner reached by
  # path (`node node_modules/.bin/vitest run`, `./node_modules/.bin/vitest run`); and npm/yarn/
  # pnpm with a workspace or prefix flag in front of the script (`npm --prefix apps/web test`).
  printf '%s' "$1" | grep -qE '^(npx +)?vitest( +run)?([ ;&|]|$)' && return 0
  printf '%s' "$1" | grep -qE '^(npx +)?playwright +test([ ;&|]|$)' && return 0
  printf '%s' "$1" | grep -qE '^(node +)?[^ ]*node_modules/\.bin/(vitest( +run)?|playwright +test)([ ;&|]|$)' && return 0
  printf '%s' "$1" | grep -qE '^(npm|yarn|pnpm)( +(--prefix|--workspace|--dir|-w|-C)([ =]+)[^ ]+)+ +(test|run +(test(:[A-Za-z0-9_.:-]+)?|e2e))([ ;&|]|$)' && return 0
  return 1
}
heavy=0
while IFS=$'\t' read -r flag seg sseg cseg csseg; do
  [ -n "$flag" ] || continue
  targeted "$seg" && continue
  hit=0
  is_heavy "$cseg" && hit=1
  [ "$hit" = 0 ] && [ "$csseg" != "$cseg" ] && is_heavy "$csseg" && hit=1
  if [ "$flag" = 1 ]; then
    # An approved segment, recorded with what it bypassed — and ONLY when this segment is
    # the heavy one. An override in front of a segment that was never going to be refused
    # waives nothing: `SUITE_OK=1 true && npm test` used to write a ledger line and then
    # refuse the suite anyway, so the record of approvals held a line for a run that never
    # happened.
    if [ "$hit" = 1 ]; then
      guard_log_override SUITE_OK "$rawcmd" "heavy suite, load check skipped" \
        || { guard_refuse_unrecorded "heavy-suite-guard" "SUITE_OK=1"; exit 2; }
    fi
    continue
  fi
  [ "$hit" = 1 ] && { heavy=1; break; }
done <<<"$segrecs"

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
  echo "heavy-suite-guard: REFUSED — the machine is busy (load $load, limit $MAX_LOAD): a full suite started now would pile onto whatever is running and slow both. Wait and retry; single-file, -t and --version/--list runs are exempt. Deliberate override: SUITE_OK=1 <command>" >&2
  exit 2
fi
exit 0
