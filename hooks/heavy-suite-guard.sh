#!/bin/bash
# PreToolUse hook on Bash. A full test suite can take minutes and pin the CPU; running two
# at once on the same machine makes both slower and their results less trustworthy. Three
# checks, in this order:
#   1. STOP-BY-NAME (always on): `pkill`, `killall` and kin are refused outright — see below.
#   2. LOAD: when the 1-minute load average is already at or above MAX_LOAD, something else
#      looks like it is running a suite — so refuse this one and say wait.
#   3. MEMORY: a test-like command is refused when free memory is under MIN_FREE percent.
# WHAT COUNTS AS HEAVY, per command segment (split on ; & | and newlines, so one segment's
# words never make another segment heavy): `npm|yarn|pnpm test`, `npm|yarn|pnpm run test`,
# a `run test:<something>` script, `run e2e`, `vitest run`, `playwright test` — with or
# without `npx`, and a bare `vitest` with no named test file too; the runner reached by path
# (`node node_modules/.bin/vitest run`, `./node_modules/.bin/vitest run`) and npm/yarn/pnpm with
# a `--prefix`/`--workspace`/`-w`/`-C` flag in front of the script (`npm --prefix apps/web test`).
# ONE SPELLING: before PATTERN is matched each segment is rewritten to a single canonical
# spelling, so the many ways to say the same thing are one thing to the guard. Wrappers are
# peeled (leading VAR=val words, time, timeout N, nice, caffeinate, nohup, env, command,
# builtin, exec, eval, stdbuf, arch, xcrun, script, watch, coproc, sudo, doas, xargs, redirections
# (also in front: `> out.log npm test`), `(` `{` `!` and if/then/do-style keywords, and `find ...
# -exec <cmd>`), `bash|sh|zsh|dash|ksh -c "..."` (also `-lc`, also an unquoted body such as
# `bash -c pkill\ x`), `env -S "..."` and `eval "..."` are unwrapped, and then `npm t`, `npm run-script test`, `npm -w x test`, `yarn test`,
# `pnpm vitest`, `npm exec`/`dlx` become `npm test`, `npm run <script>` or `npx <bin>`; `npx
# -y vitest@latest`, `node_modules/.bin/vitest` and `node node_modules/vitest/...` become
# `npx vitest`. A conf PATTERN is therefore matched against that canonical text.
# The command must stand at the segment's COMMAND POSITION: a runner named as an ARGUMENT —
# `rg vitest docs/`, `which vitest`, `echo npm test >> notes` — is not a run.
# A test run captured in a value or an echo (`out="$(npm test 2>&1)"`, `echo `npm test``) is judged
# like any other run: every $(...) and backtick body is read as a command line of its own.
# WHAT IS EXEMPT FROM THE LOAD CHECK, in the same segment: a single-file run — EVERY argument after
# the runner is a `*.test.*` / `*.spec.*` file (`a.test.ts:12` and a quoted name with a space
# count; an option value, a redirect target, an assignment or a comment never does) — and one
# named test: a `-t` / `--testNamePattern` / `-g` / `--grep` selector whose value is neither empty
# nor `.` / `.*`. They are NOT exempt from the memory check. WHAT IS EXEMPT FROM BOTH: a query — `--version`, `--list` or
# `--help` anywhere in the segment, `-h`/`-v`/`-V` as the runner's only argument, `vitest
# list` — judged per segment, so `node --version && npm test` still refuses the `npm test`.
# MEMORY: free memory is read from macOS `memory_pressure` ("free percentage"). Where that
# command is missing or its answer cannot be read (Linux, a stripped PATH) the check PASSES —
# it fails OPEN, because a guard that refuses on a number it cannot read would block every
# test run on such a machine. It covers everything PATTERN matches (even a single-file run)
# plus MEMPATTERN: type-checks (`npm|yarn|pnpm run typecheck`, `tsc`, `npx tsc`). MIN_FREE
# is the least free percentage a test may start at (default 35).
# STOP-BY-NAME: `pkill -f "cat"` once matched the command line of the Claude app itself and
# stopped it. Refused, judged per segment on quote-blanked text (also inside shell -c / eval
# bodies, $(...), backticks and <(...) up to eight deep, one level deeper is refused, and a
# live $(...) in a commit message or an unquoted-delimiter heredoc): pkill, killall, killall5, skill; kill aimed at
# a group or everything (0, -N, -1, `-- -N`, -$VAR); kill fed by a lookup ($(...) or
# backticks that are not a PID-file read, a variable filled by a lookup on the same line or by
# another such variable, an array filled by one, a lookup piped or redirected (`< <(pgrep x)`)
# into `read`/`mapfile`, a file a lookup wrote earlier on the line and is read back with
# `$(cat FILE)` or `xargs kill < FILE`); a group kill whose id comes from anywhere (`kill -9
# -$(cat pgid)`, `$((-1))`); anything piped into `xargs kill` (but not `cat FILE | xargs kill`); `fuser -k`, `npx kill-port`, `launchctl kill`, `find -exec kill`. Allowed:
# `kill <PID>`, `kill $PID`, `kill -0`, `kill %1`, `kill -l`, `pgrep` alone, `$(cat FILE)`,
# `$(head|tail -n1 FILE)`, `$(sed -n 1p FILE)`, `$(jq .pid FILE)`, `$(< FILE)`, `$(jobs -p)`,
# `pkill --help` (a FILE that no lookup on the same line wrote). This runs BEFORE the load
# and memory checks. Deliberate override: start the SEGMENT with `KILL_OK=1 `, recorded in
# the override ledger like SUITE_OK; an override that cannot be recorded is refused. A waiver is
# written to the ledger only once the WHOLE command passes (`KILL_OK=1 pkill x; pkill y` is
# refused and leaves no line).
# HOW THE COMMAND IS READ (hooks/guard-lib.sh, shared with the other Bash guards): commit
# messages and heredoc bodies are dropped, `bash|sh|zsh -c "…"` and `eval "…"` are
# unwrapped (a wrapper is not a hiding place), quoted text is blanked (so prose such as
# `echo "run npm test later" >> DEBT.md` is not a test run), and redirections (`>`, `<`)
# count as separators, so `npm test>log` is the same command as `npm test > log`.
# The command pattern and the thresholds come from hooks/heavy-suite.conf, next to this
# script (see hooks/heavy-suite.conf.example for the format: PATTERN='...' and
# MEMPATTERN='...' as extended regexes, MAX_LOAD=10, MIN_FREE=35); a conf saved with Windows
# line endings (CRLF) is read the same as a Unix one — a stray carriage return used to leave
# PATTERN unmatchable, which silently disabled the guard. No conf file: the built-in defaults
# apply.
# Deliberate override for a test: start the SEGMENT that would be refused with `SUITE_OK=1 ` —
# `cd apps/web && SUITE_OK=1 npm test` approves that run, while `SUITE_OK=1 true && npm
# test` approves only the `true`. Judged on text with quoted strings removed, so the word
# inside a commit message can no longer disarm the guard. A command word hidden in a
# variable (`T=npm; $T test`) is judged by its arguments, with `npm` standing in for the
# name the guard cannot see. Every use is written to hooks/override-ledger.sh; if that line CANNOT
# be written (no ledger script, unwritable path) the override is REFUSED, not honoured.
# NOT enforced (deliberate-bypass shapes the guard does not try to read): a word split by quotes
# (`pk""ill`, `np""m test`); a variable or alias as the command (`K=pkill; $K x`, `R=test; npm
# $R`, `alias t=...`); a command built by another command (`$(echo pkill) x`); text piped or
# fed into a shell (`echo pkill x | bash`, `bash <<< "..."`); other interpreters (`python3 -c`,
# `perl -e`, `node -e`, `osascript`, `ssh`); a case-insensitive disk (`NPM test`); the Linux
# `script -c "..."` form.
# Test seams: HEAVY_SUITE_LOAD_OVERRIDE=<load> stands in for the real `uptime` reading and
# HEAVY_SUITE_MEM_OVERRIDE=<free %> for the `memory_pressure` one.
# jq, python3 and hooks/guard-lib.sh all parse the command below; if any is missing this
# guard cannot read what it is being asked to run, so it refuses rather than silently
# letting an unparsed (and therefore unmatched) heavy suite through. Fail closed, like
# git-hooks/pre-commit.
# Tests: hooks/test-hooks.sh (`refresh 2026-09-29 (a)` for the command position, the runner by path, the busy wording and the python3 choice; `guard port 2026-10-10 (A)` for memory, the one spelling and stop-by-name; `guard port 2026-10-10 (F1)` for the routes the blind attack found).
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
# Memory-heavy but not load-heavy: type-checks. Only the memory check covers these.
MEMPATTERN='(^|[;&| ])(npm|yarn|pnpm) +run +typecheck([ ;&|]|$)|(^|[;&| ])(npx +)?tsc([ ;&|]|$)'
MAX_LOAD=10
MIN_FREE=35
if [ -f "$CONF" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"                       # a conf saved with CRLF must still bind
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in
      PATTERN=*) v="${line#PATTERN=}"; v="${v%\'}"; v="${v#\'}"; PATTERN="$v" ;;
      MEMPATTERN=*) v="${line#MEMPATTERN=}"; v="${v%\'}"; v="${v#\'}"; MEMPATTERN="$v" ;;
      MAX_LOAD=*) MAX_LOAD="${line#MAX_LOAD=}" ;;
      MIN_FREE=*) MIN_FREE="${line#MIN_FREE=}" ;;
    esac
  done < "$CONF"
