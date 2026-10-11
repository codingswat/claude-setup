#!/bin/bash
# gate-guard.sh — PreToolUse hook on Bash. Three things a hook can catch mechanically that a
# rulebook sentence can't enforce on its own:
# (a) a gate (a test run, a typecheck, a build check) is trustworthy only when its EXIT CODE
#     decides what happens next, joined with `&&`. The gate is found in the one canonical
#     spelling heavy-suite-guard.sh uses (guard-lib.sh): npm / pnpm / yarn / npx / a path /
#     time, timeout, nice, env, sudo ... in front all read the same. Refused when
#       - the gate's output is piped into a reader (tee/tail/head/grep/rg/cat/wc/sed/awk/less/
#         cut, "|" or "|&", with or without `2>&1`) — the exit code that reaches the shell is
#         then the READER's — AND a commit, a push or `echo READY` comes anywhere later in
#         the command (a piped gate with nothing riding on it, `npx vitest run x | tail -3`
#         alone, only reads output and passes; so does a commit placed BEFORE the gate); or
#       - a `;`, `&`, `||` or a bare newline follows the gate, and a commit, a push or
#         `echo READY` comes after that join, however far (`npm test; true; git commit`,
#         `npm test || git commit`): a red run continues into it. Passes: `|| exit 1` /
#         `|| return` between them, and a gate that is an `if`/`while`/`until` condition.
#     `git -C <path> commit` / `git -c k=v push` / `git --git-dir <p> push` count as a commit
#     or a push.
# (b) a loop that polls a log or a file for a marker (`while`/`until`/`for` … grep|rg|tail …
#     sleep, a `[ -f x ]` / `test -s x` test, a `$(cat x)` read, then sleep) is refused: waiting
#     on a background job should block on the job itself (`wait`, a job-control/monitor tool, a
#     task-completion notification) and then read the result file it wrote — not guess from a
#     marker that might never appear. A loop whose CONDITION checks a process or a port
#     instead (curl/nc/kill -0/pgrep/lsof) is a "is the server up yet" wait, not a poll, and
#     is exempt. The loop is read FLATTENED, so writing it across several lines is not a way out.
# (c) a `git push`, a `git rebase` or a `git pull` whose output goes through a single `|` or
#     `|&` into ANY program is refused: the exit code that reaches the shell is the reader's,
#     so a rejected push (or a failed merge or rebase) looks like success. Found at the start
#     of a statement or after `;` `&` `|` `$(` `(` `{` `if` `then` `elif` `else` `do` `while`
#     `until`, after VAR=value assignments (a quoted value too), after `time`, `!`, nice, env,
#     sudo ..., after a backslash-newline, and after git's global options (`-C <path>`, `-c
#     k=v`, `--git-dir <p>`, `--work-tree <p>`, `--namespace <n>`, `--no-pager`, `-P`). A group
#     piped as a whole (`{ git push; } 2>&1 | tail`, `( git push ) | tail`) counts. Passes:
#     `--dry-run` / `-n` (push); --help, --show-current-patch, --edit-todo; `set -o pipefail`
#     earlier in the command (and not switched off again with `set +o pipefail`); a
#     `${PIPESTATUS[…]}` READ in a statement after the pipeline (not in a comment, not in
#     single quotes); `||` (that is not a pipe). Write the output to a file and read that.
# Every violation in the command is judged on its own: GATE_OK=1 must stand at the start of
# each violating statement, and the ledger lines are written only when the whole command passes.
#     NOT enforced (deliberate-bypass shapes, left passing): quote-split words (`"git" push`,
#     `np""m test`), a variable or alias holding the command (`G=git; $G push | tail`), a
#     substitution as the command word (`$(echo git) push`), text piped into a shell (`echo
#     git push | bash`), other interpreters (python3 -c, perl -e, node -e, osascript, ssh),
#     a different spelling of the binary on a case-insensitive disk (`NPM test`), function
#     bodies, xargs, process substitution <(...), and `echo "READY"` (the quoted word).
#
# WHAT IS NOT A GATE RUN, even though the word appears:
#   - a gate word that is some other command's ARGUMENT — `ls node_modules/.bin | grep
#     vitest | head`. The word must stand at command position (the start of a pipeline
#     segment, after optional VAR=value assignments).
#   - a query rather than a run: `npx tsc --version | head -1`, `vitest --help`.
#   - quoted text, -m/--message arguments and heredoc bodies (dropped before matching), so
#     a commit message that merely NAMES a gate cannot trigger a refusal. A `bash -c "…"` /
#     `sh -c "…"` / `zsh -c "…"` / `eval "…"` wrapper is unwrapped first, so the command
#     inside it is matched too, not hidden by the quote-strip.
#
# Which commands count as a "gate": a built-in default (vitest, playwright, tsc, npm test,
# npm t, npm run test, npm run typecheck, and `npm -w <workspace> test` / `--workspace` /
# `--prefix` in front; pnpm and yarn spell the same) plus anything listed, one per line, in
# hooks/gate-guard.conf (see hooks/gate-guard.conf.example) — ADDED ON TOP of the built-in
# list, never replacing it, and never turning the built-ins into a blanket refusal (the
# conf-added names join the built-in group; they used to be spliced in as a top-level
# alternative, which made EVERY command holding a gate word a refusal).
# No conf file: the built-in list alone applies.
#
# GATE_OK=1 at the start of the SEGMENT that would be refused passes and writes a ledger
# line via override-ledger.sh, naming the rule it bypassed — `GATE_OK=1 npm test | tee
# out.log` approves that run, `GATE_OK=1 true && npm test | tee out.log` approves only the
# `true`; if that line CANNOT be written (no
# ledger script, unwritable path) the override is REFUSED, not honoured.
#
# WHAT IT DOES WITHOUT ITS TOOLS. jq missing: warns once on stderr ("install jq") and passes.
# jq present but the input unparseable: fails CLOSED (exit 2) ONLY when the raw text still
# carries gate-shaped vocabulary (test, typecheck, vitest, privacy, READY, commit, push);
# anything else passes untouched. python3 missing:
# this guard passes everything with a one-line warning on stderr — it is INERT, not
# strict. That is deliberate and it is the one guard where failing OPEN is acceptable:
# it protects no data and can destroy nothing; it only enforces a habit about exit codes.
# Refusing every Bash command on a machine without python3 would cost far more than the
# habit is worth. hooks/guard-lib.sh missing: fails CLOSED — that file is part of this
# hook, not part of the machine, so its absence means a broken install, not a thin one.
# Tests: hooks/test-hooks.sh (`refresh 2026-09-29 (a)` for A21, A22, A23, A85).
GUARD_LIB="$(dirname "$0")/guard-lib.sh"
if [ ! -r "$GUARD_LIB" ]; then
  echo "gate-guard: REFUSED — hooks/guard-lib.sh is missing next to this hook, so the command cannot be normalised before matching (fail closed, not open). Reinstall the hooks (install.sh copies hooks/*.sh)." >&2
  exit 2
