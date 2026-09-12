# A Claude Code setup you can actually run

I am not a programmer. I direct all my coding through Claude Code and cannot fully read what
it writes, so the process has to catch what I would miss. This repo is that process: the way
of working, the lessons it cost me, and the actual files — hooks, templates, skills — that
enforce them, with an installer that puts them on your machine.

It is not a framework and not a best-practices whitepaper. Every rule in it exists because
something went wrong once.

---

## Install

```bash
git clone https://github.com/codingswat/claude-setup.git
cd claude-setup
./install.sh
```

Then open a **new** Claude Code session and ask it *"what process rules are you working
under?"* — if it lists them back, you're live.

Tested on macOS; Linux should work but is unverified.

**Or let Claude do it:** open a session in the cloned folder and say *"set this up for me"*.
The repo carries its own `CLAUDE.md`, so Claude knows what to install and will then walk you
through filling in your rulebook — which is the part that actually matters.

Nothing is deleted, anything overwritten is backed up first, and two sharp-edged pieces
(the auto-backup hook and the machine-wide git hooks) are off unless you say yes. A third is
on by default: the rulebook's own first two starter rules grant standing permission to commit,
push, and merge to `main`, live from your very next session — read them before that session
starts ([TEMPLATE-CLAUDE.md](TEMPLATE-CLAUDE.md)). Full detail, including how to do it all
by hand: [INSTALL.md](INSTALL.md).

---

## Why this one might interest you

Most AI-coding setups you'll find were written by senior engineers for senior engineers. This
one answers a different question:

> **How do you stay safely in control of AI-written software when you can't fully read the
> code yourself?**

The answer, in one line: *plain language, enforced process rules, evidence instead of
promises, and a paper trail for everything.*

---

## The seven ideas worth stealing

**1. Rules are enforced by hooks, not hoped for.** A `CLAUDE.md` is advisory — over a long
session a model drifts away from it. A hook is a small script Claude Code runs itself, every
time, whatever else is happening. Anything that must happen *every time* belongs in a script,
not a sentence.

**2. Evidence, not assertions.** "It's done" proves nothing. Sessions paste real output — test
results, the running app's address. Every feature needs a test that can fail, proven both
ways: broken once to watch it go red, correct once to watch it stay green.

**3. A permission model in plain words.** A question ("thoughts?") gets an answer, not an
action. A clear go covers the whole job — no permission-nagging per step — with a short closed
list of things that always come back for approval: deleting your files, money, going public,
scope growth, reversing a settled decision, anything irreversible.

**4. One reply shape, always.** Every chat reports back in the same card: a status light,
the problem, the story, the result, then "needs my input". I read only the chat, never a file,
and my eye always knows where to look.

**5. The setup improves itself at the moment of failure.** When a session does something
wrong and you correct it, the correction gets proposed as a new rule *right then*, in your own
words, with the story of what happened attached. A rule with its failure behind it survives.

**6. Everything is written for a non-technical reader.** Rules, explanations, commit
messages. If you can't understand your own setup, you can't trust it.

**7. The cheapest model that can do the job.** Mechanical work goes to a small model, choices
to a mid-size one, verdicts to the best. Spending more than a task needs is waste, not caution.

---

## What's in here

Read them in this order if you're reading rather than installing.