fi

# The python reading prints two blocks joined by a \001 byte:
#   (1) kill records, one per segment judged a stop-by-name:   <bad 0|1> TAB <KILL_OK at the
#       segment start 0|1> TAB <segment>
#   (2) test records, one per command segment, fields joined by \037: <SUITE_OK at the start of
#       THIS segment 0|1> <query 0|1> <the segment> <the segment at its command position, in
#       the one canonical spelling>. A segment whose command word is hidden in a variable
#       (`T=npm; $T test`) also gets a record with `npm` standing in for the hidden word.
# Messages and heredocs are dropped, wrappers unwrapped, whitespace (and `${IFS}`) normalised,
# quoted text blanked and redirections turned into separators before either reading.
both="$(printf '%s' "$cmd" | "$GUARD_PY" -c "$GUARD_PY_COMMON"'
raw = sys.stdin.read()

# ---- unwrapping a shell -c / eval / env -S body, as the shell would de-escape it ----
_QSTR = r"(?:\"(?:[^\"\\]|\\.)*\"|\x27[^\x27]*\x27)"
_SHC2 = re.compile(r"(?<![\w.-])(?:[\w./-]*/)?(?:bash|sh|zsh|dash|ksh)\s+(?:--?[A-Za-z][\w-]*\s+)*?-[A-Za-z]*c[A-Za-z]*\s+(" + _QSTR + r"|(?:\\.|[^\s;&|\"\x27\\])+)")
_EVAL2 = re.compile(r"\beval\s+(" + _QSTR + ")")
_ENVS = re.compile(r"(?<![\w.-])(?:[\w./-]*/)?env\s+(?:-\S+\s+)*?-[A-Za-z]*S\s*(" + _QSTR + ")")
def _body(q):
    if q[0] not in "\"\x27":                 # a bare word: only backslash escapes to undo (`pkill\ x`)
        return " " + re.sub(r"\\(.)", r"\1", q) + " "
    b = q[1:-1]
    if q[0] == "\"":
        b = re.sub(r"\\([$\x60\"\\])", r"\1", b)
    return " " + b + " "
