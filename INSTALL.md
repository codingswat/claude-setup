# Installing this, by hand or by script

## The quick way

```bash
git clone https://github.com/codingswat/claude-setup.git
cd claude-setup
./install.sh
```

Then **open a new Claude Code session** — hooks are read at session start, so an
already-running session will not see them.

Prefer to let Claude do it? Open a Claude Code session in the cloned folder and say
*"set this up for me"*. The repo's own `CLAUDE.md` tells it what to do, and it will walk you
through filling in your rulebook afterwards — which is the part that actually matters.

---

## What the script touches

| Path | What happens |
|---|---|
| `~/.claude/hooks/` | `check-claude-md.sh`, `auto-backup.sh`, `interview.md`, `clock-in-context.sh`, `guard-lib.sh`, `block-dangerous-git.sh`, `commit-pathspec-guard.sh`, `heavy-suite-guard.sh`, `override-ledger.sh`, `gate-guard.sh`, `channel-size-guard.sh`, `channel-size-post.sh`, `helper-ledger.py`, `test-hooks.sh`, `test-helper-ledger.sh` and `test-rules-cap.sh` are copied in (backed up first if different) — the last two aren't hooks themselves, but `test-hooks.sh` runs them as subprocesses and needs them alongside it. The multi-chat coordination group (`channel-provenance-pre.sh`, `channel-provenance-post.sh`, `provenance.py`, `doorman.sh`, `stop-state-check.sh`) is copied in too, so the opt-in question below has something to register, but stays unregistered until you say yes. `owner-card.md` and `heavy-suite.conf` are copied **only if you don't already have them** — the first you personalise, the second is written from `heavy-suite.conf.example`; their config files (`backup.conf`, `project-roots.conf`) are written fresh from your answers. Five more `.conf.example` files (`gate-guard`, `channel-ceiling`, `allowed-email-domains`, `block-dangerous-git`, `state-check`) are copied as **examples only** — each matching guard stays inert until you copy one to its live name yourself |
| `~/.claude/git-hooks/` | `commit-msg`, `pre-commit`, `pre-merge-commit`, `pre-push` are copied in and made executable. They sit inert here until you opt in below — they don't run anywhere until then |
| `~/.claude/CLAUDE.md` | The starter rulebook is installed **only if you don't already have one**. It is a fill-in form, but its 17 rules are active from your next session — rules 1 and 2 grant Claude standing permission to commit, push and merge to `main` |
| `~/.claude/.redaction-names.local` | Created **only if missing**, empty, with a comment explaining its two sections (`[guard]`, `[redact-only]`) — `git-hooks/pre-commit`'s privacy check fails CLOSED (refuses every commit) with no file there at all, so a fresh machine needs at least this to unblock ordinary commits. The installer's closing summary tells you to open it and fill it in |
| `~/.claude/project-template/` | Starter files for new projects; existing files are never replaced |
| `~/.claude/skills/` | The four skills; any skill folder of the same name is left alone |
| `~/.claude/settings.json` | Hook registrations are **merged in**. By default: `SessionStart` and `UserPromptSubmit` (the rulebook check and the owner-card loader), `PreToolUse` matched to `Bash` (the git-safety guards, `gate-guard.sh`) and to `Write\|Edit\|MultiEdit\|Bash` (`channel-size-guard.sh`), `PostToolUse` on the same matcher (`channel-size-post.sh`), and `Stop` (the helper cost ledger) — up to **ten** entries, fewer when `python3` or `jq` is missing. On top of that, opt-in: the multi-chat coordination group asked as one question (`PreToolUse`/`PostToolUse` on `Write\|Edit\|MultiEdit\|Bash` for the provenance pair, `UserPromptSubmit` for `doorman.sh`, `Stop` for `stop-state-check.sh`) — up to **four** more, so **fourteen** in total with everything on. Everything else in the file is preserved |
| `~/.claude/.gitignore` | Only if you opt into the backup hook, and only if you don't have one |
| git's **global** config | Only if you opt into the "git hooks" step: sets `core.hooksPath` to `~/.claude/git-hooks`, which then applies to every repository on this machine |

**Nothing of yours is ever deleted** (the installer removes only its own empty backup
folder). Anything that would be overwritten is copied to
`~/.claude/.setup-backup-<timestamp>/` first. Re-running the script is safe.

