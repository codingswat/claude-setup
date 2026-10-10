---
name: summarize
description: Use when the owner says summarize, when sending the owner any end-of-task report or list of decisions, when the owner returns after being away (the hook says OWNER RETURNING), when the owner asks "whats next?", when asking the owner to choose between options, or when the owner shows they have lost the thread ("wait what", "explain it all", "what do you mean").
---

# The card — how the owner is told anything

The owner reads only the chat and does not scroll back; a thing they have not opened has not been said. The message is the chat reply itself, never a file, and it stands alone. Every seat writes the same card, in the same order. The card the hook injects (`~/.claude/hooks/owner-card.md`) is the compact recipe; this file is the full recipe.

## The card, top to bottom

1. **Status line.** A light and the step: 🟢 done · 🟡 waiting on you · 🔴 blocked, then "step X of Y".
2. **Problem.** Numbered. One full sentence each, the crux word bold. The problem as the owner would meet it, never as the code names it.
3. **Story.** In time order, one event per line with its time (Monday, yesterday, this morning). A rule or decision is named once, where it bites, with its date ("rule set Tuesday: unknown type means the leakiest figure"), never re-explained in another section. Earlier messages are restated, never pointed at; nothing in this message is said twice.
4. **Result.** What is built, fixed or decided, and its state — live, parked or blocked. Two lines. Understanding belongs in Story; Result is the state of the thing.
5. A `---` line, then 🔵 **Needs my input**, or "nothing needed" when there is no decision. One block per decision:
   - a bold numbered question ending in "?", short and in the owner's words — the rule itself goes in the options, never in the question;
   - a `>` quote holding the backstory, only when the backstory changes the answer;
   - a table `| | Option | Why |` with the options stacked A B C, each option a sentence that stands alone with no term the owner has not met, the pick written **B ✓** in the first column and its reason under Why, the other Why cells empty;
   - a `---` line between decisions.

## Every line

- One full sentence, one thought. Parallel items are a numbered list, one line each, key word bold, never run together with commas or slashes.
- A fact appears once: Problem names it, Story dates it, Result states its state. No process narration (how it was measured, where it was checked) and no reassurance lines — the notes hold those. The recommendation is the label on the option, not a sentence; each downside is its own labelled line (owner, 2026-09-12: "I keep rereading").
- Plain name first, then the file, code or term in parentheses at first use — "the photo upload step (`upload.ts`)" — then the plain name alone.
- Every number carries what it changes, in one form — the share or the step, never the raw figure beside it: "a photo's original size stops changing what the reader sees in 9 of 10 uploads". A count that changes nothing is left out.
- A claim whose check has not run carries "— unchecked" on that sentence.
- What was tried, the bug caught on the way, how many findings a reviewer had: the project notes, for the next chat. The chat carries the result; if the owner asks for the full story, tell it.
- On "summarize": cover everything since the owner's last message as if new; re-send, with plain explanation, anything they have not looked at.
- A routing (telling the owner which chat to open) names who, when, and the starting word: the role, the start time, the trigger word.

## Quick replies

A short exchange gets one line and "Needs my input:" (or "nothing needed"); the card is for a returning owner, a decision, or a closed task. "whats next?" gets a short ranked list with one clear recommendation.

## Picks

A choice the owner must make is pressed on a rendered page, never typed in chat: an artifact with a button under each option, a note box beside them; the chat carries the link, never the options. This covers every pick: a design pick (a picture of each option) and any question whose answer changes what a user sees (an example of each option) included. A preview open somewhere else does not count, and a drawing rendered inside the chat never reaches the owner. A page that cannot save falls back to chat letters A B C in the card's table (the table is the fallback, never the first choice). Do not ask what the owner already answered.

## One example

> 🟡 **Waiting on you** · step 4 of 5
>
> **Problem**
> 1. When a photo is over 10MB, the upload fails and the recipe never **saves**, with no error shown.
> 2. When a recipe has no photo at all, we publish it anyway, so it looks **abandoned** next to the rest.
>
> **Story**
> On Monday a rule was set: when a photo is over 10MB, resize it automatically before upload.
> On Thursday the rule was built, and the twelve tests that still assumed the old size limit were fixed.
> This morning a review found the resize step washes out the colour on food photos.
> The same review found we have no fallback for recipes with no photo.
>
> **Result**
> The rule is built and every test passes. Everything is backed up online.
> Nothing goes live until you answer the two questions below.
>
> ---
>
> 🔵 **Needs my input**
>
> **1. Do we keep automatic resizing?**
>
> > With resizing in, a photo's original size stops changing what the reader sees in 9 of 10 uploads. Whether the photo was any good stops mattering.
>
> | | Option | Why |
> |---|---|---|
> | A | Go live with it | |
> | **B ✓** | Hold it | It washes out most food photos. A version that keeps colour can be found in a few hours. |
> | C | Resize only photos over 20MB | |
>
> ---
>
> **2. Do we refuse to publish a recipe with no photo?**
>
> > Today a recipe with no photo looks the same as one with a great photo. Readers can't tell which recipes the cook actually tested.
>
> | | Option | Why |
> |---|---|---|
> | **A ✓** | Refuse, and tell the cook a photo is needed | A recipe should never look tested when it wasn't. |
> | B | Publish it anyway with a placeholder image | |

## Common mistakes

"You ruled" or "as you saw" in place of the rule restated; the question written as a statement; options run together on one line; the diary in the chat.

## Done when

The message ends with Needs my input, each decision in its own table with the pick ticked, every digit in a sentence saying what it changes, and no code, file or internal name before its plain name.

**Project part:** if the project has `.claude/skill-parts/summarize.md`, read it now; where it is more specific than this skill, it wins.
