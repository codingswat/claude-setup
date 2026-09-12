---
name: overnight
description: Overnight work session — start at the owner's given time, work through everything that needs no owner input until it is done, and end with a two-section morning summary (FYI / INPUT NEEDED). Use when the owner invokes /overnight, gives a start time for autonomous work, or asks for work to continue while they sleep.
---

# Overnight work session

The owner is going to sleep. From the start time until the queue is genuinely empty, you
work autonomously. The whole point: **nothing that can be finished without them waits for
morning, and nothing that needs them blocks the rest.**

## Before they leave (immediately on invocation — this is the only chance to ask)

1. **Restate the queue**: list what you intend to do tonight, in order, one line each.
   Pull the queue from the project's own state (plan files, the project's notes and
   decisions log, open work),
   plus anything the owner names in the invocation.
2. **Ask every clarifying question NOW.** None can be asked later. If the owner has
   already left, skip — never wait on an unanswered question; park it instead (see below).
3. **Confirm the closed gates out loud**: anything that bills money, anything
   public-facing, anything the project's rules reserve for the owner (no flags that
   flip the system into real/live mode, no live billed API calls, no deploys). These
   stay closed overnight — no exception because it is convenient at 3am.
4. **If a start time was given**, schedule it (ScheduleWakeup / scheduled task) and
   confirm the start time back in plain words. Until then, do nothing.

## Through the night

- **Work items to done** per the standing process rules: tested (tests that can fail),
  committed, pushed. Partial work is not "done" — either finish an item or park it.
- **A decision only the owner can make?** Park THAT ITEM in the morning summary's
  INPUT NEEDED section with your recommendation, and carry on with everything else.
  Never block the night on one question.
- **Two failed fix attempts** on the same problem = stop that item (the standing rule),
  write the plain-language root-cause explanation into the summary, move on.
- **Usage limit hit?** Note the reset time, schedule a wakeup for just after it, and
  continue then. Losing an hour is fine; losing the night is not. Record the interruption
  in the summary's FYI.
- **The owner may interject from a phone.** "pause" and "stop" (defined in the global
  CLAUDE.md process rules) apply overnight exactly as they do by day.
- **Keep running notes as you go** — the morning summary is assembled from notes, not
  from memory at 6am.
- Roles still hold: a Planner session does Planner work overnight (rulings, reviews,
  plans), a dev session dev work. Zone rules and coordination files apply unchanged.

## The morning summary (the last thing written, always)

Two sections, plain English, in this order:

**FYI** — no action needed:
- What got done, one line each, with the commit hash or other evidence beside it.
- What was verified and how (real output, not "it works").
- Anything surprising found along the way, and any usage-limit interruptions.

**INPUT NEEDED** — one bullet per parked item:
- The question, in one sentence.
- Your recommendation with a one-line reason, so a single word from the owner unblocks it.
- What it is currently blocking, if anything.

If INPUT NEEDED is empty, say so explicitly — an empty section is information.