**The auto-backup hook is off by default** and the script asks before setting it up.

Requires `bash`, and either `node` or `python3` for the settings merge. Claude Code already
brings Node, so this is almost always satisfied.

Three `PreToolUse` guards (`block-dangerous-git.sh`, `commit-pathspec-guard.sh`,
`heavy-suite-guard.sh`) additionally need `jq` **and** `python3` on `PATH` — they read the
tool call with one and normalise the command with the other, and fail CLOSED (refuse
everything) if either is missing, or if either is installed but **broken**: a parser that
runs and returns nothing leaves the guard with an empty command, which matches no pattern,
so an unreadable command is refused rather than waved through. So the installer registers those three only when **both**
are present, with a warning naming what to install. The size pair (`channel-size-guard.sh`
and its `PostToolUse` half `channel-size-post.sh`) needs `jq` alone and is registered
whenever `jq` is there; without `jq` both are inert, so neither is registered. A fifth, `gate-guard.sh`, is different: it degrades safely with no `jq` (a cruder
text match instead of a refusal), and with no `python3` it passes every command with a
one-line warning — it is the one guard allowed to fail OPEN, because it protects no data and
only enforces a habit about exit codes. The installer still gates it on `python3`, now for
cost rather than safety: without `python3` it could never say no, so registering it would
only add a subprocess to every Bash call.

All four Bash guards also need `hooks/guard-lib.sh` beside them — the shared file that reads
a command the way a shell would (quotes, tabs, escapes, `sh -c`/`eval` wrappers). It is not a
hook and is registered nowhere, but a guard that cannot find it REFUSES, so it must be copied
with them.

The opt-in multi-chat coordination group (below) needs `python3` for its provenance pair
only; `doorman.sh` and `stop-state-check.sh` in that same group don't, and stay registered
even without it.

---

## Doing it by hand

Skip the script entirely if you prefer. These steps reach the same end state.

**One difference, stated plainly:** the script backs up every file it replaces and never
overwrites a skill or template you already have. Plain `cp` does neither. The commands below
use `-n` ("no clobber") to get the second half of that, and back up the hooks by hand for the
first. If you already have a populated `~/.claude`, the script is the safer route.

### 1. Copy the files

```bash
mkdir -p ~/.claude/hooks ~/.claude/git-hooks ~/.claude/skills ~/.claude/project-template
cp -a ~/.claude/hooks ~/.claude/hooks.backup-$(date +%s) 2>/dev/null
cp hooks/check-claude-md.sh hooks/auto-backup.sh hooks/interview.md \
   hooks/clock-in-context.sh hooks/guard-lib.sh hooks/block-dangerous-git.sh \
   hooks/commit-pathspec-guard.sh hooks/heavy-suite-guard.sh hooks/override-ledger.sh \
   hooks/gate-guard.sh hooks/channel-size-guard.sh hooks/channel-size-post.sh \
   hooks/helper-ledger.py \
   hooks/channel-provenance-pre.sh hooks/channel-provenance-post.sh hooks/provenance.py \
   hooks/doorman.sh hooks/stop-state-check.sh \
   hooks/test-hooks.sh hooks/test-helper-ledger.sh hooks/test-rules-cap.sh \
   ~/.claude/hooks/
chmod +x ~/.claude/hooks/check-claude-md.sh ~/.claude/hooks/auto-backup.sh \
         ~/.claude/hooks/clock-in-context.sh ~/.claude/hooks/guard-lib.sh \
         ~/.claude/hooks/block-dangerous-git.sh \
         ~/.claude/hooks/commit-pathspec-guard.sh ~/.claude/hooks/heavy-suite-guard.sh \
         ~/.claude/hooks/override-ledger.sh ~/.claude/hooks/gate-guard.sh \
         ~/.claude/hooks/channel-size-guard.sh ~/.claude/hooks/channel-size-post.sh \
         ~/.claude/hooks/helper-ledger.py \
         ~/.claude/hooks/channel-provenance-pre.sh ~/.claude/hooks/channel-provenance-post.sh \
         ~/.claude/hooks/provenance.py ~/.claude/hooks/doorman.sh \
         ~/.claude/hooks/stop-state-check.sh ~/.claude/hooks/test-hooks.sh \
         ~/.claude/hooks/test-helper-ledger.sh ~/.claude/hooks/test-rules-cap.sh
cp -Rn project-template/. ~/.claude/project-template/
cp -Rn skills/. ~/.claude/skills/

# Two files you personalise — copy only if you don't already have them:
[ -f ~/.claude/hooks/owner-card.md ]    || cp hooks/owner-card.md ~/.claude/hooks/owner-card.md
[ -f ~/.claude/hooks/heavy-suite.conf ] || cp hooks/heavy-suite.conf.example ~/.claude/hooks/heavy-suite.conf
# Upgrading, and you already have a heavy-suite.conf copied from an older example? Its
# PATTERN missed `yarn test`, `pnpm test` and `npm run test:<name>`. Diff it against
# hooks/heavy-suite.conf.example (whose PATTERN is now exactly the guard's built-in
# default) and widen yours, or delete yours to fall back to the built-in.

# Five more .conf.example files — copied as EXAMPLES only, next to their hooks. Each
# matching guard stays inert until you copy one to its live name yourself:
cp -n hooks/gate-guard.conf.example hooks/channel-ceiling.conf.example \
      hooks/allowed-email-domains.conf.example hooks/block-dangerous-git.conf.example \
      hooks/state-check.conf.example \
      ~/.claude/hooks/

# The git hooks proper — copied in and made executable, but inert until step 7:
cp git-hooks/commit-msg git-hooks/pre-commit git-hooks/pre-merge-commit git-hooks/pre-push \
   ~/.claude/git-hooks/
chmod +x ~/.claude/git-hooks/commit-msg ~/.claude/git-hooks/pre-commit \
         ~/.claude/git-hooks/pre-merge-commit ~/.claude/git-hooks/pre-push
```

