# Running several Claude chats on one codebase

*A pattern for when one conversation is no longer enough. This describes the method as it is
actually run today, after an earlier version of it (every chat sharing one checkout, each one
carefully staging only its own lines) was tried and abandoned — the staging discipline kept
failing under real pressure. The fix was not "be more careful." It was: give every chat its
own folder, so there is no shared workspace left to collide in.*

---

## The problem this solves, and the one rule everything rests on

A single chat has one train of thought and one memory. Past a certain project size you hit
three walls: its memory fills up and it forgets earlier decisions; different tasks want
different amounts of thinking (planning is expensive, renaming a variable is not); and you
want more than one thing happening at once.

The obvious answer is to open several chats. The obvious problem: **chats cannot see each
other.** They share no memory. If two of them work the way one chat would — each editing the
same files — they will overwrite each other and neither will notice until something breaks.

Everything below fixes that one problem, and the fix is not clever:

> **Chats coordinate through files in the checked-out project, never through you, and never
> by sharing a workspace.**

You are not a message bus. If a ruling only exists in your memory of a conversation with a
different chat, it is lost the moment you forget it or that chat ends. Every ruling, every
claim on a piece of work, every open question is written down in a file every chat can read.
And — the part that changed — every chat now writes and edits in its **own private copy of
the project**, so two chats are never touching the same live files at once.

---

## The five roles

Five roles. Each has a job, a list of things it must **never** do, and a default "model" —
which brain runs the chat. A **model** here means the underlying AI doing the thinking for
that chat; different models cost different amounts and think at different depths. Three
tiers, always called by these names:

- **haiku** — cheapest, fastest. Fully specified mechanical work: the task is already written
  out in enough detail that there is nothing left to decide, only to do.
- **sonnet** — the middle tier. Work where the brief leaves a real choice: some judgment is
  needed, but the scope is bounded and well-described.
- **opus** — the expensive tier. A verdict or a review: weighing evidence, making a call
  nobody has made yet, catching what a cheaper reviewer would miss.

Every seat's stated model is a **default, not a rule** — whoever runs the project can put a
different model in a given seat's chair; the seat says out loud which model it is running.

### Planner — *default model: the strongest available (the tier above opus, where one exists)*

**Owns:** the specs, the overall plan, the agreed shapes that let parts of the system talk to
each other (**contracts** — an agreed data shape, frozen so nobody quietly changes it out from
under the other side), the decision log, and settling disagreements between chats.

**Never writes product code** — a chat that both plans and builds will quietly bend the plan
to fit whatever it just wrote. **Also owns being the single commander** — see "One commander"
below: every cross-chat request and every decision needing the owner's judgment passes through
this seat. **And owns the done-list:** before a stage's first task is handed out, the Planner
writes the "must be true when done" lines — never the seat that builds. Each line names a
**behaviour**, never a file state: for a guard, one input it must refuse and one it must allow
("refuses a test piped through a pager, allows one joined with &&"). A done-list of "this file
exists" lines once let three real bypasses ship with every line met. Each task names the lines
it satisfies; the review checks a task against its lines first, the builder's own tests second.

### Designer — *default model: opus*

**Owns:** the visual and interaction design — written-down design constants (type scale,
spacing, colour, motion), mockups, design specs. May also implement the front end, but only
the part the user sees and touches — **never** the underlying logic, storage, or the agreed
contracts. If that boundary isn't written down, it erodes. The owner is shown **rendered
options** to pick between, never a paragraph describing them — nobody chooses a layout from
prose.

### Advisor — *default model: opus*

**Owns:** challenging the thinking *before* a decision gets made — research, measured
comparisons, auditing decisions already taken. Its findings become a handoff document the
Planner plans from. **Writes no product code, and no plans.** Every other role helps build
the thing; this one finds out whether it's right first.

### Senior Dev — *default model: opus*

