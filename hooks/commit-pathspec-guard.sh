#!/bin/bash
# PreToolUse hook on Bash. In a checkout that might already hold other staged work — a
# second terminal, another agent, an interrupted task — a bare `git commit` with no path
# arguments sweeps in EVERYTHING currently staged, not just what was meant to go in.
# Refuses:
#   - `git commit` with no path arguments while the index already holds staged files
#   - `git commit -a` / `--all` (stages and commits every tracked change, staged or not)
#   - `git commit -i <paths>` / `--include` while the index holds staged files that are not among
#     the named paths (`-i` commits everything already staged PLUS the paths: the same sweep)
#   - whole-tree pathspecs: `git commit .` / `./` / `:/` / `*` / `..` / `/`, and the repo
#     root named by its own path — every one of them is the same sweep as `-a` wearing a
#     different hat
#   - a commit whose `git` is produced by substitution — `` `echo git` commit ``,
#     `$(which git) commit`: no pattern can see a binary that does not exist until the
#     shell runs it, so the command is refused and a plain `git commit <paths>` asked for
#   - the mirror image: a plain `git` whose ARGUMENT is a substitution — `C=commit; git $C
#     -a -m x`, `git commit $paths -m x`. The arguments are what this guard reads, so it
#     refuses rather than judge text it does not have. A substitution inside a quoted
#     message or value (`-m "$msg"`, `--author="$me"`) is blanked first and still passes
#   - a commit whose FOLDER cannot be worked out: `cd "$HOME/x" && git commit NOTES.md`
#     (only the shell can expand that target), or a path that is no git repository. The
#     whole guard reads that folder's index, so an unknown folder means an unjudged commit
#   - `--pathspec-from-file=<list>` whose list cannot be read (missing, or `-` for stdin).
#     A list holding a NUL byte is read as the NUL-separated list it can only be (that
#     byte used to reach os.path and crash this guard open, which passed the commit).
#     A readable list is EXPANDED, so the paths inside it face the same whole-tree and
#     provenance checks as paths typed on the command line — otherwise a one-line file
#     saying `.` was a sweep in disguise
#   - (2) a named pathspec commit that WOULD carry a shared channel file — see
#     hooks/provenance.py — holding a change this session did not make
# Passes: any commit that names its own paths (and whose channel files, if any, are all
# this session's own recorded work), and a bare `git commit` when the index is empty
# (there is nothing else it could sweep in).
# Also passes, unconditionally: a commit run inside a linked git worktree (`git worktree
# add`). A linked worktree has its own index, separate from the main checkout and every
# other worktree, so nothing staged there can belong to another session — the whole
# concern both checks exist for cannot arise. Judged per command segment, on the repo
# that segment actually runs in (cwd, `cd`, or `git -C`).
# HOW THE COMMAND IS READ (hooks/guard-lib.sh, shared with the other Bash guards): commit
# messages and heredoc bodies are dropped, so a message that merely MENTIONS "-a" or "."
# is not refused; `bash|sh|zsh -c "…"` and `eval "…"` are unwrapped first, so
# `sh -c "git commit -a -m sweep"` is judged as the sweep it is rather than as an
# unreadable string; tabs, escaped newlines and stray backslashes become plain spaces.
# Deliberate whole-index or reconciled commit: start the COMMIT'S OWN segment with
# `SWEEP=1 ` — `echo x && SWEEP=1 git commit -m x` carries the index deliberately, while
# `git commit -a -m x && SWEEP=1 true` approves only the `true` and the sweep is still
# refused. Judged on text with quoted strings removed. Every use is written to hooks/override-ledger.sh with the refusal it bypassed;
# if that line CANNOT be written (no ledger script, unwritable path) the override is
# REFUSED, not honoured.
# The folder is worked out where the shell would: `cd ~/x`, `cd $W` / `git -C $W` with `W=...`
# set earlier on the same line, and plain paths. A folder still holding `$` (say `$HOME`, or a
# variable never set on the line) is the "cannot be worked out" refusal above.
# A short flag with its value attached (`-Cabc`, `-mabc`) is not the `-a` cluster; `-am` is.
# A variable elsewhere in a read-only git line (`git diff HEAD -- $paths`) is not a commit.
# jq, python3 (guard-lib.sh's GUARD_PY: /usr/bin/python3, else the first on PATH) and hooks/guard-lib.sh all parse the command below; if any is missing this
# guard cannot read what it's being asked to run, so it refuses rather than silently
# letting an unparsed (and therefore unmatched) command through. Hook input that is empty
# or is not valid JSON is refused for the same reason — the one exception is a well-formed
# call for a tool other than Bash, which carries no command to judge. Fail closed, like
# git-hooks/pre-commit.
# Tests: hooks/test-hooks.sh (sections 3, 3b, 23, 28, 29; `refresh 2026-09-29 (a)` for A01, A11, A12, A85).
GUARD_LIB="$(dirname "$0")/guard-lib.sh"
if [ ! -r "$GUARD_LIB" ]; then
  echo "commit-pathspec-guard: REFUSED — hooks/guard-lib.sh is missing next to this hook, so the command cannot be normalised before matching (fail closed, not open). Reinstall the hooks (install.sh copies hooks/*.sh)." >&2
  exit 2
