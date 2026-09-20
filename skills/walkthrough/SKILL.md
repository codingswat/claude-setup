---
name: walkthrough
description: Use when someone asks for a screen, flow, animation or interaction; when two points are named ("from A to B") with the path unstated; before any mockup of a screen a person will touch; and before a screen or interaction is reported done.
---

# Walkthrough — sitting in the user's seat

## Overview

Someone names two points, A and B, and rarely the path between them. This skill walks from
A to B the way an actual person would: in time, at phone size, from first sight to done —
and brings back a strip of pictures to react to. A chat cannot picture motion, so it
observes instead of imagining: draw the **storyboard** before anything is built, do the
**rehearsal** in a real running browser before anything is called done.

## The story (both moments start here)

1. One person, one goal, from A (the first point named) to B (the second), both in the
   requester's own words.
2. Expand the path into **moments**, one line each: anything the person does, sees, or
   waits for. Every path has these moments, listed even when nobody mentioned them:
   - first sight of the screen, and what tells them what to do;
   - the touch;
   - the wait after the touch, and what shows during it;
   - the change;
   - the sign that something happened, at the moment it happens;
   - the next thing to do, and the way back;
   - the empty state (nothing there yet) and the error state (it failed).
3. Where the path forks, draw two reasonable versions and let the requester pick between
   the drawings, never between sentences.
4. If the product supports more than one language or reading direction, walk that path too,
   as its own strip, wherever a direction, number, or label differs.

## Moment 1 — the storyboard, before building

One frame per moment, drawn (a design tool, a mockup widget, or a quick sketch), in order.
A frame holds what the person sees plus one caption: what they're doing and what they
expect. The waiting, empty, and error frames are frames like any other.
Deliver the strip with one decision to make: is this the story? Pick between drawn options
wherever the path forked.
Done when every moment has a frame and the pick has been made.

## Moment 2 — the rehearsal, before "done"

1. Open the real, running app at a phone width (around 390px), then once at desktop size.
2. For each moment of the picked strip, do the action as the person would: tap, press and
   hold, drag, type. Take three pictures: at touch, during (the hold, or the wait), after.
3. Every language and theme the change actually touches.
4. For each moment, answer four questions from the pictures alone:
   - **Know**: would they know what to do here?
   - **See**: is the control visible, reachable, and at least a finger wide (roughly 44px)?
   - **Connect**: does the action visibly cause the effect?
   - **Notice**: do they see that something happened, at the moment it happens?
   A "no" to any of these is a defect: name the moment, the question, and the picture.
5. **Whoever drives the rehearsal should not be whoever built the thing.** A separate,
   disposable helper that never saw the change drives the browser, writes the pictures to
   disk, and answers the four questions; the person running the walkthrough reports those
   answers unchanged. Walking through your own work yourself is not the check — you already
   know where to click.

Deliver: the strip of "after" pictures at full-screen scale; any picture with markup shown
beside its plain original at the same crop and size; the defect list.
Done when every moment has its three pictures, every "no" has a fix landed or a tracked
follow-up, and the strip has actually been shown to whoever asked for the walkthrough.

## The strip's columns

| Moment | The person does | Sees at touch | Sees during | Sees after | Know · See · Connect · Notice | Defect |
|---|---|---|---|---|---|---|

The "during" column is the one that surprises people. Fill it for every moment — "nothing
to wait for" is a valid, and common, answer.

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

## Common mistakes

A path with only A and B, leaving the wait, empty, and error states unlisted. Judging from
the code ("the data updates on release") instead of from the pictures. One picture per
moment instead of three. Prose sent instead of a drawn strip. A fork asked as a question
instead of shown as two strips. Checking desktop size only.

## Baseline

Illustrative: in one real project, a day of testing a complex interactive screen turned up
several real defects that a large automated test suite had all missed — every one of them
found by a person, and every one of them in the "during" column: the hold or the wait,
mid-interaction, that a static test never sits through. That gap is the reason this skill
exists.

## Commit the rehearsal pictures

Every rehearsal picture cited in a "done" report belongs in the actual repo (for example,
under a path like `docs/design/<task>/pictures/`) in the same commit that reports it done —
not only in a throwaway working copy. Screenshots that were the only evidence a check had
passed have been lost before, along with a retired temporary workspace; treat them as part
of the deliverable, not scratch. Take them from fixtures or test accounts only, never from a
real user's screen — a committed screenshot can carry personal data into a public repo.
