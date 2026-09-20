#!/bin/bash
# gate-guard.sh — PreToolUse hook on Bash. Two things a hook can catch mechanically that a
# rulebook sentence can't enforce on its own:
# (a) a gate (a test run, a typecheck, a build check) is trustworthy only when its EXIT CODE
#     decides what happens next, joined with `&&`. Refused when the gate's output is piped
#     into a reader (tee/tail/head/grep/wc/sed/awk/less/cut, "|" or "|&") — the exit code
#     that reaches the shell is then the READER's, not the gate's — or when `;` (or a bare
#     newline) joins it to a commit, a push, or `echo READY`, which lets a red run continue
#     into either one anyway.
# (b) a loop that polls a log file for a marker (`while`/`until` … grep|tail … sleep) is
#     refused: waiting on a background job should block on the job itself (`wait`, a
#     job-control/monitor tool, a task-completion notification) and then read the result
#     file it wrote — not guess from a marker that might never appear. A loop whose
#     CONDITION checks a process or a port instead (curl/nc/kill -0/pgrep/lsof) is a
#     "is the server up yet" wait, not a log-marker poll, and is exempt.
#
# Quoted strings, -m/--message arguments and heredoc bodies are dropped before matching, so
# a commit message that merely NAMES a gate cannot trigger a refusal; a `bash -c "…"` /
# `sh -c "…"` / `zsh -c "…"` wrapper is unwrapped first so the command inside it is matched
# too, not hidden by the quote-strip.
#
# Which commands count as a "gate": a built-in default (vitest, playwright, tsc, npm test,
# npm run test, npm run typecheck) plus anything listed, one per line, in
# hooks/gate-guard.conf (see hooks/gate-guard.conf.example) — ADDED ON TOP of the built-in
# list, never replacing it. No conf file: the built-in list alone applies.
#
# GATE_OK=1 at the start of a command segment passes and writes a ledger line via
# override-ledger.sh (if present — a missing ledger script must never block this hook).
# Fails CLOSED (exit 2) on input that cannot be parsed ONLY when the raw text still carries
# gate-shaped vocabulary (test, typecheck, vitest, privacy, READY, commit, push); otherwise
# it passes through untouched — a missing jq or python3 must not refuse every unrelated
# Bash call.
# Tests: hooks/test-hooks.sh.
input="$(< /dev/stdin)"; [ -z "$input" ] && exit 0
if ! printf '%s' "$input" | jq -e . >/dev/null 2>&1; then
  if printf '%s' "$input" | grep -Eq 'test|typecheck|vitest|privacy|READY|commit|push'; then
    echo "gate-guard: REFUSED — unparseable hook input carrying gate vocabulary (fail closed)" >&2; exit 2
  fi
  exit 0
fi
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"; [ "$tool" = "Bash" ] || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"; [ -z "$cmd" ] && exit 0
if printf '%s' "$cmd" | grep -qE '(^|[;&|] *)GATE_OK=1 '; then
  L="$(dirname "$0")/override-ledger.sh"; [ -f "$L" ] && bash "$L" GATE_OK "$cmd"
  exit 0
fi
GATE_EXTRA=""
CONF="$(dirname "$0")/gate-guard.conf"
if [ -f "$CONF" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    GATE_EXTRA="${GATE_EXTRA}${GATE_EXTRA:+$'\n'}$line"
  done < "$CONF"
fi
verdict="$(printf '%s' "$cmd" | GATE_EXTRA="$GATE_EXTRA" python3 -c '
import re,sys,os
s=sys.stdin.read()
s=re.sub(r"<<-?\s*[\x27\"]?(\w+)[\x27\"]?[^\n]*\n.*?\n\1(?=\n|$)", " HEREDOC ", s, flags=re.S)
def unwrap_c(m):
    b=m.group(1)
    return " "+b[1:-1]+" "
s=re.sub(r"\b(?:bash|sh|zsh)\s+-c\s+(\"(?:[^\"\\\\]|\\\\.)*\"|\x27[^\x27]*\x27)", unwrap_c, s)
s=re.sub(r"(-m|--message)(=|\s+)(\"(?:[^\"\\\\]|\\\\.)*\"|\x27[^\x27]*\x27)", r"\1 MSG", s, flags=re.S)
s=re.sub(r"\"(?:[^\"\\\\]|\\\\.)*\"|\x27[^\x27]*\x27", " Q ", s)
gate=r"(?:(?:npx\s+)?(?:vitest|playwright|tsc)\b|npm\s+(?:run\s+)?(?:test(?::[\w-]+)?|typecheck)\b)"
extra=[ln.strip() for ln in os.environ.get("GATE_EXTRA","").split("\n") if ln.strip()]
if extra:
    alts=[r"(?:npx\s+)?" + r"\s+".join(re.escape(w) for w in tok.split()) + r"\b" for tok in extra]
    gate = gate + "|(?:" + "|".join(alts) + ")"
seg=r"(?:[^|;&\n]|\d?>&\d)*"   # the gate arguments: 2>&1 allowed; && ; | end them
s_flat=re.sub(r"\n", ";", s)   # a bare newline joins statements exactly like ; for rule (a)
if re.search(gate+seg+r"\|&?\s*(?:tee|tail|head|grep|wc|sed|awk|less|cut)\b", s_flat): print("pipe"); sys.exit()
if re.search(gate+seg+r";\s*(?:git\s+(?:commit|push)\b|echo\s+READY\b)", s_flat): print("semicolon"); sys.exit()
for line in s.split("\n"):
    if re.search(r"\b(?:while|until)\b", line):
        m=re.search(r"\b(?:while|until)\b(.*?);", line)
        cond=m.group(1) if m else line
        if re.search(r"\b(?:curl|nc|kill\s+-0|pgrep|lsof)\b", cond):
            continue
        if re.search(r"\bsleep\b", line) and re.search(r"\b(?:grep|tail)\b", line):
            print("waiter"); sys.exit()
print("ok")
' 2>/dev/null)" || verdict="parse-error"
case "$verdict" in
  ok) exit 0;;
  pipe) echo "gate-guard: REFUSED — a gate piped into a reader hides its exit code (gate on the EXIT CODE, joined with &&; write the output to a log file and read that afterwards). Deliberate override: GATE_OK=1 <command>." >&2; exit 2;;
  semicolon) echo "gate-guard: REFUSED — ';' (or a bare newline) after a gate lets a red run continue into the commit or push; join with &&. Deliberate override: GATE_OK=1 <command>." >&2; exit 2;;
  waiter) echo "gate-guard: REFUSED — a loop polling a log waits on a marker: wait on the process, a job-control/monitor tool, or a task-completion notification, and read the result file it writes. Deliberate override: GATE_OK=1 <command>." >&2; exit 2;;
  *) echo "gate-guard: REFUSED — could not parse the command (fail closed)." >&2; exit 2;;
esac