fi
. "$GUARD_LIB"
missing=""
command -v jq >/dev/null 2>&1 || missing="jq"
[ -n "$GUARD_PY" ] && [ -x "$GUARD_PY" ] || missing="${missing:+$missing and }python3"
if [ -n "$missing" ]; then
  echo "commit-pathspec-guard: REFUSED — $missing not found, so this guard cannot parse the command (fail closed, not open)." >&2
  exit 2
fi
input="$(cat)"
if [ -z "$input" ] || ! printf '%s' "$input" | jq -e . >/dev/null 2>&1; then
  echo "commit-pathspec-guard: REFUSED — the hook input is empty or is not valid JSON, so the command cannot be read (fail closed, not open)." >&2
  exit 2
fi
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
[ -n "$tool" ] && [ "$tool" != "Bash" ] && exit 0   # a Write/Edit call carries no command
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
if [ -z "$cmd" ]; then
  echo "commit-pathspec-guard: REFUSED — a Bash tool call with no readable command (fail closed, not open)." >&2
  exit 2
fi
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"; [ -z "$cwd" ] && cwd="$PWD"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty')"; [ -z "$sid" ] && sid="nosession"
verdict="$(printf '%s' "$cmd" | CWD="$cwd" HOOKDIR="$(dirname "$0")" "$GUARD_PY" -c "$GUARD_PY_COMMON"'
import subprocess, shlex
raw = sys.stdin.read()
s = clean(raw)
unq = blank_quoted(s)
# The override is read per SEGMENT (below): SWEEP=1 waives the refusal of the segment it
# stands at the start of, never of a segment somewhere else on the same line.
cur_sweep = False
commit_sweep = False
def log_override(reason):
    ledger = os.path.join(os.environ.get("HOOKDIR", ""), "override-ledger.sh")
    if not os.path.isfile(ledger):
        return 1
    try:
        return subprocess.run(["bash", ledger, "SWEEP", raw, reason], timeout=5).returncode
    except Exception:
        return 1
def finish(v):
    # With SWEEP=1 the refusal is waived — but only once the ledger line is on disk.
    if cur_sweep:
        if log_override(v) != 0:
            print("REFUSE_LEDGER")
        else:
            print("OK")
        sys.exit(0)
    print(v); sys.exit(0)
VALFLAGS={"-m","--message","-F","--file","--author","--date","-C","-c","--reuse-message","--reedit-message","--fixup","--squash","--trailer","--cleanup","-t","--template","--pathspec-from-file"}
WHOLE_TREE={".", "./", ":/", ":(top)", "*", "..", "../", "/"}
repo=os.environ.get("CWD") or os.getcwd()
def toks_of(seg):
    try: return shlex.split(seg, posix=True)
    except ValueError: return seg.split()
