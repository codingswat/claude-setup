#!/bin/bash
# PreToolUse hook on Bash. In a checkout that might already hold other staged work — a
# second terminal, another agent, an interrupted task — a bare `git commit` with no path
# arguments sweeps in EVERYTHING currently staged, not just what was meant to go in.
# Refuses:
#   - `git commit` with no path arguments while the index already holds staged files
#   - `git commit -a` / `--all` (stages and commits every tracked change, staged or not)
#   - whole-tree pathspecs: `git commit .` / `./` / `:/`
# Passes: any commit that names its own paths, and a bare `git commit` when the index is
# empty (there is nothing else it could sweep in).
# Commit messages and heredoc bodies are stripped out before matching, so a message that
# merely MENTIONS "-a" or "." is not refused.
# Deliberate whole-index commit: start the command (or the segment after ; && |) with
# `SWEEP=1 ` — only that position counts.
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
verdict="$(printf '%s' "$cmd" | CWD="$cwd" python3 -c '
import re,sys,os,subprocess,shlex
raw=sys.stdin.read()
s=re.sub(r"<<-?\s*[\x27\"]?(\w+)[\x27\"]?[^\n]*\n.*?\n\1(?=\n|$)", " HEREDOC ", raw, flags=re.S)
s=re.sub(r"(-m|--message)(=|\s+)(\"(?:[^\"\\\\]|\\\\.)*\"|\x27[^\x27]*\x27)", r"\1 MSG", s, flags=re.S)
# override: only at the start of a command segment, judged on text with every quoted string removed
unq=re.sub(r"\"(?:[^\"\\\\]|\\\\.)*\"|\x27[^\x27]*\x27", " Q ", s)
if re.search(r"(^|[;&|\n] *)SWEEP=1 ", unq, flags=re.M): print("OK"); sys.exit(0)
VALFLAGS={"-m","--message","-F","--file","--author","--date","-C","-c","--reuse-message","--reedit-message","--fixup","--squash","--trailer","--cleanup","-t","--template","--pathspec-from-file"}
repo=os.environ.get("CWD") or os.getcwd()
def toks_of(seg):
    try: return shlex.split(seg, posix=True)
    except ValueError: return seg.split()
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
        continue   # named paths: this commit passes
    try:
        st=subprocess.run(["git","-C",seg_repo,"diff","--cached","--name-only"],capture_output=True,text=True,timeout=5).stdout.strip()
    except Exception: st=""
    if st:
        print("REFUSE_INDEX:"+st.replace("\n",", ")); sys.exit(0)
print("OK")')"
case "$verdict" in
  OK) exit 0 ;;
  REFUSE_ALL)
    echo "commit-pathspec-guard: REFUSED — \`git commit -a\` commits every modified tracked file, which can sweep in work that was not meant to go in. Name your paths: git commit <paths> -m …" >&2; exit 2 ;;
  REFUSE_DOT)
    echo "commit-pathspec-guard: REFUSED — \`git commit .\` (or :/) commits every change under the folder — the same sweep as -a. Name your files: git commit <paths> -m …" >&2; exit 2 ;;
  REFUSE_INDEX:*)
    echo "commit-pathspec-guard: REFUSED — \`git commit\` with no paths while the index already holds: ${verdict#REFUSE_INDEX:}. That may not all belong in this commit. Use: git commit <your paths> -m …   Deliberate whole-index commit: SWEEP=1 <command>" >&2; exit 2 ;;
esac
exit 0