def unwrap2(x):
    for _ in range(3):
        t = _ENVS.sub(lambda m: _body(m.group(1)), _EVAL2.sub(lambda m: _body(m.group(1)), _SHC2.sub(lambda m: _body(m.group(1)), x)))
        if t == x:
            break
        x = t
    return x
# an escaped backtick, dollar, pipe, semicolon or ampersand is literal text, not syntax
_ESC = {"\x60": "_BQ_", "$": "_DL_", "|": "_PI_", ";": "_SC_", "&": "_AM_"}
def esc(x):
    return re.sub(r"\\([\x60$|;&])", lambda m: _ESC[m.group(1)], x)

# ---- peeling wrappers off the front of a segment ----
# word -> the options of that wrapper that take a value (so the value is skipped with the option)
LEADVAL = {"time": (), "nohup": (), "builtin": (), "command": (), "eval": (), "coproc": (), "doas": ("-u", "-C"), "exec": ("-a",),
    "stdbuf": ("-i", "-o", "-e"), "arch": ("-e", "-d"), "xcrun": ("--sdk", "-sdk", "--toolchain", "-toolchain"),
    "script": ("-t",), "watch": ("-n", "--interval"),
    "env": ("-u", "--unset", "-C", "--chdir", "-P", "-S"), "nice": ("-n", "--adjustment"),
    "timeout": ("-s", "--signal", "-k", "--kill-after"), "caffeinate": ("-t", "-w"),
    "sudo": ("-u", "-g", "-C", "-h", "-p", "-U", "-r", "-t", "-D", "-R", "-T", "--user", "--group"),
    "xargs": ("-n", "-I", "-P", "-L", "-s", "-d", "-E", "-J", "-R", "-S", "--max-args",
        "--max-procs", "--max-lines", "--max-chars", "--delimiter", "--eof")}
LEADKW = ("!", "then", "do", "else", "if", "elif", "while", "until", "{", "(", "}", ")")
FINDEXEC = ("-exec", "-execdir", "-ok", "-okdir")
def lead(toks):
    # returns (the tokens from the command word on, whether xargs stood in front)
    via = False
    i = 0
    n = len(toks)
    while i < n:
        t = toks[i]
        b = t.rsplit("/", 1)[-1]
        if t in LEADKW or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=\S*", t):
            i += 1
            continue
        if re.fullmatch(r"\d*(?:<<<|[<>]{1,2}|&>>?)", t):      # `> file` : operator and its target
            i += 2
            continue
        if re.fullmatch(r"\d*(?:<<<|[<>]{1,2}|&>>?)\S+", t):   # `>file`
            i += 1
            continue
        if b not in LEADVAL:
            break
        if b == "command" and i + 1 < n and toks[i + 1] in ("-v", "-V"):
            break
        if b == "xargs":
            via = True
        i += 1
        while i < n and toks[i].startswith("-") and toks[i] != "-":
            if toks[i] == "--":
                i += 1
                break
            i += 2 if toks[i] in LEADVAL[b] else 1
        if b in ("timeout", "script") and i < n:        # timeout takes its duration, script its file, as a bare word
            i += 1
        if b == "coproc" and i + 1 < n and toks[i + 1] == "{":     # coproc NAME { ...; }
            i += 1
    return toks[i:], via

# ---- one canonical spelling ----
BINS = ("vitest", "playwright", "tsc", "kill-port")
NPMVAL = ("-w", "--workspace", "--prefix", "-C", "--loglevel", "--userconfig", "--cwd", "--dir", "--filter", "-F")
def skipflags(t, i, val):
    while i < len(t) and t[i].startswith("-") and t[i] != "-":
        if t[i] == "--":
            return i + 1
        i += 2 if t[i] in val else 1
    return i
def binname(x):
    return re.sub(r"(?<=.)@.*$", "", x)          # vitest@latest -> vitest
def canon(t):
    # returns (canonical tokens, how many of them name the command: `npm test` 2, `npx vitest` 2)
    if not t:
        return t, 0
    w = t[0]
    b = w.rsplit("/", 1)[-1]
    m = re.search(r"node_modules/\.bin/(vitest|playwright|tsc)$", w)
    if m:
        return ["npx", m.group(1)] + t[1:], 2
    if b == "node":
        i = skipflags(t, 1, ("-r", "--require", "--import"))
        if i < len(t):
            m = re.search(r"node_modules/(?:\.bin/(vitest|playwright|tsc)$|(vitest|typescript|playwright|@playwright/test)/)", t[i])
            if m:
                k = m.group(1) or {"vitest": "vitest", "typescript": "tsc", "playwright": "playwright", "@playwright/test": "playwright"}[m.group(2)]
                return ["npx", k] + t[i + 1:], 2
        return t, 1
    if b in ("npm", "pnpm", "yarn"):
        i = skipflags(t, 1, NPMVAL)
        if i < len(t) and b == "yarn" and t[i] == "workspace":
            i = skipflags(t, i + 2, NPMVAL)
        if i >= len(t):
            return t, 1
        cm = t[i]
        if cm in ("exec", "x", "dlx"):
            return canon(["npx"] + t[i + 1:])
        if cm == "test" or (b == "npm" and cm in ("t", "tst", "it", "cit", "install-test", "install-ci-test")):
            return ["npm", "test"] + t[i + 1:], 2
        if cm in ("run", "run-script", "rum", "urn"):
            j = skipflags(t, i + 1, NPMVAL)
            if j < len(t):
                if t[j] == "test":
                    return ["npm", "test"] + t[j + 1:], 2
                if b != "npm" and binname(t[j]) in BINS:
                    return ["npx", binname(t[j])] + t[j + 1:], 2
                return ["npm", "run", t[j]] + t[j + 1:], 3
            return t, 1
        if b != "npm":
            if binname(cm) in BINS:
                return ["npx", binname(cm)] + t[i + 1:], 2
            return ["npm", "run", cm] + t[i + 1:], 3
        return ["npm"] + t[i:], 2
    if b in ("npx", "bunx"):
        i = skipflags(t, 1, ("-p", "--package", "-c", "--call", "-w", "--workspace"))
        if i < len(t):
            return ["npx", binname(t[i])] + t[i + 1:], 2
        return t, 1
    return t, 1