def git_out(r, *args):
    try:
        return subprocess.run(["git","-C",r]+list(args),capture_output=True,text=True,timeout=5).stdout
    except Exception:
        return ""
def linked(r):
    # A linked worktree has its own git-dir under <main>/.git/worktrees/<name>; the
    # main checkout (or a plain, non-worktree repo) has git-dir == common-dir.
    o=git_out(r,"rev-parse","--path-format=absolute","--git-dir","--git-common-dir").splitlines()
    return len(o)>=2 and o[0].strip()!="" and os.path.realpath(o[0].strip())!=os.path.realpath(o[1].strip())
def toplevel(r):
    t=git_out(r,"rev-parse","--show-toplevel").strip()
    return os.path.realpath(t) if t else None
UNRESOLVABLE=("$", "`", "*", "?")
# A12: a folder written with `~`, or through a variable set EARLIER ON THE SAME LINE, is worked
# out here (a hook cannot ask the shell); anything still holding `$`, a backtick or a glob
# after that -- `$HOME`, a variable never set on the line -- stays unreadable (None).
assigned = {}
_VAR = re.compile(r"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))")
def resolve_dir(t):
    if t == "~" or t.startswith("~/"):
        t = os.path.expanduser(t)
    t = _VAR.sub(lambda m: assigned.get(m.group(1) or m.group(2), m.group(0)), t)
    if any(ch in t for ch in UNRESOLVABLE):
        return None
    return t
def join_dir(base, t):
    r = resolve_dir(t)
    if r is None: return None
    if os.path.isabs(r): return r
    return os.path.normpath(os.path.join(base, r)) if base else None
def short_flag_has(a, letter):
    # the same cluster walk as short_flag_sweeps, for any one letter (`-im` holds -i).
    if not a.startswith("-") or a.startswith("--"):
        return False
    for ch in a[1:]:
        if ch == letter: return True
        if ch in "mFCctSu": return False
    return False
def short_flag_sweeps(a):
    # `-am` is a cluster holding -a; `-Cabc`, `-mabc`, `-Fa.txt` are a value-taking flag with
    # its value attached, so the a inside is not a flag. Scan left to right: the first
    # value-taking letter ends the cluster.
    if not a.startswith("-") or a.startswith("--"):
        return False
    for ch in a[1:]:
        if ch == "a": return True
        if ch in "mFCctSu": return False
    return False
def read_pathspec_file(where, name, nul):
    """The paths inside a --pathspec-from-file list, or None when it cannot be read —
    a list this guard cannot open is a commit whose contents it cannot judge."""
    if name == "-" or not where:
        return None                       # the list comes from stdin: unreadable here
    fp = name if os.path.isabs(name) else os.path.join(where, name)
    try:
        with open(fp, "rb") as fh:
            data = fh.read()
    except Exception:
        return None
    # A NUL inside the list can only be a NUL-separated list (the
    # --pathspec-file-nul format that git itself writes): read as lines it leaves a NUL
    # inside a path, and a path with a NUL raises out of os.path — which used to kill
    # this guard and let the commit through unjudged.
    if b"\0" in data:
        nul = True
    sep = b"\0" if nul else b"\n"
    return [x.decode("utf-8", "replace").replace("\0", "").strip() for x in data.split(sep) if x.strip()]
