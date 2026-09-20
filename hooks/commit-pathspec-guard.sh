#!/bin/bash
# PreToolUse hook on Bash. In a checkout that might already hold other staged work — a
# second terminal, another agent, an interrupted task — a bare `git commit` with no path
# arguments sweeps in EVERYTHING currently staged, not just what was meant to go in.
# Refuses:
#   - `git commit` with no path arguments while the index already holds staged files
#   - `git commit -a` / `--all` (stages and commits every tracked change, staged or not)
#   - whole-tree pathspecs: `git commit .` / `./` / `:/` / `*` / `..` / `/`, and the repo
#     root named by its own path — every one of them is the same sweep as `-a` wearing a
#     different hat
#   - a commit whose `git` is produced by substitution — `` `echo git` commit ``,
#     `$(which git) commit`: no pattern can see a binary that does not exist until the
#     shell runs it, so the command is refused and a plain `git commit <paths>` asked for
#   - a commit whose FOLDER cannot be worked out: `cd "$HOME/x" && git commit NOTES.md`
#     (only the shell can expand that target), or a path that is no git repository. The
#     whole guard reads that folder's index, so an unknown folder means an unjudged commit
#   - `--pathspec-from-file=<list>` whose list cannot be read (missing, or `-` for stdin).
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
# Deliberate whole-index or reconciled commit: start the command (or the segment after
# ; && |) with `SWEEP=1 ` — only that position counts, judged on text with quoted strings
# removed. Every use is written to hooks/override-ledger.sh with the refusal it bypassed;
# if that line CANNOT be written (no ledger script, unwritable path) the override is
# REFUSED, not honoured.
# jq, python3 and hooks/guard-lib.sh all parse the command below; if any is missing this
# guard cannot read what it's being asked to run, so it refuses rather than silently
# letting an unparsed (and therefore unmatched) command through. Hook input that is empty
# or is not valid JSON is refused for the same reason — the one exception is a well-formed
# call for a tool other than Bash, which carries no command to judge. Fail closed, like
# git-hooks/pre-commit.
# Tests: hooks/test-hooks.sh (sections 3, 3b, 23, 28, 29).
missing=""
command -v jq >/dev/null 2>&1 || missing="jq"
command -v python3 >/dev/null 2>&1 || missing="${missing:+$missing and }python3"
if [ -n "$missing" ]; then
  echo "commit-pathspec-guard: REFUSED — $missing not found, so this guard cannot parse the command (fail closed, not open)." >&2
  exit 2
fi
GUARD_LIB="$(dirname "$0")/guard-lib.sh"
if [ ! -r "$GUARD_LIB" ]; then
  echo "commit-pathspec-guard: REFUSED — hooks/guard-lib.sh is missing next to this hook, so the command cannot be normalised before matching (fail closed, not open). Reinstall the hooks (install.sh copies hooks/*.sh)." >&2
  exit 2
fi
. "$GUARD_LIB"
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
verdict="$(printf '%s' "$cmd" | CWD="$cwd" HOOKDIR="$(dirname "$0")" python3 -c "$GUARD_PY_COMMON"'
import subprocess, shlex
raw = sys.stdin.read()
s = clean(raw)
# override: only at the start of a command segment, judged on text with every quoted string removed
unq = blank_quoted(s)
sweep = re.search(r"(^|[;&|\n] *)SWEEP=1 ", unq, flags=re.M) is not None
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
    if sweep:
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
# A git binary produced by substitution cannot be matched by any pattern, so it is not
# read as a commit it can hide behind: refuse and ask for a plain `git`.
if has_substituted_git(unq) and not linked(repo):
    finish("REFUSE_SUBST")
UNRESOLVABLE=("$", "`", "*", "?")
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
    sep = b"\0" if nul else b"\n"
    return [x.decode("utf-8", "replace").strip() for x in data.split(sep) if x.strip()]
out=[]
for seg in re.split(r"\s*(?:&&|\|\||;|\||\n)\s*", s):
    seg=seg.strip().lstrip("(").strip()
    toks=toks_of(seg)
    if not toks: continue
    if toks[0]=="cd" and len(toks)>1:
        t=toks[1]
        if any(ch in t for ch in UNRESOLVABLE):
            repo=None; continue           # a folder only the shell can work out: unreadable
        repo=t if os.path.isabs(t) else (os.path.normpath(os.path.join(repo,t)) if repo else None); continue
    try: gi=toks.index("git")
    except ValueError: continue
    rest=toks[gi+1:]; seg_repo=repo; i=0
    while i<len(rest) and rest[i].startswith("-"):
        if rest[i]=="-C" and i+1<len(rest): seg_repo=rest[i+1] if os.path.isabs(rest[i+1]) else (os.path.normpath(os.path.join(repo,rest[i+1])) if repo else None); i+=2; continue
        if rest[i]=="-c" and i+1<len(rest): i+=2; continue
        i+=1
    if i>=len(rest) or rest[i]!="commit": continue
    args=rest[i+1:]
    # The whole guard reads the repo this commit runs in. If that folder cannot be worked
    # out — an unresolvable `cd`, or a path that is no git repo — nothing below can be
    # trusted, so refuse rather than pass a commit judged against the wrong index.
    if not seg_repo or toplevel(seg_repo) is None:
        finish("REFUSE_CD")
    if linked(seg_repo): continue   # own linked worktree: nothing else can be staged here
    if any(a in ("-a","--all") or (a.startswith("-") and not a.startswith("--") and "a" in a[1:] and a not in VALFLAGS) for a in args):
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
if sweep:
    finish("nothing refused, the whole index carried deliberately")
print("\n".join(out) if out else "OK")')"
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
    res="$(python3 "$PYPROV" check "$repo" "$sid" "${paths[@]}")"
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