fi
. "$GUARD_LIB"
input="$(< /dev/stdin)"; [ -z "$input" ] && exit 0
# jq missing: this guard is a nudge, so it warns once and PASSES (never refuses on a word such as
# "test" inside a folder name). Tests: hooks/test-hooks.sh `review fixes (critical)` 2.
if ! command -v jq >/dev/null 2>&1; then
  GG_MARK="${GATE_GUARD_STATE_DIR:-$HOME/.claude/state}/gate-guard-nojq-warned"
  if [ ! -e "$GG_MARK" ]; then
    echo "gate-guard: jq not found — this check is OFF (it passes every command); install jq to enable this check." >&2
    mkdir -p "$(dirname "$GG_MARK")" 2>/dev/null && : > "$GG_MARK" 2>/dev/null
  fi
  exit 0
fi
if ! printf '%s' "$input" | jq -e . >/dev/null 2>&1; then
  if printf '%s' "$input" | grep -Eq 'test|typecheck|vitest|privacy|READY|commit|push'; then
    echo "gate-guard: REFUSED — unparseable hook input carrying gate vocabulary (fail closed)" >&2; exit 2
  fi
  exit 0
fi
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"; [ "$tool" = "Bash" ] || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"; [ -z "$cmd" ] && exit 0
if [ -z "$GUARD_PY" ] || [ ! -x "$GUARD_PY" ]; then
  echo "gate-guard: python3 not found — this guard is INERT for this command (it only checks how gates are joined; it protects no data, so it passes rather than refusing). Install python3 to turn it back on." >&2
  exit 0
