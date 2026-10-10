---
name: context-floors
description: Use at every task boundary, whenever context used is measured, when a harness low-context warning appears, or after the conversation history has been compacted.
---

# Context floors

SUB-SKILL for pushing unlanded work: `handing-off-live-work` (when to close = this skill, how = that one; no handover file).

## The rule

The tokens used come from the context line a hook prints each turn (this kit's prompt hook prints "Context used: Nk tokens"). The two limits — a soft one (no new task from here) and a hard one (close by here) — are yours to set once, in your rulebook or the project's CLAUDE.md, sized to your model's window; this skill holds no figure.

At every task boundary, state your context used, in tokens. Below the soft limit, take new tasks. From the soft limit, take no new task: land or push, update the plan, and close at that boundary. Past the hard limit, below ~60k remaining (a smaller window), on a harness low-context warning, or after the system has compacted its history, closing is your next action — automatic, no ask needed, announced in chat with the line the next session boots from. Nothing running is ever interrupted to get there (pause is not stop). Thresholds are tokens used, never percentages and never "remaining" against a guessed window, except the ~60k remaining floor above. A close before the soft limit states its measured reason.

## Quick reference

| Context used (tokens) | Action |
|---|---|
| below the soft limit | take the next task |
| at or past the soft limit, at a task boundary | no new task; land or push, update the plan, close |
| past the hard limit, or below ~60k remaining, or a low-context warning, or history just compacted | closing is your next action — automatic, announced in chat with the next session's boot line; nothing running is interrupted |

## Done when

At every task boundary the chat has written its context used in tokens. At a limit, the project's task list is current, unlanded work is pushed and named there, and the chat has said so before any other action is taken.

**Project part:** if the project has `.claude/skill-parts/context-floors.md`, read it now; where it is more specific than this skill, it wins.
