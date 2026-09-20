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

### Write the test first, and watch it fail before the code exists

**Lesson** — the test is written before the code and run once to see it fail; a test written
afterwards mostly proves that the code does what the code does.
**What happened** — a data-format change was built first and tested afterwards; the tests passed
on their very first run, which is exactly what a test that cannot fail looks like. "Test first"
had been the named method for months but was never in the rulebook's own words, so it slid.
**The rule to copy** — every feature's test is written before its code and run once to see it go
red; that red run, with its exit code, is quoted in the commit that lands the code.
**Enforced by** — habit, checked at review: a landing with no red run quoted is a finding.

### A guard is not done until someone else has tried to break it

**Lesson** — anything that blocks, refuses, or checks gets a second reviewer who never saw it
built, briefed only "get past it, and make it refuse honest work" — every attempt actually run.
**What happened** — four hooks and two scripts shipped in one afternoon, each with the builder's
own passing tests. A blind bypass review the next day found three ways past them and thirteen
ways to trip them on honest work: a newline after a guarded command, output piped through a
logger, an ordinary wait loop refused as dangerous. The builder's tests had checked the shapes
the builder thought of.
**The rule to copy** — before a guard counts as done, a reviewer who did not build it tries to
bypass it and to make it refuse ordinary work, runs every attempt, and the builder fixes what got
through; only then do the builder's own tests count.
**Enforced by** — habit; the attack's findings become the guard's two-sided test cases.

### Run it against the real thing once, and count what it saw

**Lesson** — before calling anything done, run it once on the real input it will meet and say how
many things it actually handled; zero is a finding, not a pass.
**What happened** — two guards over a task list passed hundreds of tests for two days while
matching zero live tasks: the tests used one naming pattern and the real list used another.
Every test was green; nothing was guarded.
**The rule to copy** — the last step before "done" is one run against the real file, fixture, or
screen, with the count of what it saw stated in words; a count of zero stops the task.
**Enforced by** — habit.

### A "done" definition names behaviours, not files

**Lesson** — when you write down what "done" means before the work starts, name what the thing
must refuse and what it must let through, never which files must exist.
**What happened** — a setup reform's done-list had eleven lines, all of the form "this file exists
with this content". Every line was met, and three real bypasses shipped, because nothing on the
list said "the guard refuses X and allows Y".
**The rule to copy** — each done line names one input the thing must refuse and one it must allow
("refuses a test piped through a pager, allows one joined with &&"), and the review checks the
work against those lines before it looks at the builder's own tests.
**Enforced by** — habit.

### A simulated browser is not proof that a finger can press it

**Lesson** — for anything a person touches on screen, a test that runs in a simulated page does
not count; only a real browser at the real screen size does.
**What happened** — twice in one day a control passed every simulated-page test and was dead
under a real finger: once because a drag handle was painted underneath an invisible tap layer,
once because the simulated page fires events in a different order than a real browser. The
simulation cannot see paint order and does not pause between listeners the way a browser does.
**The rule to copy** — a button, handle, or gesture is proven in a real browser, at phone width,
by someone who did not build it, before it is called done.
**Enforced by** — habit.

### "Nothing changed" is measured over the inputs the checks sweep

**Lesson** — a claim that a change moves no result is only as good as the set of inputs it was
measured over; use the inputs the deciding tests use, not the handful you had open.
**What happened** — a build was reported as moving no output across seventeen sample cases, and
landed. One of the deciding tests sweeps eight locations, and the output moved at one of them.
**The rule to copy** — a "nothing moves" claim names the input set it was run over, and that set
is the one the judging tests sweep, not a convenient subset.
**Enforced by** — habit.

### A change's blast radius is whoever reads it

**Lesson** — when something shared changes, test everywhere that change gets used, not just the
place it was made.
**What happened** — a change was tested only at the spot it was edited; something else that
quietly depended on it broke elsewhere, once for about eighteen hours before anyone noticed.
**The rule to copy** — after any change to something shared, test every place that reads or uses
it, not only the files that were actually touched.
**Enforced by** — habit.

### "It doesn't exist" gets checked against the real thing

**Lesson** — a claim that something is missing, that something can't happen, or a description of
what a file contains only counts once it's been checked against the actual thing — never against
memory or a quick search.
**What happened** — more than once, "this doesn't exist" turned out to be wrong, coming from a
stale memory or a search that hadn't looked in the right place. Separately, instructions handed
to helpers have stated a file's contents from memory more than once, and the helpers built on a
false premise because the description was wrong.
**The rule to copy** — before accepting that something is missing or impossible, or before
telling a helper what a file contains, check it against the real thing — never memory or a
partial search.
**Enforced by** — habit.

### A decision-informing number is measured or labelled