The hook scripts are the one thing you *do* want replaced with the current versions — hence
the backup on the line above rather than `-n`.

### 2. Install your rulebook

Only if you don't already have one — this file is the whole point of the setup, so never
overwrite a version you have written:

```bash
[ -f ~/.claude/CLAUDE.md ] || cp TEMPLATE-CLAUDE.md ~/.claude/CLAUDE.md
```

Then open it and fill it in. It is written as a form and explains what each section changes.

### 2b. The redaction names list

`git-hooks/pre-commit`'s privacy check fails CLOSED — refuses every commit — when
`~/.claude/.redaction-names.local` doesn't exist at all. Only if you don't already have one:

```bash
[ -f ~/.claude/.redaction-names.local ] || cat > ~/.claude/.redaction-names.local <<'EOF'
# Names/handles that must never reach a public commit. One per line; # comments and blank
# lines ignored. An empty file (like this one) is enough to proceed with none configured.
#
# Two sections, for your own reading — as shipped, pre-commit enforces both the same way
# (a match refuses the commit either way):
#   [guard]        names that must never reach a public commit
#   [redact-only]  names you'd rather flag than hard-stop on

[guard]

[redact-only]
EOF
```

Then open it and add your own real name, handle, or employer — the check can't catch a name
you haven't listed.

### 3. Say where your projects live

```bash
echo "$HOME/projects" > ~/.claude/hooks/project-roots.conf
```

One absolute path per line. When a session starts in a folder under one of these and that
project has no `CLAUDE.md`, Claude interviews you and drafts one. Outside these folders it
does nothing at all — that is deliberate, because a session in a random folder might be a
one-off task, not a project.

No file means no roots, which switches the interview off entirely.

### 4. Register the SessionStart hook

