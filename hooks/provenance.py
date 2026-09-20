#!/usr/bin/env python3
"""Session provenance for shared CHANNEL files — the files listed in hooks/channel-ceiling.conf
(see hooks/channel-ceiling.conf.example), the same config git-hooks/pre-commit and
hooks/channel-size-guard.sh already read.

Problem: several sessions (or people) can edit ONE working tree. `git commit <path>` takes
the whole working-tree file, so a path-named commit still carries another session's
uncommitted hunks, and git alone cannot tell whose lines are whose. This module records,
per session, what the session itself did to each channel file, so a commit guard
(hooks/commit-pathspec-guard.sh) can refuse a commit that would carry a change this session
did not make.

Config: hooks/channel-ceiling.conf, read from the SAME directory as this script (patterns
only — the first field of every non-`LIMIT=` line; any extra unit/band/stop columns
channel-size-guard.sh uses are ignored here). No conf file, or one with no patterns at all:
every mode below is a no-op / always answers OK — the safe default for a repo with no
shared files.

Modes (hook JSON on stdin for pre/post):
  pre   — snapshot each channel file's working-tree blob hash and its HEAD blob hash, plus
          the tool name and its file_path / command, before a tool call
  post  — compare with the snapshot. A changed channel file is credited to THIS session
          only when the tool could have written it: Edit/Write/MultiEdit -> only
          tool_input.file_path; Bash -> only files whose name or path appears in the
          command text. A changed file the tool could not have written is a FOREIGN
          change: any chain this session holds on it is marked dirty. A file absent before
          and present after is a creation, credited by the same rule.
  check <repo> <session_id> <path>...  — for each channel path: OK, or REFUSE with a
          reason: no-record (this session never wrote it, or wrote it before a commit),
          dirty-at-start (the file already held uncommitted changes before this session's
          first write, or a foreign change landed between its writes), changed-since (the
          file changed after this session's last write), stale-chain (HEAD moved and the
          file changed afterwards without a recorded write)

State: $PROVENANCE_STATE_DIR or ~/.claude/state/provenance/<session_id>.json (local, never
backed up). Never blocks by itself; only `check` produces refusals.
RETIRED FOR LINKED WORKTREES: in a checkout made by `git worktree add`, no other session's
lines can be in the folder (it has its own index), so pre/post record nothing there and
check answers OK; a shared, non-worktree checkout keeps the full recorder.
Tests: hooks/test-hooks.sh.
"""
import fnmatch, hashlib, json, os, subprocess, sys

STATE_DIR = os.environ.get("PROVENANCE_STATE_DIR") or os.path.expanduser("~/.claude/state/provenance")
WRITE_TOOLS = {"Edit", "Write", "MultiEdit"}
SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "dist", "build", "__pycache__"}


def run(args, cwd=None, timeout=5):
    try:
        return subprocess.run(args, cwd=cwd, capture_output=True, timeout=timeout)
    except Exception:
        return None


def load_patterns():
    """The first field of every non-comment, non-LIMIT= line in hooks/channel-ceiling.conf,
    next to this script. No file, or none of its lines name a pattern: []."""
    conf = os.path.join(os.path.dirname(os.path.abspath(__file__)), "channel-ceiling.conf")
    patterns = []
    try:
        with open(conf, encoding="utf-8") as f:
            for line in f:
                s = line.strip()
                if not s or s.startswith("#") or s.startswith("LIMIT="):
                    continue
                patterns.append(s.split()[0])
    except OSError:
        pass
    return patterns


def repo_root(cwd):
    r = run(["git", "-C", cwd, "rev-parse", "--show-toplevel"])
    if r and r.returncode == 0:
        return r.stdout.decode().strip()
    return None


def linked_worktree(root):
    """True in a checkout made by `git worktree add`: its git-dir lives under <main>/.git/worktrees/
    and differs from the common dir; the root checkout's git-dir IS the common dir."""
    r = run(["git", "-C", root, "rev-parse", "--path-format=absolute", "--git-dir", "--git-common-dir"])
    if not r or r.returncode != 0:
        return False
    lines = r.stdout.decode(errors="replace").splitlines()
    return len(lines) >= 2 and os.path.realpath(lines[0].strip()) != os.path.realpath(lines[1].strip())


