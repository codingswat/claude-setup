---
name: testing-method
description: Use before writing code for a feature or a fix; before writing or changing a test, a check or a guard; and before reporting any work done or verified.
---

# Testing method — seen red, seen green, counted, on the real thing

A check earns trust only when you have seen it fail on what it must catch and pass on what it must let through, and counted what ran, on the input it will really meet. Pasted output proves; "it's done" does not.

**Words.** A **check** passes or fails: a test, a scanner, a gate, a **guard** (a check that blocks or refuses). **Red** / **green**: seen failing / passing. **Two-sided**: a case it must catch (**must-fire**) and one it must let through (**must-not-fire**), both run. A **pin** asserts the check reached its content. The **seam** is where a test touches the code.

**Every run.** Tests run where the project's CLAUDE.md says. Before any test command, check the machine: at least ~20% memory free (`memory_pressure | tail -1` on macOS; on Linux, `free -m`) and the 1-minute load under the project's stated ceiling (`uptime`); full suites, end-to-end runs and measurements run one at a time.

## Which tests, when

Not every change runs the big suites; each moment runs its own level, and the levels below it.

| Moment | What runs |
|---|---|
| Each edit | The test files for what changed and their neighbours, plus the type check |
| Before landing on `main` | The fast suite (what the project's CI runs on each push) and the lint gate below |
| A screen or flow changed | The end-to-end test for that flow, in a real browser, with an accessibility scan of each page it visits (axe or the project's equivalent; serious and critical findings fail). Browser tests run whenever a change needs them, in every project |
| Nightly | The slow tests and the lint report. In CI; when GitHub's free minutes run out, on the owner's machine instead, in projects that allow it |
| Weekly | A dependency check for known security holes (`npm audit --audit-level=high` or the stack's equivalent); a high or critical finding fails |
| After each deploy | A smoke test against the live site: the main path loads and one real action works, end to end |
| Monthly, optional | Mutation testing on the core logic: the code is broken on purpose and every break a test misses is a finding |

**Failed runs.** At a chat's start and at every task boundary, list the project's failed test runs (`gh run list --status failure --limit 20` where it tests on GitHub); a failed run on your own branch is yours to fix; a failure becomes a task or is fixed in the task in hand.

**A project without a level** (no end-to-end tests yet, no deploy) names the gap in its parked problems with what wakes it, rather than skipping silently.

**The lint gate.** The lint's known problems are counted in a committed file (e.g. `lint-baseline.json`, one count per rule). Landing fails when a count rises; when one falls, the file is lowered in the same commit. A new project starts at zero. A warning that is always on gets ignored; a count that only goes down does not.

## The method

### 1. Decide — before any code or test
- One line per behaviour (the task's done-when lines, if any), each with a must-fire case and a must-not-fire case (the nearest input where the behaviour must not happen).
- Aim at the quantity the change moves, never a neighbour that reads the same either way.
- The seam: where the real pattern reaches the user (the entry the app calls, not only the helper beneath). For a fix, where the bug occurs at its call site; if only a shallower seam exists, record that finding in the project's parked-problems list (what, why it waits, what wakes it) instead of a falsely reassuring test, and say so.
- The real input the code will meet in use, and the exact test command.

Done when each behaviour line has both cases, a seam, a real input and a command, written down.

### 2. The failing test — before the code
Write both cases at the seam, and the wiring test (step 4). Assert what the behaviour produces (a value, a link, a state), never its wording: rewording stays green, losing the behaviour goes red. For a fix, the minimised repro is the test.

Done when the must-fire test is red because the behaviour is missing, not from an import error, a typo or a crashed setup; that output kept.

### 3. The least code that turns it green
A comment you write saying something is guarded names its test, or says "not enforced"; making it a test is the fix. Run the new tests and those around the change.

Done when every new test is green and nothing that was green has gone red.

### 4. The wiring — where a test must sit
When a new part is reached through other code (a route, a registry entry, a handler, a command): test the joining code against the real table or entry point, never a hand-typed copy of it. A module green on its own can be dead in the app; present in a table is not on the screen.

Done when unhooking the part turns a test red.

### 5. The two-sided proof
Every check you wrote or changed has three kept tests, all run: must-fire, must-not-fire, and a pin (it found at least N items, read the file, reached the rendered content). A check that finds nothing passes everything else; asserting only an empty result passes a read that never reads, so seed N and see N, then clear and see empty.

Done when all three are kept, run and green.

### 6. Break it once
After green, make one plausible wrong version (flip a condition, drop a branch, widen a pattern, unhook the wiring), run, restore, run again: the test's own two-sided proof, red on broken code and green on correct code. For a guard or scanner the planted bad case stays a kept test; a broken matcher otherwise passes forever.

Done when red on the break and green on the restore are both seen and kept.

### 7. Count what ran, on the real input
- Every run you rely on reports the files and tests that ran, passed and failed; three green runs may have run nothing.
- The count matches what exists: every file the runner or check should cover, by every ending it could have (a `.ts` pattern skips `.mts`), was counted.
- Run once on the real input from step 1 and count what it saw or produced. Zero is a finding, never a pass. For a fix, re-run the original, un-minimised scenario.

Done when every relied-on run has matching counts and the real-input count is stated.

### 8. Report
- Real output: the red before the code, the red on the break, the final counts; the exact command, file or address, and whether it needs a server running.
- Gates chain by exit code, joined with `&&`; never `;`, never a grep of printed text. Counts are read from the output for the report.
- A claim whose check did not run carries "— unchecked" on that sentence, never in a banner. A gate you cannot run: name it and what it matches; the run is unchecked, not the claim you checked by reading.
- Every figure that informs a decision (in a brief, a caption, a mockup, a report or chat) is measured by a saved command, or labelled "illustrative"; no label = measured. It names the parameter that moves it and the committed script that produced it: a number from an uncommitted scratch file or an unstated method is not a measurement.

Done when every claim has its output beside it or "— unchecked" on its sentence.

## Branches — each one that applies, before step 8

**A. Screens and anything tapped.** A headless pass can hide a broken screen; a page simulated inside the test runner does not count. Visual: a real browser or window, every language the product ships; tapped: at phone size. A helper that never saw the change checks it; report its answers unchanged. Path, storyboard to rehearsal: the walkthrough skill. Pictures frame the whole object; an annotated one goes beside its plain original at identical crop and size; overlays light (colour and shape, no ids or callouts); close-ups support, never headline. Done when the helper's answers and the pictures are in the report.

**B. Guards and checkers.** A checker keeps its own right answers: a source copy, a recorded ruling, or a list typed twice blind, never what the checked data says of itself. Optional unless the project's CLAUDE.md requires it: a guard of the owner's data or a live site gets a blind break round before your own tests count: a reviewer who never saw it, briefed "find every route it misses, disguised ones included, and honest work it refuses", every attempt run, the right answers open to attack. Close honest-mistake routes (another spelling, a subfolder, an ordinary edge case, honest work refused); report any deliberate bypass. Done when each attempt's result is recorded and each route found is closed or reported.

**C. AI-dependent tests** run in their own command, apart from the deterministic ones, with their own counts, so a flaky answer never hides a real failure.

**D. Installs.** After adding a package or changing the lock file, the check that watches it runs in the same session, before saving; its counts go in the report.

**E. Scripts or steps someone else will run.** Rehearse them on a throwaway copy, end to end, including being stopped halfway and losing the connection; the report shows what each case leaves behind.

## Common failures

- Two must-fire cases called two-sided: one-sided twice.
- "N of N green" as the proof: a loosened assertion is green N of N. Loosening an assertion to turn red green.
- "No suite may run here, so no break-it proof": write the planted case as a kept test; mark only the run unchecked.

## Example — "orders of 10 or more items get 5% off"

1. Decide: 10 items at 100 → 950 (must-fire); 9 → 900 (must-not-fire). The change moves the order total, so assert what `checkout()` returns, not the helper. Real input: last month's orders.
2. Red: 1 failed ("expected 950, received 1000"), 1 passed. The right reason.
3. Green: 1 file, 16 tests, 16 passed.
4. Wiring: deleting the rule's call in `checkout()` turns the 10-item test red.
5. Pin: the real-input run asserts every row was read.
6. Break: `>= 10` as `> 10` turns the 10-item test red; restored, green.
7. Real input: 1,240 of 1,240 rows read, 87 discounted, three checked by hand.
8. Report: "`<test> checkout && <lint>` exits 0: 1 file, 16 tests, 16 passed; both reds quoted; 1,240 orders read, 87 discounted. The receipt line on screen — unchecked."

**Project part:** if the project has `.claude/skill-parts/testing-method.md`, read it now; where it is more specific than this skill, it wins.