**Owns:** executing the current stage of the plan, the genuinely hard code, and reviewing
work handed up from a Junior Dev. Its key habit: it does not type routine work into its own
memory. It hands a well-specified task to a helper chat (a **subagent** — a short-lived helper
spun up to do one bounded piece of work and report back), reviews what comes back, and keeps
its own attention for the hard parts and the review. Every helper states its own model out
loud — sonnet for well-defined work, opus for a judgment call; a too-cheap model asked for a
judgment gives a confident wrong answer, costlier to catch and redo than the right tier up
front.

### Junior Dev — *default model: sonnet*

**Owns:** exactly one piece of work, as written down for it. If the task is unclear, or needs
a file outside its given area, it **stops** and writes that down rather than guessing.

---

## One private folder per seat: the worktree

Every seat — every chat playing one of the five roles — works in its **own folder**, checked
out from the same project. In git (the tool tracking every change) this second folder is a
**worktree**: a second, independent working copy of the same repository, on its own branch,
sharing the same history but none of the same open, in-progress files. Nothing is duplicated
by hand — it is the same project, checked out twice, so two chats editing "the same codebase"
never touch the same files on disk at once.

This is the fix for the original problem. The earlier method had every chat editing one
shared folder, carefully staging only the lines it had written before committing — and that
discipline broke down repeatedly, because catching "did I just commit someone else's
in-progress edit" requires a perfect read of a moving target every time, under pressure.
Giving every seat its own folder removes the shared target.

A seat makes its worktree by branching from the project's latest known-good state, works
there, and **finishes** a piece of work by folding it back in — never by merging inside the
shared folder, only from inside its own worktree: fetch the latest state, rebase the seat's
own small stack of commits on top of it (replay them cleanly after the newest shared history,
instead of tangling the two together), then push straight to the shared main line, which only
succeeds if that push lands cleanly onto its very tip — a **fast-forward**: the seat's commits
simply extend the shared history, nothing forced, nothing rewritten. If refused because the
history moved meanwhile, repeat the fetch-and-rebase step; never force it through.

```bash
git fetch origin
git rebase origin/main
git push origin HEAD:main
```

Never `--force`. Never merge inside the shared root folder — that folder is only the meeting
point every seat starts from and lands back onto.

At most **two** dev seats run at once (see "Limits" below); each seat's folder, once its
work is finished, is removed and its branch deleted — nothing left half-open. **Before a folder
is removed, check it for untracked files, not only uncommitted ones**: sixteen screenshots
behind a "no defects" verdict once lived only in an ignored scratch folder inside a worktree,
and were removed with it.

---

## The channel files

Since chats cannot see each other and now do not even share a folder while working, the
*only* way information moves between them is a small set of shared files, read and written by
every seat. These are described here as a **practice** — what each file is *for* — not a fixed
list of exact contents; the exact shape is a project's own choice.

- **A live notes file.** The standing channel: open questions, requests between seats,
  findings that outlive one task, handoffs. Newest entries at the top, each signed with role
  and time. Only **live** items belong here — once resolved, an entry moves to an archive in
  the same piece of work that closed it. A notes file that keeps growing forever stops being
  read, which is the same as not having one. **Give it a size band with two edges:** a trigger
  (say 9,000 words) above which the Planner sweeps closed entries out before writing anything
  new, and a lower target (say 7,000) the sweep trims down to — never "just under the trigger",
  or the next entry trips it again. The band binds the Planner only: no other seat is ever
  refused an entry for size; over the band it appends with a note and the Planner sweeps
  before its own next write. An entry older than a week is archived at every sweep unless one
  signed line beside it says why it is still live.
- **A plan file** — the single source of truth for done, in progress, and next. Whoever
  claims a piece of work marks it with their role name; whoever finishes it marks that too.
  Nobody trusts memory or a transcript for this — only the file.
- **A decision log** — every choice worth remembering: what was decided, why, what it rules
  out, so nobody reopens a settled question by accident. Any role adds to it; the Planner
  keeps it tidy.
- **A mistakes ledger** — one line per mistake once understood and fixed: what happened, the
  root cause, its cost, where the full story lives. Filed by whoever catches it; a lesson
  showing up twice is a candidate to become a standing rule.