def canon(path):
    """One spelling per file: a symlinked temp folder (e.g. /var -> /private/var on macOS)
    and git reporting the resolved path both go through realpath so comparisons agree."""
    return os.path.realpath(path)


def matches(rel, base, patterns):
    return any(fnmatch.fnmatch(rel, p) or fnmatch.fnmatch(base, p) for p in patterns)


def is_channel(root, path, patterns):
    """Absolute (canonical) path of a channel file under root, or None."""
    if not patterns:
        return None
    ap = canon(path if os.path.isabs(path) else os.path.join(root, path))
    try:
        rel = os.path.relpath(ap, root)
    except ValueError:
        return None
    if rel.startswith(".."):
        return None  # outside the repo entirely
    return ap if matches(rel, os.path.basename(ap), patterns) else None


def channel_files(root, patterns):
    """Every EXISTING file under root matching a pattern — including one not yet tracked by
    git, so a brand-new channel file is picked up the moment it's created. Literal
    (wildcard-free) patterns are a single stat each; only a pattern actually containing a
    wildcard pays for a directory walk, pruned past .git/node_modules/build-ish folders."""
    if not patterns:
        return []
    literal = [p for p in patterns if not any(c in p for c in "*?[")]
    wild = [p for p in patterns if p not in literal]
    out = []
    for p in literal:
        ap = os.path.join(root, p)
        if os.path.isfile(ap):
            out.append(canon(ap))
    if wild:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
            rel_dir = os.path.relpath(dirpath, root)
            for fn in filenames:
                rel = fn if rel_dir == "." else os.path.join(rel_dir, fn)
                if matches(rel, fn, wild):
                    out.append(canon(os.path.join(dirpath, fn)))
    return sorted(set(out))


def blob_hash(path):
    """git's own blob id for the working-tree file, computed in-process."""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except Exception:
        return None
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def head_hashes(root, patterns):
    """{abs path: blob id at HEAD} for every channel file, in ONE git call."""
    out = {}
    if not patterns:
        return out
    r = run(["git", "-C", root, "ls-tree", "-r", "HEAD"])
    if not r or r.returncode != 0:
        return out
    for line in r.stdout.decode(errors="replace").splitlines():
        try:
            meta, rel = line.split("\t", 1)
            sha = meta.split()[2]
        except Exception:
            continue
        if matches(rel, os.path.basename(rel), patterns):
            out[os.path.join(root, rel)] = sha
    return out


def state_path(sid):
    return os.path.join(STATE_DIR, (sid or "nosession") + ".json")


def load(sid):
    try:
        with open(state_path(sid)) as f:
            return json.load(f)
    except Exception:
        return {"snap": {}, "chains": {}}


def save(sid, st):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(state_path(sid), "w") as f:
        json.dump(st, f)


def read_hook_input():
    try:
        d = json.load(sys.stdin)
    except Exception:
        return None
    cwd = d.get("cwd") or os.getcwd()
    ti = d.get("tool_input") or {}
    return {
        "sid": d.get("session_id") or "nosession",
        "cwd": cwd,
        "tool": d.get("tool_name") or "",
        "file_path": ti.get("file_path") or "",
        "command": ti.get("command") or "",
    }


def mode_pre():
    patterns = load_patterns()
    if not patterns:
        return
    hi = read_hook_input()
    if not hi:
        return
    root = repo_root(hi["cwd"])
    if not root:
        return
    if linked_worktree(root):
        return
    st = load(hi["sid"])
    heads = head_hashes(root, patterns)
    snap = {}
    for p in set(channel_files(root, patterns)) | set(heads):
        snap[p] = {"wt": blob_hash(p), "head": heads.get(p)}
    st["snap"] = snap
    st["snap_meta"] = {"tool": hi["tool"], "file_path": hi["file_path"], "command": hi["command"], "root": root}
    save(hi["sid"], st)


