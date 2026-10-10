---
name: coding-method
description: Use before writing or changing code for a feature or a fix, when starting a new project, before committing or landing code, when a change grows beyond its request, and when cleaning up (stopping servers, removing branches or worktrees, moving or deleting a project folder), and when writing a NOTES, DECISIONS or MISTAKES entry or parking a problem or an idea.
---

# Coding method — from a request to landed code

Nine steps, in order, for every change; a one-line fix runs them fast and skips none. Tests and checks: the `testing-method` skill, inside steps 2–5. Rules the owner's global rulebook also states are written out here in plain words. Skills named here that this kit does not ship are listed with their sources in `skills/ATTRIBUTION.md`; without one, do that step by hand as described. The same steps bind with seats or without: a seat only decides who does a step. The chat starts each skill named below itself, at its step; the owner never has to name one.

**Force.** A project may skip a step drawn from the coding rules where it costs more than it protects, with one line of why in its decision log. A rule the global rulebook states never skips. The owner's word overrules both.

**Optional rules** (marked *optional* below) bind only a project whose CLAUDE.md names them.

## 1. Understand

**When:** a request arrives. **Do:**
- Read every file the change touches as it is now, in this session, never from memory or another document's description; current state comes from the repo (tests, `git log`).
- Test an absence claim ("nothing writes Y") on the running program: read what writes it, or try to make it happen.
- Measure reach by what consumes the changed thing (callers, screens rendering it, downstream fixtures and recorded outputs, other tasks reading the same data), never by the files you edit.
- Read the area's decision log and the word list. A settled decision in your way is reopened out loud (the decision, the reason it did not weigh, a recommendation) for the owner to decide; one marked 🔒 LOCKED stays shut.
- Check before asking; ask every foreseeable question in one message, not one at a time.

**Done when** every touched file and every consumer is named from a read made this session, and the area's decisions are read.

## 2. Plan

**When:** before any code. **Do:**
- Write each behaviour as a done-when line: an input it must refuse (or act on) and one it must allow, never a file's state; `testing-method` step 1 turns each into tests.
- A screen, flow or interaction: `walkthrough` (storyboard before any mockup, rehearsal before "done"); then one page shows the owner the finished screens, and screen code waits for the answer.
- A foggy idea: `grilling` (interview the requester one question at a time until the idea is sharp). A question only running code answers: `prototype` (build a throwaway to answer it). A build bigger than one session: once its plan is settled, `to-spec` publishes the spec as a GitHub issue in the project's repo, `to-tickets` cuts it into task issues (each with its done-when lines and "waits for" links), and the owner approves the done-when lines before the first ticket starts; `implement-spec` then works through them: helpers build each ticket by steps 1 and 3–6 (each re-reads the code itself; exploration notes are a pointer, never a substitute), the managing chat checks and lands them (steps 5 and 7) and runs step 9 at the spec's end; each ticket's acceptance criteria stand as step 2's lines.
- A paid AI service: a spending cap, a cost log per job, a limit per visitor; the owner hears before anything costs money.
- A new project: the stack that fits the idea best, the known-good options below weighed, never defaulted to. The pick, why, and the runner-up go to the owner before building, then to the decision log; versions the owner names are taken as given. Then create the project's files (below).
- Known-good options to weigh, never to copy: TypeScript end-to-end; React + Vite + React Router v7 + TanStack Query + Shadcn/ui; Hono for new backends (Express stays where it already ships); Drizzle ORM; Postgres for real users, SQLite for small tools; Better Auth; direct-to-storage signed URLs for uploads (privacy check first).
- A new project's files (a small tool may merge them): README.md (what it is, how to run it, how to test it); CLAUDE.md (what binds here, which optional rules it takes); DECISIONS.md and MISTAKES.md (tasks, specs, parked problems and ideas are GitHub issues, step 6; `DEBT.md` and `IDEAS.md` only without a GitHub repo); CONTEXT.md (word list); ARCHITECTURE.md (folder map); a what-breaks page; TESTING.md (which suites exist, how to run each, what each proves). When the project has the thing: a deploy checklist (every gate before a release, in order); a rules changelog; data-format contracts (versioned); a design spec and roadmap (finished plans archived); research notes (one file per question, each claim cited); project skills (a procedure repeated three times).
- *Optional:* storage truth: write down what is kept where; raw uploads are never stored durably; no real customer data on the dev machine. Record the project's frameworks, database and hosting in its CLAUDE.md, with why they fit.

