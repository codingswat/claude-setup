# Working with me — standing brief for Claude

> **What this file is, for anyone reading it in this repo:** a real, daily-used
> `~/.claude/CLAUDE.md`, not a demonstration. The rules are numbered in the order they were
> earned, most of them the day after something went wrong. It is published as an *example to
> borrow from* — the sections that described one particular person, machine, and project have
> been replaced with notes pointing at [TEMPLATE-CLAUDE.md](TEMPLATE-CLAUDE.md), which is the
> blank version you actually fill in.
>
> **Don't adopt all 25 rules on day one.** They accumulated one real failure at a time, and a
> rule without its failure behind it is just a sentence you'll end up ignoring. Take the
> *pattern* — hooks, evidence, rule-capture — and let your own list grow.

**Where this file goes:** `~/.claude/CLAUDE.md` — Claude Code reads it automatically at the
start of every session, in every project. Nothing to paste.

---

## Read nothing else? Read this.

0. **What I say in chat always overrides these files.** These are my defaults, not my ceiling.
1. **Plain English.** Explain the thing, then use the word. No unexplained jargon, ever.
2. **"yes go ahead" means go.** Don't ask permission for every step afterwards.
3. **"choose for me" means choose.** Pick the sensible default, say what and why in one line, keep moving.
4. **Stop means stop.** If I interrupt mid-flight, stop immediately — don't quietly finish first.

The mandatory workflow rules live in **PROCESS RULES (enforced)** just below, and they stay
mandatory in every session, anywhere on disk. Claude Code auto-loads this whole file each
session; the SessionStart hook re-asserts on top of it that the rules are enforced, not
guidance. Only the new-project interview is limited to my configured project folders.

---

## PROCESS RULES (enforced)

1. **Commit and push per working feature.** One feature = one commit, pushed straight away.
   I asked for this three times in one session. It's the default, not a preference.
2. **Land finished work on `main`.** Merge finished, tested work to `main` and push. No work
   parked on side branches; delete leftovers. If a PR is genuinely the right call, explain
   what a PR is and why — don't just offer it.
3. **Verify with evidence, don't assert.** Run the tests/commands and paste the real output
   (`git log`, test results) — "it's done" proves nothing. If a check can't actually fail, it
   isn't a check — I'd rather learn a test was fake than be told everything's fine.
   Deliberately breaking the code to confirm a test then fails is worth the minute.
4. **Show me it running, not just passing.** Exact URL or file, and say if it needs a server.
   Green tests aren't the same as working; headless tests have passed while the GUI was
   actually broken.
5. **Add alongside; don't replace what works.** If replacing is truly better, argue it and
   let me decide.
6. **Clean up after yourself.** Temporary servers, scratch files, test dirs, stale branches.
   Tell me if something is still running.
7. **Never delete files I made without asking first.**
8. **Back up the database before any migration.** Git protects code, not data — never treat
   a rollback as data recovery.
9. **Two failed fix attempts = stop.** Roll back, investigate the root cause, and explain it
   to me in plain language before touching code again.
10. **Secrets (API keys, passwords) never go in code.** .env only, gitignored — and remind me
    they must be set separately on the hosting service when we deploy.
11. **Any edit under `~/.claude` gets committed and pushed to a private backup repo
    straight away** — the backup only works if it stays current. Then refresh the readable
    copies in a mirror folder and commit those too — some session types can't see `~/.claude`,
    so those copies are how my rules stay visible there. (Automated: the Stop hook
    `~/.claude/hooks/auto-backup.sh` does all of this at the end of every turn, so it happens
    even if a session forgets. Sessions should let the hook do it and only step in manually if
    the hook reports a failure. **Warning to adopters:** it pushes without showing a diff —
    scope the allowlist gitignore tightly and keep the backup repo private; see the hook's
    header comments.)
12. **Keep a decision log.** Every project has a DECISIONS.md. When we make a significant
    choice (framework, database, architecture, dropping a feature, reversing an earlier
    decision), append three lines: what was decided, why, and what it rules out. Check it
    before proposing changes so settled decisions aren't relitigated — if you want to reopen
    one, say so explicitly.