| File | What it is | Read time |
|---|---|---|
| **[HOW-I-WORK.md](HOW-I-WORK.md)** | **Start here.** The daily loop: the card every chat answers in, the control words, what a "yes" covers, the paper trail habits. | 10 min |
| [LESSONS.md](LESSONS.md) | The rules as lessons — 28 of them, each with the incident that taught it, the sentence to paste into your own rulebook, and what enforces it. | 15 min |
| [MULTI-CHAT-ROLES.md](MULTI-CHAT-ROLES.md) | Running several Claude chats on one codebase: five roles, one private folder each, the files they coordinate through, and the one commander. | 10 min |
| [GLOSSARY.md](GLOSSARY.md) | Every technical term ever explained to me, one plain-English line each. My substitute for a CS degree. | as needed |
| [TEMPLATE-CLAUDE.md](TEMPLATE-CLAUDE.md) | The rulebook as a form: sections to fill in, each saying what changes when you do, plus 17 starter rules that are live from your next session. This is what the installer puts at `~/.claude/CLAUDE.md`. | 10 min |
| [TEMPLATE-project-CLAUDE.md](TEMPLATE-project-CLAUDE.md) | The per-project rulebook, as a form. | 5 min |
| [hooks/](hooks/) | The scripts that enforce the rules: the rules injector, the card injector, the dangerous-git blocker, the bare-commit guard, the heavy-test-suite guard, the auto-backup with a secret scan — and a test script that proves each one fires and each one stays quiet. | — |
| [git-hooks/](git-hooks/) | Three git-side guards, opt-in: commits carry your name not the assistant's, no home-directory path or listed name gets committed, and a push is type-checked first. | — |
| [skills/](skills/) | My own skills plus four cherry-picked from bigger packs — and a credited list of everything else I run. See [skills/ATTRIBUTION.md](skills/ATTRIBUTION.md). Four of my own (`summarize`, `overnight`, `handing-off-live-work`, `handover`) come from a multi-chat way of working and are optional — `summarize` shapes every report you get, so delete its folder if you don't want that. | — |
| [project-template/](project-template/) | Starter files every new project gets: a gitignore that keeps secrets out, an empty decision log, a specs folder, a minimal README. Note: the installed `domain-modeling` skill keeps its own decision log in ADR format (`docs/adr/`) — pick one decision-log convention per project. | — |
| [DECISIONS.md](DECISIONS.md) | Three entries from this repo's own decision log, to show the format. | 2 min |

---

## What is deliberately not here

**The personal half.** Who I am, my machine, my projects. Not only privacy hygiene — a
rulebook full of *someone else's* preferences is worse than no rulebook, because you inherit
their answers without noticing.

**My rulebook, verbatim.** It is 28 rules written in my voice for my situation. What
transfers is the lesson behind each, so that is what [LESSONS.md](LESSONS.md) carries.

**Project-specific hooks.** The ones wired to one project's file names and layout stay
private; their ideas are described in the multi-chat guide, and their generic cousins ship.

**The skills packs I run alongside this.** They are installed plugins, auto-updated from
their authors' repositories; republishing copies would hand you a stale fork. Install them
from source instead. The big one:

```bash
claude plugin install superpowers@superpowers-marketplace
```

That is [obra/superpowers](https://github.com/obra/superpowers) — brainstorm → spec → plan →
implement-with-tests. The rulebook references that workflow; with the plugin installed, those
references just work.

---

## Adapting it

1. **Fill in `~/.claude/CLAUDE.md`.** Nothing else matters as much. The template tells you
   what each section changes.
2. **Start with fewer rules than you think.** Mine accumulated one real failure at a time.
   Adopting all of them on day one is cargo-culting. Take the *pattern* — hooks, evidence,
   rule-capture — and let your own list grow from things that actually annoy you.
3. **Rewrite the card in your voice.** `hooks/owner-card.md` is injected into every prompt;
   it should sound like you.
4. **Keep your machine-specific notes private.** A gotchas list for your own computer saves
   whole sessions. Publishing one attached to a public identity does not.
5. **Decide about the two sharp pieces deliberately.** The backup hook pushes without
   showing you a diff; the git hooks apply to every repository on the machine.
   [INSTALL.md](INSTALL.md) sets out both trade-offs in full.

---

## Sources that shaped it

- [Anthropic's Claude Code best practices](https://code.claude.com/docs/en/best-practices)
- [obra/superpowers](https://github.com/obra/superpowers) — the process-skills pack this runs
  alongside
- The authors credited in [skills/ATTRIBUTION.md](skills/ATTRIBUTION.md)

## License

My files: MIT ([LICENSE](LICENSE)). The cherry-picked skills in `skills/` are MIT by their
original authors — see [skills/ATTRIBUTION.md](skills/ATTRIBUTION.md).