**Done when** every behaviour has its refuse/allow pair, any screen has the owner's answer, and a new project's stack is answered and recorded.

## 3. Build the smallest change

**When:** the plan is written. **Do:**
- Each behaviour through `testing-method`, red before the code.
- Write less: reuse what the codebase has, then the standard library, native platform features, an installed dependency (an installed design system beats native HTML); only then the least new code, never thinning the correctness machinery (refusal rules, disclosures, break-it proofs, pins). A module's shape: `codebase-design` (prefer a few deep modules with small interfaces over many shallow ones).
- Touch only what the request needs: adjacent code, comments and formatting stay; unrelated dead code is named to the owner and left. Add alongside what works; if replacing is truly better, argue it and let the owner decide.
- A new dependency's licence passes the project's CLAUDE.md (some bar AGPL in anything shipped; *optional rule:* no AGPL code in anything shipped, because it can force you to publish your own source). A skill or plugin from outside gets `skill-security-auditor` (read it for hidden instructions, network calls and file access) before it is installed, and nothing is installed without the owner's yes.
- Secrets live in `.env`, gitignored; tell the owner to set each on the hosting service at deploy.
- Lay out code so each parallel worker owns its own files (one per feature, screen area or content unit), edits no other's, and reads only what its job needs. Helpers run side by side only when neither needs the other's result (`briefing-subagents`).
- A token budget is a measurement to report, never a reason to shrink the work silently.
- Growth beyond the request: small and the same kind, flag it with evidence and proceed. A new feature, money, a change to existing users' output, or a reversed decision: stop and ask, with options and a recommendation, all questions in one message.

**Done when** every behaviour is green by `testing-method`, the diff holds only what the request needs, and any growth was flagged or asked.

## 4. When stuck

**When:** a fix has failed twice, or you would drop an approach. **Do:**
- Two failed fixes: stop, roll back to the last green state, run `diagnosing-bugs` (reproduce, minimise, form and test hypotheses one at a time), and explain the root cause plainly before touching code again. Before a third attempt, write down the one assumption both failed fixes shared and test that assumption first; a blind opus reviewer checks the work.
- An idea dies only with proof: the reason it fails and a failed repair. Otherwise park it with its wake-up condition.

**Done when** the root cause is named in plain words and the next attempt aims at it, or the idea is parked with its kill evidence and wake-up condition.

## 5. Compare to the plan

**When:** green, before the records. **Do:**
- Quote each plan line the change satisfies (task, ticket, done-when line) with "match", or how it differs and why.
- **One review per moment:** every change gets the independent check; a whole multi-task branch against its spec gets `two-axis-review` (one pass for whether it meets the spec, one for code quality); a guard or code check gets the blind break round (`testing-method`); a release that touches data gets fresh eyes (`going-live`). A guard's break round counts as its independent check; the checks before a deploy (`going-live`) always run.
- **The independent check:** a helper that never saw the change (a fresh context: `sonnet`; `opus` for a guard, a large change or a verdict) gets the done-when lines, the diff and the test command only, and checks the work against the lines FIRST, then the standards. One helper may do a screen's checks (`testing-web-ui-two-sided`) and this check together. Where a managing chat reviews its helpers' diffs, that review is the check for their work; the managing chat's own edits still get a helper. Its findings are fixed, or answered with why not, before step 7; its answers go in the report unchanged.

**Done when** every plan line the change claims is quoted with its verdict, and the independent check's findings are each fixed or answered.

## 6. Records, in the same save as the change

**When:** before the commit; each record moves in the commit that changes what it describes, in the files the project's CLAUDE.md names. **Do:**
- **Decision log:** each significant choice: what, why, what it rules out.
- **Mistakes ledger:** each mistake you catch: what, root cause, cost, pointer, status; in the fix's commit where possible. Three similar lines: propose a rule to the owner.
- **Tasks:** the commit that finishes a task issue closes it (`closes #N` in the message); a finished task's proof goes in a comment on it. Decisions and rules stay as files in the repo.
- **Parked problems and ideas:** each problem put off is a GitHub issue labelled `parked`: what, why it waits, what wakes it; an idea is one labelled `idea`. Unparking closes or relabels it in the unparking commit. A project with no GitHub repo keeps them in `DEBT.md` and `IDEAS.md`, one line each. **On a public repo, issues are public:** a security problem, or anything private, never goes in an issue, a spec issue or a tracked file; it goes to a private tracker or a private note outside the repo. At a chat's start, list the open `parked` issues (`gh issue list --label parked`).
- **Word list:** read before naming a thing or writing screen text; add terms you coin (`domain-modeling`).
- **Folder map, what-breaks page** (fragile spots and how they fail) and **any reference page** whose subject you changed: updated, with its "last checked" line.
- **Signatures:** an entry in a shared file names its writer and the time copied from the clock in the same command; another's entry is never rewritten, only added beneath.
- **Contact details:** a tester's or user's address never enters a tracked file; a letter or note id names the person.

