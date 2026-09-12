---
name: summarize
description: Use when the owner says summarize, when sending the owner any end-of-task report or list of decisions, when the owner returns after being away (the hook says OWNER RETURNING), or when the owner shows they have lost the thread ("wait what", "explain it all", "what do you mean").
---

# The card — how the owner is told anything

## Overview

The owner reads only the chat and does not scroll back. A thing they have not opened has not been said. The message is the chat reply itself, never a file, and it stands alone. Every seat writes the same card, in the same order, so the owner's eye knows where each thing lives. The compact version is injected on every prompt by `~/.claude/hooks/owner-card.md`; this file is the full recipe.

## The card, top to bottom

1. **Status line.** A light and the step: 🟢 done · 🟡 waiting on you · 🔴 blocked, then "step X of Y".
2. **Problem.** Numbered. One full sentence each, the crux word bold. The problem as the owner would meet it, never as the code names it.
3. **Story.** What happened, in time order, one event per line with its time (Monday, yesterday, this morning). A rule or decision is named once, where it bites, with its date ("rule set Tuesday: unknown type means the leakiest figure"), never re-explained in another section. Earlier MESSAGES are restated, never pointed at; nothing in this message is said twice.
4. **Result.** What the work left behind: what is built, fixed or decided, and its state — live, parked or blocked. Two lines. Understanding belongs in Story; Result is the state of the thing.
5. A `---` line, then 🔵 **Needs my input**. One block per decision:
   - a bold numbered question ending in "?", short and in the owner's words — the rule itself goes in the options, never in the question;
   - a `>` quote holding the backstory, only when the backstory changes the answer;
   - a table `| | Option | Why |` with the options stacked A B C, each option a sentence that stands alone with no term the owner has not met, the pick written **B ✓** in the first column and its reason under Why, the other Why cells empty;
   - a `---` line between decisions.
   "nothing needed" when there is no decision.

## Every line

- One full sentence, one thought. Lists are stacked, never run together with commas or slashes; parallel items are a numbered list, one line each, key word bold — no paragraph where a list will do (the owner reads visually).
- A fact appears ONCE in the message: Problem names it, Story dates it, Result states its state. No process narration (how it was measured, where it was checked) and no reassurance lines — the notes hold those. The recommendation is the label on the option, not a sentence; each downside is its own labelled line.
- Plain name first, then the file, code or term in parentheses at first use — "the developer on the drawing tooling (D5)" — then the plain name alone.
- Every number carries what it changes, in ONE form — the share or the step, never the raw figure beside it: "orientation stops changing the answer in 6 of 8 cities, so the drawings stop mattering". A count that changes nothing is left out.
- A claim whose check has not run carries "— unchecked" on that sentence.
- What was tried, the bug caught on the way, how many findings a reviewer had: the project notes, for the next chat. The chat carries the result. If the owner asks for the full story, tell it.

## Quick replies

A short exchange gets one line and "Needs my input:" (or "nothing needed"). The card is for a returning owner, a decision, or a closed task.

## One example

> 🟡 **Waiting on you** · step 4 of 5
>
> **Problem**
> 1. When we do not know a home's AC type, the unit size we recommend comes out too **small**.
> 2. When a buyer says their windows are double glazed, we size their home as if the glass were **cheap**.
>
> **Story**
> On Monday a rule was set: when the AC type is unknown, assume the leakiest published figure.
> On Thursday the rule was built, and the seven tests that still assumed the old size were fixed.
> This morning a review found the leaky figure was measured in ducted homes with the fan running.
> The same review found we hold no published figures for double glazed glass.
>
> **Result**
> The rule is built and every test passes. Everything is backed up online.
> Nothing goes live until you answer the two questions below.
>
> ---
>
> 🔵 **Needs my input**
>
> **1. Do we keep the leakiest figure?**
>
> > With this figure in, which way a house faces stops changing our answer in 6 of our 8 cities. Reading the drawings, the point of the product, stops mattering.
>
> | | Option | Why |
> |---|---|---|
> | A | Go live with it | |
> | **B ✓** | Hold it | It over-sizes most real homes. A split-unit figure can be found in a few hours. |
> | C | Use it only for ducted homes | |
>
> ---
>
> **2. Do we refuse honestly when a buyer says double glazed?**
>
> > Today a buyer who says nothing is treated better than one who tells the truth. The honest buyer gets a bigger unit in two rooms.
>
> | | Option | Why |
> |---|---|---|
> | **A ✓** | Refuse, and tell the buyer we have no figures for that glass yet | Honesty should never cost the buyer. |
> | B | Keep sizing them as cheap glass | |

## Common mistakes

A question that carries the whole rule ("do quick replies stay one line, with the card only when…?") instead of a short one with the rule in the options; an option that is a label ("keep the two sizes") instead of a sentence; a code standing in for a name; a count with nothing attached; "you ruled" or "as you saw" in place of the rule restated; the question written as a statement; options run together on one line; the pick explained in prose above the table instead of under Why; the diary in the chat.

## Done when

The message ends with Needs my input; every decision sits in its own table with the pick ticked; every digit sits in a sentence that says what it changes; and no code, file, or internal name appears before its plain name.
