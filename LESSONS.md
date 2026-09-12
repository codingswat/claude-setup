# Lessons

This is from someone who isn't a coder. I run all my coding through Claude Code — I read the
plan and the results, not every line it writes — and the rules in my setup exist because I
can't fully check the code myself, so the process has to catch what I'd miss. I publish as
`codingswat`. Every lesson below was paid for once, in a real working session, before it
became a rule — copy the habit of writing your own down after a real mistake, not just the
words below.

Each lesson is four lines: what to remember, the real incident that taught it (no names, no
dates, no project details — just "once" or "three times in one session"), the one sentence
you can paste into your own rulebook, and whether anything actually enforces it automatically
or it's just a habit you keep by repeating it.

---

## Proof, not promises

### Ask for the command, not the claim

**Lesson** — don't take "it's done" for an answer — ask for the exact command that was run and
its real output.
**What happened** — more than once a chat reported a fix was finished when it wasn't. A check
that literally cannot fail isn't a check at all — it just looks like one. Breaking something on
purpose once, to watch the check turn red, has been worth the extra minute every time.
**The rule to copy** — before you believe "it's done," ask for the exact command that was run
and its real output, and once in a while break the thing on purpose to prove the check can fail.
**Enforced by** — habit.

### See it running, not just passing

**Lesson** — a passing test is not the same as a working app — ask to see it running on the
actual screen.
**What happened** — a test suite has gone green more than once while the thing you'd actually
look at was broken the whole time on screen. Tests that never touch a real window can't see a
broken button, a missing translation, or a layout that only breaks at one screen size.
**The rule to copy** — for anything visual, ask to see it running in the real app — the exact
page or file, and say if it needs a server started first — not just a passing test report.
**Enforced by** — habit.

### A test has to be provably two-sided

**Lesson** — nothing is finished until there's a check that would actually catch it breaking
again, proven both ways.
**What happened** — a check tested only on the good case has let real problems straight
through, because nobody ever tried the broken case to see if it would notice.
**The rule to copy** — before calling anything done, prove its check fails on a broken version
and passes on a working one — one-sided proof doesn't count.
**Enforced by** — habit.

### Two failed fixes means stop guessing

**Lesson** — after two failed attempts at a fix, stop trying variations and go find the actual
cause first.
**What happened** — real time has been burned trying a third and fourth version of the same
broken fix, each one wrong in the same way as the last, because nobody stepped back to ask why
the first two hadn't worked.
**The rule to copy** — after two failed fix attempts, stop, roll back to the last working
version, and get a plain explanation of the real cause before touching the code again.
**Enforced by** — habit.

### Security review before anything goes live

**Lesson** — run a dedicated security check before anything you built goes live, goes public,
or gets shared past your own machine.
**What happened** — AI-written code ships with real security holes at a high rate, because the
model is optimizing for "it runs," not "it's safe." This step exists specifically to catch that
gap before a stranger finds it for you.
**The rule to copy** — before any deploy, before a repo goes public, and before sharing an app
beyond your own machine, run a dedicated security check and treat anything serious it finds as
non-negotiable.
**Enforced by** — habit (there is a dedicated review checklist for it, but you still have to
run it).

### Get a genuinely blind second opinion before anything permanent

**Lesson** — before any one-way step — going public, a real deploy, sending work outside your
own machine — get a second, completely blind look from a chat that knows nothing about the
project.
**What happened** — a review that already knows a project's history shares its blind spots. A
genuinely blind reviewer — no memory, no rules file, no backstory, just the finished thing and
the question "how could this be bad for me?" — has found real leaks (leftover file paths and
settings that could identify the owner) that a briefed review had completely missed.
**The rule to copy** — before anything irreversible, open a brand-new chat with no project
files or memory loaded, hand it only the finished thing, and ask "how could this hurt me, and
what's missing?" — fix what it finds before you take the step.
**Enforced by** — habit.

### Whole-picture proof, not a close-up

