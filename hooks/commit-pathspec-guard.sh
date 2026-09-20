#!/bin/bash
# PreToolUse hook on Bash. In a checkout that might already hold other staged work — a
# second terminal, another agent, an interrupted task — a bare `git commit` with no path
# arguments sweeps in EVERYTHING currently staged, not just what was meant to go in.
# Refuses:
#   - `git commit` with no path arguments while the index already holds staged files
#   - `git commit -a` / `--all` (stages and commits every tracked change, staged or not)
#   - whole-tree pathspecs: `git commit .` / `./` / `:/`
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
# Commit messages and heredoc bodies are stripped out before matching, so a message that
# merely MENTIONS "-a" or "." is not refused.
# Deliberate whole-index or reconciled commit: start the command (or the segment after
# ; && |) with `SWEEP=1 ` — only that position counts. Every use is logged by
# hooks/override-ledger.sh, if present (a missing ledger script never blocks this guard).
# Both jq and python3 parse the command below; if either is missing this guard cannot
# read what it's being asked to run, so it refuses rather than silently letting an
# unparsed (and therefore unmatched) command through. Fail closed, like
# git-hooks/pre-commit.
# Tests: hooks/test-hooks.sh.
missing=""
command -v jq >/dev/null 2>&1 || missing="jq"
command -v python3 >/dev/null 2>&1 || missing="${missing:+$missing and }python3"
if [ -n "$missing" ]; then
  echo "commit-pathspec-guard: REFUSED — $missing not found, so this guard cannot parse the command (fail closed, not open)." >&2
  exit 2
fi
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"; [ -z "$cwd" ] && cwd="$PWD"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty')"; [ -z "$sid" ] && sid="nosession"
verdict="$(printf '%s' "$cmd" | CWD="$cwd" HOOKDIR="$(dirname "$0")" python3 -c '
import re,sys,os,subprocess,shlex
raw=sys.stdin.read()
s=re.sub(r"<<-?\s*[\x27\"]?(\w+)[\x27\"]?[^\n]*\n.*?\n\1(?=\n|$)", " HEREDOC ", raw, flags=re.S)
s=re.sub(r"(-m|--message)(=|\s+)(\"(?:[^\"\\\\]|\\\\.)*\"|\x27[^\x27]*\x27)", r"\1 MSG", s, flags=re.S)
# override: only at the start of a command segment, judged on text with every quoted string removed
unq=re.sub(r"\"(?:[^\"\\\\]|\\\\.)*\"|\x27[^\x27]*\x27", " Q ", s)
if re.search(r"(^|[;&|\n] *)SWEEP=1 ", unq, flags=re.M):
    ledger=os.path.join(os.environ.get("HOOKDIR",""), "override-ledger.sh")
    if os.path.isfile(ledger):
        try: subprocess.run(["bash", ledger, "SWEEP", raw], timeout=5)
        except Exception: pass
    print("OK"); sys.exit(0)
VALFLAGS={"-m","--message","-F","--file","--author","--date","-C","-c","--reuse-message","--reedit-message","--fixup","--squash","--trailer","--cleanup","-t","--template","--pathspec-from-file"}
repo=os.environ.get("CWD") or os.getcwd()
def toks_of(seg):
    try: return shlex.split(seg, posix=True)
    except ValueError: return seg.split()
def linked(r):
    # A linked worktree has its own git-dir under <main>/.git/worktrees/<name>; the
    # main checkout (or a plain, non-worktree repo) has git-dir == common-dir.
    try:
        o=subprocess.run(["git","-C",r,"rev-parse","--path-format=absolute","--git-dir","--git-common-dir"],capture_output=True,text=True,timeout=5).stdout.splitlines()
        return len(o)>=2 and o[0].strip()!="" and os.path.realpath(o[0].strip())!=os.path.realpath(o[1].strip())
    except Exception: return False
out=[]
for seg in re.split(r"\s*(?:&&|\|\||;|\||\n)\s*", s):
    seg=seg.strip().lstrip("(").strip()
    toks=toks_of(seg)
    if not toks: continue
    if toks[0]=="cd" and len(toks)>1 and not toks[1].startswith("$"):
        repo=toks[1] if os.path.isabs(toks[1]) else os.path.normpath(os.path.join(repo,toks[1])); continue
    try: gi=toks.index("git")
    except ValueError: continue
    rest=toks[gi+1:]; seg_repo=repo; i=0
    while i<len(rest) and rest[i].startswith("-"):
        if rest[i]=="-C" and i+1<len(rest): seg_repo=rest[i+1] if os.path.isabs(rest[i+1]) else os.path.normpath(os.path.join(repo,rest[i+1])); i+=2; continue
        if rest[i]=="-c" and i+1<len(rest): i+=2; continue
        i+=1
    if i>=len(rest) or rest[i]!="commit": continue
    args=rest[i+1:]
    if linked(seg_repo): continue   # own linked worktree: nothing else can be staged here
    if any(a in ("-a","--all") or (a.startswith("-") and not a.startswith("--") and "a" in a[1:] and a not in VALFLAGS) for a in args):
        print("REFUSE_ALL"); sys.exit(0)
    paths=[]; j=0; after_dd=False
    while j<len(args):
        a=args[j]
        if after_dd: paths.append(a); j+=1; continue
        if a=="--": after_dd=True; j+=1; continue
        if a in VALFLAGS: j+=2; continue
        if a.startswith("-"): j+=1; continue
        paths.append(a); j+=1
    if any(p in (".", "./", ":/", ":(top)") for p in paths):
        print("REFUSE_DOT"); sys.exit(0)
    if paths:
        try:
            r1=subprocess.run(["git","-C",seg_repo,"diff","HEAD","--name-only","--"]+paths,capture_output=True,text=True,timeout=5).stdout.split("\n")
            r2=subprocess.run(["git","-C",seg_repo,"diff","--cached","--name-only","--"]+paths,capture_output=True,text=True,timeout=5).stdout.split("\n")
            files=sorted({f for f in r1+r2 if f.strip()})
        except Exception: files=[]
        # a path git resolves to nothing (a typo) is still passed through, so the
        # provenance check below can name it.
        out.append("CHECK\t"+seg_repo+"\t"+"\t".join(files if files else paths)); continue
    try:
        st=subprocess.run(["git","-C",seg_repo,"diff","--cached","--name-only"],capture_output=True,text=True,timeout=5).stdout.strip()
    except Exception: st=""
    if st:
        print("REFUSE_INDEX:"+st.replace("\n",", ")); sys.exit(0)
print("\n".join(out) if out else "OK")')"
case "$verdict" in
  OK) exit 0 ;;
  REFUSE_ALL)
    echo "commit-pathspec-guard: REFUSED — \`git commit -a\` commits every modified tracked file, which can sweep in work that was not meant to go in. Name your paths: git commit <paths> -m …" >&2; exit 2 ;;
  REFUSE_DOT)
    echo "commit-pathspec-guard: REFUSED — \`git commit .\` (or :/) commits every change under the folder — the same sweep as -a. Name your files: git commit <paths> -m …" >&2; exit 2 ;;
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