fi
GATE_EXTRA=""
CONF="$(dirname "$0")/gate-guard.conf"
if [ -f "$CONF" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"                       # a conf saved with CRLF must still bind
    case "$line" in ''|'#'*) continue ;; esac
    GATE_EXTRA="${GATE_EXTRA}${GATE_EXTRA:+$'\n'}$line"
  done < "$CONF"
fi
verdict="$(printf '%s' "$cmd" | GATE_EXTRA="$GATE_EXTRA" "$GUARD_PY" -I -c "$GUARD_PY_COMMON"'
s0 = clean(sys.stdin.read())

# ---- text copies, all with comments removed (a comment is never a command or a read) ----
def strip_comments(x):
    mk = _mask(x)
    out_ = list(x)
    for m in re.finditer(r"(?:^|(?<=[\s;&|(]))#[^\n]*", mk):
        for i in range(m.start(), m.end()):
            out_[i] = " "
    return "".join(out_)
def blank_keep_subs(x):
    # quoted text blanked, except a $(...) or backtick body inside a double quote: it runs
    def f(m):
        q = m.group(0)
        if q[0] == "\"":
            return " Q " + " ".join(re.findall(r"\$\([^()]*\)|\x60[^\x60]*\x60", q)) + " "
        return " Q "
    return _QUOTED.sub(f, x)
s0 = strip_comments(s0)
s_loop = blank_keep_subs(s0).replace("\n", ";")        # for the polling-loop rule
# For the statement reading: arithmetic is a number, $( and each ( ) { } stands alone as a word, a
# quoted assignment value (VAR="a b" git push) is reduced so the assignment still reads as one word.
s = re.sub(r"\$\(\([^()]*\)\)", " 0 ", s0)
s = s.replace("$(", " ( ")
s = re.sub(r"[()]", lambda m: " " + m.group(0) + " ", s)
s = re.sub(r"(?<![\w-])(\w+)=(?:\"(?:[^\"\\]|\\.)*\"|\x27[^\x27]*\x27)", r"\1=x", s)
so = s                      # quotes intact (the PIPESTATUS read is judged on this copy)
mk = _mask(so)              # same length; quoted text is x, so a separator inside quotes never splits

gate_re = r"(?:test(?::[\w-]+)?|t|typecheck)"
extra = [ln.strip().split() for ln in os.environ.get("GATE_EXTRA", "").split("\n") if ln.strip()]
READERS = ("tee", "tail", "head", "grep", "rg", "cat", "wc", "sed", "awk", "less", "cut")
PIPES = ("|", "|&")
GROUPS = ("(", ")", "{", "}")
STRONG = ("&&", "||", "|", "|&", "&")
_SPLIT = re.compile(r"&&|\|\||\|&|;|(?<!>)\||\n|(?<![<>&])&(?!>)|(?:(?<=\s)|^)[(){}](?=\s|$)")

def is_gate(t):
    # t: the command and its arguments (wrappers peeled). The one canonical spelling decides, so
    # pnpm / yarn / npx / a path / a wrapper in front all read as the same gate.
    if not t:
        return False
    ct, h = canon(t)
    if is_query(ct, h) or any(x in ("--version", "--help", "--list") for x in ct):
        return False
    b = ct[0].rsplit("/", 1)[-1]
    if ct[:1] == ["npx"] and len(ct) > 1 and ct[1] in ("vitest", "playwright", "tsc"):
        return True
    if b in ("vitest", "playwright", "tsc"):
        return True
    if ct[:1] == ["npm"] and len(ct) > 2 and ct[1] == "run" and re.fullmatch(gate_re, ct[2]):
        return True
    if ct[:1] == ["npm"] and len(ct) > 1 and re.fullmatch(gate_re, ct[1]):
        return True
    for words in extra:
        for tt in (ct, t):
            tt = tt[1:] if tt[:1] == ["npx"] else tt
            if tt[:len(words)] == words:
                return True
    return False

