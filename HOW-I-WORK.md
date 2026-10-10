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

**Anything I'll actually see on a screen gets drawn before it gets built.** For a screen, an
animation, or an interaction, a chat sketches every step first — a storyboard, in words or
pictures — so we agree on the path before any of it exists as code. Once it's built, a second
chat that never saw the change rehearses it in a real browser, at real phone width, and answers
a short fixed set of questions about it. A finished-looking screen has shipped with real defects
on the same day its own tests passed — the rehearsal is what a test suite can't do, because it
never actually looks at the thing.

## From need to done

When the job is building something, the chat follows one fixed path, and starts the step's
skill itself; I never have to name one:

1. **Idea** — questions until the want is one sentence I agree with.
2. **Research** — a fact the decision needs, read from its source and cited.
3. **Decide** — when there is more than one sensible way, a page with a button per option;
   the chat tests its own favourite against the alternatives before showing me.
4. **Plan** — every file it will touch read first, and every behaviour written as one input
   it must refuse and one it must allow.
5. **Build, test first** — each test seen failing before the code exists, then passing.
6. **Review** — one helper that never saw the change checks it against the plan.
7. **Land** — the records (decisions, mistakes) ride in the same commit as the change.
8. **Deploy or share** — privacy check, security review, a blind reviewer, then my yes, then
   the live site checked.
9. **Look back** — at the end of a phase: what slowed us down, with rule changes proposed to
   me, never made.

A one-line fix goes through every step, quickly. The chat copies the steps into its own to-do
list, and a skipped step stays on it with the reason. The map itself is
[TEMPLATE-coding-CLAUDE.md](TEMPLATE-coding-CLAUDE.md); the detail of each step lives in the
skill for it (`coding-method`, `testing-method`, `going-live`), which loads only when that
step starts.

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
so I never have to reread the same sentence three times to find the new part. And the full
card only when it matters — a task closing, a decision, or me coming back after a break; an
ordinary turn gets one line and "needs my input".

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

## Design choices and guards

- **Every pick is made on a rendered page** — an example of each option with a button beside
  it, an artifact rather than a paragraph in chat, and never a drawing that only exists inside
  the chat window. It started with design choices and now covers any choice I'm asked to make.
- **One review per moment, not a pile of them.** Every change gets one check by a helper that
  never saw it; a whole multi-task branch gets one review against its spec; a guard gets one
  round of someone trying to break it; anything going live gets the fixed checks in
  `going-live`.
- **Rules and guards guide a chat; they are not walls.** They are tested against honest mistakes
  and against honest work wrongly refused, never built to make a deliberate bypass impossible.
- **Before I'm handed a script or a set of steps, it has been run end to end on a throwaway
  copy**, including stopped halfway and losing the connection.
- **A third attempt at a stubborn fix gets a blind review first** by the strongest model.

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

Everything else, once started, keeps moving without a check-in. Two habits keep the
questions down: **look first** — never ask me what the files, git or the chat list already
show — and **ask everything at once**, every question the job will need in one message, so I
can step away without being pulled back for each one.

## The paper trail