**Done when** the commit's file list holds every record the change touched, beside the code.

## 7. Commit and land

**When:** steps 1–6 are done; the project's own workflow (its CLAUDE.md or a project skill) comes first. **Do:**
- One working feature, one commit, pushed straight away.
- Read the content you stage (`git diff HEAD -- <paths>`), then commit by named paths (`git commit <paths> -m …`); a staged path you did not write means stop.
- Commits carry your own publishing identity and no AI attribution line, whatever a tool's default adds — unless the repo's own contribution rules require AI disclosure; then they win. Use only your own git identities; an AI assistant's address is never one.
- Gates chain by exit code with `&&`, never piped (`testing-method` step 8).
- The owner's solo repos land on `main` by rebase and fast-forward: `git fetch origin && git rebase origin/main`, confirm the rebase finished, `git push origin HEAD:main`; on "non-fast-forward", repeat; a conflict: `resolving-merge-conflicts` (find what each side meant, resolve, re-run the tests). Never `--force` or `--no-verify`. A repo with a team, branch protection or PR checks follows its own workflow, never bypassed.
- "I'll review it later" means land nothing until the owner says; "just finish it" means land after real verification.
- Anything live or public: the owner's yes comes last, and `going-live` first.

**Done when** the push prints `<old>..<new>` onto `main` (or the project's workflow shows it merged), or the commit waits on its branch for the owner's review; the report says which.

## 8. Clean up

**When:** after landing, or when the session ends. **Do:** Tell the owner what still runs. Stop only your own processes, by PID, never with pkill, killall, or by port or pattern. Remove your merged branches, finished worktrees, scratch dirs and leftover docs without asking; untracked files go to the Trash (on a machine without one, a dated holding folder), never a hard delete; files a project's docs cite are records, not leftovers; unmerged work and backups stay. Never move, rename or delete a project folder while any session is open in it (sessions bind to the exact path): close them first, reorganize, reopen. Ending mid-task: `handing-off-live-work`.

**Done when** nothing you started runs unannounced and no branch or worktree of yours outlives its merge.

## 9. Learn — at a phase's end

**When:** a phase or a big build (a spec's last ticket) has landed; skipped for a single change. **Do:**
- `retro`: what slowed the work or let a mistake through, findings ranked in chat; a rule change is proposed to the owner, never made.
- `improve-codebase-architecture` (survey the code for shallow modules and tangled seams) when the retro says a survey is due (one area needed fixing twice this phase, or three phases since the last survey): the survey ends on a pick page, and nothing changes before the owner's pick.

**Done when** the retro's findings are in chat and, when due, the survey's pick page is sent.

## Common failures

- Editing from what a file said an hour ago.
- "Nothing else uses this", checked only in the edited folder.
- Tidying adjacent code on the way; the diff hides the change.
- `<test> | tail` as a gate: exit 0 on a failing suite.

## Example — "add a `since` date filter to the orders list"

1. Read `orders/list.ts` and its tests; consumers: the admin screen, the nightly report; the decision log: dates are UTC.
2. `since=2026-01-01` returns orders on or after it; no `since` returns all; `since=yesterday` is refused with a 400.
3. Red first; parsing reuses the existing `parseIsoDate`.
4. Not reached.
5. Lines 1–2 match; line 3 differs: a 422, the API's convention for bad input (decision log). The independent check (a fresh `sonnet` helper, lines and diff only) finds the nightly report not re-run; re-run, 0 changes.
6. Word list: "since filter"; parked: issue #41 labelled `parked`, "admin screen filter; waits for a screen request".
7. `git commit src/orders/list.ts src/orders/list.test.ts CONTEXT.md -m "… closes #38"`; `<test> && <lint>` exits 0; rebased; pushed `a1b2c3d..e4f5a6b HEAD -> main`.
8. Dev server stopped by its PID; branch deleted.
9. Skipped: a single change, not a phase's end.

**Project part:** if the project has `.claude/skill-parts/coding-method.md`, read it now; where it is more specific than this skill, it wins.