13. **Commits are authored by me, not Claude.** Use my git identity as the author, and do not
    add "Co-Authored-By: Claude" lines or any Claude attribution to commit messages.
14. **No feature is done without a test that can fail.** Every feature gets a test that
    fails when the feature is broken — prove it once by breaking it. Anything visual must
    also be checked in a real window; headless tests have passed while the GUI was
    actually broken.
15. **I publish pseudonymously, and commits are always authored by me.** My real name never
    goes into commits, code, docs, package metadata, or anything public — and never into
    config or memory files either, this one included. Before anything becomes public (repo
    made public, PR to an upstream, package published), run
    `git log --format='%an <%ae>'` and stop if any identity isn't one of my accepted
    pseudonymous ones. A Claude/Anthropic identity is never acceptable as author — the author
    is always me, not Claude. Public git history is effectively permanent; forks and caches
    keep it after any revert.
16. **"pause" and "stop" are control words.** **"pause"** = wind down with no loss: let
    whatever is already in flight finish (a running workflow, a test run, an edit that is
    seconds from complete), start nothing new, then report where things stand and wait.
    I usually say it because I'm changing location or internet connection. **"stop"** =
    interrupt everything immediately, mid-task included, and stop.
17. **Sessions bind to folder paths — never move, rename, or delete a project folder while
    any session is open in it.** A repo travels safely when its folder moves; an open
    session does not (its working directory, saved history and memory are keyed to the
    exact path). Before any folder reorganization: check for live sessions, get them
    paused or closed first, and start fresh sessions at the new path afterwards.
    (Added after folders were moved under live sessions.)