**Lesson** — when you're shown a picture of your own work, ask for the whole thing, not a tight
zoomed-in crop.
**What happened** — evidence for a finished piece of work once arrived only as close-up,
annotated crops. The complaint was simple and fair: "don't zoom in too much, I get confused" —
a crop can't be checked against the whole picture you actually care about.
**The rule to copy** — ask for the full, whole-object view alongside a plain, unmarked original
at the same size — treat any close-up as backup material, never the main proof.
**Enforced by** — habit.

## Git and things you cannot undo

### One working feature, one commit, pushed now

**Lesson** — the moment a piece of work actually works, save it (a "commit," a labeled snapshot)
and send it somewhere safe (a "push") — don't let finished work sit unsaved.
**What happened** — this had to be said three separate times in one sitting before it stuck.
Work that worked was sitting unsaved, at real risk from a crash, an accidental undo, or a chat
that goes sideways.
**The rule to copy** — the instant a feature works, commit it and push it — one working
feature, one commit, immediately, not batched up for later.
**Enforced by** — habit.

### Finished work lands on the real version

**Lesson** — on your own solo project, finished and tested work goes straight into the one real
version — no side copies left dangling.
**What happened** — work has sat finished on a side branch (an unmerged parallel copy) instead
of being folded into the real thing, so it never actually shipped and had to be found and
re-merged later.
**The rule to copy** — on a project that's only yours, merge tested work into the main version
and delete the side copy; on any project with teammates or protected branches, follow that
project's own process instead of overriding it.
**Enforced by** — habit.

### Clean up your own mess

**Lesson** — temporary servers, scratch files, and stale side branches get cleaned up the
moment they're no longer needed.
**What happened** — test servers and throwaway files have been left running or lying around
after a task finished, quietly using resources and confusing the next session about what's real.
**The rule to copy** — at the end of every task, close any temporary server, delete scratch
files and stale branches, and say out loud if anything is still running.
**Enforced by** — habit.

### Back up the data before you touch its shape

**Lesson** — back up your actual stored data before any change that touches how it's structured
or stored.
**What happened** — saving your code is not the same as saving your data. A rollback to an
older commit undoes code; it does not bring back a row that a bad database change deleted.
**The rule to copy** — before any database or storage change, take a real backup of the data
first, and treat "I can just roll back the code" as false comfort.
**Enforced by** — habit.

### Name it, then get a real yes, before anything permanent

**Lesson** — before anything that can't be undone — deleting your files, force-pushing over
history, wiping a database, making something public — stop and get your explicit yes first.
**What happened** — this covers everything from a plain "please don't delete a file I made
without asking" up to bigger one-way doors: overwriting history, deleting branches or data,
dropping a database, changing hosting, publishing something, or making a private project
public. Naming the exact action and its consequence, then waiting for a plain yes, has caught
mistakes that would otherwise have been permanent.
**The rule to copy** — before anything irreversible or outward-facing, state exactly what
you're about to do and what it costs if it's wrong, and wait for an explicit yes — don't treat
silence, or a vague "sounds good," as that yes.
**Enforced by** — a hook that blocks the most dangerous git commands before they run (a forced
history overwrite, a hard reset, a branch deletion); everything outside git is habit.

### Secrets never go in the code itself

**Lesson** — passwords and API keys (a private password your own code uses to talk to another
service) never get typed directly into your code.
**What happened** — a key or password committed into a project's history is effectively there
forever — deleting the line later doesn't erase it from every copy and cache that already
exists.
**The rule to copy** — keep secrets in a separate, ignored settings file (commonly `.env`),
never in the code itself, and remember they must be set again, separately, on whatever service
actually hosts the app.
**Enforced by** — habit.

### Back up your assistant's own rules, too

**Lesson** — if you build up your own written rules for your AI assistant, back that file up
automatically, and make the backup refuse to run if it spots something secret-shaped.
**What happened** — once, to prove the safety net actually worked, a fake-looking secret was
deliberately planted in a changed file — the backup refused to send it anywhere. Removed, the
backup resumed on its own, no manual fix needed.
**The rule to copy** — automate the backup of your assistant's own rules the moment they
change, and have that automation scan for anything secret-shaped and refuse to proceed if it
finds one.
**Enforced by** — an automatic end-of-turn backup script that also refuses to push while a
secret-looking string is present in the changed files.

