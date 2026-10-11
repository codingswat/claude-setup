#!/bin/bash
# guard-lib.sh — NOT a hook. Shared text handling for the four PreToolUse Bash guards
# (block-dangerous-git.sh, commit-pathspec-guard.sh, heavy-suite-guard.sh, gate-guard.sh),
# kept in one place so a normalisation fix lands in all four at once instead of drifting
# between four copies.
# What a guard reads is a SHELL command line, and the same command can be written many
# ways: quoted (`git reset "--hard"`), tab-separated, backslash-escaped (`gi\t`), split
# over lines with a trailing backslash, spelled with `${IFS}` in place of every space, or
# hidden inside `sh -c "…"` / `eval "…"`. Every helper below exists to make those
# spellings match the one the pattern is written for.
#   strip_heredocs / strip_messages — drop pasted text and -m/--message arguments, so a
#     commit message that merely NAMES a banned command neither triggers nor disarms.
#   unwrap        — bring the command inside `bash|sh|zsh -c "…"` and `eval "…"` out to
#                   the top level, so a wrapper is not a bypass.
#   normalize_ws  — CR, tabs, escaped newlines, stray backslashes AND `${IFS}` / `$IFS`
#                   become plain spaces. `git${IFS}reset${IFS}--hard` is one space away
#                   from `git reset --hard` and the shell runs it as such, so the guards
#                   must read it as such.
#   strip_quotechars — drop the quote CHARACTERS, keep the words (matching copy).
#   blank_quoted  — drop the quoted CONTENT (override copy: a word inside a string can
#                   never count as an override the user typed).
#   segments / seg_bounds / override_here — split a command on ; && || | & and newlines
#                   OUTSIDE quoted strings. Every guard judges a segment on its own, and
#                   an override word counts ONLY at the start of the segment that matched
#                   — `git push --force && GITGUARD=1 true` approves the `true`, not the
#                   force-push.
#   override_at_start — an override word counts only as a leading environment assignment.
#   hidden_cmdword — a command word produced by a variable or a substitution (`$GIT`,
#                   `${G}`, `$(which git)`, `` `echo git` ``) cannot be matched by any
#                   pattern, because the binary does not exist until the shell runs it.
#                   It is replaced by a STAND-IN (the guard passes the binary it protects
#                   against, e.g. "git"), so the ARGUMENTS still decide: `$GIT reset
#                   --hard` is judged as `git reset --hard` and refused, while
#                   `$(which git) status` and `$TOOLS/lint.sh --fix` are judged as
#                   `git status` / `git --fix` and pass. Refusing every `$`-led command
#                   word instead would refuse honest work (`"$W/bin/lint.sh" --fix`).
#   has_substituted_git — the same shape in front of `commit`, where the arguments alone
#                   cannot say what will be committed: that one is refused outright.
#   substituted_args — the mirror image, and the hole hidden_cmdword leaves open: the
#                   command word is a plain `git`, but its SUBCOMMAND comes from a variable
#                   or a substitution (`R=reset; git $R --hard`), or the subcommand is a
#                   mutating one the guard judges by its arguments (the caller names them:
#                   push, reset, commit...) and one of THOSE comes from a variable
#                   (`git push origin $F`). There the arguments are exactly what cannot be
#                   read, so the shape decides nothing and the command is refused. A
#                   variable in a READ-ONLY command (`git diff HEAD -- $paths`, `git -C
#                   $W/repo status`, `git log -$n`) is an honest read and passes. Read on
#                   the copy with quoted CONTENT blanked, so a substitution inside a quoted
#                   message or value (`git commit -m "$msg" f.ts`, `git log
#                   --author="$me"`) is not a substituted argument and still passes.
#   wrapped_substitution — `eval`/`sh -c`/`bash -c` handed an argument that is itself a
#                   substitution or a bare variable (`eval "$cmd"`). unwrap can bring an
#                   inline literal out to the top level; it cannot bring out text that
#                   does not exist until the shell runs, so that wrapper is refused.
#                   Checked BEFORE unwrap, on text that still holds the wrapper.
#   lead / canon / is_query — the canonical reading of a command segment, shared by
#                   heavy-suite-guard.sh and gate-guard.sh: lead() peels what stands in front
#                   of the command word (VAR=value, redirections, ! time nohup env sudo nice
#                   timeout stdbuf watch ... and the keywords then/do/{/( ), canon() spells
#                   npm / pnpm / yarn / npx / bunx / node_modules/.bin/ paths one way
#                   (`npm test`, `npx vitest ...`), is_query() says it only asks (--version,
#                   --help, tsc --init ...).
# A guard that cannot find this file REFUSES the command (fail closed) — never carries on
# with un-normalised text, which would silently reopen every bypass above.
# Tests: hooks/test-hooks.sh (sections 28 and 30; `refresh 2026-09-29 (a)` for A01 and A85).

# guard_resolve_python — the python3 every guard runs. PREFER /usr/bin/python3, else the
# first python3 on PATH: a broken python3 earlier on PATH (a conda or pyenv shim that exits
# non-zero) then cannot make every Bash call fail closed. On a host with no /usr/bin/python3
# (some Linux images) the PATH one is used, as before. GUARD_PYTHON_PREFERRED is a TEST SEAM
# (the suite points it at a missing file to drive the PATH fallback and the failing-parser
# cases); leave it unset in real use. Each guard checks the result is executable before use.
# The preferred one must also RUN: on a Mac without the Command Line Tools /usr/bin/python3 is a
# stub that exits non-zero, and choosing it would fail every guard closed (test-hooks.sh "D1b").
guard_resolve_python() {
  local p="${GUARD_PYTHON_PREFERRED:-/usr/bin/python3}"
  if [ -x "$p" ] && "$p" -c '' >/dev/null 2>&1; then printf '%s' "$p"; else command -v python3 2>/dev/null; fi
}
GUARD_PY="$(guard_resolve_python)"

