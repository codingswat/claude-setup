---
name: handing-off-live-work
description: Use when a work session is ending mid-task and another session will continue it — being replaced, running out of context, pausing indefinitely, or asked to hand off. Not for a finished project's documentation.
---

# Handing off live work

Four acts, in this order: **let everything finish, tidy up, write down what you are standing on,
then commit it and hand the next session its opening prompt.** The order IS the skill. A handover written while anything is still running describes a
machine that no longer exists by the time it is read.

**Pause is not stop.** Pausing means: start nothing new, let what is already running land, then
report. It never means interrupting work mid-flight. Killing a running agent destroys work nobody
has written down yet — which is the exact loss this skill exists to prevent.

Not the same as `handover`, which documents a finished project for someone who has never seen the
code. This is a session handing live, half-finished work to the session replacing it.

## Two rules

**1. Every claim names where it lives.** A handover fails not by saying false things but by saying
true things the reader cannot act on. "A plan file carries the status" is unfollowable; a path is
followable. Files get paths, commits get hashes, records get filenames, gotchas get the command or
the file that trips them.

**2. Say what the work DID, not only what state it is in.** Process state is easy to enumerate and
easy to over-serve. In testing, two of three drafts that reported machine state perfectly **lost
the single most consequential fact being handed over** — a data leak the last task had found and
fixed — because no slot asked for it. Substance first, then bookkeeping.

## Write while you work — the handover starts on the first task

A handover is cheap only when the plan file already holds what the transcript holds. During
the work, not at its end:

- **A ruling lands on disk the moment it is made** — in the plan file, the owner's words
  verbatim with the date. Gist survives compaction; the words that made it binding do not.
- **Tried-and-rejected is a section of the plan**, each idea with the reason it died, so a
  fresh session cannot re-propose it.
- **A costly fact is written where the next reader trips over it** — the command that
  silently fails, the port another seat owns, the test that cannot fail — beside the file or
  line it concerns.
- **The self-sufficiency drill:** from the plan alone, answer "what am I building, and why
  not the obvious alternative?" A plan that cannot answer is unfinished — name what it
  assumes its reader already knows, and write that down.
- **The handover is written before the context floor**, never at it.

## Step 0 — Let every subagent and workflow FINISH. Do not interrupt anything.

**You do not write a word of the handover while anything you started is still running — and you
do not shorten the wait by cutting anything off.** Let it land.

Wait for every subagent and every workflow to report. All of them. Then write.

**No exceptions:**
- **Never interrupt, cancel or kill a running agent to get to the handover sooner.** Its work is
  real and unreported; ending it early destroys exactly what you are trying to hand over. Waiting
  costs minutes; the work costs hours.
- **Do not write the handover "while they finish".** Anything that reports after you write is
  invisible to the document — commits it made, findings it had, files it changed. The next session
  inherits work the handover does not know exists, and cannot tell it from debris.