### Commits are recorded under your name

**Lesson** — make sure finished work is recorded under your own name, not the assistant's.
**What happened** — without a check, commit messages can end up attributed to the AI, which is
both inaccurate (you directed the work) and, for anyone publishing under a chosen name, a real
identity risk.
**The rule to copy** — set your own name and email as the author on every commit, and strip any
"co-authored by AI" line from every commit message.
**Enforced by** — a commit-message hook and a pre-commit hook that refuse commits attributed to
the assistant.

### One public identity, checked every time

**Lesson** — if you publish under a chosen name rather than your real one, use exactly that
name everywhere, and check every commit before anything goes public.
**What happened** — checking only the commit log isn't enough — tags, packaging files, docs,
screenshots, and even file paths embedded in logs can all leak a real identity that a quick
commit-log check would never show. Public history is effectively permanent: copies and forks
keep it even after you "fix" it.
**The rule to copy** — before anything goes public, run a full identity check across commit
authors, tags, package metadata, docs, screenshots, and any embedded file paths — not just the
commit log.
**Enforced by** — the commit-authorship hooks above catch the git half; the rest is a manual
check.

## Talking to Claude

### Add alongside, don't quietly replace

**Lesson** — ask your assistant to add new code next to what already works, not rip it out and
replace it, unless it argues the case and you agree.
**What happened** — working code has been swapped for a "better" rewrite without being asked
first, losing something that was fine while chasing something supposedly nicer.
**The rule to copy** — default to adding alongside what already works; if a replacement is
truly better, have it argue the case to you and let you decide — don't let the swap just happen.
**Enforced by** — habit.

### Agree on your stop words

**Lesson** — agree on two exact words with your assistant — one that means "wrap up gently,"
one that means "stop right now" — and expect them obeyed literally.
**What happened** — without agreed words, a "pause" and a "stop" get treated the same, or get
ignored mid-task. Defining them once made both reliable.
**The rule to copy** — define "pause" (finish what's already running, start nothing new, report
back and wait) and "stop" (interrupt everything immediately, even mid-task) as fixed control
words.
**Enforced by** — habit.

### Don't stop while the road is clear

**Lesson** — let your assistant keep working through a whole task without stopping to check in
after every single step.
**What happened** — in the owner's own words: "Don't stop as long as the road is clear for
you... if I don't respond and you can continue, just continue, and the next time you need my
input just ask me the accumulated questions."
**The rule to copy** — tell your assistant to keep going through ordinary work without asking
permission at each step, save up real questions, and raise them together, once, when it
genuinely needs an answer.
**Enforced by** — habit.

### A question is not a green light

**Lesson** — "what do you think?" is asking for an opinion, not permission to go build it.
**What happened** — in the owner's own words, after a tool got installed when only a review had
been asked for: "Don't do unless it's clear that I want you to start an action."
**The rule to copy** — treat "thoughts?", "review this," or "what would you do?" as a request
for a recommendation only, and wait for an explicit go before anything gets built, installed,
or changed.
**Enforced by** — habit.

### Ask for the smallest change, not a rewrite

**Lesson** — ask for the smallest working change, not a rewrite of things nobody asked to touch.
**What happened** — reused code and existing tools beat brand-new dependencies almost every
time, and code left un-touched right next to the actual fix isn't a bug — it's the point.
**The rule to copy** — ask your assistant to touch only what the task actually needs — no
drive-by cleanup of nearby code or formatting; flag anything genuinely dead instead of quietly
deleting it.
**Enforced by** — habit.

### Announce, don't ask, for ordinary tool use — but warn first for anything that reaches you

**Lesson** — your assistant should say out loud, the moment it happens, whenever it opens
another app on your computer — and it must warn you, with the reason, before anything that
would send a message, a code, or an email to you.
**What happened** — in the owner's own words, after an assistant opened another program
mid-task without mentioning it: "If you're going to use the apps on the computer, inform me
please, don't stop, just inform me." Separately, once, a helper triggered a login code to the
owner's own inbox with no warning: a code that arrives with no warning and no way to tell who
requested it is exactly what a phishing attempt looks like.
**The rule to copy** — have it say "I just opened [app]" the moment it does, without stopping
to ask — but require a heads-up with the reason BEFORE any step that would send you a message,
a code, or an email, never after.
**Enforced by** — habit.

