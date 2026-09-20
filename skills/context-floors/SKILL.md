---
name: context-floors
description: Use at every task boundary, whenever remaining context is measured, when a harness low-context warning appears, or after the conversation history has been compacted.
---

# Context floors

## Overview

Every agent session's working memory (its context window) is finite, and it fills up as
work happens. Closing well before it runs out, in an orderly way, beats scrambling once it's
nearly gone. This is a general method for deciding when to stop taking new work and start
closing.

## The method

At every natural task boundary, a session notes roughly how much context it has left, **in
tokens, never as a percentage** — the percentage depends on which model is in the seat and
how big its window is; the token count doesn't.

Set two floors for your own setup:

- **An upper floor** (for example, `<~150k tokens>`): below this, at a task boundary, take
  no new task. Land or push what's in progress, mark the shared plan file, and close at that
  boundary.
- **A lower floor** (for example, `<~60k tokens>`): below this — or on a low-context warning
  from the harness, or right after the conversation's history has been compacted — closing
  is the session's very next action. No need to ask first; just announce it in chat along
  with the opening line for whoever picks the work up next.

**Nothing already running is ever interrupted to hit either floor** — pausing to close well
is not the same as stopping mid-task. A session whose own measured cost per task differs
from these defaults should say so and set its own floor accordingly; the numbers above are a
starting point, not a law of physics.

## Quick reference

| Remaining context | Action |
|---|---|
| Above the upper floor | Take the next task |
| Below the upper floor, at a task boundary | No new task; land or push, mark the plan file, rewrite the role's state file (under two hundred words: current task, next step, open questions, what not to repeat — see `handing-off-live-work`), close |
| Below the lower floor, a low-context warning, or right after compaction | Closing is your NEXT action — automatic, announced in chat with the next session's opening line; nothing running gets interrupted |

Sub-skill for actually pushing unfinished work cleanly: `handing-off-live-work`.

## Done when

At every task boundary, the chat has stated its remaining context in tokens. Below a floor,
the shared plan file is current, unfinished work is pushed and named there, and the chat has
said so before taking any other action.