Add this to `~/.claude/settings.json`, merging with whatever is already there:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ {
          "type": "command",
          "command": "/bin/bash \"$HOME/.claude/hooks/check-claude-md.sh\"",
          "statusMessage": "Checking for project CLAUDE.md..."
      } ] }
    ]
  }
}
```

This is the hook that re-asserts your process rules at the start of every session, and runs
the new-project interview. **It is the one that makes the difference** — a rulebook Claude
reads can be drifted away from over a long session; a hook fires every time.

### 5. Optional: the auto-backup hook

Read this section before enabling it.

This hook commits and pushes everything under `~/.claude` at the end of **every turn**,
without showing you a diff. It is convenient and it is sharp. It also refuses to commit when a
changed file holds a secret-looking string (an API key, a token, a private key) — one more
reason a genuinely sensitive value should never sit under `~/.claude` in the first place. Two
things make the rest of it safe, and it is not safe without them:

**First, install the allowlist.** `~/.claude/.gitignore` must ignore everything and then
re-include only named files. Without it, `git add -A` sweeps up your credentials file, shell
history, and complete session transcripts and pushes them.

```bash
cp hooks/dot-claude.gitignore ~/.claude/.gitignore
```

If you already have a `~/.claude/.gitignore`, the installer will not replace it — but it also
**will not enable the backup hook** until it can prove with `git check-ignore` that your file
actually ignores the sensitive paths. An ordinary blocklist (`*.log`, `node_modules/`) does
not, and that is the case where this hook would quietly publish your session transcripts. If
that happens, merge `hooks/dot-claude.gitignore` into your file and run the installer again.

Checking by hand:

```bash
cd ~/.claude && git init -q 2>/dev/null
git check-ignore -v .credentials.json projects/x/session.jsonl shell-snapshots/s.sh
```

Every one of those paths must come back as ignored.

**Second, keep the backup repo private.** It holds your AI's standing instructions. So does
the optional mirror folder, which receives a copy of `settings.json`.

Then configure it:

```bash
cat > ~/.claude/hooks/backup.conf <<EOF
AUTHOR=your-handle <you@example.com>
MIRROR_DIR=
EOF
```

Plain `KEY=value`, no quotes. This file is **parsed**, never sourced — it is read at the end
of every turn, so anything that could write into it would otherwise get to run shell commands
on your machine for free.

`MIRROR_DIR` is optional — a folder that gets readable copies of your config, useful if you
work in a context that can't see `~/.claude`. Leave it empty to skip that step.

**Without `backup.conf` the hook does nothing at all**, so registering it early is harmless.
Register it the same way as step 4, under `"Stop"` instead of `"SessionStart"`, with the
command `/bin/bash "$HOME/.claude/hooks/auto-backup.sh"` and `"timeout": 30`.

Finally, make `~/.claude` a git repo with a **private** remote — and look before you leap:

```bash
cd ~/.claude && git init && git add -A && git status
```

Read that list properly. It is the complete set of files that will be pushed. Only if it holds
nothing you would mind publishing, commit and push once by hand, so you have seen exactly what
lands there before the hook starts doing it automatically.

**Two honest trade-offs, stated plainly.**

Anything that writes into `~/.claude` gets committed with no human review. If a malicious
instruction ever reached your config, this hook would faithfully preserve it. The allowlist is
the boundary; convenience and safety genuinely pull against each other here.

And the hook will never merge the other direction. If the remote has commits your machine
doesn't, the push is refused and you are told — it does not pull them in. This repo holds
hooks and settings, so auto-merging would mean running whatever someone else pushed in your
next session. Your local commit stays safe either way; resolving it is a decision you make,
not one the hook makes for you.

### 6. Register the new safety hooks

Same merge as step 4, three more events this time.

`clock-in-context.sh` goes under `SessionStart` (a second entry, alongside
`check-claude-md.sh`) and again under `UserPromptSubmit`:

```json
{ "hooks": [ {
    "type": "command",
    "command": "/bin/bash \"$HOME/.claude/hooks/clock-in-context.sh\"",
    "statusMessage": "Loading the owner card..."
} ] }
```

Then the Bash-only guards go under `PreToolUse`. Each carries a `"matcher"` on the
group — that's what restricts a hook to firing only before the `Bash` tool runs:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [
          { "type": "command", "command": "/bin/bash \"$HOME/.claude/hooks/block-dangerous-git.sh\"" } ] },
      { "matcher": "Bash", "hooks": [
          { "type": "command", "command": "/bin/bash \"$HOME/.claude/hooks/commit-pathspec-guard.sh\"" } ] },
      { "matcher": "Bash", "hooks": [
          { "type": "command", "command": "/bin/bash \"$HOME/.claude/hooks/heavy-suite-guard.sh\"" } ] },
      { "matcher": "Bash", "hooks": [
          { "type": "command", "command": "/bin/bash \"$HOME/.claude/hooks/gate-guard.sh\"" } ] },
      { "matcher": "Write|Edit|MultiEdit|Bash", "hooks": [
          { "type": "command", "command": "/bin/bash \"$HOME/.claude/hooks/channel-size-guard.sh\"" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Write|Edit|MultiEdit|Bash", "hooks": [
          { "type": "command", "command": "/bin/bash \"$HOME/.claude/hooks/channel-size-post.sh\"" } ] }
    ]
  }
}
```

