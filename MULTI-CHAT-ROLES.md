# Running several Claude chats on one codebase

*A pattern for when one conversation is no longer enough. Everything here was learned by
doing it — including the parts learned by getting it wrong.*

---

## The problem this solves

A single Claude Code session has one context window and one train of thought. Past a certain
project size, you hit three walls at once:

- **The context fills up.** The session that designed your architecture in the morning has
  forgotten the details by evening, because it spent its attention on boilerplate.
- **You want different thinking at different moments.** Planning wants a careful, expensive
  model. Renaming forty variables does not. Paying the same rate for both is waste.
- **You want more than one thing happening.** Design work and backend work do not need to
  take turns.

The obvious answer is to open several chats. The obvious problem is that **chats cannot see
each other.** They do not share memory. Two sessions editing the same file will each happily
overwrite the other's work and neither will notice.

The pattern below fixes that, and the fix is not clever: **give every chat a named role and a
zone it owns, and make the files in the repo the only channel between them.**

---

## The one rule everything else rests on

> **Chats coordinate through files in the repo, never through you.**

You are not a message bus. If the only place a decision exists is in your memory of a
conversation you had two chats ago, it will be lost. Every ruling, every claim on a file,
every open question lives in a file that all the chats can read.

---

## The roles

Five roles, each with a model tier and — more importantly — a list of what it must **never**
touch. The "never" list is what makes this work.

### Planner
*Best model you have.*

**Owns:** specs, the implementation plan, the interface contracts between components, the
decision log, and arbitration when two chats disagree.

**Never writes product code.** This is the constraint that makes the role valuable. A chat
that plans and builds will quietly reshape the plan to suit whatever it just wrote.

### Designer
*Best model you have.*

**Owns:** the visual and interaction design — the design constants (type scale, spacing,
colour, motion), the mockups, and the design briefs handed to other chats.

Worth knowing: this role works far better when your design decisions have been **ratified as
constants** in a file first. Otherwise every chat re-invents the spacing scale. And present
the user with *rendered options*, never prose descriptions of options — nobody can choose a
layout from a paragraph.

*Optional extension:* the Designer can also implement the front end, provided it stays
strictly presentation-only and never reaches into business logic. If you allow this, write
the boundary down explicitly, or it will erode.

### Advisor
*Best model you have.*

**Owns:** challenging your thinking *before* decisions get made — research, measured
comparisons, auditing decisions already taken, and interrogating requirements you have not
thought through.

**Writes no code and no plans.** Its output is a document the Planner then plans from.

This is the role people skip, and it is the one that prevents the most expensive mistakes.
Every other role is trying to help you build the thing. This one is trying to find out
whether the thing is right.

### Senior Dev
*Best model you have.*

**Owns:** executing the current phase of the plan, the genuinely hard code, and reviewing
and merging junior work.

**Its most important habit: it does not type routine tasks into its own context.** It
dispatches a subagent per task and reviews the result. Its own context is the scarce
resource — spending it on boilerplate is exactly why senior chats fill up and get stupid.

### Junior Dev
*Cheap, fast model.*

**Owns:** exactly one task at a time, as written. If the task is unclear, or doing it needs a
file outside its zone, it **stops and writes a note** rather than improvising.

---

## Choosing the model for each piece of work

State the model explicitly, every time. Never leave it to default.

| Kind of work | Model | Why |
|---|---|---|
| Weighing evidence, deciding what something means, resolving contradictions | Expensive | The right answer is not already in the brief |
| A task whose interfaces are already written; mechanical fixes; exact copy changes | Cheap | The thinking already happened |
| Retrieval, fact-checking, mechanical sweeps across many files | Cheap | Volume, not judgement |

**The asymmetry matters.** A too-expensive model on boilerplate wastes money. A too-cheap
model on a judgement call returns a confident wrong answer that has to be found and redone.
The second failure costs far more, so when genuinely unsure, go up a tier.

There is also a quiet trap: if the orchestrating chat is running an expensive model and you
omit the model on a subagent, you often get *another* expensive model for boilerplate. Say it
explicitly.

**A useful test for whether to delegate at all:** if explaining the task to a subagent takes
more words than just doing it, do it yourself. If the task involves reading or writing a lot
more than its briefing, delegate it.

---

## The coordination rules

These are the ones that came from real collisions. Each exists because something went wrong.