**Lesson** — any number that's actually going to influence a real decision either gets measured,
with how it was measured stated alongside it, or it's clearly labelled a guess.
**What happened** — five separate figures used in real decisions turned out to be guesses dressed
up as measurements; one of them reached the project owner sitting inside what looked like an
already-approved design.
**The rule to copy** — a number feeding a decision is freshly measured, with the method that
produced it named beside it, or it's labelled an estimate — never presented as fact when it's
neither.
**Enforced by** — habit.

### A comment claiming protection is not protection

**Lesson** — a code comment that says "this is safe because X is checked" is worthless unless
something actually checks X — the comment itself isn't the safeguard.
**What happened** — four separate comments, written in a single day, each claimed a safety
property was being enforced when nothing in the code actually enforced it.
**The rule to copy** — a comment claiming a guard exists names the actual test or check that
enforces it, or it plainly says the guard isn't enforced yet.
**Enforced by** — habit, checked at review: an unnamed guard claim is a finding.

### A verification command is copied from what actually ran

**Lesson** — when a set of instructions states the exact command that proves the work is done,
that command is copied from the one that was actually run — never retyped from memory.
**What happened** — a set of instructions once quoted an expected result from a search pattern
that was different from the one that had actually produced it, so the number didn't match what
running the real command gave.
**The rule to copy** — a stated verification command is pasted straight from the one that was
actually run, never retyped or reconstructed afterward.
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

### Other people's addresses never go into tracked files

**Lesson** — a tester's or a customer's email address, name, or phone number stays in the one
store built for it, never in a note, log, or plan that git tracks.
**What happened** — a relay of tester feedback carried a tester's email address into a shared notes file that git tracks. The fix was a rule, a letter per tester in every tracked file, and a scan for the next one.
**The rule to copy** — people are named in tracked files by a letter or a note id; their
addresses live only in the feedback store; a relay carrying one is a review finding.
**Enforced by** — the pre-commit privacy check, for anything on its list; otherwise habit.

### Evidence lives where git carries it

**Lesson** — a result that proves something (screenshots, measured numbers, a review's findings)
is written to a tracked path before the task is called done; an ignored scratch folder is not a
record.
**What happened** — sixteen screenshots behind a "16 pictures, 0 defects" verdict lived only in
an ignored folder inside one chat's private worktree; the worktree was removed as finished, and
the evidence went with it. The removal check had looked only at tracked work.
**The rule to copy** — every measured result a decision leans on is written to a path git tracks,
in the same commit as the claim; a folder about to be deleted is checked for untracked files,
not only for uncommitted ones.
**Enforced by** — habit.

### Never gate a commit on a piped or semicolon-joined check

**Lesson** — a check that's supposed to block a commit or push only blocks it if its pass/fail
result is chained straight into the command with a real "and" — never piped through something
else, never joined with a semicolon.
**What happened** — a failing test suite still got pushed twice, because its result had been
piped through a filter in one case, and separated from the push with a semicolon in the other —
both let the push run whether the check passed or not.
**The rule to copy** — a blocking check runs alone, its exit code is captured, and it's joined to
the commit or push with a real "and" — never filtered, never semicolon-joined.
**Enforced by** — the private setup has a hook for this, not yet published.

### Log every use of a safety-bypass override

**Lesson** — if a safety check can be bypassed with an override word or flag, every single use
of that override gets logged — when, where, and what was run.
**What happened** — checks that could be bypassed were being bypassed with no record left behind
of when it happened or why.
**The rule to copy** — every use of a safety-bypass override is logged — the time, the folder,
and the exact command — to a separate file kept just for that.
**Enforced by** — not logged by this repo's own shipped hooks today (this repo's override words
are `PRIVACY_OK`, `GITGUARD`, `SWEEP`); the private setup has a ledger hook for it, not yet
published.

### A redaction scrub must catch every spelling of a name

**Lesson** — a privacy filter that's supposed to catch an identifying name or path has to catch
every way that name can be written, not just the one spelling it was tested against.
**What happened** — a privacy filter matched a name written one way (with slashes) but missed
the very same name written another way (with dashes) — twice.
**The rule to copy** — an identifier-scrubbing filter is checked against every encoded form the
identifier could take, not just its most common spelling.
**Enforced by** — the shipped pre-commit privacy check, but only for the slash form of a home
path; the dashed form and the percent-encoded form pass it today, so those are still habit.

### A "clean" privacy scan proves nothing about untracked files

**Lesson** — a privacy scan that only looks at files already tracked by git tells you nothing
about a brand-new file that hasn't been added yet.
**What happened** — a leak-checking scan repeatedly passed clean while checking only tracked
files; a new file that actually leaked something kept slipping through because it was never
staged when the scan ran.
**The rule to copy** — run the privacy scan again after staging a change — a scan of only
tracked files proves nothing about files that are new.
**Enforced by** — habit.

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

### One go per task, not one per step

