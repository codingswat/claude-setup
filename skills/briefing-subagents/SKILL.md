---
name: briefing-subagents
description: Use when handing work to a subagent or a workflow agent — a read, a measurement, a draft, a mechanical sweep, a fix — or when choosing an agent's model and effort.
---

# Briefing subagents

The brief is the whole world the helper has; what it leaves out, the helper invents. Six slots, in this order, in every brief. A slot that does not apply is written out with its reason on one line ("Load check: not applicable — no suite or measurement runs"), never omitted. A brief with a slot missing is not sent.

| Slot | Contains |
|---|---|
| Output on disk | The exact path of the result — inside the project or the current worktree (the project's CLAUDE.md says where reports go), never the session scratchpad (it dies with a reboot). The final measurement runs in the foreground and the file is written before the helper's turn ends. The reply is: the path, the counts, one line on what was left undone — no pasted output, no diffs, no root-cause prose. The result is read from the file, never from the reply. |
| Git boundary | "Do not run git add, commit, push, stash, reset, checkout, clean or branch. Read-only git — status, log, diff, show — is fine." |
| Model and effort | Haiku for a job whose steps are fully written out and whose answer a command checks — a count or recount, a sweep or verbatim move compared by `cmp`, a test or mutation run read from its result line, a mechanical edit checked by its diff, a named fix re-run to green, a failed CI run read for its failing test, a closing comment's proof claims checked against the repo, a docs lookup that quotes its source, a worktree survey, a name-and-path scan (each passed a haiku trial in the owner's setup, 2026-10-10). Sonnet for well-defined work with a choice left in it. Opus for judgment. Never haiku for a review, a verdict, a diagnosis without a named cause, a design choice, or long multi-step coding (untested on haiku). A haiku job fits within 100k tokens of context, reading included; a bigger one splits before it is sent. Effort medium for a full brief, high for open judgment; the top rung is for one named, bounded job, then back down. Prefer purpose-built agent types when your setup has them — for example, an editing type (`executor`: sonnet, may edit, holds Write), a read-only judgment type (`reviewer`: opus, no Write tool, answers in the reply), a read-only checking type (`fact-checker`: haiku, no Write tool), a read-only exploring type (`Explore`) — and make your own if you have none. A file output needs a type that holds Write (the editing type; or a general-purpose agent on opus when a judgment must reach disk). A no-Write type is briefed for a short reply and you write it to the file. Trigger words: a task sentence holding fix, flaky, debug, why, root cause or intermittent is judgment, in one of two shapes and no third — (a) one brief on opus, may edit; (b) two briefs: the read-only judgment type names the root cause in a short reply (you save it to the output file), then the editing type implements only the named cause and changes no assertion the diagnosis did not name. Do it yourself when briefing would take more words than the change. An always-identical mechanical step is a hook, not a helper. (This kit's `agent-model-guard.sh` hook refuses a helper launch that names no model.) |
| Load check | Before any test suite or measurement: `uptime`; a 1-minute load at or above the project's stated ceiling (default 10) means wait. |
| Verification line | A command and its count line for every number the brief asks for — run it once yourself before sending and put the measured total in the brief (a total of 0 means the metric is wrong for this codebase; change it first). Every background figure in the brief — a failure rate, a file count — carries the command that measured it, the word "illustrative", or "owner-supplied". When the files-it-may-touch list holds a test file: the must-fire input (the break on which the test must go red) and the must-not-fire input (correct code on which it must stay green), both runs pasted into the output file, the reply carrying only the two counts — "N of N green" alone is not verification; a loosened assertion is green N of N. |
| Safety | These three lines, copied word for word: "Never write a real name, a client name or an absolute home-folder path into any file or reply; write `~/` for the home folder. Secrets never go in code, files, commits or replies; they live in `.env`, gitignored. Nothing you write carries a Claude attribution line or any author but your own publishing identity." Helper agent types may start without the rulebook (a Claude Code agent file can set `omitClaudeMd: true`), so the brief is the only place they learn these. |

## Before dispatch

**A background waiter blocks on the process, never on a marker in its log.** A brief that waits for a job names the job's end — the harness's task notification, the process exit, or a monitoring tool's exit condition — and reads the result from the file the job writes. **A waiter that matches processes by name excludes its own process, or waits on the process id captured when the job started — never on text the waiter itself contains.**

A helper that waits on a long job (a test run, a measurement, a process) waits in checks at most 4½ minutes apart, never one long wait: each check is a foreground wait on the job's end (its exit, or the monitoring tool's exit condition) with a timeout of 4½ minutes or less, and each resets the helper's 5-minute prompt cache, which a longer pause loses.

A run projected above $10 at list price (about five Sonnet one-task helpers or two Opus helpers): state the projection in one line and wait for the owner's yes — the brake is cost, not agent count. Before a big research round, workflow or paid call, state cost and value in one line; ask if unclear. A yes on an estimate allows up to twice it; ask again only past that. A limit the owner set may be passed only for work sure to fix a named problem (a known cause, a known fix), never to keep hammering an unsolved one.

**Helper size:**
1. One task per helper, about 150k tokens of work, ceiling 200k (a haiku job smaller: see Model and effort). Size it before briefing, the brief listing the file sections to read; a bigger task splits before it is sent. The last similar helper's token count (its task notification) sets the next brief. A third level only when this brief grants it, naming the grandchild's model and job.
2. Big files are read by section, in every helper brief.
3. After a build helper reports, a haiku fact-checker re-runs the report's counts (the result line and failure count, `git diff --stat` against the brief's file list, both two-sided runs present, the quoted requirement line matching the brief) in place of your own log reads; it never judges whether the line is met.

Reviews cluster findings first and verify only blocker and major clusters, on the cheapest capable model. Review a helper's result before trusting it; the main chat keeps the decisions and the commits.

## Shape of a brief

The task in one sentence → the files it may touch, and no others — read before the brief is written, so a "likely cause" names a file and line the writer has seen or says "not investigated — the helper starts here" → the six slots → "Stop and report when the brief is unclear or the work needs a file outside those" → the reply: the path, the counts, one line on what was left undone. A helper type without the Skill tool gets the paths of the skill files and project parts its job needs (`testing-method` for any code or check), to read first.

## One example

> Count, for every test file under `tests/`, how many `test(` blocks it has and whether it
> imports the shared test-routing fixture (measured before sending: 35 files, 414 `test(`
> calls, 0 imports). Write the table to `docs/reviews/<date>-test-inventory.md`; reply with
> the path, the three counts (files, `test(` total, fixture-import files), and one line on
> anything left undone. Do not run git add, commit, push, stash, reset, checkout, clean or
> branch. Read-only git — status, log, diff, show — is fine. Model: sonnet, effort: medium.
> Load check: not applicable — no suite runs. Verification: your file count matches a plain
> `ls tests/*.test.ts | wc -l`, and your `test(` total matches a plain grep for the word.
> Safety: Never write a real name, a client name or an absolute home-folder path into any
> file or reply; write `~/` for the home folder. Secrets never go in code, files, commits or
> replies; they live in `.env`, gitignored. Nothing you write carries a Claude attribution
> line or any author but your own publishing identity.

## Done when

The brief carries all six slots in order, every number in it names the command that measured it, and the helper's reply back is the path, the counts, and one line on what was left undone. You read the real result from the file it named — never from the reply alone.

**Project part:** if the project has `.claude/skill-parts/briefing-subagents.md`, read it now; where it is more specific than this skill, it wins.
