---
name: testing-web-ui-two-sided
description: Use when writing or reviewing tests for a web app's routes, screens or components; when a test builds fake routes with a stub instead of the real route table; when a check is called two-sided or a break-it proof; or when a web-UI change is reported done.
---

# Testing web UI two-sided, with wiring covered

## Overview

A check earns trust only when one input makes it fire and another keeps it silent, and both
are actually run. A module can be perfectly tested and still be dead in the running app, so
wiring gets its own check too.

## When to use / when not

Any test for a web app's routes, screens or components; any "done / verified" claim about a
screen. Not for a backend engine's own pure-logic tests, which have their own rules.

## Quick reference — required slots

| Slot | Contains |
|---|---|
| Must-fire | An input the check MUST fire on |
| Must-not-fire | An input it MUST NOT fire on |
| Anti-vacuity pin | Proof the test actually reached real content, not an empty render |
| Break-it proof | A kept test that plants the exact thing the check exists to catch |
| Wiring assertion | Proof the path/route/config is present in the REAL table your app runs from, not a hand-typed copy of it |
| Every locale and theme | Toggle it inside the test; assert the visible change (label text, reading direction, whatever the toggle should change) |
| Run evidence | The files and tests that actually ran, not just an exit code |
| Unchecked marker | Write "— unchecked" wherever a check did not actually run |

## Rules

1. **Both sides, both run.** One-sided proofs let broken checks through — a scanner that
   finds nothing still shows green next to every other test in its file. This pattern has
   cost real projects real debugging time more than once.
2. **Keep the break-it proof as a test**, not a one-off manual check. A break-it test that
   plants a real bad case and asserts it's caught stays useful forever; a broken matcher
   that nobody re-tests can pass forever too.
3. **Pin against vacuity.** A scanner asserting "found nothing bad" is worthless unless a
   companion test proves the scanner can find something when it's actually there — assert a
   minimum count, and name a specific file it must have scanned.
4. **A hand-typed test double drifts from the real thing.** A common pattern: dozens of test
   files each retype a copy of the app's real route table (or config, or schema) for a stub,
   and none of them import the real one — so a real rename can leave routing silently broken
   while every test stays green. Illustrative: in one project this cost dozens of call sites
   across many files, one stale stub turning an 18-second fix into about fifteen minutes of
   confused debugging before anyone found it. The floor fix: one test that imports the real table and asserts your new
   addition is a member of it. The complete fix: derive every stub from the real table, plus
   a membership test over all of them — say plainly which one you did, because a floor fix
   ticked off as if it were the complete fix leaves the rest still drifting.
5. **Every locale or theme toggle is tested from inside the render**, not just checked
   against the data object holding the strings. A string sitting correctly in a translations
   object proves nothing about what's actually on screen — click the toggle inside the test,
   then assert the visible label and the visible layout direction actually changed.
6. **A relied-on run quotes its counts.** "Tests passed" with no number attached could mean
   nothing ran at all.
7. **Name the real script** from your project's own command list (for example
   `npm run test:e2e`), and check how loaded the machine already is before running a heavy
   suite — a shared machine under load has made real end-to-end runs fail that passed fine
   when idle.

## Example — rule 2

```ts
test("nothing sensitive reaches the output tree", () => {
  expect(scanOutputTree(dir)).toEqual([]);              // must-NOT-fire
});
test("the scan still catches a leak when there is one", () => { // must-fire, kept as a test
  writeFileSync(join(dir, "planted.txt"), SENSITIVE_MARKER);
  expect(scanOutputTree(dir)).toHaveLength(1);
});
```

## More detail

- **Environment splits.** If your test runner splits tests by environment (browser-like vs.
  real Node), name files so the runner's own file-matching picks the right one — a glob
  written for one extension silently skips test files with a different one (a glob for
  `.ts` does not match `.mts`, for instance). Server-only tests that touch a real database
  or a native module usually can't run in a browser-like test environment at all; keep them
  out of it by naming convention, not by hoping nobody puts one there.
- **End-to-end runs** are worth pinning down as: one worker (not parallel, unless you've
  proven your app tolerates it), a generous timeout, a fresh throwaway database per run, and
  screenshot baselines compared with a small allowed difference ratio rather than
  pixel-perfect (fonts and animation timing vary run to run).
- **A relied-on command is never piped into something else for its exit code** —
  `command | grep something` reports grep's exit code, not the command's; if you need to
  inspect the output, save it to a file and check the original exit status separately.

## Common mistakes

| Rationalization | Reality |
|---|---|
| "No suite can run right now, so no break-it proof." | Write the planted case as a kept test anyway; mark only the run itself "— unchecked." |
| "Two tests, so it's two-sided." | Two must-fire cases are one-sided, twice. |
| "The stub renders it, so the route/wiring works." | A stub is disconnected from the real table by construction — assert against the real one. |
| "The translation is in the copy object." | Existing in the data isn't the same as rendering on screen. Toggle it and assert what changed. |
| "I can't run the suite, so I can't claim it covers this." | Name the check and what it matches; mark the RUN "— unchecked," never the claim itself. |
