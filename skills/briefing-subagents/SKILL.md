---
name: briefing-subagents
description: Use when handing work to a subagent or a workflow agent — a read, a measurement, a draft, a mechanical sweep, a fix — or when choosing an agent's model and effort.
---

# Briefing subagents

## Overview

A brief is the whole world a helper gets; whatever it leaves out, the helper invents. Five
slots belong in every brief, always in this order. A slot that doesn't apply is written out
with its reason on one line ("Load check: not applicable — no suite or measurement runs"),
never simply omitted. A brief missing a slot is not sent yet.

## The five slots

| Slot | Contains |
|---|---|
| Output on disk | The exact path the result is written to — a real path in the repo or the seat's own working copy, never a throwaway scratch location that disappears on restart. The final measurement runs in the foreground, and the file is written before the helper's turn ends. The reply back to you is short: the path, the counts, one line on what was left undone — no pasted output, no diffs, no root-cause prose. Everything else lives in the file. |
| Git boundary | "Do not run git add, commit, push, stash, reset, checkout, clean or branch. Read-only git — status, log, diff, show — is fine." |
| Model and effort | Haiku for one checkable fact, sonnet for well-defined work, opus for judgment; medium effort for a fully-specified brief, high effort for open judgment. Prefer a purpose-built agent type when your setup has one: something read-only for a review or a fact-check (no ability to write files, so it answers in its reply and you save that reply to the file yourself), something that can edit for a task that must produce a file. A task whose wording trips words like fix, flaky, debug, why, root cause or intermittent is a judgment call, not a mechanical one — brief it as either (a) one capable helper on the strongest model, allowed to edit, or (b) two helpers: the first names the root cause in a short reply, which you save to the output file yourself; the second implements only that named cause and touches no assertion the first didn't call out. |
| Load check | Before any heavy test suite or measurement: check how busy the machine already is (for example `uptime` on a shared machine). Heavily loaded means wait, not start-anyway. |
| Verification line | A command and its count, for every number the brief asks for — run the command yourself once before sending, and put the real total in the brief (a total of zero usually means the metric is wrong for this codebase; fix that before sending). Every background figure in the brief — a failure rate, a file count — carries the command that measured it, or is marked "illustrative" or "as told to me." When the helper may touch a test file: the input that MUST make the test fail and the input that MUST NOT, both runs pasted into the output file — the reply itself carries only the two counts. "N of N green" alone is not verification; a loosened assertion is green N of N too. |

## Before dispatch

A helper that waits on a background job blocks on the job itself — its exit, a
task-completion notification, or a monitoring tool's own exit condition — and then reads
the result from the file that job wrote. A helper that has to guess from a log line whether
the job is done is a bug waiting to happen. If a waiting helper matches running processes
by name, it excludes its own process (or better, waits on the exact process id it captured
when the job started) — never on a text string the waiter itself contains, or it will match
itself.

Before dispatching a run that will cost real money at list price, say so in one line and
wait for a yes rather than assuming the go-ahead. Keep each helper to one clearly bounded
task; a task that would take a helper far longer than a normal single piece of work should
be split before it's briefed, not handed over whole. Reviews are cheaper when they cluster
their findings first and only re-verify the clusters that matter, on the cheapest model that
can check them.

## Shape of a brief

The task in one sentence → the files it may touch, and no others (read before the brief is
written, so a "likely cause" names a file and line the writer has actually seen, or says
plainly "not investigated — the helper starts here") → the five slots → "Stop and report
back if the brief is unclear, or if the work needs a file outside this list" → the reply:
the path, the counts, one line on anything left undone. The verification output itself lives
in the output file, never in the reply.

## One example

> Count, for every test file under `tests/`, how many `test(` blocks it has and whether it
> imports the shared test-routing fixture (measured before sending: 35 files, 414 `test(`
> calls, 0 imports). Write the table to `docs/reviews/<date>-test-inventory.md`; reply with
> the path, the three counts (files, `test(` total, fixture-import files), and one line on
> anything left undone. Read-only: no git add, commit, push, stash, reset, checkout, clean
> or branch. Model: sonnet, effort: medium. Load check: not applicable — no suite runs.
> Verification: your file count matches a plain `ls tests/*.test.ts | wc -l`, and your
> `test(` total matches a plain grep for the word.

## Common mistakes

Reading the result back in chat instead of the file (spending your own budget on it);
briefing "fix the test" with no diagnosis, so the helper loosens an assertion to make it
pass; saying nothing about git, so the helper stashes someone else's in-progress work;
putting a diagnosis on the cheap model and a headcount on the expensive one; a count brief
whose metric was never actually measured first; a reply that asks the helper for "the
output in full."

## Done when

The brief carries all five slots in order, every number in it names the command that
measured it, and the helper's reply back is the path, the counts, and one line on what was
left undone. You read the real result from the file it named — never from the reply alone.