def is_query(t, h):
    if any(x in ("--version", "--list", "--help") for x in t):
        return True
    a = t[h:]
    if a in (["-h"], ["-v"], ["-V"]):
        return True
    if t[:h] in (["npx", "tsc"], ["tsc"]) and any(x in ("--init", "--showConfig", "--listFiles", "--listEmittedFiles") for x in a):
        return True
    return t[:h] in (["npx", "vitest"], ["vitest"]) and a[:1] == ["list"]
MAXD = 8              # substitutions are read this deep; one level deeper is refused, not guessed at
def close_paren(t, i):
    depth = 0
    q = None
    for k in range(i, len(t)):
        ch = t[k]
        if q:
            if ch == q:
                q = None
        elif ch in "\x27\"":
            q = ch
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return k
    return len(t)
def lift_subs(t, lq=False):
    # -> (the text with each substitution replaced by a marker, the list of their inner texts)
    # $(...), backticks and process substitutions <(...) >(...) are lifted. lq: the text is the body of a
    # message or heredoc, where a quote character is just a character.
    out = []
    subs = []
    q = None
    i = 0
    n = len(t)
    while i < n:
        ch = t[i]
        if lq:
            pass
        elif q == "\x27":                     # inside single quotes nothing is special
            out.append(ch)
            if ch == "\x27":
                q = None
            i += 1
            continue
        elif ch == "\x27" and q is None:
            q = "\x27"
            out.append(ch)
            i += 1
            continue
        elif ch == "\"":
            q = None if q == "\"" else "\""
            out.append(ch)
            i += 1
            continue
        if t[i:i + 3] == "$((":               # arithmetic, unless it hides a real substitution
            j = close_paren(t, i + 1)
            if "$(" not in t[i + 3:j] and "\x60" not in t[i + 3:j]:
                inner = t[i + 3:j - 1]
                v = None
                if re.fullmatch(r"(?:\s*[-+]?\s*\d+)+\s*", inner):          # a literal number, or a plain sum of them, is the value
                    v = sum((-1 if sg == "-" else 1) * int(d) for sg, d in re.findall(r"([-+]?)\s*(\d+)", inner))
                out.append(str(v) if v is not None else "ARITH")
                i = j + 1
                continue
        if ch == "$" and t[i + 1:i + 2] == "(":
            j = close_paren(t, i + 1)
            subs.append(t[i + 2:j])
            out.append("__SUB%d__" % (len(subs) - 1))
            i = j + 1
            continue
        if ch in "<>" and t[i + 1:i + 2] == "(" and q != "\"" and not lq:
            j = close_paren(t, i + 1)
            subs.append(t[i + 2:j])
            out.append(ch + " __SUB%d__" % (len(subs) - 1))
            i = j + 1
            continue
        if ch == "\x60":
            j = t.find("\x60", i + 1)
            if j < 0:
                j = n
            subs.append(t[i + 1:j])
            out.append("__SUB%d__" % (len(subs) - 1))
            i = j + 1
            continue
        out.append(ch)
        i += 1
    return "".join(out), subs
def dropped_subs(x):
    # live $(...) / backtick bodies inside the text strip_messages and strip_heredocs drop: a double-quoted
    # message and an unquoted-delimiter heredoc body are expanded by the shell, so they are commands too
    got = []
    for m in _MSG.finditer(x):
        if m.group(3)[0] == "\"":
            got.extend(lift_subs(esc(m.group(3)[1:-1]), True)[1])
    for m in _HEREDOC.finditer(x):
        h = x[m.start():m.end()]
        if not re.match(r"<<-?\s*[\x27\"]", h):
            got.extend(lift_subs(esc(h[h.index("\n") + 1:]), True)[1])
    return got
c = normalize_ws(esc(unwrap2(strip_messages(strip_heredocs(raw)))))
extra = dropped_subs(raw)
if extra:
    c = c + "\n" + "\n".join(normalize_ws(e) for e in extra)

# redirections: the operator and its target are not arguments of the command
_REDIR = re.compile(r"\d*(?:<<<|>>|>|<<|<)")
def strip_redirs(toks):
    out = []
    i = 0
    while i < len(toks):
        if _REDIR.fullmatch(toks[i]):
            i += 2
            continue
        out.append(toks[i])
        i += 1
    return out
def reading(seg):
    # a segment -> (its text at the command position in canonical spelling, is it a query, the tokens after the runner)
    toks, _ = lead(seg.split())
    if toks and toks[0].rsplit("/", 1)[-1] == "find":
        for fi, fx in enumerate(toks):
            if fx in FINDEXEC:
                toks, _ = lead(toks[fi + 1:])
                break
    toks, h = canon(strip_redirs(toks))
    if not toks:
        return "", False, []
    return " ".join(toks), is_query(toks, h), toks[h:]