out=[]
for seg in segments(s):
    seg=seg.strip().lstrip("(").strip()
    cur_sweep = override_at_start(blank_quoted(seg), "SWEEP")
    toks=toks_of(seg)
    if not toks: continue
    if all(re.match(r"[A-Za-z_][A-Za-z0-9_]*=", t) for t in toks):
        for t in toks:
            k, v = t.split("=", 1)
            assigned[k] = v            # a value that is itself unreadable stays so: see resolve_dir
        continue
    # A git binary produced by a substitution or held in a variable cannot be matched by
    # any pattern, so it is not read as a commit it can hide behind: refuse and ask for a
    # plain `git`.
    if has_substituted_git(blank_quoted(seg)) and not (repo and linked(repo)):
        finish("REFUSE_SUBST")
    # The mirror image: a plain `git` whose SUBCOMMAND or PATHSPEC is a variable —
    # `C=commit; git $C -a -m x`, `git commit $paths -m x`. The arguments are what this
    # guard reads, so when they only exist once the shell runs, nothing can be judged.
    # A substitution inside a quoted message or value is blanked out first and still passes.
    if substituted_args(blank_quoted(seg), "git", ("commit",)) and not (repo and linked(repo)):
        finish("REFUSE_ARGSUB")
    if toks[0]=="cd" and len(toks)>1:
        repo=join_dir(repo, toks[1]); continue    # None: a folder only the shell can work out
    try: gi=toks.index("git")
    except ValueError: continue
    rest=toks[gi+1:]; seg_repo=repo; i=0
    while i<len(rest) and rest[i].startswith("-"):
        if rest[i]=="-C" and i+1<len(rest): seg_repo=join_dir(repo, rest[i+1]); i+=2; continue
        if rest[i]=="-c" and i+1<len(rest): i+=2; continue
        i+=1
    if i>=len(rest) or rest[i]!="commit": continue
    if cur_sweep: commit_sweep = True
    args=rest[i+1:]
    # The whole guard reads the repo this commit runs in. If that folder cannot be worked
    # out — an unresolvable `cd`, or a path that is no git repo — nothing below can be
    # trusted, so refuse rather than pass a commit judged against the wrong index.
    if not seg_repo or toplevel(seg_repo) is None:
        finish("REFUSE_CD")
    if linked(seg_repo): continue   # own linked worktree: nothing else can be staged here
    if any(a in ("-a","--all") or (a not in VALFLAGS and short_flag_sweeps(a)) for a in args):
        finish("REFUSE_ALL")
    nul = "--pathspec-file-nul" in args
    paths=[]; j=0; after_dd=False
    while j<len(args):
        a=args[j]
        if after_dd: paths.append(a); j+=1; continue
        if a=="--": after_dd=True; j+=1; continue
        if a.startswith("--pathspec-from-file"):
            name = a.split("=",1)[1] if "=" in a else (args[j+1] if j+1<len(args) else "")
            extra = read_pathspec_file(seg_repo, name, nul)
            if extra is None: finish("REFUSE_PSF")
            paths.extend(extra); j += 1 if "=" in a else 2; continue
        if a in VALFLAGS: j+=2; continue
        if a.startswith("-"): j+=1; continue
        paths.append(a); j+=1
    if any(p in WHOLE_TREE for p in paths):
        finish("REFUSE_DOT")
    # `-i` / `--include` commits what is ALREADY STAGED plus the named paths, so it carries
    # the staged files of another session exactly as a bare commit does: judged like one.
    include = any(a == "--include" or (a not in VALFLAGS and short_flag_has(a, "i")) for a in args)
    if include:
        named = {f for f in git_out(seg_repo,"diff","HEAD","--name-only","--",*paths).split("\n") if f.strip()} | set(paths)
        extra = sorted(f for f in git_out(seg_repo,"diff","--cached","--name-only").split("\n") if f.strip() and f not in named)
        if extra: finish("REFUSE_INDEX:"+", ".join(extra))
    if paths:
        tl=toplevel(seg_repo)
        if tl and any(os.path.realpath(p if os.path.isabs(p) else os.path.join(seg_repo,p))==tl for p in paths):
            finish("REFUSE_DOT")
        r1=git_out(seg_repo,"diff","HEAD","--name-only","--",*paths).split("\n")
        r2=git_out(seg_repo,"diff","--cached","--name-only","--",*paths).split("\n")
        files=sorted({f for f in r1+r2 if f.strip()})
        # a path git resolves to nothing (a typo) is still passed through, so the
        # provenance check below can name it.
        out.append("CHECK\t"+seg_repo+"\t"+"\t".join(files if files else paths)); continue
    st=git_out(seg_repo,"diff","--cached","--name-only").strip()
    if st:
        finish("REFUSE_INDEX:"+st.replace("\n",", "))