# Python helper definitions, prepended to each guard's own python snippet:
#   python3 -c "$GUARD_PY_COMMON"'<the guard-specific code>'
GUARD_PY_COMMON='
import re, sys, os
_HEREDOC = re.compile(r"<<-?\s*[\x27\"]?(\w+)[\x27\"]?[^\n]*\n.*?\n\1(?=\n|$)", re.S)
_MSG = re.compile(r"(-m|--message)(=|\s+)(\"(?:[^\"\\\\]|\\\\.)*\"|\x27[^\x27]*\x27)", re.S)
_SHC = re.compile(r"\b(?:bash|sh|zsh)\s+-c\s+(\"(?:[^\"\\\\]|\\\\.)*\"|\x27[^\x27]*\x27)")
_EVAL = re.compile(r"\beval\s+(\"(?:[^\"\\\\]|\\\\.)*\"|\x27[^\x27]*\x27)")
_QUOTED = re.compile(r"\"(?:[^\"\\\\]|\\\\.)*\"|\x27[^\x27]*\x27")
_IFS = re.compile(r"\$\{IFS\}|\$IFS(?![A-Za-z0-9_])")
_SEGRE = re.compile(r"&&|\|\||;|\||&|\n")
_HIDDEN = re.compile(r"(^|[;&|(\n])(\s*(?:[A-Za-z_][A-Za-z0-9_]*=[^\s]*\s+)*)(\$\{?[A-Za-z_][^\s]*|\$\([^()]*\)|[\x60][^\x60]*[\x60])")
_SUBGIT = re.compile(r"(?<!-C )(?<!-c )(?<!--git-dir )(?<!--work-tree )(?:\$\{?[A-Za-z_][^\s]*|\$\([^()]*\)|[\x60][^\x60]*[\x60])\s+(?:-\S+\s+)*commit\b")
_ANYSUB = re.compile(r"\$\{?[A-Za-z_(0-9]|[\x60]")
_WRAPARG = re.compile(r"\b(?:eval|(?:bash|sh|zsh)\s+-c)\s+(\"[^\"]*\"|\x27[^\x27]*\x27|[^\s;&|]+)")
def strip_heredocs(s):
    return _HEREDOC.sub(" HEREDOC ", s)
def strip_messages(s):
    return _MSG.sub(r"\1 MSG", s)
def unwrap(s, rounds=3):
    for _ in range(rounds):
        t = _SHC.sub(lambda m: " " + m.group(1)[1:-1] + " ", s)
        t = _EVAL.sub(lambda m: " " + m.group(1)[1:-1] + " ", t)
        if t == s:
            break
        s = t
    return s
def blank_quoted(s):
    return _QUOTED.sub(" Q ", s)
def strip_quotechars(s):
    return re.sub(r"[\x27\"]", "", s)
def normalize_ws(s):
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    s = re.sub(r"\\\n", " ", s)
    s = re.sub(r"\\(?=[^\n])", "", s)
    s = s.replace("\t", " ")
    s = _IFS.sub(" ", s)
    s = re.sub(r"[^\S\n]{2,}", " ", s)
    return s
def clean(s):
    return normalize_ws(unwrap(strip_messages(strip_heredocs(s))))
def has_substituted_git(s):
    return _SUBGIT.search(s) is not None
def hidden_cmdword(s, standin):
    return _HIDDEN.sub(lambda m: m.group(1) + m.group(2) + standin, s)
def substituted_args(s, binary, whole_for=()):
    # s: ONE segment with quoted CONTENT already blanked. True when `binary` is spelled
    # plainly and what it will be told to do cannot be read: (1) the SUBCOMMAND token -- the
    # word right after `binary`, skipping global flags and their values (`-C <path>`,
    # `-c <k>=<v>`, `--git-dir <path>`, `--work-tree <path>`) -- is itself a substitution or a
    # bare variable (`R=reset; git $R --hard`); or (2) the subcommand is one of `whole_for`
    # (the mutating ones the calling guard judges by their arguments: push, reset, commit...)
    # and any LATER token is a substitution (`git push origin $F`, `git commit $paths`).
    # A variable elsewhere in a READ-ONLY command is an honest read and passes:
    # `git diff HEAD -- $paths`, `git -C $W/repo status`, `git log --oneline -$n`.
    m = re.match(r"\s*(?:[A-Za-z_][A-Za-z0-9_]*=[^\s]*\s+)*" + re.escape(binary) + r"(?:\s|$)", s)
    if not m:
        return False
    toks = s[m.end():].split()
    i = 0
    while i < len(toks) and toks[i].startswith("-") and toks[i] != "-":
        if toks[i] in ("-C", "-c", "--git-dir", "--work-tree") and i + 1 < len(toks):
            i += 2
        else:
            i += 1
    if i >= len(toks):
        return False
    if _ANYSUB.search(toks[i]) is not None:
        return True
    return toks[i] in whole_for and _ANYSUB.search(" ".join(toks[i + 1:])) is not None
_ASSIGN_ONE = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)=(\"[^\"]*\"|\x27[^\x27]*\x27|\$\([^()]*\)|[\x60][^\x60]*[\x60]|[^\s\"\x27]*)")
_VARREF = re.compile(r"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))")
_LEADASSIGN = re.compile(r"\s*((?:[A-Za-z_][A-Za-z0-9_]*=\S*\s*)+)")
def resolve_assigned(s, assigned):
    # Replace every `$VAR` / `${VAR}` whose value was assigned EARLIER IN THE SAME COMMAND
    # (`B=feature; git push origin $B`) with that value; one that was never assigned, or whose
    # value only the shell can work out, is left as written. A hook cannot ask the shell.
    return _VARREF.sub(lambda m: assigned.get(m.group(1) or m.group(2), m.group(0)), s)