**1. Pull before you start. Commit and push per finished task.** Uncommitted work in a shared
repo is exposure. Never sit on finished work.

**2. One owner per zone at a time.** Split the codebase into zones — typically one per
package or app. The plan file records who owns what *right now*. Never edit outside your
zone; if you must, stop and write a note instead.

**3. Interface contracts are frozen, and only the Planner changes them.** When components
talk to each other through an agreed shape, that shape is changed in one place, by one role,
with a version bump and a decision-log entry. A dev chat that needs the contract to grow
**stops** and files a request. This single rule prevents the worst failure mode in
multi-chat work: two chats independently "fixing" an interface in incompatible ways.

**4. The plan file is the single source of truth** for what is done, in progress, and next.
Chats mark tasks with their role name when they claim one and when they finish it.

**5. Significant choices go to the decision log** — what was decided, why, what it rules out.
Any role can append; the Planner curates.

**6. Keep one standing channel between chats.** A single `NOTES.md`, newest first, signed with
role and date. Contract requests, open questions, findings that outlive one plan file. Plan
files are archives once complete — don't append live discussion to them.

**7. Hold that channel to live items only.** Whoever closes an item moves the resolved entry
to an archive file in the same commit. Without this the notes file grows until no chat reads
it, which is the same as not having one.

**8. A task is not done until its paper trail moves in the same commit.** The plan checkbox
ticks, the status page updates, and the note lands *together with the code*. A stale checkbox
is a bug — it makes the next chat do work that is already finished.

**9. Every change signs its changer, in words, inside the file.** All the chats commit under
your git identity, so git history genuinely cannot tell them apart. The in-file signature is
the only durable record of who did what. Use full role names — codes need a legend, and fresh
chats invent colliding ones.

**10. Never rewrite another role's entry.** Append your amendment underneath it, signed and
dated. Editing someone else's words in a shared file is how context silently disappears.

**11. Some files have a single writer.** The project rulebook and the role definitions — the
Planner. Each role's handover file — that role. The design constants — the Designer. Anyone
else's need against those files is a request, never an edit. Shared channels (notes,
decisions, plan files) stay open to everyone, with attribution.

**12. Stage your own hunks in shared files — and read what you staged.**

This one cost four separate incidents over two days before it got written down properly.
Naming explicit file paths in `git add` stops you committing someone else's *file*. It does
**not** stop you committing someone else's *words* inside a file you are both editing. Only
staging your own changes and then reading the staged content catches that:

```bash
git add -p NOTES.md
git diff --cached          # read the actual content, not --stat
```

And if you sweep up someone else's work anyway: **say so, and leave it.** Rewriting pushed
history to fix an attribution detail is worse than the problem, and deleting the swept text
to "give it back" destroys the work in order to fix a byline.

**13. Filing something in a shared file does not count as telling the user.**

The notes, the handovers, the plan files, the decision log — that is all chat-to-chat
machinery. Most people never open it. When a chat needs a decision, an answer, or is blocked,
it must say so **in the chat**: plain language, short, enough context to decide without
opening any file, and a recommendation attached. The file entry is the record between chats.
The chat message is the ask. They are not substitutes.

---

## Making it survive a chat ending

Chats end — you close them, or they fill up. Two habits carry the work across:

- **A handover file per role.** A new chat picking up that role reads it and knows where it
  is. It is updated by that role, and updated *before* the role retires.
- **Name your sessions `Role — scope (status)`**, e.g. `Dev — phase 3, tasks 7-10 (active)`.
  When you have six chats open, this is the difference between finding the right one and
  opening four wrong ones.

---

## When not to do this

Honest limits. This pattern has real overhead — the notes, the signing, the zone discipline —
and it is only worth paying past a certain size.

**Don't use it when:**

- The project is small enough for one chat to hold. Most are.
- The tasks depend on each other in a chain. Sequential work in parallel chats is pure
  overhead with a collision risk attached.
- You are debugging. Debugging wants one mind with the full picture, not five partial ones.

**Do use it when:** the work genuinely splits into independent zones, the project outlives a
single context window, and being wrong is expensive enough to justify a role whose only job
is to argue with you.

---

## The shortest possible version

1. Give each chat a role and a zone it owns.
2. Write down what each role must never touch.
3. Coordinate through files, never through your own memory.
4. Sign everything, in the file, in words.
5. Expensive models decide; cheap models execute.
6. Tell the user in the chat — filing a note is not telling anyone.
