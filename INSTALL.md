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
| `~/.claude/hooks/` | `check-claude-md.sh`, `auto-backup.sh`, `interview.md`, `clock-in-context.sh`, `block-dangerous-git.sh`, `commit-pathspec-guard.sh`, `heavy-suite-guard.sh` and `test-hooks.sh` are copied in (backed up first if different). `owner-card.md` and `heavy-suite.conf` are copied **only if you don't already have them** — the first you personalise, the second is written from `heavy-suite.conf.example`; their config files (`backup.conf`, `project-roots.conf`) are written fresh from your answers |
| `~/.claude/git-hooks/` | `commit-msg`, `pre-commit`, `pre-push` are copied in and made executable. They sit inert here until you opt in below — they don't run anywhere until then |
| `~/.claude/CLAUDE.md` | The starter rulebook is installed **only if you don't already have one**. It is a fill-in form, but its 15 rules are active from your next session — rules 1 and 2 grant Claude standing permission to commit, push and merge to `main` |
| `~/.claude/project-template/` | Starter files for new projects; existing files are never replaced |
| `~/.claude/skills/` | The four skills; any skill folder of the same name is left alone |
| `~/.claude/settings.json` | Hook registrations are **merged in** — `SessionStart` and `UserPromptSubmit` (the rulebook check and the owner-card loader) and `PreToolUse` matched to the `Bash` tool (the three git-safety guards); everything else is preserved |
| `~/.claude/.gitignore` | Only if you opt into the backup hook, and only if you don't have one |
| git's **global** config | Only if you opt into the "git hooks" step: sets `core.hooksPath` to `~/.claude/git-hooks`, which then applies to every repository on this machine |

**Nothing is deleted.** Anything that would be overwritten is copied to
`~/.claude/.setup-backup-<timestamp>/` first. Re-running the script is safe.

**The auto-backup hook is off by default** and the script asks before setting it up.

Requires `bash`, and either `node` or `python3` for the settings merge. Claude Code already
brings Node, so this is almost always satisfied.

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
   hooks/clock-in-context.sh hooks/block-dangerous-git.sh \
   hooks/commit-pathspec-guard.sh hooks/heavy-suite-guard.sh hooks/test-hooks.sh \
   ~/.claude/hooks/
chmod +x ~/.claude/hooks/check-claude-md.sh ~/.claude/hooks/auto-backup.sh \
         ~/.claude/hooks/clock-in-context.sh ~/.claude/hooks/block-dangerous-git.sh \
         ~/.claude/hooks/commit-pathspec-guard.sh ~/.claude/hooks/heavy-suite-guard.sh \
         ~/.claude/hooks/test-hooks.sh
cp -Rn project-template/. ~/.claude/project-template/
cp -Rn skills/. ~/.claude/skills/

# Two files you personalise — copy only if you don't already have them:
[ -f ~/.claude/hooks/owner-card.md ]    || cp hooks/owner-card.md ~/.claude/hooks/owner-card.md
[ -f ~/.claude/hooks/heavy-suite.conf ] || cp hooks/heavy-suite.conf.example ~/.claude/hooks/heavy-suite.conf

# The git hooks proper — copied in and made executable, but inert until step 7:
cp git-hooks/commit-msg git-hooks/pre-commit git-hooks/pre-push ~/.claude/git-hooks/
chmod +x ~/.claude/git-hooks/commit-msg ~/.claude/git-hooks/pre-commit ~/.claude/git-hooks/pre-push
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

Then the three Bash-only guards go under `PreToolUse`. Each carries a `"matcher"` on the
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
          { "type": "command", "command": "/bin/bash \"$HOME/.claude/hooks/heavy-suite-guard.sh\"" } ] }
    ]
  }
}
```

Merge these arrays into whatever `hooks` block already exists — don't replace it.

### 7. Optional: git hooks for every repo on this machine

Read this before running it:

```bash
git config --global core.hooksPath ~/.claude/git-hooks
```

This makes `commit-msg`, `pre-commit` and `pre-push` (copied in step 1) run in **every
repository on this machine** — and it **replaces any hooks that repo already has** in its own
`.git/hooks/`, silently. That's the sharp edge: only do this if you want it everywhere.

`pre-push` will not type-check a repo unless that repo opts in: without it, a pushed repo's
own `package.json` would otherwise run whatever its `scripts.typecheck` says on your machine,
just because you cloned or forked it. Opt in per repo with:

```bash
git config --local hooks.typecheck true
```

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

To turn off the git hooks step: `git config --global --unset core.hooksPath` — the files stay
at `~/.claude/git-hooks/`, just unwired from every repo. The new files themselves, if you want
them gone entirely: `~/.claude/hooks/clock-in-context.sh`, `owner-card.md`,
`block-dangerous-git.sh`, `commit-pathspec-guard.sh`, `heavy-suite-guard.sh`,
`heavy-suite.conf`, `test-hooks.sh`, and `~/.claude/git-hooks/{commit-msg,pre-commit,pre-push}`.