def note_assignments(seg, assigned):
    # Call once per segment, in order. A segment made ONLY of `NAME=value` words records those
    # values (a value that holds `$`, a backtick or `$(...)` after resolving is unreadable, so
    # the name is forgotten -- a stale earlier value must never stand in for it). Any other
    # segment that starts with NAME=... only sets a per-command variable: forget those names.
    m = _LEADASSIGN.match(seg)
    if not m:
        return
    pure = seg[m.end():].strip() == "" and _ASSIGN_ONE.sub("", m.group(1)).strip() == ""
    for a in _ASSIGN_ONE.finditer(m.group(1)):
        name, v = a.group(1), a.group(2)
        if not pure:
            assigned.pop(name, None); continue
        if v[:1] == "\x27":
            v = v[1:-1]
            assigned.pop(name, None) if ("$" in v or "\x60" in v) else assigned.__setitem__(name, v)
            continue
        if v[:1] == "\"":
            v = v[1:-1]
        v = resolve_assigned(v, assigned)
        if "$" in v or "\x60" in v:
            assigned.pop(name, None)
        else:
            assigned[name] = v
def wrapped_substitution(s):
    # s: the whole command, BEFORE unwrap (the wrapper must still be in the text).
    for m in _WRAPARG.finditer(s):
        a = m.group(1)
        if a[:1] in ("\"", "\x27"):
            a = a[1:-1]
        if re.match(r"\s*(?:\$\{?[A-Za-z_(0-9]|[\x60])", a):
            return True
    return False
def _mask(s):
    out = list(s)
    for m in _QUOTED.finditer(s):
        for i in range(m.start(), m.end()):
            out[i] = "x"
    return "".join(out)
def segments(s):
    mask = _mask(s)
    parts = []
    last = 0
    for m in _SEGRE.finditer(mask):
        parts.append(s[last:m.start()])
        last = m.end()
    parts.append(s[last:])
    return [p for p in parts if p.strip()]
def seg_bounds(s, pos):
    start, end = 0, len(s)
    for m in _SEGRE.finditer(s):
        if m.end() <= pos:
            start = m.end()
        elif m.start() >= pos:
            end = m.start()
            break
    return start, end
def override_at_start(s, word):
    return re.match(r"\s*(?:[A-Za-z_][A-Za-z0-9_]*=[^\s]*\s+)*" + re.escape(word) + r"=1(\s|$)", s) is not None
def override_here(s, word, pos):
    a, b = seg_bounds(s, pos)
    return override_at_start(s[a:b], word)
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
'

# guard_parsed NAME PARSER STATUS OUTPUT INPUT — the ONE check every guard runs after a
# $(python3 …) / $(jq …) substitution. A parser that is INSTALLED but broken (a python3 on
# PATH that exits 1, a jq that cannot run) makes the substitution an empty string, and an
# empty command matches no pattern: every guard then passed `git reset --hard`, `npm test`
# and `git commit --all` without a word. A guard that cannot read what it is being asked
# to judge must refuse, exactly as it does when the parser is missing altogether.
# Called as:  out="$( … )"; guard_parsed NAME python3 $? "$out" "$in"
# INPUT is the text that was fed in: pass "" when an empty result is a legitimate answer.
guard_parsed() {
  local name="$1" parser="$2" st="$3" out="$4" in="$5"
  if [ "$st" != 0 ] || { [ -n "$in" ] && [ -z "$out" ]; }; then
    echo "$name: REFUSED — the guard could not parse its input ($parser is installed but exited $st and returned nothing usable), so the command could not be read and nothing in it could be judged. Fail closed, not open. Check the parser: $parser --version" >&2
    exit 2
  fi
}

# guard_log_override NAME COMMAND PATTERN — record an honoured override. Exit status 0 only
# when the line was actually written: a missing override-ledger.sh, or a ledger path that
# cannot be written, must make the CALLER refuse the override (an override nobody can see
# is not an approved act — it is the same silent bypass the guard exists to stop).
guard_log_override() {
  local d="${BASH_SOURCE[0]%/*}" L
  [ "$d" = "${BASH_SOURCE[0]}" ] && d="."
  L="$d/override-ledger.sh"
  [ -f "$L" ] || return 1
  bash "$L" "$1" "$2" "$3" </dev/null
}

# guard_refuse_unrecorded GUARDNAME WORD — the one message every guard prints when an
# override could not be recorded.
guard_refuse_unrecorded() {
  echo "$1: REFUSED — the $2 override could not be recorded in the override ledger (hooks/override-ledger.sh is missing, or its ledger file cannot be written), so it is NOT honoured. Fix the ledger path (OVERRIDE_LEDGER, or ~/.claude/ledgers/), then run the command again." >&2
}

# ---- the multi-chat group's shared readers (hooks/state-check.conf) -------------------------
# Used by stop-state-check.sh and doorman.sh (the opt-in multi-chat group); the PreToolUse guards
# never call them. All three read the ONE conf file, hooks/state-check.conf, beside this file
# (or the path passed as the last argument). Tests: hooks/test-hooks.sh, "refresh 2026-09-29 (c2a)".

# The conf file beside this library.
_stc_conf_default() {
  local d="${BASH_SOURCE[0]%/*}"
  [ "$d" = "${BASH_SOURCE[0]}" ] && d="."
  printf '%s/state-check.conf' "$d"
}

# _hook_role_norm FOLDER-NAME — lower-case it, cut at the first digit, drop trailing hyphens, and
# keep only file-name-safe characters (the result names files under the state folder).
_hook_role_norm() {
  local b
  b=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  b="${b%%[0-9]*}"
  while [ "${b%-}" != "$b" ]; do b="${b%-}"; done
  printf '%s' "$b" | tr -c 'a-z0-9._-' '_'
}