_GVAL = ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--config-env", "--attr-source", "--exec-path")
def git_verb(t):
    # -> (the subcommand, its arguments), after git global options and their values; None when not git
    if not t or t[0].rsplit("/", 1)[-1] != "git":
        return None
    i = 1
    while i < len(t) and t[i].startswith("-") and t[i] != "-":
        i += 2 if t[i] in _GVAL else 1
    if i >= len(t):
        return None
    return t[i], t[i + 1:]
def is_rider(t):
    # what can ride on a gate: a commit, a push, or `echo READY`
    if not t:
        return False
    if t[0].rsplit("/", 1)[-1] == "echo":
        return len(t) > 1 and re.match(r"READY(?![\w])", t[1]) is not None
    v = git_verb(t)
    return v is not None and v[0] in ("commit", "push")
def piped_verb(t):
    # a push, a rebase or a pull, that is not asking for help or a dry run
    v = git_verb(t)
    if v is None or v[0] not in ("push", "rebase", "pull"):
        return False
    verb, args = v
    if any(a in ("--help", "-h", "--show-current-patch", "--edit-todo") for a in args):
        return False
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-o", "--push-option", "--receive-pack", "--exec", "--repo"):
            i += 2                                  # the value of -o is not an option
            continue
        if a == "--dry-run" or (verb == "push" and a == "-n"):
            return False
        i += 1
    return True
def ov_at(toks):
    # GATE_OK=1 counts only as a leading assignment of THIS statement (after !, time, braces)
    for x in toks:
        if x == "GATE_OK=1":
            return True
        if x in LEADKW or x == "time" or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=\S*", x):
            continue
        break
    return False

# ---- cut the command into statements; remember what joins them and which groups a pipe follows ----
stmts = []
pending = ""
gstack = []
closed = []
pos = 0
for m in list(_SPLIT.finditer(mk)) + [None]:
    end = m.start() if m else len(so)
    text = so[pos:end]
    toks = blank_quoted(text).split()
    t = lead(toks)[0] if toks else []
    sepw = m.group(0) if m else ""
    sep = ";" if sepw == "\n" else sepw
    isgrp = sepw in GROUPS
    if t:
        closed = []
        stmts.append({"a": pos, "b": end, "sb": pending, "toks": toks, "t": t, "gp": False})
        pending = sepw if isgrp else sep
    elif sep and not isgrp:
        if sep in PIPES:                            # `{ ...; } 2>&1 | tail`: the pipe takes the whole group
            for (ga, gb) in closed:
                for k in range(ga, gb):
                    stmts[k]["gp"] = True
        closed = []
        if not (sep == ";" and pending in STRONG):  # a newline after `&&` keeps the `&&`
            pending = sep
    if sepw in ("(", "{"):
        gstack.append(len(stmts))
    elif sepw in (")", "}") and gstack:
        closed.append((gstack.pop(), len(stmts)))
    pos = m.end() if m else 0
n = len(stmts)
for i in range(n):
    stmts[i]["sa"] = stmts[i + 1]["sb"] if i + 1 < n else ""

def pipe_end(i):
    while i + 1 < n and stmts[i]["sa"] in PIPES:
        i += 1
    return i
viol = []      # (rule, waived)
def flag(rule, i):
    viol.append((rule, ov_at(stmts[i]["toks"])))

# (a): a gate whose exit code does not decide what happens next
for gi in range(n):
    st = stmts[gi]
    if st["toks"][0] in ("if", "elif", "while", "until") or not is_gate(st["t"]):
        continue
    pe = pipe_end(gi)
    readers = any(stmts[k]["t"][0].rsplit("/", 1)[-1] in READERS for k in range(gi + 1, pe + 1))
    rider = None
    if pe > gi and readers:
        rule, cands = "pipe", [j for j in range(pe + 1, n) if is_rider(stmts[j]["t"])]
    else:
        f = next((j for j in range(pe + 1, n) if stmts[j]["sb"] in (";", "&", "||")), None)
        rule, cands = "semicolon", ([] if f is None else [j for j in range(f, n) if is_rider(stmts[j]["t"])])
    if not cands:
        continue
    if any(stmts[k]["t"][0] in ("exit", "return") for k in range(gi + 1, cands[0])):
        continue                                    # `|| exit 1` stops the run: the exit code decides
    flag(rule, gi)

