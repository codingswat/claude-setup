# Working with me — standing brief for Claude

**Where this file goes:** `~/.claude/CLAUDE.md`. Claude Code reads it automatically at the
start of every session, in every project. You never paste it anywhere.

**How to use this file.** It is a form. Sections marked **`FILL THIS IN`** are blank on
purpose — they are the parts that make Claude work like *your* colleague instead of a
generic assistant. Each one says what to write and what changes when you write it.
Everything else is a working starter set you can keep, edit, or delete.

**Two things worth knowing before you start:**

1. **Write in your own voice, and quote yourself.** The most effective lines in a rulebook
   are the ones that record what you actually said when something went wrong. "Added after
   a branch got deleted with unmerged work in it" carries more weight than "be careful with
   branches", because it tells Claude *what failure it is preventing*.
2. **Do not fill in everything today.** A rule you invented in advance is a guess. A rule
   you wrote right after being annoyed by something is a fact. Start with the sections
   below, and let the rest grow one real incident at a time.

---

## Read nothing else? Read this.

0. **What I say in chat always overrides these files.** These are my defaults, not my ceiling.
1. **Plain English.** Explain the thing, then use the word. No unexplained jargon, ever.
2. **"yes go ahead" means go.** Don't ask permission for every step afterwards.
3. **"choose for me" means choose.** Pick the sensible default, say what and why in one line,
   keep moving.
4. **Stop means stop.** If I interrupt mid-flight, stop immediately — don't quietly finish first.

---

## PROCESS RULES (enforced)

> **Don't rename this heading.** The SessionStart hook looks for the exact text
> `## PROCESS RULES (enforced)` and re-asserts this section at the start of every session.
> Rename it and the hook will warn you loudly, which is the intended behaviour — but the
> re-assertion stops until you fix it.
>
> **Why a hook at all?** A file Claude *reads* can be drifted away from over a long session.
> A hook fires every single time, whatever else is going on. Anything that must happen
> *every* time belongs in a script, not a sentence.

These are a starter set — deliberately fewer than a mature rulebook. Add yours as you earn
them.

> **Read rules 1 and 2 before you keep them.** They tell Claude to commit, push, merge to
> `main`, and delete leftover branches on its own, in every project, without asking again.
> That is deliberate — it is what stops work being lost — but it is a real grant of autonomy
> and it starts the moment this file is in place. If you would rather approve each push, edit
> or delete those two rules now, before your next session.

1. **Commit and push per working feature.** One feature = one commit, pushed straight away.
   Work that only exists on your laptop is work you can lose.
2. **Land finished work on `main`.** Merge finished, tested work and push. No work parked on
   side branches; delete leftovers.
3. **Verify with evidence, don't assert.** Run the tests and paste the real output. "It's
   done" proves nothing. If a check cannot actually fail, it isn't a check — prove it once by
   deliberately breaking the code and watching the test go red.
4. **Show me it running, not just passing.** Give me the exact URL or file, and say if it
   needs a server started first. Green tests are not the same as a working app.
5. **Add alongside; don't replace what works.** If replacing is genuinely better, argue for it
   and let me decide.
6. **Clean up after yourself.** Temporary servers, scratch files, test folders, stale
   branches. Tell me if something is still running.
7. **Never delete files I made without asking first.**
8. **Back up the database before any migration.** Git protects code, not data. A code
   rollback is not data recovery.
9. **Two failed fix attempts = stop.** Roll back, find the root cause, and explain it to me in
   plain language before touching code again.
10. **Secrets never go in code.** API keys and passwords live in `.env`, gitignored — and
    remind me they must be set separately on the hosting service at deploy time.
11. **Keep a decision log.** Every project gets a `DECISIONS.md`. Significant choice =
    three lines: what was decided, why, and what it rules out. Check it before proposing
    changes so settled decisions aren't re-argued.
12. **No feature is done without a test that can fail.** Anything visual also gets checked in
    a real window — headless tests have passed while the actual screen was broken.
13. **Don't act unless it's clear I want an action started.** A question ("thoughts?",
    "what do you think?", "review this") asks for an answer — recommend, then wait. If a
    message could mean "discuss" or "do", it means discuss.
14. **Once I've said go, don't stop while the road is clear.** Permission covers the whole
    job, not each step. If you need my input, ask — then carry on with everything that
    doesn't depend on the answer, and batch the questions rather than asking one at a time.
15. **Security review before anything goes live.** Before a deploy, before a repo goes public,
    before an app is shared beyond my own machine: run a security review and fix what it
    finds. AI writes working code faster than it writes safe code; this is the checkpoint
    that catches the difference.

<!-- FILL THIS IN (over time)
Add your own rules here as you earn them. The format that works: the rule in bold, then
the reason, then — if it came from something going wrong — one line about what happened.

Why it matters: a rule with its story attached survives. A rule without one gets argued
with, softened, or quietly ignored, because nothing tells Claude what it is protecting.
-->