# hook_role_from_cwd CWD [CONF] — the role of the chat opened in CWD, printed on stdout; exit 1 when
# the folder name leaves nothing. Read from the git TOPLEVEL folder's name (a chat opened in a
# subfolder of a seat's folder reads the same role as one at its top; not a git folder: CWD itself),
# lower-cased, cut at the first digit ("myapp-planner-3" -> "myapp-planner"), trailing hyphen
# dropped. Aliases come from state-check.conf lines "ROLE_ALIAS <name> <role>" (name compared after
# the same cut), so "ROLE_ALIAS myapp-planner planner" reads that folder as "planner".
hook_role_from_cwd() {
  local cwd="$1" conf="${2:-$(_stc_conf_default)}" top base role kw a b
  top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
  base="$(basename "${top:-$cwd}")"
  role=$(_hook_role_norm "$base")
  [ -n "$role" ] || return 1
  if [ -r "$conf" ]; then
    while read -r kw a b _ || [ -n "$kw" ]; do
      if [ "$kw" = ROLE_ALIAS ] && [ -n "$b" ] && [ "$(_hook_role_norm "$a")" = "$role" ]; then role="$b"; break; fi
    done < "$conf"
  fi
  printf '%s' "$role"
}

# _stc_unattended_file CONF — the unattended-run file path: "UNATTENDED_UNTIL <path>" in the conf
# (a leading ~/ or $HOME/ is expanded), default ~/.claude/state/unattended-until.
_stc_unattended_file() {
  local conf="$1" f="$HOME/.claude/state/unattended-until" kw v
  if [ -r "$conf" ]; then
    while read -r kw v _ || [ -n "$kw" ]; do
      [ "$kw" = UNATTENDED_UNTIL ] && [ -n "$v" ] && f="$v"
    done < "$conf"
  fi
  case "$f" in '~/'*) f="$HOME/${f#\~/}" ;; '$HOME/'*) f="$HOME/${f#\$HOME/}" ;; esac
  printf '%s' "$f"
}

# unattended_run_active [CONF] — exit 0 only while an unattended run is on: the file (see above)
# holds ONE line, an end time in epoch seconds, and that time is still in the future. A missing,
# empty, garbled or past file is a normal run (exit 1). It suppresses only the wrap-up; nothing
# here writes the file — a person or a script of your own does (see state-check.conf.example).
unattended_run_active() {
  local f end
  f=$(_stc_unattended_file "${1:-$(_stc_conf_default)}")
  [ -f "$f" ] || return 1
  end=$(head -1 "$f" 2>/dev/null)
  case "$end" in ''|*[!0-9]*) return 1 ;; esac
  [ "$(date +%s)" -lt "$((10#$end))" ]
}

# state_conf_read CWD [CONF] — read state-check.conf for the chat opened in CWD. Sets STC_TOP (git
# toplevel, else CWD), STC_BASE (its folder name), and the settings below, then returns 0 when a
# conf row matched this folder, 1 when there is no conf or no row matches (the group is then off
# for this chat). Rows: "<folder-glob> <role|auto> <floor-k>", matched against the toplevel folder's
# name AS WRITTEN and against its normalised role name (lower, cut at the first digit); the first
# match wins; "auto" reads the role with hook_role_from_cwd. Key lines, anywhere in the file:
#   STATE_FILE <path>        ({role} filled in)        default docs/state/{role}.md
#   WRAPUP_K <n>             wrap-up point, thousands  default 600 (illustrative)
#   WRAPUP_ROLES <r> <r>...  who is wrapped up ("*" = every role)   default: the dev seats
#   TELL_GROWTH_K <n>        helper-tell threshold, thousands       default 30 (illustrative)
#   TELL_EXEMPT_ROLES <r>... roles never given the helper tell      default none
#   UNATTENDED_UNTIL <path>  see unattended_run_active
#   ROLE_ALIAS <a> <b>       see hook_role_from_cwd
STC_DEV_ROLES="dev senior junior designer senior-dev junior-dev"
state_conf_read() {
  local cwd="$1" conf="${2:-$(_stc_conf_default)}" line kw pat r fk rest top norm
  STC_ROLE=""; STC_FLOOR_K=""; STC_STATE_FILE="docs/state/{role}.md"
  STC_WRAPUP_K=600; STC_WRAPUP_ROLES="$STC_DEV_ROLES"; STC_TELL_K=30; STC_TELL_EXEMPT=""
  top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
  STC_TOP="${top:-$cwd}"; STC_BASE="$(basename "$STC_TOP")"
  norm=$(_hook_role_norm "$STC_BASE")
  [ -r "$conf" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    read -r kw pat r fk rest <<<"$line"
    case "$kw" in
      STATE_FILE) STC_STATE_FILE="${line#STATE_FILE }"; continue ;;
      WRAPUP_K) case "$pat" in ''|*[!0-9]*) ;; *) STC_WRAPUP_K=$((10#$pat)) ;; esac; continue ;;
      TELL_GROWTH_K) case "$pat" in ''|*[!0-9]*) ;; *) STC_TELL_K=$((10#$pat)) ;; esac; continue ;;
      WRAPUP_ROLES) STC_WRAPUP_ROLES="${line#WRAPUP_ROLES}"; continue ;;
      TELL_EXEMPT_ROLES) STC_TELL_EXEMPT="${line#TELL_EXEMPT_ROLES}"; continue ;;
      UNATTENDED_UNTIL|ROLE_ALIAS) continue ;;
    esac
    [ -z "$STC_ROLE" ] || continue                       # first matching row wins; keys keep being read
    read -r pat r fk rest <<<"$line"
    case "$fk" in ''|*[!0-9]*) continue ;; esac          # a non-numeric floor: skip this row, not the file
    [ -n "$pat" ] && [ -n "$r" ] || continue
    if [ "$STC_BASE" = "$pat" ] || { case "$STC_BASE" in $pat) true ;; *) false ;; esac; } \
       || { [ -n "$norm" ] && case "$norm" in $pat) true ;; *) false ;; esac; }; then
      if [ "$r" = auto ]; then r=$(hook_role_from_cwd "$cwd" "$conf") || continue; fi
      STC_ROLE="$r"; STC_FLOOR_K="$fk"
    fi
  done < "$conf"
  [ -n "$STC_ROLE" ]
}