- **A parked-work file** — anything postponed on purpose, each with a note on what would wake
  it back up.

- **One boot digest per role.** A fresh chat reading the whole notes channel at boot costs a
  large share of its memory before it has done anything — one seat spent roughly a third of
  its room on the boot read alone. So each role boots from **one short file** (at most 350
  words) read *instead of* the decision index and the channel's top. Fixed slots: the role's
  title and default model, where its private folder goes, its zone, the ten-or-so live rulings
  that bind it (one line each), three or four hazards with the command that checks each, and
  three pointers — the roster line naming its current order, its state file, its inbox. No
  task, no open questions, no date: the digest is who you are, not what happened. Whoever
  changes a ruling or a hazard updates the digest in the same commit; a ruling leaves the
  digest once it is built and pinned by a test.
- **One state file per role** — where the last holder of the seat stopped, rewritten at every
  task boundary, under two hundred words: current task, next step, open questions, what must
  not be repeated. This, with the order file, is the whole handover (see "Context floors").

None of these files' contents are invented here — this describes the practice, not a template
to copy. A project adopting this pattern writes its own.

---

## Signing every entry

Every commit in a shared project is typically made under one person's identity, not the
chat's, so git's own history cannot tell which chat did what. The only durable record is the
signature written inside the file itself: the role's full name — not a short code, which
needs a legend and which fresh chats will reinvent and collide with — and the time, **copied
from an actual clock check made at that moment**, never guessed from how long the
conversation feels like it has run.

**Never rewrite another role's entry.** If a note needs correcting, append a new entry
underneath it, signed and timed as its own thing. Editing someone else's words is how the
*reason* something changed silently disappears, even if the correction survives.

---

## One commander

Seats never instruct each other directly. If one chat needs something from another, the
request goes through the Planner, who decides whether and how to route it. A chat may still
*notify* another that its work is ready, but that is not an instruction and not
authorization to act.

**Decisions are made only in the Planner's own chat.** A chat running one of the other roles
gets its go-ahead there, does its work, and reports back — the weighing of options stays in
the Planner's chat, never scattered across every seat. If the owner says something in a dev
chat that would change a standing ruling, that chat relays it to the Planner and waits for
the ruling to be recorded, rather than acting on it as though it had already changed.

A report from a dev chat to the Planner is kept to **three lines**: current state, what it
needs, what is blocking it — unless asked for more. The full story lives in the notes file;
the report is the short version that gets read.

**One machine steward.** Worktrees separate the files, not the machine: the shared installed
dependencies, the running servers and their ports, the hooks. Those are one zone, "the
machine", owned by the Planner and touched only through **one seat the Planner names** — the
Planner itself by default. Anything machine-wide (an install in the shared folder, a repair of
the shared tree, deleting folders or branches, a full test suite under load) is done by that
seat alone, which says "starting" and "finished" as two separate messages while every other
seat holds its runs between them. Whoever finds a breakage says so and **waits**; two seats
each "fixing" the shared tree is how it ends up half-written for everyone. A package is only
ever *added to the list files* from a worktree; the one install runs in the shared folder,
announced.

**One go per task.** The owner's go-ahead is given once, in the Planner's chat, recorded on
the task's file, and covers the task's follow-ons — a fix opened by its review, a build whose
numbers the owner already read. A seat does not come back for a fresh yes on each of those.

---

## A routing names who, when, and the starting word

When the Planner hands work to a seat, or parks it, the routing is a short table — not a
paragraph — so who does what and what word starts it is unambiguous:

| Who | When | Starting word |
|---|---|---|
| Senior Dev | now | "go" |
| Designer | after the mockup is approved | "build it" |
| Junior Dev | once the Senior Dev's task file is written | "start task 4" |

A routing without this table is incomplete — "someone should look at this" tells nobody
anything they can act on.

---

## Limits: how many seats, how much load