# ---- a single-file or one-test run (exempt from the load check) ----
# Targeted = every positional argument after the runner is a test file (never an option value, a
# redirect target, an assignment or a comment), or a test-name selector whose value is not empty
# and not a match-everything pattern.
_TESTFILE = re.compile(r".*\.(?:test|spec)\.[A-Za-z0-9]+(?::\d+)*")
SELECT = ("-t", "--testNamePattern", "-g", "--grep")
OPTVAL = ("--outputFile", "--exclude", "--reporter", "--config", "-c", "--root", "-r", "--project", "--dir", "--shard",
    "--testTimeout", "--environment", "--pool", "--mode", "--workspace", "--include", "--retry", "--repeat-each",
    "--workers", "-j", "--timeout", "--browser", "--output", "--grep-invert", "-gv", "--tsconfig", "--coverage.reporter",
    "--coverage.reportsDirectory", "--maxWorkers", "--minWorkers", "--setupFiles", "--globals", "--logHeapUsage")
def qtext(x, qs):
    m = re.fullmatch(r"Q(\d+)", x)
    return qs[int(m.group(1))] if m and int(m.group(1)) < len(qs) else x
def targeted(args, qs):
    pos = []
    i = 0
    n = len(args)
    first = True
    while i < n:
        x = args[i]
        i += 1
        if x == "--":
            continue
        name, eq, val = x.partition("=")
        if name in SELECT and x.startswith("-"):
            if not eq:
                val = qtext(args[i], qs) if i < n else ""
                i += 1
            else:
                val = qtext(val, qs)
            if val.strip() not in ("", ".", ".*"):
                return True
            continue
        if x.startswith("-"):
            if not eq and name in OPTVAL:
                i += 1
            continue
        if first and x in ("run", "test"):        # the runner own subcommand, not a file
            first = False
            continue
        first = False
        pos.append(qtext(x, qs))
    return bool(pos) and all(_TESTFILE.fullmatch(x) for x in pos)

# ---- the test reading: records of (override, query, targeted, segment, canonical text) ----
# a quoted VALUE (A="x y") becomes a plain word; a quoted plain word ("vitest") loses its quotes;
# any other quoted text becomes a numbered word Q<n> (its text kept aside, for the -t value check)
_QV = re.compile(r"(?<![\w$])([A-Za-z_][A-Za-z0-9_]*=)(?:\"(?:[^\"\\]|\\.)*\"|\x27[^\x27]*\x27)")
_QW = re.compile(r"\"([-A-Za-z0-9_./%:+=@${}!#,]+)\"|\x27([-A-Za-z0-9_./%:+=@${}!#,]+)\x27")
def parens_apart(x):
    return re.sub(r"[()]", " ; ", x)
def test_texts(t, depth=0):
    # the command line itself, then every $(...) and backtick body in it (a test run captured in a value is a run)
    out = [t]
    if depth < MAXD:
        for x in lift_subs(t)[1]:
            out.extend(test_texts(x, depth + 1))
    return out
def test_records(c):
    recs = []
    qs = []
    def blank_idx(m):
        qs.append(m.group(0)[1:-1])
        return " Q%d " % (len(qs) - 1)
    s = _QW.sub(lambda m: m.group(1) or m.group(2), _QV.sub(r"\1QV", c))
    s = _QUOTED.sub(blank_idx, s)
    s = re.sub(r"\d*[<>]&(?:\d+|-)", " ", s).replace("&>", ">").replace(">|", ">")
    s = re.sub(r"(?:(?<![\w.-])\d+)?(?:<<<|>>|>|<<|<)", lambda m: " " + m.group(0) + " ", s)
    s = re.sub(r"(?<!\S)#[^\n]*", "", s)
    for seg in segments(parens_apart(s)):
        seg = seg.strip().replace("\n", " ")
        text, q, args = reading(seg)
        if text:
            recs.append("\x1f".join(["1" if override_at_start(seg, "SUITE_OK") else "0", "1" if q else "0", "1" if targeted(args, qs) else "0", seg, text]))
    for seg in segments(s):
        hid = hidden_cmdword(seg, "npm")
        if hid == seg:
            continue
        flag = "1" if override_at_start(seg, "SUITE_OK") else "0"
        for sub in segments(parens_apart(hid)):
            text, q, args = reading(sub.strip().replace("\n", " "))
            if text:
                recs.append("\x1f".join([flag, "1" if q else "0", "1" if targeted(args, qs) else "0", seg.replace("\n", " "), text]))
    return recs
trecs = []
for ct in test_texts(c):
    trecs.extend(test_records(ct))