# hook_state_role CWD TRANSCRIPT [PROMPT] — the role lookup for a project whose chats SHARE one folder,
# where the folder name cannot name the role. A repo opts in by COMMITTING `.claude/state-roles.tsv` at its
# git top (TRACKED: git ls-files must list it): one line per role, `<pattern><TAB><state file path from the top>` ('#' lines and blank lines
# skipped). No state-check.conf line is needed; callers run this only when state_conf_read found no row for
# the folder. The chat's identity is the session's title (the last {"type":"custom-title"} line of the
# transcript), else the text of its first user message (system-reminder blocks stripped, first 300
# characters; an isMeta line and a slash-command wrapper, text starting <command- or <local-command-, are
# skipped), else the optional PROMPT (the prompt hook's text: a chat's very first prompt, before the
# transcript holds anything). The first pattern found in the identity (case-insensitive, literal substring)
# wins. Prints "<pattern><TAB><state file>" and returns 0; returns 1, printing nothing, for no git repo, no
# mapping file, no identity, no match, no jq, or a path that is absolute or holds "..". Needs jq.
# Tests: hooks/test-hooks.sh, "guard port 2026-10-10 (C1)".
hook_state_role() {
  local cwd="$1" tp="$2" prompt="$3" top map pat path ident lid lpat
  command -v jq >/dev/null 2>&1 || return 1
  [ -n "$cwd" ] && { { [ -n "$tp" ] && [ -r "$tp" ]; } || [ -n "$prompt" ]; } || return 1
  top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$top" ] || return 1
  map="$top/.claude/state-roles.tsv"
  [ -f "$map" ] && [ -r "$map" ] || return 1
  git -C "$top" ls-files --error-unmatch -- .claude/state-roles.tsv >/dev/null 2>&1 || return 1   # tracked only: an untracked or ignored file opts nobody in
  ident=""
  [ -n "$tp" ] && [ -r "$tp" ] && ident="$(/usr/bin/grep -a '"type"[[:space:]]*:[[:space:]]*"custom-title"' "$tp" 2>/dev/null | /usr/bin/tail -1 | jq -r '.customTitle // empty' 2>/dev/null)"
  if [ -z "$ident" ] && [ -n "$tp" ] && [ -r "$tp" ]; then
    ident="$(/usr/bin/grep -a -m 40 '"type"[[:space:]]*:[[:space:]]*"user"' "$tp" 2>/dev/null | jq -R -r '
      fromjson? | select(.isSidechain != true and .isMeta != true and (.message.role // "") == "user")
      | .message.content
      | (if type == "string" then . elif type == "array" then (map(select(.type == "text") | .text) | join(" ")) else "" end)
      | gsub("<system-reminder>.*?</system-reminder>"; ""; "s") | gsub("^\\s+|\\s+$"; "") | select(length > 0)
      | select(test("^<(local-)?command-") | not)
      | .[0:300] | gsub("\\s+"; " ")' 2>/dev/null | head -1)"
  fi
  if [ -z "$ident" ] && [ -n "$prompt" ]; then
    ident="$(printf '%s' "$prompt" | jq -Rrs 'gsub("<system-reminder>.*?</system-reminder>"; ""; "s") | gsub("^\\s+|\\s+$"; "") | .[0:300] | gsub("\\s+"; " ")' 2>/dev/null)"
  fi
  [ -n "$ident" ] || return 1
  lid="$(printf '%s' "$ident" | tr 'A-Z' 'a-z')"
  while IFS=$'\t' read -r pat path || [ -n "$pat" ]; do
    path="${path%$'\r'}"
    case "$pat" in ''|'#'*) continue ;; esac
    case "$path" in ''|/*|*..*) continue ;; esac
    lpat="$(printf '%s' "$pat" | tr 'A-Z' 'a-z')"
    case "$lid" in *"$lpat"*) printf '%s\t%s' "$pat" "$path"; return 0 ;; esac
  done < "$map"
  return 1
}

# ---- the context reader shared by doorman.sh and stop-state-check.sh -------------------------
# stc_ctx_read TRANSCRIPT — the chat's context size, read ONCE with a growing tail window (the last
# 256 KB, then 8 MB, then the whole file; it stops at the first window that holds the newest usage
# line or a compact boundary), so a long chat costs milliseconds, not seconds, per prompt. Sets
#   STC_CTX_TOT  input + cache-creation + cache-read tokens of the newest usage line (0 = none found)
#   STC_CTX_ULN  that line's number, and STC_CTX_CLN the newest compact boundary's (window-relative,
#                comparable with each other; 0 = none)
# A usage line whose counters are ALL zero (what an API error such as "overloaded" writes) is not a
# measurement and is skipped, so an error answer at the end of a turn never reads as "0 tokens". Only the
# newest 64 usage lines are examined. The same rule and windows as clock-in-context.sh, which keeps its
# own copy. Tests: hooks/test-hooks.sh "attack fixes (3)" (M1, M11).
_stc_ctx_window() {   # $1 = transcript, $2 = bytes of the file's end to read (0 = the whole file)
  { if [ "$2" -gt 0 ]; then /usr/bin/tail -c "$2" "$1" 2>/dev/null | /usr/bin/sed 1d; else /bin/cat "$1" 2>/dev/null; fi; } \
    | /usr/bin/grep -E 'cache_read_input_tokens|"subtype"[[:space:]]*:[[:space:]]*"compact_boundary"' 2>/dev/null | /usr/bin/awk '
    function lastnum(s, key,   re, r, v) { re="\"" key "\"[ \t]*:[ \t]*[0-9]+"; v=0
      while (match(s, re)) { r=substr(s,RSTART,RLENGTH); sub(/.*:[ \t]*/,"",r); v=r+0; s=substr(s,RSTART+RLENGTH) }
      return v }
    { l=$0; ln=NR
      if (index(l,"compact_boundary") && l ~ /"type"[ \t]*:[ \t]*"system"/ && l ~ /"subtype"[ \t]*:[ \t]*"compact_boundary"/) cln=ln
      if (index(l,"cache_read_input_tokens") && l ~ /"type"[ \t]*:[ \t]*"assistant"/) { n++; ring[n%64]=l; rln[n%64]=ln } }
    END { for (k=n; k>0 && k>n-64; k--) { l=ring[k%64]
            t=lastnum(l,"input_tokens")+lastnum(l,"cache_creation_input_tokens")+lastnum(l,"cache_read_input_tokens")
            if (t>0) { tot=t; uln=rln[k%64]; break } }
          printf "%d %d %d\n", tot+0, uln+0, cln+0 }' 2>/dev/null
}
stc_ctx_read() {
  local _tp="$1" _size _w _t _u _c
  STC_CTX_TOT=0; STC_CTX_ULN=0; STC_CTX_CLN=0
  [ -n "$_tp" ] && [ -r "$_tp" ] || return 1
  _size=$(/usr/bin/wc -c < "$_tp" 2>/dev/null | tr -d ' ')
  for _w in 262144 8388608 0; do
    if [ "$_w" -gt 0 ] && [ "${_size:-0}" -le "$_w" ]; then _w=0; fi
    read -r _t _u _c <<<"$(_stc_ctx_window "$_tp" "$_w")"
    case "$_t$_u$_c" in ''|*[!0-9]*) _t=0; _u=0; _c=0 ;; esac
    STC_CTX_TOT=$_t; STC_CTX_ULN=$_u; STC_CTX_CLN=$_c
    [ "$_w" = 0 ] && break
    { [ "$_t" -gt 0 ] || [ "$_c" -gt 0 ]; } && break
  done
  return 0
}