**At most two dev seats run against the shared project at once** — in practice the one that
builds and deploys the front end, and one on the engine. This was three; it came down to two
because the chance of two chats stepping on the same shared machinery (not files — those are
separated per worktree — but installed dependencies, a running server, test infrastructure)
rose faster than the benefit of the extra parallelism, and because the owner's attention is the
real ceiling: every seat reports to one person.

**Only one heavy test run happens at a time**, project-wide. A full test suite, an end-to-end
run, or anything that seriously loads the machine is exclusive — check how busy the machine
already is first; busy means wait, not "start anyway and hope." Small, single-file test runs
are fine anytime.

---

## Context floors: closing before a chat runs out of room

Every chat's memory (its **context window** — how much prior conversation and file content it
can hold at once) is finite, and it fills as work happens. At every natural break, a seat notes
roughly how much room is left, **in tokens, never as a percentage** (the percentage depends on
which model is in the chair; the token count does not). Below a set floor it takes no new
task; lower still, closing is the next action — so a chat running low is never tempted to
squeeze in "just one more task" and lose track on the way out.

**Closing means: land or push what is finished, mark the order file, rewrite the role's state
file, close. No handover document.** This is a change from an earlier version of the method.
Two seats once retired at their floors mid-order and each wrote a four-thousand-word handover
— spending, on the way out, exactly the memory the retirement was meant to protect, and
restating what the order file already held. The order file and the boot digest are the
handover; the state file is the note on the desk.

**The doorman.** The floor can be enforced rather than hoped for: a hook that runs when a
turn ends reads the chat's context use and, at or over the role's floor, writes a "retired"
marker that makes every later message to that chat bounce to the next holder's inbox. The
same hook refuses to let a turn end with changed tracked files unless the state file is among
them — so the state file is always current when the doorman closes the door. One caution from
its own blind review: "idle" must mean the chat has stopped working, never that the *owner*
has been silent for a while.

---

## Wake messages are notifications, never authorization

A message reaching a sleeping or paused seat is information, nothing more; it grants no
permission to act. The go-ahead always comes from the project owner, said directly in that
seat's own chat. A seat woken by a message and finding no such go-ahead there holds where it
is, rather than assuming the message was permission.

---

## When not to do this

This pattern carries real overhead — separate folders, signed notes, a commander — and is
only worth paying past a certain size.

**Don't use it when:**

- The project is small enough for one chat to hold in its head. Most are.
- The tasks depend on each other in a strict chain — running dependent work in parallel chats
  is pure overhead with a collision risk bolted on, since one chat's output is the next chat's
  input anyway.
- You are debugging. Debugging wants one mind holding the whole picture, not several partial
  ones comparing notes through files.

**Do use it when:** the work genuinely splits into independent areas, the project has outgrown
one chat's memory, and getting something wrong is expensive enough to justify a role whose
entire job is arguing with the plan before it gets built.

---

## The shortest possible version

1. Chats cannot see each other — coordinate only through files in the project, never through
   memory of a conversation.
2. Give each chat one role, with a clear list of what it must never touch.
3. Every seat gets its own private folder (a worktree) — no shared workspace to collide over;
   the shared machine (installs, servers, hooks) is touched by one named steward only.
4. Land finished work by fetching, rebasing, and fast-forward pushing — never force, never
   merge in the shared folder.
5. Keep a live notes file, a plan file, a decision log, a mistakes ledger, a parked-work file
   — live items only, closed items archived, each channel with a size band; and one short boot
   digest and one state file per role, so a fresh chat reads a page, not the channel.
6. Sign every entry with role and a real clock time; never rewrite someone else's entry.
7. One commander (the Planner) routes every cross-seat request; decisions happen only in its
   chat, one go per task; every other seat reports in three lines. The Planner writes each
   stage's done-list — behaviours, never file states — before the first task goes out.
8. A wake message is information, not permission — the go-ahead always comes in that seat's
   own chat.
9. At most two dev seats at once; one heavy test run at a time; a seat past its context floor
   lands, marks the order, rewrites its state file and closes — no handover essay.
10. Tell the project owner in the chat itself — a note filed in a shared file is not the same
    as telling anyone.
