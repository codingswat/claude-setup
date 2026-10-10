---
name: walkthrough
description: Use when the requester asks for a screen, a flow, an animation or an interaction; when they name two points ("from A to B", "when they press this, then the panel") and the path between is unstated; when they say "imagine the workflow" or "picture it"; before any mockup of a screen a person will touch; and before a screen, animation or interaction is reported done or verified.
---

# Walkthrough — sitting in the person's shoes

## Overview

The requester names two points, A and B, and rarely the path. Walk from A to B as the person would: in time, at phone size, from first sight to done, and bring back a strip the requester reacts to. A chat cannot picture motion, so the walkthrough observes instead of imagining: the storyboard is drawn, the rehearsal is done in the real browser and judged from pictures. Two moments, one story: the **storyboard** before anything is built, the **rehearsal** before anything is called done.

## The story (both moments start here)

1. One person, one goal, from A (the requester's first point) to B (the second point), both written in the person's words.
2. Expand the path into **moments**, one line each: anything the person does, sees, or waits for. Every path holds these moments, listed even when the requester never mentioned them:
   - first sight of the screen, and what tells them what to do;
   - the touch;
   - the wait after the touch, and what shows during it;
   - the change;
   - the sign that something happened, at the moment it happens;
   - the next thing to do, and the way back;
   - the empty state (nothing yet) and the error state (it failed).
3. Where the path forks, two reasonable ways from one moment to the next, keep both as two strips. The requester picks between drawn options, never between sentences.
4. Every language the product ships is walked; a path in a language that reads in another direction is its own strip wherever a direction, a number, or a label differs.

## Moment 1 — the storyboard, before building

One frame per moment, drawn (a canvas, a widget or an image), in order. A frame holds what the person sees and one caption line: what they are doing and what they expect. The waiting, empty, and error frames are frames like any other.
Deliver the strip to the requester with one question: is this the story? A or B wherever the path forks.
Done when every moment has a frame and the requester has picked.

## Moment 2 — the rehearsal, before "done"

1. Open the real app in a real browser at 390 px wide (the mobile preset), then once at desktop size.
2. For each moment of the picked strip, do the action as the person would: tap, press and hold, drag, type. Take three pictures: at touch, during (the hold, or the wait), after.
3. Every language the product ships, and both themes, for the screens the change touched.
4. For each moment answer four questions from the pictures alone:
   - **Know**: would they know what to do here?
   - **See**: is the control visible, reachable, and at least a finger wide (44 px)?
   - **Connect**: does the action visibly cause the effect?
   - **Notice**: do they see that something happened, at the moment it happens?
   A "no" is a defect: the moment, the question, the picture.
5. The tester is not the builder: a helper that never saw the diff (sonnet or lighter; see the `briefing-subagents` skill) drives the browser, writes the pictures to disk and answers the four questions; you report its answers unchanged and carry the strip to the requester. Your own walk is not the check.

Deliver: the strip of "after" pictures at whole-screen scale; any marked picture beside its plain original at the same crop and size; the defect list in your report to the requester.
Done when every moment has its three pictures, every "no" has a fix landed or a task, and the requester has seen the strip.

## The strip's columns

| Moment | The person does | Sees at touch | Sees during | Sees after | Know · See · Connect · Notice | Defect |
|---|---|---|---|---|---|---|

The "during" column is the one that surprises people. It is filled for every moment, "nothing to wait for" included.

## One example

A: the person taps a card in a list. B: the card's detail panel is open.
Moments: first sight (cards laid out, one tap target each) → touch (the card darkens under
the finger) → during (nothing to wait for; the panel is already sliding) → change (panel
open below the list, the list still a list) → notice (the card stays marked while its panel
is open) → next (edit something, or tap outside to close) → back (panel slides down, the
mark clears) → empty (a card with nothing in it yet says so in the panel) → error (a
refused value shows why, next to the field).
Rehearsal at phone width found: during the hold, the list's text became selectable, like a
text-drag instead of a tap. Notice failed at "touch." Defect logged with its picture; the
fix made the surface non-selectable.

## Common errors

A path of only A and B, with the wait, the empty state, and the error unlisted. Judging from the code ("the data moves on release") instead of the pictures. One picture per moment. Prose to the requester instead of a drawn strip. A fork asked as a question instead of two strips. The desktop size only.

## The pictures are committed

Commit the rehearsal pictures a landing cites into the repo; a scratch or worktree folder is lost when it is removed.

**Project part:** if the project has `.claude/skill-parts/walkthrough.md`, read it now; where it is more specific than this skill, it wins.
