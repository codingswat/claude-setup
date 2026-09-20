# This repo — instructions for the Claude Code session reading it

**What this repo is:** a working Claude Code configuration — a rulebook, 7 hook scripts and 3
git hooks, a project template, a glossary and a few skills. Someone has just opened a session
here because they want it set up on their machine.

**Your job in this session is to install it and then help them personalise it.** Not to build
anything. If they ask for something else entirely, do that instead — this is a starting
assumption, not a constraint.

---

## What to do first

Greet them briefly and offer the install. Say plainly what it will touch:

> This will add hook scripts, a project template and some skills under `~/.claude`, and
> register the hooks (seven entries) in `~/.claude/settings.json`. Anything it would overwrite gets backed up
> first, and nothing is deleted. The two sharp pieces — the auto-backup hook and the
> machine-wide git hooks — are off unless you ask for them.

Then, with their go-ahead, run it and show them the output:

```bash
./install.sh
```

If they would rather not run a script, everything it does is written out step by step in
[INSTALL.md](INSTALL.md) — walk them through it manually instead.

**Run the script; do not reimplement it.** It handles backups, idempotency and JSON merging
carefully, and a hand-rolled equivalent will get one of those wrong.

## After it runs

The installer puts **a rulebook that is a form but not empty** at `~/.claude/CLAUDE.md` (or
leaves theirs alone if they already had one): its starter rules, including standing permission
to commit and push, are live from the next session — read them with the person. Filling in the
rest of the form is still the part that actually matters:

1. **Open `~/.claude/CLAUDE.md` and walk them through it section by section.** Ask the
   questions in it conversationally rather than telling them to go and write an essay. Write
   their answers into the file for them as they talk.
2. **Push hardest on "How to talk to me" and "Context about me".** These change every future
   session more than any rule does. The single most valuable thing to extract is an honest
   answer to *where does your technical knowledge stop?* — most people undersell this and
   then get explanations pitched over their head forever.
3. **Do not invent rules for them.** A rule they did not ask for is a guess, and guesses get
   ignored. If they want more than the starter set, point them at
   [LESSONS.md](LESSONS.md) — the rules as lessons, each with the incident behind it — and let
   them pick.
4. **Privacy check before you finish.** If this file will be backed up or shared, remind them:
   write what changes Claude's behaviour, not who they are. Legal name, address, employer,
   hostname and exact folder layout change nothing about the code, and cannot be taken back
   once published.

## Then tell them the three things that are easy to miss

- **Hooks load at session start.** The current session will not see them. They need to open a
  new one before anything is live.
- **A way to check it worked:** in a fresh session, ask *"what process rules are you working
  under?"* If it can list them back, the setup is live. For the guards, run
  `bash ~/.claude/hooks/test-hooks.sh` and expect its last line to say `0 failed`.
- **The card is theirs to rewrite.** `~/.claude/hooks/owner-card.md` is the reply shape every
  chat will use, injected on every prompt; it ships in a neutral voice and should end up in
  theirs. Offer to reword it with them once the rulebook is done.

## Also worth mentioning, briefly

- [MULTI-CHAT-ROLES.md](MULTI-CHAT-ROLES.md) — running several Claude chats on one codebase
  without them overwriting each other. Only relevant once a project outgrows one session;
  mention it exists, don't walk them through it unprompted.
- The auto-backup hook is genuinely useful *and* genuinely sharp — it pushes without showing a
  diff. If they turn it on, make sure the allowlist `~/.claude/.gitignore` went in first and
  that the backup repo is private.

## House style while doing this

Plain English. Explain a term the moment you use it, in the same sentence. Short answers. If
something has a downside, say it up front rather than after they hit it.
