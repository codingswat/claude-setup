# A Claude Code setup you can actually run

A real, daily-used Claude Code configuration: a rulebook that gets **enforced by hooks**
instead of hoped for, a project template, a plain-English glossary, and the pattern for
running several Claude chats on one codebase without them overwriting each other.

It is not a framework and not a best-practices whitepaper. It is the actual files, grown one
incident at a time. Every rule in it exists because something went wrong once.

---

## Install

```bash
git clone https://github.com/codingswat/claude-setup.git
cd claude-setup
./install.sh
```

Then open a **new** Claude Code session and ask it *"what process rules are you working
under?"* — if it lists them back, you're live.

**Or let Claude do it:** open a session in the cloned folder and say *"set this up for me"*.
The repo carries its own `CLAUDE.md`, so Claude knows what to install and will then walk you
through filling in your rulebook — which is the part that actually matters.

Nothing is deleted, anything overwritten is backed up first, and the sharp-edged auto-backup
hook is off unless you ask for it. The rulebook it installs is a form, but not an empty one —
its starter rules take effect immediately, so read them before your next session. Full detail, including how to do it all by hand:
[INSTALL.md](INSTALL.md).

---

## Why this one might interest you

Most AI-coding setups you'll find were written by senior engineers for senior engineers. This
one answers a different question:

> **How do you stay safely in control of AI-written software when you can't fully read the
> code yourself?**

The answer, in one line: *plain language, enforced process rules, evidence instead of
promises, and a paper trail for everything.*

---

## The six ideas worth stealing

**1. Rules are enforced by hooks, not hoped for.** A `CLAUDE.md` is advisory — over a long
session a model can drift away from it. The SessionStart hook re-asserts the rules every
single session, whatever else is happening. Anything that must happen *every time* belongs in
a script, not a sentence.

**2. Evidence, not assertions.** "It's done" proves nothing. Sessions must paste real output —
test results, `git log`, the running app's address. Every feature needs a test that can fail,
proven once by deliberately breaking it. Headless tests have passed while the actual window
was broken, so anything visual gets checked in a real window.

**3. A permission model in plain words.** A question ("thoughts?") gets an answer, not an
action. A clear go covers the whole job — no permission-nagging per step — with a short closed
list of things that always come back for approval: deleting your files, money, going public,
scope growth, reversing a settled decision.

**4. The setup improves itself at the moment of failure.** When a session does something wrong
and you correct it, the correction gets proposed as a new rule *right then*, in your own
words, with the story of what happened attached. A rule with its failure behind it survives.
A rule without one gets quietly ignored.

**5. Everything is written for a non-technical reader.** Rules, explanations, commit messages.
If you can't understand your own setup, you can't trust it.

**6. Skills are cherry-picked, not installed wholesale.** Whole plugin packs bring overlapping
skills that compete for the same tasks. Single files, copied in and reworded to fit, keep one
clear owner per job.

---

## What's in here

Read them in this order if you're reading rather than installing.

| File | What it is |
|---|---|
| **[TEMPLATE-CLAUDE.md](TEMPLATE-CLAUDE.md)** | **Start here.** The rulebook as a form: sections to fill in, each saying what to write and what changes when you do — plus 15 starter rules that are **live from your next session**, including two that let Claude commit and push on its own. Read those before you keep them. This is what the installer puts at `~/.claude/CLAUDE.md`. |
| [CLAUDE-global.md](CLAUDE-global.md) | A real, lived-in rulebook — 25 numbered rules in the order they were earned. Borrow from it; don't adopt it wholesale. |
| [MULTI-CHAT-ROLES.md](MULTI-CHAT-ROLES.md) | Running several Claude chats on one codebase: five roles, which model each gets, and the coordination rules that stop them overwriting each other. |
| [hooks/check-claude-md.sh](hooks/check-claude-md.sh) | The SessionStart hook. Re-asserts the rules every session, and interviews you for a new project's `CLAUDE.md` when one is missing. |
| [hooks/auto-backup.sh](hooks/auto-backup.sh) | The Stop hook. Auto-commits and pushes config changes. **Optional and sharp** — read its header and the warning in [INSTALL.md](INSTALL.md) before enabling it. |
| [TEMPLATE-project-CLAUDE.md](TEMPLATE-project-CLAUDE.md) | The per-project rulebook, as a form. What belongs here versus in the global file. |
| [GLOSSARY.md](GLOSSARY.md) | Every technical term ever explained to me, one plain-English line each. Built one line at a time; my substitute for a CS degree. |
| [project-template/](project-template/) | Starter files every new project gets: a gitignore that keeps secrets out, an empty decision log, a specs folder, a minimal README. |
| [skills/](skills/) | Four skills cherry-picked from bigger packs — see [skills/ATTRIBUTION.md](skills/ATTRIBUTION.md). |
| [DECISIONS.md](DECISIONS.md) | This repo's own decision log, kept in the format the rules require. The format, demonstrated on itself. |

---

## What is deliberately not here

**The personal half.** The sections describing one particular person, machine and project have
been stripped out and replaced with notes pointing at the blank template. That isn't only
privacy hygiene — a rulebook full of *someone else's* preferences is worse than no rulebook,
because you inherit their answers without noticing.

**The skills packs I run alongside this.** They are installed plugins, auto-updated from their
authors' repositories, so republishing copies would only hand you a stale fork. Install them
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
2. **Start with fewer rules than you think.** The 25 in `CLAUDE-global.md` accumulated one
   real failure at a time. Adopting all of them on day one is cargo-culting. Take the
   *pattern* — hooks, evidence, rule-capture — and let your own list grow from things that
   actually annoy you.
3. **Keep your machine-specific notes private.** A gotchas list for your own computer is a
   great idea and saves whole sessions. Publishing one attached to a public identity is not.
4. **Decide about the backup hook deliberately, not by default.** It is genuinely useful and
   it pushes without showing you a diff. [INSTALL.md](INSTALL.md) sets out the trade-off in
   full.

---

## Sources that shaped it

- [Anthropic's Claude Code best practices](https://code.claude.com/docs/en/best-practices)
- [obra/superpowers](https://github.com/obra/superpowers) — the process-skills pack this runs
  alongside
- [mattpocock/skills](https://github.com/mattpocock/skills) and
  [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) — sources of the
  cherry-picked skills

## License

My files: MIT ([LICENSE](LICENSE)). The skills in `skills/` are MIT by their original
authors — see [skills/ATTRIBUTION.md](skills/ATTRIBUTION.md).
