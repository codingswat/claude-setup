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
# A guard that cannot find this file REFUSES the command (fail closed) — never carries on
# with un-normalised text, which would silently reopen every bypass above.
# Tests: hooks/test-hooks.sh (sections 28 and 30; `refresh 2026-09-29 (a)` for A01 and A85).

# guard_resolve_python — the python3 every guard runs. PREFER /usr/bin/python3, else the
# first python3 on PATH: a broken python3 earlier on PATH (a conda or pyenv shim that exits
# non-zero) then cannot make every Bash call fail closed. On a host with no /usr/bin/python3
# (some Linux images) the PATH one is used, as before. GUARD_PYTHON_PREFERRED is a TEST SEAM
# (the suite points it at a missing file to drive the PATH fallback and the failing-parser
# cases); leave it unset in real use. Each guard checks the result is executable before use.
guard_resolve_python() {
  local p="${GUARD_PYTHON_PREFERRED:-/usr/bin/python3}"
  if [ -x "$p" ]; then printf '%s' "$p"; else command -v python3 2>/dev/null; fi
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