# ---- the stop-by-name reading ----
# Every $(...) and backtick is lifted out by a quote- and paren-aware scan (so it is also found
# inside double quotes and assignments) and judged as a command line of its own; the outer text
# keeps a __SUBn__ marker. fd duplications (2>&1) are dropped before the split on & .
_SIGTOK = re.compile(r"^-(?:[A-Za-z][A-Za-z0-9]*|\d+)$")
_SIMPLE = re.compile(r"[-A-Za-z0-9_./%:+=@${}!#,\[\]]+")
KWORDS = ("pkill", "killall", "killall5", "skill")
LOOKUPW = ("pgrep", "pidof", "lsof", "ps", "pstree", "fuser", "ss", "netstat", "pidwait")
_QASSIGN = re.compile(r"(?<![\w$])([A-Za-z_][A-Za-z0-9_]*\+?=)(\"(?:[^\"\\]|\\.)*\"|\x27[^\x27]*\x27)")
def blank_for_kill(x):
    # quoted text blanked, except a quoted plain word is unquoted (kill "0") and a double-quoted marker is kept;
    # a quoted assignment value (A="x y") is reduced first, so the assignment stays one word with its markers
    def qa(m):
        b = m.group(2)[1:-1]
        k = re.findall(r"__SUB\d+__", b) if m.group(2)[0] == "\"" else []
        if k:
            return m.group(1) + "".join(k)
        return m.group(1) + (b if _SIMPLE.fullmatch(b) else "QV")
    x = _QASSIGN.sub(qa, x)
    def f(m):
        q = m.group(0)
        b = q[1:-1]
        if _SIMPLE.fullmatch(b):
            return b
        if q[0] == "\"":
            k = re.findall(r"__SUB\d+__", b)
            if k:
                return " " + " ".join(k) + " "
        return " Q "
    return _QUOTED.sub(f, x)
_PIDARG = r"(?:\s+[^\s|;&()<>\x60-][^\s|;&()<>\x60]*)+\s*"
def is_pid_read(inner):
    # a captured PID, not a lookup: $(cat FILE), $(head|tail [-n N] FILE), $(sed -n Np FILE), $(jq [-r] .key FILE),
    # $(< FILE), $(jobs -p); quotes and output redirections (2>/dev/null) ignored; FILE may be a variable
    x = re.sub(r"[\"\x27]", "", inner)
    x = re.sub(r"\d*(?:>>?|>&|&>)\s*[^\s|;&()<>]+", " ", x)
    if re.fullmatch(r"\s*<\s*[^\s|;&()<>\x60]+\s*", x) or re.fullmatch(r"\s*jobs\s+-p[a-z]*\s*", x):
        return True
    if re.fullmatch(r"\s*echo(?:\s+(?:\$\{?[A-Za-z_]\w*\}?|\$\$|\$!|\d+))+\s*", x):
        return True
    mp = re.fullmatch(r"\s*pgrep\s+-P\s*\$\((.*)\)\s*", x)
    if mp and is_pid_read(mp.group(1)):
        return True
    if re.fullmatch(r"\s*pgrep\s+-P\s*\$\$\s*", x) or re.fullmatch(r"\s*ps\s+-o\s*pid=\s+-p\s*(?:\$\{?[A-Za-z_]\w*\}?|\d+)\s*", x):
        return True
    stages = x.split("|")
    if not re.fullmatch(r"\s*(?:cat|head(?:\s+-n\s*\d+|\s+-\d+)?|tail(?:\s+-n\s*\d+|\s+-\d+)?|sed\s+-n\s+\d+p|jq(?:\s+-r)?\s+\.[\w.\[\]]*)" + _PIDARG, stages[0]):
        return False
    return all(re.fullmatch(r"\s*(?:head|tail)(?:\s+-n\s*\d+|\s+-\d+)?\s*", y) for y in stages[1:])
_HARMLESS = re.compile(r"\s*(?:git\s+rev-parse|mktemp|pwd|dirname|basename|date)(?:\s+[^\s|;&()<>\x60]+)*\s*")
def split_keep_sep(x):
    mk = _mask(x)
    parts = []
    last = 0
    for m in _SEGRE.finditer(mk):
        parts.append((x[last:m.start()], m.group(0)))
        last = m.end()
    parts.append((x[last:], ""))
    return parts
def marks_in(x):
    return [int(k) for k in re.findall(r"__SUB(\d+)__", x)]
def words_of(x):
    return [w for w in re.split(r"[\s\x27\"<>|;&()]+", x) if w]
def stops(seg, ok, taint, prev, before, tfiles):
    toks, via = lead(seg.split())
    toks, _ = canon(toks)
    if not toks:
        return False
    w = toks[0].rsplit("/", 1)[-1]
    a = toks[1:]
    if w in KWORDS:
        return not (a and all(x in ("--help", "--version", "-V") for x in a))
    if w == "kill-port" or (w == "npx" and a[:1] == ["kill-port"]):
        return True
    if w == "fuser":
        return "--kill" in a or any(re.fullmatch(r"-[A-Za-z]*k[A-Za-z]*", x) for x in a)
    if w == "launchctl":
        return [x for x in a if not x.startswith("-")][:1] == ["kill"]
    if w == "find":
        for i, x in enumerate(a):
            if x in FINDEXEC:
                r, _ = lead(a[i + 1:])
                if r and r[0].rsplit("/", 1)[-1] in ("kill",) + KWORDS:
                    return True
        return False
    if w != "kill":
        return False
    if via:
        # `xargs kill`: fine only when a PID file is piped straight in (cat run.pid | xargs kill) or redirected in
        # (a file a lookup wrote earlier on the line is a lookup)
        if before == "|" and prev is not None:
            pt, _ = lead(prev.split())
            if pt and is_pid_read(" ".join(pt)) and not any(f in tfiles for f in words_of(" ".join(pt))):
                return False
        mf = re.search(r"(?:^|\s)<\s+([^\s<>|;&()]+)\s*$", seg)
        if mf and "__SUB" not in mf.group(1) and mf.group(1) not in tfiles:
            return False
        return True
    rest = re.sub(r"(?<!\S)\d*[<>]+&?\S*|[<>]+&?\S*", " ", " ".join(a))
    a = [x.rstrip(")}") for x in rest.split()]
    a = [x for x in a if x]
    if a and a[0] in ("-l", "-L"):
        return False
    i = 0
    sig = None
    if a and a[0] in ("-s", "-n"):
        i = 2
    elif a and _SIGTOK.match(a[0]):
        sig = a[0]
        i = 1
    elif len(a) > 1 and re.fullmatch(r"-\$\S+", a[0]):
        sig = a[0]
        i = 1
    if i < len(a) and a[i] == "--":
        i += 1
    tg = a[i:]
    if not tg and sig == "-1":
        return True
    for x in tg:
        if re.fullmatch(r"-\d+", x) or re.fullmatch(r"0+", x) or x.startswith("-"):    # a group: any target led by a minus
            return True
        if any(not ok[k] for k in marks_in(x)):
            return True
        if any(v in taint for v in re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)", x)):
            return True
    return False