# ---- "what did this turn write or commit": the ONE transcript reader of the opt-in chat hooks ----
# Used by stop-state-check.sh (shared-folder chats: did THIS chat change the repo?) and chapter-note.sh
# (is this the session's first change, did it push?). turn_scan TRANSCRIPT [CHAPTER_TOOL] reads only the
# CURRENT turn: the file's last 1 MB, then 8 MB, then 64 MB, then the whole file, stopping at the first
# window that holds the turn's start. The turn starts at the last TYPED prompt: a user line whose "origin"
# kind is human or peer; a user line without an "origin" counts when it is not a tool result, not
# isMeta, and its text does not start with <task-notification, <command- or <local-command- (so a
# mid-turn task notification, a skill body or a slash-command wrapper never moves the start). Sets
#   TS_PL      transcript line number of that prompt (0 = none found: callers do nothing)
#   TS_MC      the turn's last chapter-tool call (a tool_use whose name ENDS with CHAPTER_TOOL), else 0
#   TS_PU      the turn's last counted `git push` (not --dry-run/-n/--help; not one whose result is an
#              error, says "rejected]" with no ref updated, or says "Everything up-to-date"), else 0
#   TS_ED      the turn's last change: Edit/Write/MultiEdit/NotebookEdit, a Bash `sed -i`, tee, a > or >>
#              redirect to a file (not /dev/*), cp, mv, git apply, an interpreter -c/-e body that writes,
#              or a git commit/merge/cherry-pick/revert; else 0
#   TS_ANY     1 when a chapter-tool call exists anywhere in the part read
#   TS_COMMIT  the turn's last git commit/merge/cherry-pick/revert, else 0
#   TS_UNREAD  1 when a write was seen whose target could not be read (sed -i, git apply, a quoted or
#              variable target, an interpreter body): the caller counts it as this chat's
#   TS_PATHS   the file paths the turn wrote, one per line, as spelled (absolute or relative)
# A command counts only at a command start: `git` after ; & | ( && ||, after if/then/elif/else/do/while/
# until, after `command`, inside bash|sh|zsh -c "...", with global options (-C dir, -c k=v, --no-pager...)
# before the verb. A word inside quotes, a heredoc body or a commit message never counts. Not covered:
# eval, xargs, a function wrapper, a variable as the command, env/time/nice prefixes, { ...; } groups.
# Tests: hooks/test-hooks.sh "guard port 2026-10-10 (F3b)" and (C3).
TURN_AWK='
function endswith(s, t) { return length(s) >= length(t) && substr(s, length(s) - length(t) + 1) == t }
function unesc(v) {
  gsub(/\\\\/, "\001", v); gsub(/\\n/, "\n", v); gsub(/\\t/, "\t", v); gsub(/\\r/, "", v); gsub(/\\"/, "\"", v)
  return v
}
function nohd(t,   n, a, i, o, tag, m, pre) {   # drop heredoc bodies
  n = split(t, a, "\n"); o = ""; tag = ""
  for (i = 1; i <= n; i++) {
    if (tag != "") { if (a[i] ~ ("^[ \t]*" tag "[ \t]*$")) tag = ""; continue }
    o = o a[i] "\n"
    if (match(a[i], /<<-?[ \t]*["\047\\]?[A-Za-z_][A-Za-z0-9_]*/)) {
      pre = (RSTART > 1) ? substr(a[i], RSTART - 1, 1) : ""
      if (pre != "<") { m = substr(a[i], RSTART, RLENGTH); sub(/^<<-?[ \t]*["\047\\]?/, "", m); tag = m }
    }
  }
  return o
}
function gitcmd(t, verb, skipdry,   re, c, seg, k) {   # is there a `git ... <verb>` at a command start?
  re = "(^|[;&|(])[[:space:]]*(" KW "[[:space:]]+)*(command[[:space:]]+(-[A-Za-z]+[[:space:]]+)*)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(/[^[:space:]]*/)?git[[:space:]]+(" OPT "[[:space:]]+)*" verb
  while (match(t, re)) {
    c = substr(t, RSTART + RLENGTH, 1); seg = substr(t, RSTART + RLENGTH + 1); t = seg
    if (c ~ /[A-Za-z0-9_-]/) continue
    if (skipdry) {
      k = match(seg, /[;&|]/); if (k > 0) seg = substr(seg, 1, k - 1)
      seg = c seg
      if (seg ~ /(^|[[:space:]])(--dry-run|--help)([[:space:]=]|$)/ || seg ~ /(^|[[:space:]])-[A-Za-z]*n[A-Za-z]*([[:space:]]|$)/) continue
    }
    return 1
  }
  return 0
}
# one left-to-right quote strip: a double-quoted string may hold a backslash-escaped character (the
# backslash is \001 by now), so an escaped quote does not end it; a single-quoted one holds none
function stripq(t) { gsub(/"([^"\001]|\001.)*"|\047[^\047]*\047/, "Q", t); return t }
# `bash|sh|zsh [-opts] -c "body"` at a command start runs its body: the body replaces the wrapper
function unwrap(t,   re, n, b, pre, post) {
  re = "(^|[;&|(\n])[[:space:]]*(/[^[:space:]]*/)?(bash|sh|zsh)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*c[[:space:]]+(\"([^\"\001]|\001.)*\"|\047[^\047]*\047)"
  for (n = 0; n < 6 && match(t, re); n++) {
    b = substr(t, RSTART, RLENGTH); pre = substr(t, 1, RSTART - 1); post = substr(t, RSTART + RLENGTH)
    sub(/^[^"\047]*[ \t]-[A-Za-z]*c[ \t]+/, "", b)
    if (substr(b, 1, 1) == "\"") { b = substr(b, 2, length(b) - 2); gsub(/\001"/, "\"", b); gsub(/\001\$/, "$", b) } else b = substr(b, 2, length(b) - 2)
    t = pre ";" b ";" post
  }
  return t
}
function addpath(p) {
  if (p ~ /^\/dev\//) return
  if (p == "Q" || p ~ /[$`*?]/) { un = 1; return }
  if (wn < 500) wp[++wn] = p
}
# does this command write? (u = the command with quoted text blanked, wrappers brought out); records the
# targets it can read in wp[], sets un when one cannot be read, returns 1 for a write
function bashw(t, raw,   u, rest, w, hit, n, a, i, k, seg, st, opt, lastw) {
  u = stripq(t); gsub(/\001/, "_", u); gsub(/\n/, ";", u)
  gsub(/[0-9&]?>>?[ \t]*\/dev\/[A-Za-z0-9_\/.-]*/, "", u)
  hit = 0
  rest = u
  while (match(rest, /(^|[^0-9&>])>>?[ \t]*[^ \t;&|<>()]+/)) {
    w = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
    sub(/^[^>]*>>?[ \t]*/, "", w); hit = 1; addpath(w)
  }
  rest = u
  while (match(rest, /(^|[[:space:];&|(])tee([[:space:]]|$)/)) {
    seg = substr(rest, RSTART + RLENGTH); rest = seg; hit = 1
    st = match(seg, /[;&|]/); if (st > 0) seg = substr(seg, 1, st - 1)
    n = split(seg, a, /[ \t]+/)
    for (i = 1; i <= n; i++) if (a[i] != "" && a[i] !~ /^-/) addpath(a[i])
  }
  rest = u
  while (match(rest, "(^|[;&|(])[[:space:]]*(" KW "[[:space:]]+)*(/[^[:space:]]*/)?(cp|mv)[[:space:]]+[^;&|]*")) {
    seg = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH); hit = 1
    opt = (seg ~ /(^|[[:space:]])(-[A-Za-z]*[tT]|--target-directory|--no-target-directory)([[:space:]=]|$)/)
    n = split(seg, a, /[ \t]+/); k = 0; lastw = ""
    for (i = 1; i <= n; i++) if (a[i] ~ /^(.*\/)?(cp|mv)$/) { k = i; break }
    for (i = k + 1; i <= n; i++) if (a[i] != "" && a[i] !~ /^-/) { lastw = a[i]; if (a[k] ~ /mv$/) addpath(a[i]) }
    if (opt) un = 1
    else if (lastw != "") addpath(lastw)
  }
  if (u ~ /(^|[[:space:];&|(])sed[[:space:]]+([^;&|]*[[:space:]])?(-[A-Za-z]*i|--in-place)/) { hit = 1; un = 1 }
  if (u ~ /(^|[[:space:];&|(])perl[[:space:]]+([^;&|]*[[:space:]])?-[A-Za-z]*i/) { hit = 1; un = 1 }
  if (gitcmd(u, "apply", 0)) { hit = 1; un = 1 }
  if (raw ~ /(^|[;&|(\n])[[:space:]]*(\/[^[:space:]]*\/)?(python[0-9.]*|node|perl|ruby)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*[ceE][[:space:]]/ && raw ~ /(open\(|write|shutil|os\.(remove|rename|replace)|unlink|truncate|rmSync|renameSync)/) { hit = 1; un = 1 }
  return hit
}
# is this user line a typed prompt? (see the header)
function isprompt(l) {
  if (l ~ /"isMeta"[ \t]*:[ \t]*true/) return 0
  if (index(l, "\"origin\"")) return (l ~ /"origin"[ \t]*:[ \t]*\{[ \t]*"kind"[ \t]*:[ \t]*"(human|peer)"/)
  if (index(l, "\"tool_result\"")) return 0
  if (l ~ /"(content|text)"[ \t]*:[ \t]*"([ \t]|\\n)*<(task-notification|command-|local-command-)/) return 0
  return 1
}
# did a push result show a ref that went? (an updated ref, a new branch or tag, a deleted ref)
function went(l) {
  return (l ~ /[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]+\.\.\.?[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]+[ \t]+[^ \t]+[ \t]+->/ || l ~ /\[new (branch|tag)\]/ || l ~ /- \[deleted\]/)
}
BEGIN {
  Q1 = "\"[^\"]*\""; Q2 = "\047[^\047]*\047"; ARG = "(" Q1 "|" Q2 "|[^[:space:]]+)"
  OPT = "(-C[[:space:]]+" ARG "|-c[[:space:]]+" ARG "|-[Pp]|--[A-Za-z-]+(=" ARG ")?)"
  KW = "(if|then|elif|else|do|while|until)"
  CV = "(commit|merge|cherry-pick|revert)"
}
{
  line = $0
  if (part && NR == 1) next   # a window cut from the middle of the file starts inside a line
  if (index(line, "\"user\"") && line ~ /"type"[ \t]*:[ \t]*"user"/ && isprompt(line)) { pl = NR; mc = 0; ed = 0; cm = 0; un = 0; wn = 0; pn = 0; delete wp; delete pushes; delete bad; delete seen; cur = ""; curpush = 0; next }
  if (index(line, "\"tool_result\"")) {
    if (pl && (line ~ /"is_error"[ \t]*:[ \t]*true/ || index(line, "rejected]") || index(line, "Everything up-to-date")) && !went(line)) {
      tid = ""; if (match(line, /"tool_use_id"[ \t]*:[ \t]*"[^"]*"/)) { tid = substr(line, RSTART, RLENGTH); sub(/^"tool_use_id"[ \t]*:[ \t]*"/, "", tid); sub(/"$/, "", tid) }
      if (tid in pushes) bad[pushes[tid]] = 1
      else if (!(tid in seen) && curpush) bad[cur] = 1
    }
    next
  }
  if (!index(line, "\"tool_use\"")) next
  if (!match(line, /"type"[ \t]*:[ \t]*"tool_use"/)) next
  s = substr(line, RSTART); nm = ""; id = ""
  if (match(s, /"name"[ \t]*:[ \t]*"[^"]*"/)) { nm = substr(s, RSTART, RLENGTH); sub(/^"name"[ \t]*:[ \t]*"/, "", nm); sub(/"$/, "", nm) }
  if (match(s, /"id"[ \t]*:[ \t]*"[^"]*"/)) { id = substr(s, RSTART, RLENGTH); sub(/^"id"[ \t]*:[ \t]*"/, "", id); sub(/"$/, "", id) }
  if (id != "") seen[id] = 1
  cur = NR; curpush = 0
  if (endswith(nm, CT)) { any = 1; if (pl) mc = NR; next }
  if (!pl) next
  if (nm == "Edit" || nm == "Write" || nm == "MultiEdit" || nm == "NotebookEdit") {
    ed = NR
    if (match(s, /"(file_path|notebook_path)"[ \t]*:[ \t]*"([^"\\]|\\.)*"/)) {
      w = substr(s, RSTART, RLENGTH); sub(/^"[a-z_]*"[ \t]*:[ \t]*"/, "", w); sub(/"$/, "", w); gsub(/\\\//, "/", w); gsub(/\\\\/, "\\", w); addpath(w)
    } else un = 1
    next
  }
  if (nm == "Bash") {
    if (!match(s, /"command"[ \t]*:[ \t]*"([^"\\]|\\.)*"/)) next
    cmd = substr(s, RSTART, RLENGTH); sub(/^"command"[ \t]*:[ \t]*"/, "", cmd); sub(/"$/, "", cmd)
    cmd = nohd(unesc(cmd)); gsub(/\001[ \t]*\n/, " ", cmd)
    unw = unwrap(cmd)
    if (bashw(unw, cmd)) ed = NR
    cmd = stripq(unw); gsub(/\001/, "_", cmd); gsub(/\n/, ";", cmd)
    if (gitcmd(cmd, CV, 0)) { ed = NR; cm = NR }
    if (gitcmd(cmd, "push", 1)) { pn++; pl_at[pn] = NR; curpush = 1; if (id != "") pushes[id] = NR }
  }
}
END {
  pu = 0
  for (k = pn; k >= 1; k--) if (!(pl_at[k] in bad)) { pu = pl_at[k]; break }
  off = total - NR   # a window numbers its lines from 1: shift to whole-file numbers so the record keys never move
  print (pl ? pl + off : 0), (mc ? mc + off : 0), (pu ? pu + off : 0), (ed ? ed + off : 0), any + 0, (cm ? cm + off : 0), un + 0
  for (k = 1; k <= wn; k++) print "P" wp[k]
}'
turn_scan() {
  local _tp="$1" _ct="${2:-}" _size _total _w _out="" _l1
  TS_PL=0; TS_MC=0; TS_PU=0; TS_ED=0; TS_ANY=0; TS_COMMIT=0; TS_UNREAD=0; TS_PATHS=""
  [ -n "$_tp" ] && [ -r "$_tp" ] || return 1
  case "$_ct" in ''|*[!A-Za-z0-9_.-]*) _ct="-no-chapter-tool-" ;; esac
  _size=$(/usr/bin/wc -c < "$_tp" 2>/dev/null | tr -d ' '); _total=$(/usr/bin/wc -l < "$_tp" 2>/dev/null | tr -d ' ')
  [ -n "$(/usr/bin/tail -c 1 "$_tp" 2>/dev/null)" ] && _total=$((${_total:-0} + 1))
  for _w in 1048576 8388608 67108864 0; do
    if [ "$_w" = 0 ] || [ "${_size:-0}" -le "$_w" ]; then
      _out=$(LC_ALL=C /usr/bin/awk -v part=0 -v total="${_total:-0}" -v CT="$_ct" "$TURN_AWK" < "$_tp" 2>/dev/null); break
    fi
    _out=$(/usr/bin/tail -c "$_w" "$_tp" 2>/dev/null | LC_ALL=C /usr/bin/awk -v part=1 -v total="${_total:-0}" -v CT="$_ct" "$TURN_AWK" 2>/dev/null)
    _l1="${_out%%$'\n'*}"
    [ "${_l1%% *}" != 0 ] && [ -n "$_out" ] && break
  done
  _l1="${_out%%$'\n'*}"
  read -r TS_PL TS_MC TS_PU TS_ED TS_ANY TS_COMMIT TS_UNREAD <<< "$_l1"
  case "$TS_PL$TS_MC$TS_PU$TS_ED$TS_ANY$TS_COMMIT$TS_UNREAD" in ''|*[!0-9]*) TS_PL=0; TS_MC=0; TS_PU=0; TS_ED=0; TS_ANY=0; TS_COMMIT=0; TS_UNREAD=0; return 1 ;; esac
  case "$_out" in *$'\n'*) TS_PATHS=$(printf '%s\n' "${_out#*$'\n'}" | /usr/bin/sed -n 's/^P//p') ;; esac
  return 0
}