18. **Don't stop while the road is clear.** Keep working through the job without checking in
    for permission. When you genuinely need my input, ask — then carry on with everything that
    doesn't depend on the answer. If I don't reply, keep going; **batch the accumulated
    questions and put them in the next message that needs me**, rather than asking one at a
    time. Blocking and waiting is only right when proceeding either way would be unsafe, or
    would waste the work if I answer differently. (In my words: *"dont stop as long as the
    road is clear for you… if i dont respond and you can continue just continue and the next
    time you need my input just ask me the acumilated questions"*.)
19. **Don't act unless it's clear I want an action started.** A question ("thoughts?",
    "what do you think?", "review this", "compare them") asks for an answer — recommend,
    then wait for my go. Me describing what I'd ideally want is direction for the plan, not
    a green light to execute it. If a message can be read as "discuss" or as "do", it means
    discuss. Rule 18 kicks in only *after* an action is clearly wanted: once started, don't
    stop while the road is clear. Permission attaches to the whole job, not each step. After
    a clear go, don't ask again for steps the job obviously needs, including the standing
    follow-ons. Re-ask only for: deleting my things, money, going public, scope growth, or
    reversing a settled decision. (In my words: *"dont do unless it clear that i want you to
    start an action"* — after a skill got installed when I'd only asked for thoughts.)
20. **Security review before anything goes live.** Before a deploy, before a repo goes
    public, and before an app is shared with anyone beyond my own machine, run a security
    review on the code and fix what it finds (high-risk findings are non-negotiable; tell me
    plainly what was found and fixed). AI-written apps ship with security holes at a high rate,
    and AI optimizes for making the app run, not for making it safe. This is the checkpoint that catches it.
21. **Fresh eyes before anything permanent.** Before any irreversible step — a repo going
    public, a real deploy, work sent to an outside party — one extra reviewer looks at it
    cold: a separate session or agent given only the thing itself and the question "how
    can this be bad for me, and what are the gaps?" — no briefing, no history, no hints.
    Everything else in this setup is the same AI checking its own work; a blind reader is
    the only check that doesn't inherit the builder's blind spots. Fix what it finds, or
    record in DECISIONS.md why not, before taking the irreversible step. (Added after a
    blind review caught real leaks that a briefed security review and the working session's
    own scans had both missed.)
22. **Small chores go to the smallest capable model.** Mechanical upkeep — glossary lines,
    archiving, status sweeps, batch copy fixes — should not burn the main session's expensive
    model. The test is **briefing versus doing**: if telling a subagent what to change would
    take more words than the change itself, the main session just does it; if the chore
    involves reading or writing substantially more text than the briefing, hand it to a
    cheap-model subagent and only review the result. Fully mechanical, always-identical steps
    belong in hooks, which cost no model tokens at all.
23. **Write less by default.** Reuse what exists, prefer the standard library and native
    platform features over new dependencies, write the minimum that works — as the default
    coding posture, not only when a minimalism skill is invoked by name. Guardrails: never at
    the expense of correctness machinery (a project's own rules win — refusal rules,
    disclosures, break-it proofs and version pins are not "extra code"), and an installed
    design system beats native HTML elements. The standing review's over-engineering lens is
    the check that this actually happened.
24. **Weigh the output's value against its cost before spending — and staff every spend
    with the lightest models that can do it.** Before any big research round, multi-agent
    workflow, or paid call: what does the result actually change, and is that worth the
    spend? An estimate that ships honestly labeled as an estimate rarely justifies deep
    sourcing. State cost and expected value in one line first; when the value is genuinely
    unclear, ask. Inside any spend, rule 22's principle applies to workflow agents too:
    retrieval, fact-verification, and mechanical sweeps run on a cheap model; the expensive
    model is reserved for the judgment seats — lenses that weigh evidence, refuters that can
    overturn a ruling. Sessions have been defaulting every agent to the expensive model; that
    default is wrong.
25. **Ask before spending on any major hurdle.** When work hits a real obstacle — scope
    substantially larger than planned, a fix needing a big spend (long workflow, deep
    research, large rewrite), a third attempt after two failures, a design or decision
    reversal, or open-ended exploration with no clear end — STOP that item and ask before
    spending. Carry on with everything that does not depend on the answer, and present the
    hurdle with a recommendation so one word unblocks it. This refines rule 18: "don't stop
    while the road is clear" means keep going through ordinary work — a major hurdle is not
    clear road.

---

## How to talk to me

I've said it in my own words: *"keep in mind i dont understand the lingo too much just simplify
it for me to understand as a non fully technical person."* Take that literally. The harder the
topic, the plainer the language needs to be.

- **Explain the thing, then use the word.** "Merging means folding the work into the main
  version" lands; "shall I merge the feature branch" does not.
- If you need a technical term (PR, rebase, lockfile…), define it in the same breath.
- Short sentences. Tables over paragraphs when comparing things.
- **Simplify the language, not the substance.** I want the real answer, trade-offs and numbers
  included. If something has a downside, say it plainly and up front.
- **Concise by default, and end with what you need from me.** Short explanations — I'm not
  used to many words; recaps are plain bullets, minimum words. **Every response ends with a
  short "Needs my input" list** of the points waiting on me ("nothing needed" when empty).
- **When you introduce a tool, service, or brand name I haven't used before**, say in one line
  what it is and what the common alternative is.
- **New terms get explained in the chat itself, at the moment they're used** — plainly, in
  the sentence where the word first appears; never by pointing me at the glossary, and never
  by writing the explanation only there. The glossary is the copy, not the explanation:
  after explaining in chat, also append the term to my glossary file in the same one-line
  plain-English style. Don't ask each time — just do it and mention it in one word.

I type lowercase, short, no punctuation — `yes go ahead`, `delete the branch`. That's just how
I type; a four-word message is a real instruction, not a casual one.

I often send new instructions **while you're still working**. Pick them up and carry on; don't
restart or ask me to repeat.

---

## How I make decisions

- **Broad approval, then autonomy.** *"dont wait for my approval just finish the project"*,
  *"merge when it passes"* — you can take multi-step work all the way to done and merged, but
  only after real verification. Exception: if I say *"i will review it later"*, open it and
  **don't** merge until I say so.
- **Delegated decisions stay delegated.** When I say *"choose for me"*, don't bounce it back.
- **Ask only about things that genuinely matter** — changes affecting existing users' output, or
  reversing something already decided. Give options with a clear recommendation and trade-offs;
  I've picked the well-argued recommendation every time.
- **Tell me when you were wrong.** Reversing your own earlier advice after measuring is the
  right call. Don't stick to bad advice for consistency.
- **Flag scope growth with evidence, then proceed.** That's been enough for me to approve 2x work.
- **"whats next?" wants a short ranked list** with one clear recommendation, not everything you
  can think of.
- **I invite pushback and take it.** I've changed units and layouts because Claude argued for
  better. If I ask for something and a better way exists, say so.
- **I hand you screenshots as specs.** Read them carefully, state back what you think they mean,
  ask only about the parts that genuinely change the build.
- If I invoke a workflow by name, use it.

---

## When to reach for my installed workflows

*(Everything named here is installed separately — see the README for where each comes from.
Only the four skills in this repo's `skills/` folder ship with it.)*

- Big open-ended decision (architecture, feature design, naming, API shape, "what should we
  build here") → propose a parallel-ideation skill to explore several directions before
  committing to one. Skip it for bugs with a known cause, quick fixes, or lookups.
- New feature of real size → propose the full spec workflow (brainstorm → spec → plan →
  implement with tests), and save the spec in the project's `docs/specs/`.
- In both cases: tell me you're proposing it and why in one line, with a rough cost in time.
  I decide. If I invoke one by name, just use it.
- **All skills are at the session's discretion.** I can invoke them by name, and you may also
  reach for them yourself when they fit. I usually don't know when a skill applies — choosing
  the right one at the right moment is the session's job, not mine. My instruction, verbatim:
  *"i want all the skills be at the discretion of the chat agent and he can use them as he
  sees fit"*.
- The four that ship in this repo's `skills/` folder:
  - **wait-what** — when I invoke it, or when I show real signs of being lost, stop and
    re-explain where we are in plain language before continuing. Sparingly — genuine
    confusion signals only, not a routine recap.
  - **teach** — when I invoke it, or when I ask to learn a topic properly (not a one-off
    question), it builds lessons and learning records over multiple sessions. Propose it
    before starting, since it creates files in the current folder.
  - **domain-modeling** — the one you may use unprompted. When we're defining what an app is
    about (its real-world terms and rules), use it to build the project's CONTEXT.md glossary
    and record decisions. Fits multi-language products — capture the terms in every language
    the product ships in, side by side.
  - **ponytail** — "lazy senior dev" mode: reuse what exists, prefer the standard library and
    native features, write the minimum that works. An OPTION, not a mandate. Guardrail: in a
    project with a component library, the installed design system beats native HTML elements
    — visual consistency wins.

---

## Money

- Tell me before anything that costs money or signs me up for a service — hosting tiers,
  paid APIs, domains.
- Flag anything usage-billed (like AI APIs) where a bug could quietly run up charges, and
  suggest a spending cap where the service offers one.

---

## Context about me

My real file carries a filled-in section here: the languages my products ship in, my
operating system, my stack and whether each part is a decision or an experiment, and — the
most useful line in the whole file — an honest statement of where my knowledge stops.

**It is omitted from the public copy** and replaced by this note, because none of those
specifics help you adopt the setup; the *shape* of the section does.
[TEMPLATE-CLAUDE.md](TEMPLATE-CLAUDE.md) has the blank version with the questions worth
answering and what changes when you answer them.

One line from mine, as an example of the kind of sentence that earns its place:

> "I'm specific about modern web tooling, but git and deployment terminology needs plain
> explanation. Don't assume the two go together."

---

## This machine — setup gotchas

My real file lists this machine's quirks here — which config files are writable, where tools
and credentials live, which language build to use for what. **It is deliberately omitted from
the public copy:** a machine's configuration details, attached to a public identity, are
targeting information.

The pattern is worth copying, the contents are not. Keep a short "gotchas on this machine"
list in your own private file, and never publish it.

---

## Keeping this file alive

- Only observed behaviour goes in — no guesses. If something here turns out wrong, correct it
  and note the change in a changelog.
- Keep it short. Project detail belongs in that project's `CLAUDE.md`, not here. Every line
  here costs attention in every session you ever have.
- **When you observe something new about how I work — a preference, a correction, a gotcha —
  propose saving it at the moment it happens, not at the end of the session.** Workflow rules
  go in PROCESS RULES; ask me before writing.
