# How I work with Claude Code

I am not a programmer. This is not a coding tutorial — it's the daily habit of running
Claude Code as a non-coder, so a friend who wants to copy the working style (not the
rulebook — that's a separate file, `LESSONS.md`) can see the actual loop.

## The loop

A session looks the same almost every time:

1. Open a chat. Say the job in plain words — a feature, a bug, "look at this".
2. If it's a real decision rather than a described job, I get asked, not acted on.
3. A clear go ("yes go ahead") covers the whole job — no nagging me step by step.
4. Work happens; I don't watch it happen.
5. Results come back as one message in a fixed shape (the card, below) — never a file
   I have to go open.
6. I only ever have to answer the "needs my input" part. Everything else, I skim.

## The card

Every chat reports back in the same shape, so my eye always knows where to look:

```
🟡 waiting on you · step 3 of 5

**Problem**
1. What's actually wrong, in one plain sentence.

**Story**
What happened, in order, with roughly when.

**Result**
What the work left behind, and its state — live, parked, or blocked.

---
🔵 **Needs my input**
1. **The actual question, in my own words, ending in a question mark?**
   | | Option | Why |
   |---|---|---|
   | A | Do the safe thing | |
   | **B ✓** | Do the other thing | one-line reason |
```

Two reasons this exists: I read only the chat, never a file — a thing filed away and
never said to me hasn't been said. And I'm a visual reader — a heading and a short list
land; a paragraph doesn't. One rule inside the card worth naming: **each fact is said
once** — the problem names it, the story dates it, the result states where it landed —
so I never have to reread the same sentence three times to find the new part.

## The five control words

- **What I say in chat overrides everything else.** Any written rule is a default, not
  a ceiling.
- **Plain English.** Explain the thing, then use the word — no term I haven't been
  handed first.
- **"yes go ahead" means go.** No re-asking permission for each step after that.
- **"choose for me" means choose.** Pick the sensible default, say what and why in one
  line, keep moving.
- **"pause" and "stop" are different.** Pause: finish what's in flight, start nothing
  new, tell me where things stand, wait. Stop: drop everything immediately, mid-task
  included.

## What a "yes" covers

A question gets an answer, not an action. If I say "thoughts?" or "review this" or
"compare them", that's asking for my read on it — not a green light to go build it.
Once I've clearly started something, a "yes" covers the *whole* job, not each step of
it — I don't want to be asked five times for one task.

A short, fixed list always comes back to me no matter how broad the earlier "yes"
was:

1. **Deleting anything of mine** — files, branches, data.
2. **Anything that costs money** or signs me up for a paid service.
3. **Going public** — a repository, a page, anything outward-facing.
4. **Scope growing** past what was asked.
5. **Reversing a decision** that was already settled.
6. **Anything irreversible or outward-facing** — a real deploy, a database change, a
   message sent on my behalf.

Everything else, once started, keeps moving without a check-in.

## The paper trail

None of these are read by me directly day to day — they're habits a chat keeps up on
its own, so the *next* chat (which can't see this one) has the context. As habits, not
as file contents:

- **A decision log, per project.** Every real choice gets three lines: what was
  decided, why, and what it now rules out. Before proposing something new, a chat
  checks this first, so we don't relitigate a settled call by accident.
- **A mistakes ledger.** One line per mistake: what happened, the root cause, what it
  cost, where the full story lives. The same mistake showing up twice is what promotes
  it into an actual rule.
- **A parked-work file.** Anything postponed goes here with what would wake it back
  up — so a stalled idea doesn't quietly die, and slack time has somewhere to look for
  free work.
- **A glossary.** Plain-English, one line per term, that chats keep appending to as new
  words come up (see below).
- **A changelog for the rulebook itself.** So the rules have their own history — what
  changed, and why, not just the current state.

## Plain English, always

- **Explain the thing, then use the word.** A technical term gets defined the moment
  it's first used in a message — never assumed, never left for me to look up.
- **New terms go to the glossary at the moment they're used** — one plain line, added
  without being asked, right when the word first comes up. Not "see the glossary" —
  the explanation happens in the chat itself, and the glossary just keeps a copy.
- **Simplify the language, not the substance.** The real answer, trade-offs and numbers
  included, downsides stated up front — just said in words I actually understand,
  as I once put it myself: *"just simplify it for me to understand as a non fully
  technical person."*

## Money

- **Tell me before anything costs money** — a hosting tier, a paid subscription, a
  paid API call, a domain.
- **Flag anything billed by usage**, where a bug could quietly run up a bill, and
  suggest a spending cap if the service offers one.
- **Use the lightest tool that can actually do the job.** A cheap, fast model for
  mechanical work; a stronger one only where real judgment is needed. Spending more
  than a task needs isn't caution, it's waste.

## Keeping the rulebook alive

- **Only observed behaviour goes in.** No rule gets written on a guess about what
  might go wrong — it gets written after something actually did.
- **The moment I correct a chat, that's the moment to propose saving it** — not
  saved at the end of the session as an afterthought, and not paraphrased, but written
  back in roughly my own words, with the situation that caused it attached, so a rule
  without a reason behind it doesn't quietly get ignored later.
- **A chat proposes; it doesn't just write.** Nothing goes into the standing rules
  without my yes first — a proposal in the chat, then a save, never the reverse.
