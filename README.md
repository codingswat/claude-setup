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

Tested on macOS. The installer and the hook test suite were also smoke-tested once on Linux, in a cloud sandbox, on 20 September 2026: the installer ran twice against an empty home folder without duplicating a hook entry, and the suite passed all 114 cases. The 29 September refresh of the guards and installer was run on macOS only; its Linux-specific branches have not been run.

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

## The eight ideas worth stealing

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
A helper starts with only its brief, so every brief carries the privacy, secrets and
authorship lines word for word.

**8. One path from an idea to landed code.** Nine steps — idea, research, decide, plan, build
test-first, review, land, deploy, look back — in a one-page map. Each step's detail lives in
the skill for that step, which loads only when the step starts, so the rulebook every session
reads stays short. A chat copies the steps into its own to-do list, and a skipped step stays
there with its reason.

---

## What's in here

Read them in this order if you're reading rather than installing.

| File | What it is | Read time |
|---|---|---|
| **[HOW-I-WORK.md](HOW-I-WORK.md)** | **Start here.** The daily loop: the card every chat answers in, the control words, what a "yes" covers, the paper trail habits. | 10 min |
| [LESSONS.md](LESSONS.md) | The rules as lessons — 62 of them, each with the incident that taught it, the sentence to paste into your own rulebook, and what enforces it. | 25 min |
| [MULTI-CHAT-ROLES.md](MULTI-CHAT-ROLES.md) | Running several Claude chats on one codebase: five roles, one private folder each, the files they coordinate through, and the one commander. | 10 min |
| [GLOSSARY.md](GLOSSARY.md) | Every technical term ever explained to me, one plain-English line each. My substitute for a CS degree. | as needed |
| [TEMPLATE-CLAUDE.md](TEMPLATE-CLAUDE.md) | The rulebook as a form: sections to fill in, each saying what changes when you do, plus 18 starter rules that are live from your next session. This is what the installer puts at `~/.claude/CLAUDE.md`. | 10 min |
| [TEMPLATE-coding-CLAUDE.md](TEMPLATE-coding-CLAUDE.md) | The coding rules for every project in your projects folder: the nine-step map from an idea to landed code, each step pointing at the skill that runs it. You copy it into that folder as `CLAUDE.md`. | 3 min |
| [TEMPLATE-project-CLAUDE.md](TEMPLATE-project-CLAUDE.md) | The per-project rulebook, as a form. | 5 min |
| [hooks/](hooks/) | The scripts that enforce the rules: the rules injector, the card injector, the dangerous-git blocker (which also refuses switching the git hooks off, the going-public commands, and deleting a remote branch that is not merged yet), the bare-commit guard, a guard that refuses to start a helper agent unless the launch names which model it runs on, the heavy-test-suite guard (also refuses stopping programs by name, such as `pkill`, and starting a test run when free memory is low, and recognises many more spellings of a test run), the gate guard (refuses a test run piped into a reader and then committed on the back of it, raced against a commit with `;`, or waited on with a log-polling loop instead of the job itself, and a `git push`, `git rebase` or any `git pull` piped into a reader; it knows `yarn` and `pnpm` test runs too), a growth watcher for shared files like a running notes doc that re-measures after every write, the auto-backup with a secret scan, a ledger that records what each helper agent cost, an override-use ledger that logs every time you tell a hook to stand down — plus an opt-in group for running more than one Claude Code session on the same repo (an edit-provenance pair that tracks who wrote which line of a shared file, a doorman that holds back a message sent to a session that is already at its context limit, and an end-of-turn check that a session actually updated its state file, and asks a long-running one to wrap up; chats that share one folder can opt in with a small `state-roles.tsv` file) — plus two more opt-in single hooks: an idle-chat warning (holds one message after a long idle, because the chat's saved copy has expired; its config file shows the keys and carries an example price) and a chapter reminder (Claude desktop app only) — and a test suite of over a thousand cases that proves each one fires and each one stays quiet. | — |
| [git-hooks/](git-hooks/) | Four git-side guards, opt-in: commits carry your name not the assistant's, no home-directory path or listed name gets committed, a merge carries the same privacy scan as a normal commit, a commit is refused if it stages a key or token or is unusually large, and a push is type-checked first. The privacy and key scans also catch the encoded home-path form, a home path that ends at a quote or a space rather than a slash, and a home folder in a staged file's path (the shared system folders pass), ignore an external diff tool, and treat a worktree of an exceptions-listed repo as that repo; the push check ignores `git replace` stand-ins, refuses a push whose remote tip is not in your copy, judges a push from a bare repo, and has an opt-in issue-number rule for pushes to `main` (`AGENTS.md` and `GEMINI.md` count as rules files there, like `CLAUDE.md`). | — |
| [skills/](skills/) | Thirteen of my own skills plus three cherry-picked from bigger packs — and a credited list of everything else I run. See [skills/ATTRIBUTION.md](skills/ATTRIBUTION.md). Three of mine carry the coding path that the coding-rules map puts in order: `coding-method` (the nine steps from a request to landed code), `testing-method` (every check seen failing, then passing, and counted) and `going-live` (the checks before anything is deployed, made public or shared). Several of my own (`briefing-subagents`, `shared-tree-commit`, `rally`, `context-floors`, `handing-off-live-work`) only matter once you're running more than one Claude Code session on the same project — see [MULTI-CHAT-ROLES.md](MULTI-CHAT-ROLES.md) — and are optional; `summarize` shapes every report you get, so delete its folder if you don't want that. | — |
| [project-template/](project-template/) | Starter files every new project gets: a gitignore that keeps secrets out, an empty decision log, a specs folder, a minimal README. Note: the installed `domain-modeling` skill keeps its own decision log in ADR format (`docs/adr/`) — pick one decision-log convention per project. | — |
| [DECISIONS.md](DECISIONS.md) | A few entries from this repo's own decision log, to show the format. | 2 min |

---

## What is deliberately not here

**The personal half.** Who I am, my machine, my projects. Not only privacy hygiene — a
rulebook full of *someone else's* preferences is worse than no rulebook, because you inherit
their answers without noticing.

**My rulebook, verbatim.** It is around thirty rules written in my voice for my situation. What
transfers is the lesson behind each, so that is what [LESSONS.md](LESSONS.md) carries.

**Project-specific hooks.** Two install-layout hooks, wired to one project's file names and
layout, stay private; their ideas are described in the multi-chat guide, and their generic
cousins ship.

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