None of these are read by me directly day to day — they're habits a chat keeps up on
its own, so the *next* chat (which can't see this one) has the context. As habits, not
as file contents:

- **A decision log, per project.** Every real choice gets three lines: what was
  decided, why, and what it now rules out. Before proposing something new, a chat
  checks this first, so we don't relitigate a settled call by accident.
- **A mistakes ledger.** One line per mistake: what happened, the root cause, what it
  cost, where the full story lives. The same kind of mistake showing up three times is what
  promotes it into an actual rule.
- **A parked-work file.** Anything postponed goes here with what would wake it back
  up — so a stalled idea doesn't quietly die, and slack time has somewhere to look for
  free work.
- **A glossary.** Plain-English, one line per term, that chats keep appending to as new
  words come up (see below).
- **A changelog for the rulebook itself.** So the rules have their own history — what
  changed, and why, not just the current state.

## Plain English, always

- **Skip what I already know — and only that.** My own field's basics, and why a wrong input in
  it is bad, are never explained; software terms and a project's internal names still get a
  one-line explanation. The words go to what is new: the cause, the change, the choice, the cost.
- **Explain it my way.** What I will see and what we want, in one plain sentence; how it works
  — the scripts, the internal names, the steps — only when I ask.
- **Explain the thing, then use the word.** A technical term gets defined the moment
  it's first used in a message — never assumed, never left for me to look up.
- **New terms go to the glossary at the moment they're used** — one plain line, added
  without being asked, right when the word first comes up. Not "see the glossary" —
  the explanation happens in the chat itself, and the glossary just keeps a copy.
- **Times are 12-hour with AM/PM** in the chat (2:30 PM, not 14:30); the files that other
  chats read keep the 24-hour clock beside it.
- **Simplify the language, not the substance.** The real answer, trade-offs and numbers
  included, downsides stated up front — just said in words I actually understand,
  as I once put it myself: *"just simplify it for me to understand as a non fully
  technical person."*
- **A line of on-screen text earns its place only if I couldn't already guess it.** Anything a
  reader could already infer gets cut; what stays is a real qualifier on a number I'm meant to
  trust, or an actual consequence, never filler dressed up as information. Measured against
  exactly that test, one project's own screens came back honest by this standard — a real score
  to beat, not a formality.

## Money

- **Tell me before anything costs money** — a hosting tier, a paid subscription, a
  paid API call, a domain.
- **Flag anything billed by usage**, where a bug could quietly run up a bill, and
  suggest a spending cap if the service offers one.
- **A yes on a price estimate covers up to twice the estimate.** A limit I set may be passed
  only for work that is sure to fix a named problem, never to keep hammering an unsolved one.
- **Use the lightest tool that can actually do the job.** A cheap, fast model for
  mechanical work; a stronger one only where real judgment is needed. Spending more
  than a task needs isn't caution, it's waste. A hook enforces the habit: a helper agent
  cannot be launched without naming the model it runs on. The small model takes any job
  whose steps are written out and whose answer a command checks; it never gets a review, a
  verdict or a design choice.
- **A helper starts with only its brief.** My helper types skip the rulebook, which saves each
  one thousands of words of reading — so every brief carries three lines word for word: no
  real names or home-folder paths in anything written, no secrets anywhere, no author but me.
  A helper waiting on a long job checks back at most every four and a half minutes, because
  a longer pause throws away the cheap re-read of its own memory.
- **A budget is a gauge to report, not a stop sign to quietly obey.** Once a job is under way,
  going over an estimate means saying so and continuing — not trimming the work down to fit
  without telling me. An earlier habit did the opposite: work quietly got smaller once an
  estimate ran out, and I never found out it had been cut. Economizing happens by using cheaper
  tools for what's left, never by delivering less than what was asked. This is about effort and
  token budgets for helpers, never a money cap — a spending cap still stops the work; an
  overrun of effort is reported and continued with cheaper helpers, never by delivering less.

## Keeping the rulebook alive

- **Only observed behaviour goes in.** No rule gets written on a guess about what
  might go wrong — it gets written after something actually did.
- **The moment I correct a chat, that's the moment to propose saving it** — not
  saved at the end of the session as an afterthought, and not paraphrased, but written
  back in roughly my own words, with the situation that caused it attached, so a rule
  without a reason behind it doesn't quietly get ignored later.
- **The rules file holds rules; their history lives next door.** Dates, quotes, and the story
  behind each rule moved to a changelog, so the file every chat reads stays short enough to be
  read — and a hook refuses a commit that lets it grow past a word cap.
- **A rule with a moment lives in the skill for that moment.** The rulebook every chat reads
  keeps only what has no moment — how to talk to me, what a yes covers. A rule about commits,
  tests or deploys moves into the skill that runs at that moment, with a one-line pointer
  left behind.
- **A correction becomes a check or a rule.** When I correct a chat, it proposes an automatic
  check if the mistake was mechanical, a rule line if it needs judgment.
- **A chat proposes; it doesn't just write.** Nothing goes into the standing rules
  without my yes first — a proposal in the chat, then a save, never the reverse.