def could_have_written(meta, root, path):
    """Did THIS tool call plausibly write this channel file?"""
    tool = meta.get("tool", "")
    if tool in WRITE_TOOLS:
        fp = meta.get("file_path") or ""
        if not fp:
            return False
        fp = canon(fp if os.path.isabs(fp) else os.path.join(root, fp))
        return fp == canon(path)
    if tool == "Bash":
        cmd = meta.get("command") or ""
        rel = os.path.relpath(path, root)
        return os.path.basename(path) in cmd or rel in cmd
    return False


def mode_post():
    patterns = load_patterns()
    if not patterns:
        return
    hi = read_hook_input()
    if not hi:
        return
    root = repo_root(hi["cwd"])
    if not root:
        return
    if linked_worktree(root):
        return
    st = load(hi["sid"])
    snap = st.get("snap", {})
    meta = st.get("snap_meta", {})
    if meta.get("root") and meta.get("root") != root:
        snap = {}
    chains = st.setdefault("chains", {})
    heads = head_hashes(root, patterns)
    for p in set(channel_files(root, patterns)) | set(snap) | set(heads):
        now = blob_hash(p)
        headnow = heads.get(p)
        pre = snap.get(p)
        chain = chains.get(p)
        # HEAD moved since the chain opened
        if chain and chain.get("head") != headnow:
            if now == headnow:
                del chains[p]
                chain = None  # committed and clean
            elif pre and pre.get("wt") == chain.get("last_after"):
                chain["head"] = headnow  # my last write is still the content: carry the chain over
            else:
                chains[p] = chain = {"head": headnow, "dirty_at_start": True,
                                     "first_before": pre.get("wt") if pre else None, "last_after": now}
        pre_wt = pre.get("wt") if pre else None
        changed = (now != pre_wt) if pre else (now is not None)
        if not changed:
            continue
        mine = could_have_written(meta, root, p)
        if mine:
            if chain is None:
                chains[p] = {"head": headnow,
                             "dirty_at_start": bool(pre) and (pre.get("wt") != pre.get("head")),
                             "first_before": pre_wt, "last_after": now}
            else:
                if pre_wt != chain.get("last_after"):
                    chain["dirty_at_start"] = True  # a foreign change landed between my writes
                chain["last_after"] = now
        elif chain is not None:
            chain["dirty_at_start"] = True  # someone else changed a file I hold a chain on
    st["snap"] = {}
    st["snap_meta"] = {}
    save(hi["sid"], st)


def mode_check(argv):
    patterns = load_patterns()
    if not patterns or len(argv) < 3:
        print("OK")
        return
    repo, sid, paths = argv[0], argv[1], argv[2:]
    root = repo_root(repo) or repo
    if linked_worktree(root):
        print("OK")
        return
    st = load(sid)
    chains = st.get("chains", {})
    heads = head_hashes(root, patterns)
    refusals = []
    for path in paths:
        ap = is_channel(root, path, patterns)
        if not ap:
            continue
        now = blob_hash(ap)
        headh = heads.get(ap)
        if now is None or now == headh:
            continue  # nothing to commit for this path
        chain = chains.get(ap)
        rel = os.path.relpath(ap, root)
        if chain is None:
            refusals.append(f"{rel}: no-record — this session never wrote it (or wrote it before a commit); the change is someone else's or unrecorded")
        elif chain.get("head") != headh:
            refusals.append(f"{rel}: stale-chain — HEAD moved since this session's write and the file changed afterwards")
        elif chain.get("dirty_at_start"):
            refusals.append(f"{rel}: dirty-at-start — the file held uncommitted changes before this session's first write, or a foreign change landed between its writes")
        elif now != chain.get("last_after"):
            refusals.append(f"{rel}: changed-since — the file changed after this session's last write (another session's edit is inside)")
    if refusals:
        print("REFUSE\n" + "\n".join(refusals))
    else:
        print("OK")


if __name__ == "__main__":
    m = sys.argv[1] if len(sys.argv) > 1 else ""
    if m == "pre":
        mode_pre()
    elif m == "post":
        mode_post()
    elif m == "check":
        mode_check(sys.argv[2:])
    else:
        print("usage: provenance.py pre|post|check <repo> <session_id> <paths…>", file=sys.stderr)
        sys.exit(1)