if commit_sweep:
    cur_sweep = True
    finish("nothing refused, the whole index carried deliberately")
print("\n".join(out) if out else "OK")')"
guard_parsed "commit-pathspec-guard" python3 $? "$verdict" "$cmd"
case "$verdict" in
  OK) exit 0 ;;
  REFUSE_LEDGER)
    guard_refuse_unrecorded "commit-pathspec-guard" "SWEEP=1"; exit 2 ;;
  REFUSE_ALL)
    echo "commit-pathspec-guard: REFUSED — \`git commit -a\` commits every modified tracked file, which can sweep in work that was not meant to go in. Name your paths: git commit <paths> -m …" >&2; exit 2 ;;
  REFUSE_DOT)
    echo "commit-pathspec-guard: REFUSED — a whole-tree pathspec (\`.\`, \`*\`, \`..\`, \`/\`, \`:/\`, or the repo root itself) commits every change under it — the same sweep as -a. Name your files: git commit <paths> -m …" >&2; exit 2 ;;
  REFUSE_SUBST)
    echo "commit-pathspec-guard: REFUSED — the git binary in this commit comes from a substitution (\`\$(…)\` or backticks), so what it will actually commit cannot be read before it runs. Write it as a plain: git commit <paths> -m …" >&2; exit 2 ;;
  REFUSE_ARGSUB)
    echo "commit-pathspec-guard: REFUSED — an argument of this git command comes from a variable or a substitution (\`\$C\`, \`\${C}\`, \`\$(…)\`, backticks), so the subcommand and the paths it would commit cannot be read before it runs — \`C=commit; git \$C -a -m x\` is a whole-index sweep no pattern can see. Write it plainly: git commit <paths> -m …   (a substitution inside a quoted message or value, like -m \"\$msg\", is fine)" >&2; exit 2 ;;
  REFUSE_CD)
    echo "commit-pathspec-guard: REFUSED — this commit runs in a folder this guard cannot work out (a \`cd\` whose target only the shell can expand, such as \`cd \"\$HOME/x\"\`, or a path that is not a git repository), so what it would commit cannot be read. Write the folder out in full, or run the commit from that folder: git -C /full/path commit <paths> -m …" >&2; exit 2 ;;
  REFUSE_PSF)
    echo "commit-pathspec-guard: REFUSED — \`--pathspec-from-file\` names a list this guard cannot read (missing, unreadable, or \`-\` for standard input), so the paths it would commit are unknown. Name the paths on the command line: git commit <paths> -m …" >&2; exit 2 ;;
  REFUSE_INDEX:*)
    echo "commit-pathspec-guard: REFUSED — \`git commit\` with no paths while the index already holds: ${verdict#REFUSE_INDEX:}. That may not all belong in this commit. Use: git commit <your paths> -m …   Deliberate whole-index commit: SWEEP=1 <command>" >&2; exit 2 ;;
esac
# (2) provenance check for every pathspec commit found — no-op when hooks/provenance.py is
# missing, or when hooks/channel-ceiling.conf names no channel files (see provenance.py).
PYPROV="$(dirname "$0")/provenance.py"
if [ -f "$PYPROV" ]; then
  printf '%s\n' "$verdict" | grep '^CHECK' | while IFS=$'\t' read -r _ repo rest; do
    IFS=$'\t' read -r -a paths <<<"$rest"
    res="$("$GUARD_PY" "$PYPROV" check "$repo" "$sid" "${paths[@]}")"
    case "$res" in
      REFUSE*)
        echo "commit-pathspec-guard: REFUSED — a named shared file holds a change this session did not make (commit only what YOU wrote, reconciled line by line). ${res#REFUSE}" | tr '\n' ' ' >&2
        echo "  Reconcile: git diff HEAD -- <path>   then, if every hunk is yours or deliberately carried: SWEEP=1 <command>" >&2
        exit 2 ;;
    esac
  done
  rc=$?; [ "$rc" = 2 ] && exit 2
fi
exit 0
