---
name: handing-off-live-work
description: Use when a work session is ending mid-task and another session will continue it — being replaced, running out of context, pausing indefinitely, or asked to hand off. Leaves the state in the plan file and one short state file, never a handover document. Not for a finished project's documentation.
---

# Handing off live work

Four acts, in this order: **let everything finish, tidy up, write down what you are standing on,
then commit it and hand the next session its opening prompt.** The order IS the skill. A state
written while anything is still running describes a machine that no longer exists by the time it
is read.

**What gets written is short.** The plan file (or order file) already holds what landed and what
is open, because it was kept current during the work; the closing session marks it and rewrites
**one state file under two hundred words**. It does not write a handover document. Two sessions
once retired at their memory floors mid-task and each wrote a four-thousand-word handover —
spending, on the way out, exactly the memory the retirement was meant to protect, and restating
what the plan file already held. The plan file and the role's boot file are the handover; the
state file is the note left on the desk.

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
  invisible to the state file — commits it made, findings it had, files it changed. The next session
  inherits work the handover does not know exists, and cannot tell it from debris.
- **Do not substitute "record where it stopped" for waiting.** That is the exit for work you
  *cannot* wait on (a scheduled job, another person's session) — never for an agent of yours that
  is simply still going.
- **Do not start anything new**, however small, however useful it would be for the next session.
- **A run with a known finish time inside ~15 minutes is NEVER exception-eligible. Wait for it.**
  Tested: given a 6-agent review four minutes from done, one draft in three filled in the exception
  instead of waiting four minutes. The exception is for runs that genuinely cannot be waited out —
  unbounded, or hours away — not a disclosure form you complete to leave sooner.
- Only then, if a run truly cannot be waited out, say so **in the state file, by name**, all four:
  1. what is running; 2. what it will touch; 3. **where its output lands — as a path**, not "in the
  tree somewhere"; 4. that the state file predates it. It is the state file's first line.
- **A run you DID wait out is re-reported with its FINAL state, never its pre-wait numbers.**
  Tested: a draft waited correctly and still handed over the agent's "~25 minutes in, nothing
  committed" snapshot, which was stale by the time it wrote.

**Why this is Step 0 and not a bullet in Step 1:** the pressure to skip it is highest exactly when
it matters most — context filling, a replacement waiting, a long-running agent. Writing early feels
efficient and produces a state that is wrong on arrival.

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
  with the machine. This is the one claim in the state file that requires evidence; do not paste
  command output for claims that need none.
- Do YOUR paper trail now. Never delegate your own bookkeeping forward. Writing "log this if it
  isn't already" tells the reader you did not check, and devalues every other claim you make.
- Clean up scratch files, temp servers, processes. Say what is still running.

## Step 2 — Mark the plan, rewrite the state file

Two writes, both into files that already exist — nothing new is created.

**The plan or order file** is the record of what landed and what is open. Mark every task you
touched with its honest state: DONE-and-reviewed / DONE-but-unreviewed / NOT-STARTED /
PARKED-by-<who>. **IN-FLIGHT is not a legal state once Step 0 is done** — a run you waited out
gets the state it ENDED in, never what it was doing when the pause was called. Tested: 2 of 3
drafts waited half an hour and still tabled the run with its pre-wait numbers. Anything the
work FOUND that outlives the task — a bug, a behaviour change, a leak fixed inside unreviewed
work — goes on the task's line in the plan, not in your head: in testing, drafts that reported
machine state perfectly lost the single most consequential fact because no slot asked for it.

**The role's state file** — one per role, a fixed path the next session boots from, rewritten
(not appended) at every task boundary and now:

```markdown
# <role> — where I stopped
Current task: <task id and one line> — <its state from the plan>
Next step: <the one thing the next session does first>
Open questions: <each with who owes the answer, or "none">
Do not repeat: <the thing tried that failed, with why — or "none">
Unverified: <numbers you took from a helper and never re-ran — or "none">
Heartbeat: <clock time, copied from the clock>
```

Under two hundred words. **A slot with nothing in it says "none"** — never invent an item to fill
it; in testing, slot pressure produced a fabricated reason and a row that contradicted the same
document two sections later. Every path, hash, or file the state names is one you confirmed with
a command. If something was still running when you wrote (the Step 0 exception, genuinely
earned), it goes on the first line, with where its output will land as a path.

**What does NOT go in the state file:** the story of the session, what the plan file already
says, the reasoning behind your judgement calls, advice. A judgement call is named on the plan
line it concerns, with what you chose between — not defended.

## Step 3 — COMMIT it, and say where it landed

State that exists only in this session's scrollback is not state. The next session inherits the
repo, not your transcript.

- **Commit and push the plan file and the state file together**, with the paper-trail edits they
  refer to — the notes entry, the decision record. Pathspec commits only.
- **Paste the push confirmation.** `git log --oneline -1` plus an empty
  `git log --oneline origin/main..HEAD` are the two lines that prove it. If the push failed, say so
  and make it the reader's first action — the same rule as Step 1's preservation claim.
- In a shared working tree, read `git diff --cached --name-only` with **no path filter** before
  committing: a path you did not stage is another session's work.
- **If a decision lands after you write** — the owner answers an open question minutes later — go
  back and correct the state file and the plan line that still say it is open.

**If the state is not committed, nothing below matters.** A prompt pointing at an uncommitted
file sends the next session to a path that does not exist.

## Step 4 — Write the next session's opening prompt

**The handover is for the reader; the prompt is what actually starts them.** In practice the owner
pastes a prompt into a fresh session — so the last thing you produce is that prompt, written by the
session that knows the most and will not be there to answer questions.

Give it **in chat, as one copy-pasteable block** (the owner pastes it; they do not open files to
find it). It carries:

1. **Role, model, and the boot order** — the role's boot digest, then the state file you just
   committed, then the order file, then the notes channel — the state file before the channel,
   because it is the account of where things actually stand.
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

**A prompt is not a copy of the state file.** The state file says where things stand; the prompt
says what to do next and what to distrust. If the prompt reads like the state file with
greetings, it is doing the wrong job.

## Rationalisations for writing before everything has stopped

| Excuse | Reality |
|---|---|
| "I'll note it's still running and move on" | Then the state is wrong on arrival. Wait. |
| "It's only a few minutes, the exception covers it" | It does not. Under ~15 minutes there is no exception — you wait. |
| "I'm out of context, I have to write now" | A state file missing a whole agent's work costs the next session more than one written late. Two hundred words fit in any floor. |
| "It's nearly done, I'll write the rest meanwhile" | You cannot know what it will report. Two of six tested drafts invented facts under exactly this kind of time pressure. |
| "Cancelling it is cleaner than waiting" | Cancelling destroys unreported work. Waiting costs minutes. |
| "I'll tell them about it in chat, that's enough" | Chat is not inherited. Commit the state file. |
| "The next session can find it, it's in the repo" | The state file is at the fixed path the role boots from; the prompt names it. |
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
| Writing a handover document | Mark the plan, rewrite the state file. Two hundred words. |
| Writing while an agent is still running | Wait. Its commits land after your sentence and nobody sees them. |
| Leaving the state file uncommitted | The next session inherits the repo, not your scrollback. |
| A prompt that just copies the state file | The prompt says what to DO and what to distrust. |
| A prompt that hides your recommendation's weak spots | Name what you did not test. Inherited confidence is the expensive kind. |

## Red flags

- About to write "a plan file", "the notes", "the config" — with no path.
- Explaining *why* your judgement call was right.
- You wrote "if it isn't already".
- An agent or workflow of yours is still running and you are writing anyway.
- You are filling in the exception for something that finishes in minutes.
- You waited for a run and then reported the numbers it had BEFORE you waited.
- Nothing is running and a plan line still says IN-FLIGHT.
- The state file is over two hundred words, or has a section the template does not.
- You wrote a branch name, a hash or a path you did not confirm with a command.
- The second copy of unpushed work is a recommendation, not a location.
- Nothing on the plan lines says what the work actually found.
- The reader could not, in 30 seconds, say what to do first.
- The state file is written but not committed.
- You wrote a prompt containing a path, hash or URL you did not confirm with a command.
- Your prompt recommends something and does not say what you failed to test about it.
- **Anything you started is still running.** Stop reading this and go wait for it.