---

## How to talk to me

**`FILL THIS IN` — this is the single highest-value section in the file.**

Write down how you want to be spoken to, especially where you need things simplified.

Things worth answering:

- How technical are you, honestly? Where exactly does your knowledge stop?
- Should unfamiliar terms be explained the moment they appear, or do you want them plain?
- Long explanations or short ones? Tables or paragraphs?
- Do you type in short lowercase fragments? Say so — otherwise a four-word message can read
  as casual when you meant it as an instruction.
- Do you send new instructions while Claude is still working? Say how it should handle that.

**Why filling this in makes Claude better:** by default Claude pitches its explanations at
whoever it guesses you are, and it guesses from your code. If your tooling looks advanced it
will assume you can read everything it writes — which is exactly wrong for people who are
strong in one area and new in another. Naming the gap out loud is what stops it from
explaining nothing.

*A worked example of a line that does real work:*

> "I'm specific about modern web tooling, but git and deployment terminology needs plain
> explanation. Don't assume the two go together."

That one sentence changes every future session.

<!-- Write yours below this line. -->


---

## How I make decisions

**`FILL THIS IN`**

This section is about **permission** — when Claude should act on its own and when it must
stop and ask.

Things worth answering:

- What does broad approval mean to you? Can Claude take a job all the way to merged, or do
  you want to see it first?
- What is the short, closed list of things that always come back to you? (Common ones:
  deleting your files, spending money, publishing anything public, the scope growing much
  bigger, reversing something already decided.)
- When you say "choose for me", do you want the choice made and explained — or offered back?
- Do you want pushback? Say so explicitly if you do; most people say they want it and then
  phrase requests in a way that discourages it.

**Why filling this in makes Claude better:** without it, Claude picks a middle setting and
gets it wrong in both directions — asking permission for trivial steps while quietly making
one big decision you would have wanted a say in. A written permission model fixes both at
once.

<!-- Write yours below this line. -->


---

## Context about me

**`FILL THIS IN` — the part people skip, and the part that pays back most.**

This is not a biography. Everything here should change what Claude *does*.

Things worth answering:

- **The languages your product ships in.** If it is more than one, say whether the second is
  a first-class language or a translation layer — and whether text direction, sorting, or
  encoding are real requirements. This is the difference between support that works and
  support that was bolted on at the end.
- **Your operating system.** Shell, package manager, and path conventions all follow from it.
- **Your stack — and whether it is a decision or an experiment.** Say which. "We use X" and
  "I am trying X" lead to completely different advice. If versions matter, name them, and say
  they should be taken seriously rather than modernised away.
- **Where your knowledge stops.** The most useful sentence in this whole file is usually the
  one that says "I'm fluent in A but need B explained in plain words."
- **How your projects are organised** — enough for Claude to find its way, no more.

**Why filling this in makes Claude better:** every one of these turns a guess into a fact.
Without them Claude re-derives your context from whatever files happen to be open, gets it
subtly wrong, and gives advice that is correct in general and wrong for you. This is also
the section that stops the same explanation being requested session after session.

**A privacy note, and it is a real one.** This file often ends up backed up, mirrored, or
shared. Write what changes Claude's behaviour and nothing else. Your legal name, your street,
your employer, your exact folder layout, and your machine's hostname change nothing about the
code — and if this file ever becomes public, they are the parts you cannot take back.

<!-- Write yours below this line. -->


---

## This machine — setup gotchas

**`FILL THIS IN`, and keep this section private.**

A short list of the things about *this specific computer* that have cost you time. Real
examples of the kind of thing that belongs here:

- A config file that is owned by root and silently fails when a tool tries to write it.
- Two versions of the same language installed, where one has a bug the other doesn't.
- A tool installed somewhere unusual, because the normal package manager isn't available.

**Why filling this in makes Claude better:** these are the failures that waste a whole
session. Claude runs the standard command, it fails in a way that looks like your code's
fault, and you both go looking in the wrong place. One line here prevents that permanently.

**Why to keep it private:** a detailed description of one machine's configuration, attached
to a public identity, is useful to exactly one kind of reader. Keep the *pattern* — a
gotchas list is a great idea. Never publish the contents.

<!-- Write yours below this line. -->


---

## Keeping this file alive

- **Only observed behaviour goes in — no guesses.** If something here turns out to be wrong,
  correct it rather than working around it.
- **Keep it short.** Anything specific to one project belongs in that project's own
  `CLAUDE.md`, not here. This file is loaded into every session, so every line costs
  attention in every conversation you ever have.
- **When Claude observes something new about how you work — a preference, a correction, a
  gotcha — it should propose saving it at that moment, not at the end of the session.**
  The SessionStart hook already instructs it to do this. Say yes often; that is how this file
  gets good.

**Last updated:** <date you last changed this>
