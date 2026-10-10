---
name: testing-web-ui-two-sided
description: Use when writing or reviewing tests for a web route, screen, component or translated copy; when a test builds a route table by hand (a routes stub); when a screen test must prove a language toggle or a reading-direction change; when an end-to-end run is about to start; or when a web-UI change is reported done or verified.
---

# Testing web UI two-sided, with wiring covered

The method (two-sided cases, pins, break-it, counts, "— unchecked", red before code) is the `testing-method` skill; read it first. This skill adds only what a web UI changes.

## Rules

1. **A routes stub is a hand-typed copy of the route table.** A stub links to nothing: renaming a URL parameter leaves the URL matching and the screen silently rendering its empty branch, not a 404, and types cannot see it when components read parameters untyped. A stale stub turns a short test run into a long one. The fix is one shared stub fixture derived from the real route table, plus one test asserting every stub path is a member of it, red when one path is renamed and green on the unchanged table. The floor is one test that imports the real table and asserts your new path. Say which you did; a floor ticked as a fix leaves every other stub drifting.
2. **The pin for a screen is content only real data can put there** (a seeded item's title), so a route rendering its empty branch cannot pass (`testing-method` §5).
3. **Every language inside the test.** Click the language toggle, assert a translated label and, where the language changes reading direction, `document.documentElement.dir` (`"rtl"` for a right-to-left language). Copy existing in a translations object is not copy rendering on screen. Spelling, digits and direction mechanics: the project's own skill for them, if it has one.
4. **Name the real script** from `package.json`, never a guessed command, and check the machine load before an end-to-end run: a run that times out under heavy load proves nothing about the screen; re-run at low load before calling it red.
5. **A test that reads the project's files to check a rule must run by name.** Change-based test selection (`vitest --changed` and kin) cannot pick it, so add it to whatever list the landing gate runs by name, in the same commit; otherwise a broken rule sits on the main branch unseen.

## Common failures

| Rationalization | Reality |
|---|---|
| "The stub renders it, so the route works." | A stub links to nothing. Assert against the real route table. |
| "The translation is in the copy object." | Existing is not rendering. Toggle and assert what changed on screen. |

**Project part:** if the project has `.claude/skill-parts/testing-web-ui-two-sided.md`, read it now; where it is more specific than this skill, it wins.