- **Do not substitute "record where it stopped" for waiting.** That is the exit for work you
  *cannot* wait on (a scheduled job, another person's session) — never for an agent of yours that
  is simply still going.
- **Do not start anything new**, however small, however useful it would be for the next session.
- **A run with a known finish time inside ~15 minutes is NEVER exception-eligible. Wait for it.**
  Tested: given a 6-agent review four minutes from done, one draft in three filled in the exception
  instead of waiting four minutes. The exception is for runs that genuinely cannot be waited out —
  unbounded, or hours away — not a disclosure form you complete to leave sooner.
- Only then, if a run truly cannot be waited out, say so **in the document, by name**, all four:
  1. what is running; 2. what it will touch; 3. **where its output lands — as a path**, not "in the
  tree somewhere"; 4. that the handover predates it. Repeat it in slot 0.
- **A run you DID wait out is re-reported with its FINAL state, never its pre-wait numbers.**
  Tested: a draft waited correctly and still handed over the agent's "~25 minutes in, nothing
  committed" snapshot, which was stale by the time it wrote.

**Why this is Step 0 and not a bullet in Step 1:** the pressure to skip it is highest exactly when
it matters most — context filling, a replacement waiting, a long-running agent. Writing early feels
efficient and produces a document that is wrong on arrival.

## Step 1 — Tidy up, and ACT (before writing a word)

Testing: **no draft written without this step described the state being handed over**, and every
draft told to preserve the only copy of unpushed work wrote it as advice for the *next* session
instead of doing it. Advice is not a backup.

- Step 0 is done: nothing of yours is still running. Start nothing new.
- **Preserve anything that exists in only one place, NOW.** Unpushed commits live in one working
  directory; if that environment is reclaimed the work is gone. Push, push to a side branch, or
  bundle it.
- **A preservation claim carries the command that produced it and that command's output.** Paste
  both. **Never name a second-copy location a command has not confirmed.** If the command failed or
  the repo is not reachable from this shell, paste the failure, say you could not act, and make it
  the reader's first action.
  Tested, both models, 2 of 6 drafts: asked for a completed fact and given no way to check, a
  session invents one — a branch that does not exist, a commit hash never issued. **That is worse
  than admitting nothing was preserved**, because the reader stops worrying and the only copy dies
  with the machine. This is the one claim in the document that requires evidence; do not paste
  command output for claims that need none.
- Do YOUR paper trail now. Never delegate your own bookkeeping forward. Writing "log this if it
  isn't already" tells the reader you did not check, and devalues every other claim you make.
- Clean up scratch files, temp servers, processes. Say what is still running.

## Step 2 — The document

**The slots are a floor, not a ceiling.** Fill every one; add anything that does not fit. **A slot
with nothing in it says "none".** Never invent an item to populate a slot, and never infer a cause
you were not told — in testing, slot pressure produced both a fabricated reason and a task-table
row that contradicted the same document two sections later.

```markdown
# Handover — <what> → next session

## 0. Read this first (30 seconds)
The two or three things that decide what the reader does in the next ten minutes.
Every tested draft invented this header when the template lacked it — write it.
If anything was still running when you wrote, it goes here, first.

## 1. State of the machine
Branch. Working tree clean or not, and what in it is NOT yours. What is running.
Anything unpushed — and WHERE THE SECOND COPY IS, as a fact, not a plan.

## 2. What the work found or changed          ← substance; the slot most often lost
Bugs found, behaviour changed, anything discovered that outlives the task.
Especially anything sitting inside unreviewed or unpushed work.

## 3. Where the work is
Table: task | state | commits | its record. State honestly:
DONE-and-reviewed / DONE-but-unreviewed / IN-FLIGHT / NOT-STARTED / PARKED-by-<who>.
**IN-FLIGHT is only legal if slot 1 says something is still running.** A run you waited
out gets the state it ENDED in — what it produced, what it committed — never what it was
doing when the pause was called. Tested: 2 of 3 drafts waited half an hour and still
tabled the run as IN-FLIGHT with its pre-wait numbers, contradicting their own slot 1.

## 4. Verified vs reported
Which numbers you re-ran yourself; which you took from an agent. Label each.

## 5. Owed and unexecuted
Decided and assigned but NOT done. If there is exactly one, it gets its own
heading — not a bullet among six.

## 6. Facts that cost time to learn
Each as a performable check: name the file, give the command. "Run from the repo
root" → the command. For anything with a budget, state the REMAINING NUMBER and
stop — every tested draft got the arithmetic right and then contradicted itself
restating the mechanism in the next clause.

## 7. Claims nobody has audited
Proofs an agent says it did but you never opened. Queue them as work. A passing
suite proves tests pass, never that one could fail.

## 8. Judgement calls — named, not defended
The choice, **and what you chose between** (drafts drop the alternative). Do not argue for it; invite disagreement.
Add what would prove you wrong ONLY where there is a real test — a mechanical
falsifier for every item produces off-target answers the reader cannot tell from
real ones. "A judgement with no clean test" is a legitimate entry.

## 9. Waiting on people
Who owes what, and what it blocks — or "blocks nothing", or "never established,
ask". Do not guess which.

## 10. Where the detail lives
Paths. Flag records other sessions write concurrently, and records that are
gitignored and exist only on this machine.
```

## Step 3 — COMMIT the handover, and say where it landed

A handover that exists only in this session's scrollback is not a handover. The next session
inherits the repo, not your transcript.

- **Commit and push the document itself**, together with the paper-trail edits it refers to — the
  notes entry, the role's own handover file, the decision record. Pathspec commits only.
- **Route the reader to it.** A document nobody is pointed at is a document nobody reads: add the
  pointer to the file the next session BOOTS from *and* to the standing notes channel, in the same
  commit.
- **Paste the push confirmation.** `git log --oneline -1` plus an empty
  `git log --oneline origin/main..HEAD` are the two lines that prove it. If the push failed, say so
  and make it the reader's first action — the same rule as Step 1's preservation claim.
- In a shared working tree, read `git diff --cached --name-only` with **no path filter** before
  committing: a path you did not stage is another session's work.
- **If a decision lands after you write** — the owner answers an open question minutes later — go
  back and correct every document that still says it is open, the handover included. A handover
  that misstates the one open item is worse than none.

**If the handover is not committed, nothing below matters.** A prompt pointing at an uncommitted
file sends the next session to a path that does not exist.

## Step 4 — Write the next session's opening prompt

**The handover is for the reader; the prompt is what actually starts them.** In practice the owner
pastes a prompt into a fresh session — so the last thing you produce is that prompt, written by the
session that knows the most and will not be there to answer questions.

Give it **in chat, as one copy-pasteable block** (the owner pastes it; they do not open files to
find it). It carries:

1. **Role, model, and the boot order** — including the handover you just committed, positioned
   *before* the shared notes channel, because it is the account of what actually happened.
2. **The state they inherit**, in three or four lines: what is released or claimed, what is green,
   what is explicitly NOT dispatched. Verify each by reading the file, not from memory.
3. **Their work in priority order**, with the ONE thing anyone is waiting on first.
4. **The weaknesses of your own recommendations.** If you recommended something, name what you did
   not test about it, so the next session can check it rather than inherit it as settled. This is
   the part sessions omit and the part that most repays being written.
5. **The hazards that already cost time** — each as a performable check with its command.
6. **How to talk to the owner** — the project's own rule, restated, because a fresh session has
   no way to know it.

**Every path, hash and URL in the prompt gets confirmed by a command before you write it.** A
prompt is a brief, and a brief that misstates its target files sends the next session to work on
something that is not there.

**A prompt is not a summary of the handover.** The handover says what happened; the prompt says
what to do next and what to distrust. If the prompt reads like the handover's abstract, it is
doing the wrong job.

## Rationalisations for writing before everything has stopped

| Excuse | Reality |
|---|---|
| "I'll note it's still running and move on" | Then the document is wrong on arrival. Wait. |
| "It's only a few minutes, the exception covers it" | It does not. Under ~15 minutes there is no exception — you wait. |
| "I'm out of context, I have to write now" | A handover missing a whole agent's work costs the next session more than a shorter one written late. |
| "It's nearly done, I'll write the rest meanwhile" | You cannot know what it will report. Two of six tested drafts invented facts under exactly this kind of time pressure. |
| "Cancelling it is cleaner than waiting" | Cancelling destroys unreported work. Waiting costs minutes. |
| "I'll tell them about it in chat, that's enough" | Chat is not inherited. Commit the document. |
| "The next session can find it, it's in the repo" | Route them: a pointer in the boot file and the notes channel. |
| "The prompt is the owner's job" | You know the most and will not be there. Write it. |
| "Stopping now is what pause means" | It is not. Pause = start nothing new and let running work land. Stop = interrupt immediately, and nobody asked for that. |
| "They said pause, so I should wind up now" | Pause means start nothing new and let running work land — not abandon it mid-flight. |

## Common mistakes

| Mistake | Instead |
|---|---|
| "A decisions log exists" | The path. Every time. |
| "Don't push until reviewed" | Preserve a second copy first — unpushed is one copy. |
| "Log these if not already logged" | Check, then state. |
| Reporting state but not substance | What did the work FIND? That is the part worth inheriting. |
| Defending your judgement calls | State the choice; invite the disagreement. |
| Filling a slot to avoid a gap | "None." Inventing an item to fill it creates contradictions. |
| Rewriting what the plan file says | Point at it. Duplicates go stale, then contradict. |
| Writing while an agent is still running | Wait. Its commits land after your sentence and nobody sees them. |
| Leaving the handover uncommitted | The next session inherits the repo, not your scrollback. |
| A prompt that just abstracts the handover | The prompt says what to DO and what to distrust. |
| A prompt that hides your recommendation's weak spots | Name what you did not test. Inherited confidence is the expensive kind. |

## Red flags

- About to write "a plan file", "the notes", "the config" — with no path.
- Explaining *why* your judgement call was right.
- You wrote "if it isn't already".
- An agent or workflow of yours is still running and you are writing anyway.
- You are filling in the exception for something that finishes in minutes.
- You waited for a run and then reported the numbers it had BEFORE you waited.
- Slot 1 says nothing is running and slot 3 still says IN-FLIGHT.
- You wrote a branch name, a hash or a path you did not confirm with a command.
- The second copy of unpushed work is a recommendation, not a location.
- Nothing in the document says what the work actually found.
- The reader could not, in 30 seconds, say what to do first.
- The handover is written but not committed — or committed but nothing points at it.
- You wrote a prompt containing a path, hash or URL you did not confirm with a command.
- Your prompt recommends something and does not say what you failed to test about it.
- **Anything you started is still running.** Stop reading this and go wait for it.