### Keep a written list of your machine's traps

**Lesson** — every computer has quirks that silently eat hours; write each one down the day
you find it, in the same file your assistant reads at every start.
**What happened** — a config folder owned by the wrong user broke a tool login with no error
message, and a second copy of a language runtime dropped mouse clicks in one kind of window.
Each cost a session to find, and would have cost another the next time without the note.
**The rule to copy** — keep a "this machine" section in your assistant's rulebook: one line per
trap, what it broke, and the workaround; add to it the moment a new one is found.
**Enforced by** — habit.

## Money and models

### Small chores go to the cheapest model that can do them

**Lesson** — send simple, well-defined chores to a smaller, cheaper AI model — save the
expensive one for real judgment calls.
**What happened** — in the owner's own words: "Try to conserve context and use agents; use the
lowest model possible." The test that decides it: if explaining the change to a helper would
take more words than just making the change, do it yourself; if it's bigger than the
instructions, hand it to the cheapest model that can actually do it.
**The rule to copy** — keep three tiers in mind: a small model for fully-specified mechanical
work, a mid-size model for anything needing a real choice, and your best model only for a final
verdict or review — default every task to the cheapest tier that fits.
**Enforced by** — habit.

### Weigh the payoff against the cost before spending big

**Lesson** — before a big research task or a job that spins up a lot of AI helpers, ask whether
the answer is even worth what it will cost.
**What happened** — once, a review that spun up dozens of AI helpers at the same time burned
through a whole week's usage limit in one sitting, and roughly half of what it found turned out
to be noise, paid for twice.
**The rule to copy** — state the expected cost and the expected payoff in one line before any
big or multi-helper job, and get an explicit yes before anything that would spin up more than
around ten helpers at once.
**Enforced by** — habit.

### A real hurdle stops and asks, it doesn't just push through

**Lesson** — when a task hits something bigger than expected — a big cost, a design reversal, a
third attempt after two failures — stop and ask before spending more to push through it.
**What happened** — in the owner's own words: "For any major hurdle, ask me before spending
resources on it," said after a session had spent real time chasing a side question that turned
out not to matter at all.
**The rule to copy** — on a real hurdle (much bigger scope, a costly fix, a third attempt, a
reversal, or open-ended exploration with no clear end), stop that one item, present it with a
clear recommendation, and keep working on everything else that doesn't depend on the answer.
**Enforced by** — habit.

## When one chat is not enough

### Write decisions and mistakes down, not just in the chat

**Lesson** — write every real decision (what, why, what it rules out) and every real mistake
(what happened, the actual cause, the cost) into a plain file, not only into the chat.
**What happened** — a chat that hasn't seen an earlier conversation will happily reopen a
settled decision, or repeat a mistake that's already been made once. A short, append-only
written log is the only memory that survives between separate chats.
**The rule to copy** — keep a running decisions file (three lines per choice: what, why, what
it rules out) and a running mistakes file (one line: what, cause, cost, status), and promote a
repeated mistake into an actual rule the second time it happens.
**Enforced by** — habit.

### A chat is bound to the exact folder it started in

**Lesson** — don't move, rename, or delete a project's folder while a chat is still open and
working inside it.
**What happened** — a chat's whole sense of "where am I" — its working folder, its history, its
memory of the project — is tied to the exact file location it started in. Move the folder
mid-session and it loses that thread entirely.
**The rule to copy** — before reorganizing any project folder, close or pause every chat
working inside it first, move the folder, then start fresh chats at the new location.
**Enforced by** — habit.

---

## Not in this file

- **"Never delete files I made without asking first."** Folded into the "name it, then get a
  real yes" lesson above (irreversible actions): the private rule this comes from is explicitly
  described as the umbrella over this one, so one lesson covers both rather than repeating the
  same "ask before removing anything" idea twice.