`block-dangerous-git.sh` inspects quoted text too, so a command that
merely quotes a dangerous git command — `echo "git reset --hard is dangerous"` — is
refused along with the real thing; put that text in a file with an editor instead of
echoing it. (The
trade-off is deliberate: reading only unquoted words would let `sh -c "git reset --hard"`
through, which is the real command wearing quotes.)

`gate-guard.sh` is gated on `python3` (see the note above the "Requires" paragraph): with
no `python3` it passes everything with a warning, so registering it would cost a subprocess
per Bash call and catch nothing. Only register it if `python3` is on `PATH`. `channel-size-guard.sh` and its `PostToolUse` half
`channel-size-post.sh` need `jq` only and do nothing at all without it, so register the two
together whenever `jq` is there. The `PostToolUse` half is what catches growth the
`PreToolUse` half cannot see in the command text — a filename held in a variable, an `Edit`
whose one new "word" is 100,000 characters long: it re-measures the file on disk afterwards
and says loudly that it is over. It cannot undo a write; nothing can, after the fact.
`override-ledger.sh` (copied in step 1, called by the guards above and by `pre-commit`) is
not itself registered anywhere — it has no event of its own.

Merge these arrays into whatever `hooks` block already exists — don't replace it.

Finally, `helper-ledger.py` goes under `"Stop"` (needs `python3`, not `jq`):

```json
{ "hooks": [ {
    "type": "command",
    "command": "/usr/bin/env python3 \"$HOME/.claude/hooks/helper-ledger.py\""
} ] }
```

### The helper ledger

`helper-ledger.py` is a `Stop` hook that scans finished subagent/workflow-agent transcripts
and appends one row per helper to `~/.claude/ledgers/helpers.tsv` — model, steps, peak
context, output tokens, minutes, and an estimated cost. Nothing is printed and nothing
blocks; it is silent on every error path, same as every other hook here. The prices baked
into it (`RATES` near the top of the file) are **illustrative list prices** — edit them to
whatever your own provider actually charges before trusting the cost column. `--tail N`
prints the last N rows plus a per-model summary.

### 6b. Optional: multi-chat coordination hooks

Only useful once more than one Claude Code session works in the same repo at a time —
skip this entirely for a single-session project. Four hooks (copied in step 1), one config
file (`hooks/state-check.conf`, see `hooks/state-check.conf.example`), which is shared with
`stop-state-check.sh`.

`channel-provenance-pre.sh` records, before an `Edit`/`Write`/`MultiEdit`/`Bash` call, each
shared channel file's current hash for this session; `channel-provenance-post.sh` compares
after, so a later pathspec commit can't sweep in another session's uncommitted change. Both
need `python3` — inert without it:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Write|Edit|MultiEdit|Bash", "hooks": [
          { "type": "command", "command": "/bin/bash \"$HOME/.claude/hooks/channel-provenance-pre.sh\"" } ] }
    ],
    "PostToolUse": [
      { "matcher": "Write|Edit|MultiEdit|Bash", "hooks": [
          { "type": "command", "command": "/bin/bash \"$HOME/.claude/hooks/channel-provenance-post.sh\"" } ] }
    ]
  }
}
```

`doorman.sh` (bounces a new prompt to a session already retired, or idle a while at a high
context) goes under `UserPromptSubmit`; `stop-state-check.sh` (marks a session retired past
its configured context floor, and holds a turn open until the role's state file is among
the changed files) goes under `"Stop"`. Neither needs `python3` or `jq`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "/bin/bash \"$HOME/.claude/hooks/doorman.sh\"" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "/bin/bash \"$HOME/.claude/hooks/stop-state-check.sh\"" } ] }
    ]
  }
}
```

All four are harmless to register even before `hooks/state-check.conf` exists — with no
config, or a working-directory name matching no line in it, every one of them is a no-op.

### 7. Optional: git hooks for every repo on this machine

Read this before running it:

```bash
git config --global core.hooksPath ~/.claude/git-hooks
```

This makes `commit-msg`, `pre-commit`, `pre-merge-commit` and `pre-push` (copied in step 1)
run in **every repository on this machine** — and it **replaces any hooks that repo already has** in its own
`.git/hooks/`, silently. That's the sharp edge: only do this if you want it everywhere.

`pre-push` checks two things. First, the **identity** of every commit the push would add —
author and committer alike. This is where a `git rebase` is caught: a rebase replays commits
without running `pre-commit` or `commit-msg` on any of them, so `GIT_COMMITTER_NAME=… git
rebase` (and `git commit --author="…"`, which never reaches the author check either) used to
reach the remote unseen. An author or committer naming Claude/Anthropic is refused always;
matching `AUTHOR=` in `hooks/backup.conf` is required only when that line exists, with the
same per-repo opt-out as `pre-commit` (`git config --local hooks.identity false`). Only what
the push ADDS is judged, never history the remote already has.

Second, the type-check — and that one will not run in a repo unless the repo opts in: without
it, a pushed repo's own `package.json` would otherwise run whatever its `scripts.typecheck`
says on your machine, just because you cloned or forked it. Opt in per repo with:

```bash
git config --local hooks.typecheck true
```

`pre-merge-commit` runs `pre-commit`'s privacy check on a **merge** commit, which no
`pre-commit` hook ever sees — without it, `git merge --no-ff some-branch` lands every line
of that branch with no privacy check at all. **Stated plainly: a fast-forward merge cannot
be hooked.** It writes no commit, so git runs nothing; that is git's design, not a gap in
this script. It matters less than it sounds: a fast-forward only moves the branch pointer
onto commits that were themselves made with `git commit`, and each of those already passed
`pre-commit` when it was written. The case to watch is a merge of commits made on **another
machine** (a pull, a PR merge) — run the full privacy sweep before any public step rather
than trusting a hook for that.

`pre-commit` also caps a root `CLAUDE.md` by word count (4000 words if the repo's top level
is `$HOME/.claude`, 5750 otherwise; override with `RULES_CAP_OK=1 git commit ...`) — a
rulebook that grows without limit stops being read.

To undo:

```bash
git config --global --unset core.hooksPath
```

---

## Checking it worked

Open a **new** session and ask:

> what process rules are you working under?

If it lists them back, the hook is firing. If it says it can't see them, the section heading
in `~/.claude/CLAUDE.md` has probably been renamed — the hook looks for the exact text
`## PROCESS RULES (enforced)`.

Then run the hook self-test:

```bash
bash ~/.claude/hooks/test-hooks.sh
```

Expect its final line to say something like `... passed, 0 failed`. Any failed count above
zero means one of the hooks above isn't wired the way this script expects — read its output,
it names which one.

## Undoing it

Everything replaced is in `~/.claude/.setup-backup-<timestamp>/`. To switch the setup off
without deleting anything, remove the `hooks` entries you added from
`~/.claude/settings.json`. To disable just the backup hook, delete
`~/.claude/hooks/backup.conf` — the script exits immediately without it.

To turn off just the multi-chat coordination group, remove its four `hooks` entries from
`~/.claude/settings.json` (or simplest: never create `~/.claude/hooks/state-check.conf` —
all four stay inert without it).

To turn off the git hooks step: `git config --global --unset core.hooksPath` — the files stay
at `~/.claude/git-hooks/`, just unwired from every repo. The new files themselves, if you want
them gone entirely: `~/.claude/hooks/clock-in-context.sh`, `owner-card.md`,
`guard-lib.sh`, `block-dangerous-git.sh`, `commit-pathspec-guard.sh`, `heavy-suite-guard.sh`,
`override-ledger.sh`, `gate-guard.sh`, `channel-size-guard.sh`, `channel-provenance-pre.sh`,
`channel-provenance-post.sh`, `provenance.py`, `doorman.sh`, `stop-state-check.sh`,
`channel-size-post.sh`, `heavy-suite.conf`, `test-hooks.sh`, `test-helper-ledger.sh`,
`test-rules-cap.sh`, `.redaction-names.local`, and
`~/.claude/git-hooks/{commit-msg,pre-commit,pre-merge-commit,pre-push}`.