# (c): a push, a rebase or a pull whose output goes through a pipe
for k in range(n):
    st = stmts[k]
    j = k
    if st["gp"]:
        while j < n - 1 and stmts[j]["sa"] not in PIPES:
            j += 1
    if stmts[j]["sa"] not in PIPES or not piped_verb(st["t"]):
        continue
    pe = pipe_end(j)
    on = None
    for pm in re.finditer(r"\bset\s+(?:[-+][A-Za-z]+\s+)*([-+])[A-Za-z]*o\s+pipefail\b", mk[:st["a"]]):
        on = pm.group(1) == "-"
    if on:
        continue
    after = _QUOTED.sub(lambda q: "" if q.group(0)[0] == "\x27" else q.group(0), so[stmts[pe]["b"]:])
    if re.search(r"\$\{PIPESTATUS\[[^\]]*\]\}", after):
        continue
    flag("pushpipe", k)

# (b): a loop polling a log or a file for a marker
filetest = r"(?:\[\[?|\btest)\s+(?:!\s+)?-[fsedrL]\s"
for m in re.finditer(r"\b(?:while|until|for)\b(.*?)(?:;|\bdo\b)", s_loop):
    cond = m.group(1)
    if re.search(r"\b(?:curl|nc|kill\s+-0|pgrep|lsof)\b", cond):
        continue
    body = s_loop[m.end():]
    k = re.search(r"(?<![\w.-])done(?![\w.-])", body)
    if k:
        body = body[:k.start()]
    both = cond + " " + body
    if re.search(r"\bsleep\b", both) and (re.search(r"\b(?:grep|tail|rg)\b", both) or re.search(filetest, both) or re.search(r"(?:\$\(|\x60)\s*cat\b", both)):
        viol.append(("waiter", override_here(s_loop, "GATE_OK", m.start())))

bad = [r for r, w in viol if not w]
if bad:
    print(bad[0] + "\t0")
elif viol:
    print(",".join(r for r, w in viol) + "\t1")
else:
    print("ok\t0")
' 2>/dev/null)"
guard_parsed "gate-guard" python3 $? "$verdict" "$cmd"
rule="${verdict%%$'\t'*}"; over="${verdict##*$'\t'}"
if [ "$over" = 1 ]; then
  # every waived violation is logged, and only now that the whole command passes
  IFS=, read -r -a waived <<< "$rule"
  for rule in "${waived[@]}"; do
    guard_log_override GATE_OK "$cmd" "$rule" || { guard_refuse_unrecorded "gate-guard" "GATE_OK=1"; exit 2; }
  done
  exit 0
fi
case "$rule" in
  ok) exit 0;;
  pipe) echo "gate-guard: REFUSED — a gate piped into a reader hides its exit code (gate on the EXIT CODE, joined with &&; write the output to a log file and read that afterwards). Deliberate override: GATE_OK=1 <command>." >&2; exit 2;;
  pushpipe) echo "gate-guard: REFUSED — a pipe after git push, git rebase or git pull hides its exit code (a rejected push would look like success); run it without the pipe and judge \$?, or write its output to a file and read that. Deliberate override: GATE_OK=1 <command>." >&2; exit 2;;
  semicolon) echo "gate-guard: REFUSED — ';', '&', '||' (or a bare newline) after a gate lets a red run continue into the commit or push; join with &&. Deliberate override: GATE_OK=1 <command>." >&2; exit 2;;
  waiter) echo "gate-guard: REFUSED — a loop polling a log waits on a marker: wait on the process, a job-control/monitor tool, or a task-completion notification, and read the result file it writes. Deliberate override: GATE_OK=1 <command>." >&2; exit 2;;
  *) echo "gate-guard: REFUSED — could not parse the command (fail closed)." >&2; exit 2;;
esac