**Lesson** — a "go" covers the task and its follow-ons; a chat does not come back for a fresh yes
on a piece of work whose results you have already read.
**What happened** — a chat asked whether a fix opened by a review, and a build whose numbers the
owner had already read, each needed a new go-ahead — when go had been said an hour earlier. Each
trip is a round of the owner's attention for nothing.
**The rule to copy** — the owner's go is given once per task, in the chat that owns decisions,
recorded on the task's file, and covers the review's follow-on work; nobody asks twice.
**Enforced by** — habit.

### Design picks are clicked, not typed

**Lesson** — when there's more than one way something could look, the choice gets made by
clicking an option on the actual rendered page, not by naming a letter back in chat.
**What happened** — an owner kept typing back which mockup they'd picked from a description in
chat; asking for a real button next to each option, on the page itself, ended the back-and-forth.
**The rule to copy** — for anything visual, put the options on a real rendered page with a way to
pick one there, and read the pick back from the page — never choose from a paragraph in chat.
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
big or multi-helper job, and get an explicit yes before any run projected above a fixed price
(mine is ten dollars at list price, about five mid-size helpers or two of the best) — a price,
not a headcount, because two big helpers can cost more than ten small ones.
**Enforced by** — a Stop hook that writes one line per finished helper to a ledger with what it
cost, so the spend is visible after the fact; the yes before the run is habit.

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

### A helper that must write a file needs a helper type that can

**Lesson** — before asking a helper to leave its result in a file, check that its type has the
file-writing tool; a read-only reviewer asked for a file answers in chat instead.
**What happened** — three chats in one day briefed a review-only helper to write a report file;
that type cannot write files, so each poured a long report into the parent chat, costing the very
memory the file was meant to save.
**The rule to copy** — a brief that names an output file names a helper type that holds the write
tool; review-only and fact-check types are briefed for a short answer in chat.
**Enforced by** — habit; the brief template names the type next to the output path.

### A waiter blocks on the process, not a line in a log

**Lesson** — a script that's waiting for a helper to finish should watch for the actual job to
end, never for a line of text the job might print — because it might never print it.
**What happened** — a helper's shell once sat idle for over three hours, once for nine and a
half, waiting for text a finished job had never actually printed.
**The rule to copy** — a wait loop checks whether the job's process has exited, never whether
some expected text has shown up in its log.
**Enforced by** — the private setup has a hook for this, not yet published.

### A waiter must not watch itself

**Lesson** — a script that waits by matching a running command's name has to make sure it isn't
matching its own command line.
**What happened** — fixing the mistake above backfired once: the new wait loop searched for a
command pattern that matched its own line, so it sat waiting for itself to finish.
**The rule to copy** — a process-matching wait either excludes its own line or pins the exact
process id captured when the job started — never a pattern generic enough to catch itself.
**Enforced by** — habit.

### A helper's results have to land before its turn ends

**Lesson** — a helper chat has to write its finished results to a real, durable file before its
turn ends — not to a temporary scratch spot that disappears with the session.
**What happened** — three separate times, a helper's results died along with its own turn; once
because they'd been written to a temporary folder that a reboot wiped clean.
**The rule to copy** — before a helper's turn ends, its results are saved to a durable file the
next session can actually open — never left in scratch space or only in its own memory of the
conversation.
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

### A closing chat leaves its state in the plan, not a handover essay

**Lesson** — a chat that is retiring lands or pushes its work, marks the plan, and rewrites one
short state file; it does not write a long handover document.
**What happened** — two chats retired at their memory floors mid-task and each wrote a
four-thousand-word handover — spending, on the way out, the very memory the retirement was meant
to protect, and telling the next chat things the plan file already held.
**The rule to copy** — at retirement: push what is finished, mark the plan, rewrite one state
file under two hundred words (current task, next step, open questions, what must not be
repeated), and close; the plan and the role's boot file are the handover.
**Enforced by** — habit here; the private setup has a Stop hook that refuses to end a turn with
changed tracked files unless the state file is among them, not yet published.

### One helper commits to a shared workspace at a time

**Lesson** — if more than one helper is working in the same shared copy of a project, only one
of them may save (commit) at a time — the rest stay read-only until it's their turn.
**What happened** — two helpers once worked in the same shared copy at the same time; one
helper's in-progress files got swept into the other's commit by mistake.
**The rule to copy** — in any shared workspace, exactly one helper stages and commits at a time;
every other helper working there in parallel stays read-only.
**Enforced by** — habit.

### Parallelize by shared data, not shared files

**Lesson** — before splitting work across two helpers to run at once, check whether they touch
the same underlying information, not just whether they touch different files.
**What happened** — two tasks once ran in parallel on entirely separate files that happened to
describe the same underlying data; one task's change silently broke the other's assumption.
**The rule to copy** — before running two pieces of work in parallel, check for shared data
behind them, not only separate file names.
**Enforced by** — habit.

---

## Not in this file

- **"Never delete files I made without asking first."** Folded into the "name it, then get a
  real yes" lesson above (irreversible actions): the private rule this comes from is explicitly
  described as the umbrella over this one, so one lesson covers both rather than repeating the
  same "ask before removing anything" idea twice.