_ASSIGNRE = re.compile(r"(?:^|[\s;&|({])(?:for\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\s+([^;&|\n]*)|([A-Za-z_][A-Za-z0-9_]*)\+?=(?:\(([^)]*)\)|(\S*)))")
_READRE = re.compile(r"(?<![\w-])(?:read|mapfile|readarray)\b([^;&|\n<>]*)")
def read_names(args):
    return re.findall(r"(?<![-\w$])([A-Za-z_]\w*)", args)
def kill_lines(t, depth=0):
    outer, subs = lift_subs(t)
    ok = [is_pid_read(x) for x in subs]
    if depth >= MAXD:
        inner_bad = [True] * len(subs)               # nested deeper than it is read: refused, not guessed at
    else:
        inner_bad = [any(r[0] for r in kill_lines(x, depth + 1)) for x in subs]
    b0 = blank_for_kill(outer)
    harmless = [_HARMLESS.fullmatch(x) is not None for x in subs]
    def bad_mark(k):
        return not ok[k] and not harmless[k]
    # a file a lookup wrote (pgrep x > p; pgrep x | tee p) is a lookup when read back
    tfiles = set()
    for chunk in re.split(r"&&|\|\||;|&|\n", b0):
        lk = any(bad_mark(k) for k in marks_in(chunk))
        for stage in chunk.split("|"):
            st, _ = lead(stage.split())
            if st and st[0].rsplit("/", 1)[-1] in LOOKUPW:
                lk = True
        if lk:
            tfiles.update(re.findall(r"(?<![<>])>>?\s*([^\s<>|;&()]+)", chunk))
            tfiles.update(re.findall(r"\btee\s+(?:-a\s+)?([^\s<>|;&()]+)", chunk))
    for k in range(len(ok)):
        if ok[k] and any(f in tfiles for f in words_of(subs[k])):
            ok[k] = False
    # a variable filled by a lookup on the same line (pids=$(pgrep x); for p in $(pgrep x)) is a lookup too,
    # and so is every variable that is set from a tainted one (to a fixed point)
    taint = set()
    assigns = []
    for m in _ASSIGNRE.finditer(b0):
        if m.group(1):
            assigns.append((m.group(1), m.group(2) or ""))
        else:
            assigns.append((m.group(3), (m.group(4) if m.group(4) is not None else m.group(5)) or ""))
    # a lookup piped into a read (while read, { read ...; }, mapfile) taints what it reads; a PID file piped in does not
    for m in re.finditer(r"([^;&|\n]*)\|\s*[{(]?\s*(?:while\s+)?(?:IFS=\S*\s+)?(?:read|mapfile|readarray)\b([^;&|\n]*)", b0):
        stage = m.group(1)
        if not (is_pid_read(stage) and not any(f in tfiles for f in words_of(stage))):
            taint.update(read_names(m.group(2)))
    # a read fed by redirection (< <(pgrep x), < file-a-lookup-wrote) taints every variable read on the line
    for m in re.finditer(r"(?<![<\d])<\s*(__SUB\d+__|[^\s<>|;&()]+)", b0):
        src = m.group(1)
        bad_src = bad_mark(marks_in(src)[0]) if src.startswith("__SUB") else src in tfiles
        if bad_src:
            for r in _READRE.finditer(b0):
                taint.update(read_names(r.group(1)))
    changed = True
    while changed:
        changed = False
        for name, val in assigns:
            if name not in taint and (any(bad_mark(k) for k in marks_in(val)) or any(v in taint for v in re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)", val))):
                taint.add(name)
                changed = True
        for k in range(len(ok)):
            if ok[k] and any(v in taint for v in re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)", subs[k])):
                ok[k] = False
                changed = True
    b = re.sub(r"[()]", " ; ", b0)
    res = []
    prev = None
    before = ""
    for seg, sep in split_keep_sep(b):
        if seg.strip():
            bad = stops(seg, ok, taint, prev, before, tfiles) or any(inner_bad[k] for k in marks_in(seg))
            res.append((bad, seg.strip()))
            prev = seg
        before = sep
    return res
kt = re.sub(r"\d*(?:>&|<&)(?:\d+|-)", " ", c).replace("&>", ">")
krecs = []
for bad, seg in kill_lines(kt):
    krecs.append(("1" if bad else "0") + "\t" + ("1" if override_at_start(seg, "KILL_OK") else "0") + "\t" + seg.replace("\n", " "))
sys.stdout.write("\n".join(krecs) + "\x01" + "\n".join(trecs))')"
guard_parsed "heavy-suite-guard" python3 $? "$both" "$rawcmd"
SEP=$'\001'
krecs="${both%%$SEP*}"; segrecs="${both#*$SEP}"

# Waivers are only NOTED while the command is judged and written to the ledger by finish() once the
# WHOLE command has passed: `KILL_OK=1 pkill x; pkill y` is refused and leaves no ledger line.
waivers=()
finish() {   # <exit code 0>: record every waiver, then pass; an unrecordable one refuses
  local w word detail
  for w in "${waivers[@]}"; do
    word="${w%%$'\t'*}"; detail="${w#*$'\t'}"
    guard_log_override "$word" "$rawcmd" "$detail" || { guard_refuse_unrecorded "heavy-suite-guard" "$word=1"; exit 2; }
  done
  exit 0
}

# ---- 1. stop by name (before the load and memory checks) ----
while IFS=$'\t' read -r kflag kok kseg; do
  [ "$kflag" = 1 ] || continue
  if [ "$kok" = 1 ]; then
    waivers+=("KILL_OK"$'\t'"$kseg")
    continue
  fi
  echo "heavy-suite-guard: REFUSED — this stops every process matching a name, word, port or group, which can stop the Claude app itself. Stop only the process you started, by the PID you captured when you started it: kill <PID>. Deliberate override, only on the owner's word: KILL_OK=1 <command>" >&2
  exit 2
done <<<"$krecs"

is_heavy() {   # $1 a segment AT ITS COMMAND POSITION, canonical spelling: PATTERN, then the always-on safety net beside it
  # PATTERN is anchored: a runner word that is another command's ARGUMENT (`rg vitest docs/`,
  # `which vitest`, `echo npm test`) is not a run.
  printf '%s' "$1" | grep -qE "^($PATTERN)" && return 0
  # Always-on safety net alongside PATTERN (never narrower, only wider): a bare
  # `vitest`/`npx vitest` naming no test file still runs the whole suite; the runner reached by
  # path (`node node_modules/.bin/vitest run`, `./node_modules/.bin/vitest run`); and npm/yarn/
  # pnpm with a workspace or prefix flag in front of the script (`npm --prefix apps/web test`).
  # The canonical spelling already folds most of these into `npm test` / `npx vitest`.
  printf '%s' "$1" | grep -qE '^(npx +)?vitest( +run)?([ ;&|]|$)' && return 0
  printf '%s' "$1" | grep -qE '^(npx +)?playwright +test([ ;&|]|$)' && return 0
  printf '%s' "$1" | grep -qE '^(node +)?[^ ]*node_modules/\.bin/(vitest( +run)?|playwright +test)([ ;&|]|$)' && return 0
  printf '%s' "$1" | grep -qE '^(npm|yarn|pnpm)( +(--prefix|--workspace|--dir|-w|-C)([ =]+)[^ ]+)+ +(test|run +(test(:[A-Za-z0-9_.:-]+)?|e2e))([ ;&|]|$)' && return 0
  return 1
}
is_memheavy() {   # $1 the same canonical text: the memory-only pattern (type-checks)
  printf '%s' "$1" | grep -qE "^($MEMPATTERN)"
}
heavy=0       # a segment the LOAD check applies to
memheavy=0    # a segment the MEMORY check applies to
while IFS=$'\037' read -r flag query tgt seg cseg; do
  [ -n "$flag" ] && [ -n "$cseg" ] || continue
  [ "$query" = 1 ] && continue                       # --version / --list / --help: exempt from both
  hit=0; mem=0
  is_heavy "$cseg" && hit=1
  if [ "$hit" = 1 ]; then mem=1; elif is_memheavy "$cseg"; then mem=1; fi
  [ "$mem" = 1 ] || continue
  if [ "$flag" = 1 ]; then
    # An approved segment, recorded with what it bypassed — and ONLY when this segment is
    # the one that would have been refused. An override in front of a segment that was never
    # going to be refused waives nothing: `SUITE_OK=1 true && npm test` used to write a ledger
    # line and then refuse the suite anyway. The line is written by finish(), once the whole
    # command has passed.
    waivers+=("SUITE_OK"$'\t'"heavy suite, load and memory checks skipped")
    continue
  fi
  memheavy=1
  if [ "$hit" = 1 ] && [ "$tgt" != 1 ]; then heavy=1; fi
done <<<"$segrecs"

[ "$heavy" = 1 ] || [ "$memheavy" = 1 ] || finish

# ---- 2. load ----
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
if [ "$heavy" = 1 ]; then
  load="${HEAVY_SUITE_LOAD_OVERRIDE:-$(read_load)}"
  if awk -v l="$load" -v m="$MAX_LOAD" 'BEGIN{exit !(l+0>=m+0)}'; then
    echo "heavy-suite-guard: REFUSED — the machine is busy (load $load, limit $MAX_LOAD): a full suite started now would pile onto whatever is running and slow both. Wait and retry; single-file, -t and --version/--list runs are exempt from the load check. Deliberate override: SUITE_OK=1 <command>" >&2
    exit 2
  fi
fi

# ---- 3. memory ----
# macOS `memory_pressure` ends with "System-wide memory free percentage: NN%". Missing command
# or unreadable answer = pass (fail open).
if [ "$memheavy" = 1 ]; then
  free="${HEAVY_SUITE_MEM_OVERRIDE:-$(memory_pressure 2>/dev/null | tail -1 | sed -nE 's/.*free percentage: *([0-9]+)%.*/\1/p')}"
  case "$free" in ''|*[!0-9]*) finish ;; esac
  case "$MIN_FREE" in ''|*[!0-9]*) MIN_FREE=35 ;; esac
  if [ "$free" -lt "$MIN_FREE" ]; then
    echo "heavy-suite-guard: REFUSED — the machine is low on memory ($free% free; a test needs $MIN_FREE%). Another test is probably running: wait and retry. Single-file and -t runs are NOT exempt from this check; only --version/--list/--help queries are. Deliberate override: SUITE_OK=1 <command>" >&2
    exit 2
  fi
fi
finish
