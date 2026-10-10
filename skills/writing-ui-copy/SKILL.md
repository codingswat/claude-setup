---
name: writing-ui-copy
description: Use when writing, translating, trimming, or reviewing any user-facing string — screens, buttons, error and refusal messages, disclosures, public pages — when adding a second language beside the first, or when a screen is called wordy.
---

# Writing user-facing copy under the honesty test

## Overview

A sentence stays on screen when it is what a helpful person would say once: new to the reader, or a short line on what happened, what to do next, or why — being true is not enough. Copy lives in the file that renders it, and every claim in it traces to code that makes it true.

## When to use / when not

Any user-facing string: screens, buttons, errors, refusals, disclosures, public pages, a server message a user reads. Not comments or docs. Mechanics of a language that reads in another direction (vowel marks, digits, direction), and spelling and grammar of a document in another language: the project's own skill for them, if it has one.

## The honesty test

1. Write what a helpful person would say once, in as few words as that takes.
2. Cut filler, anything said twice, selling, praise, and comfort with no new fact.
3. A short line saying what just happened, where the reader is, what to do next, or why, may stay — even when they could work it out.
4. Always keep anything about a number they'll rely on, a refusal, or a step that can't be undone.
5. Never hide a warning or a disclosure.

## Quick reference — per sentence

| The sentence | Verdict |
|---|---|
| Already on this screen, said twice, filler, selling, praise, comfort with no new fact | **CUT** |
| Half new, half repeated | **TRIM** to the new half |
| Something new to the reader | **KEEP** |
| A short line on what just happened, where they are, what to do next, or why | **KEEP** |
| Qualifies a number they will rely on — an assumption, an estimate, a confidence grade | **KEEP**, always |
| A refusal and its reason; a consequence they act on — can't be undone, spent, expires, limited | **KEEP**, always |

## Never hidden

A number shown without its caveat is a wrong number, so honesty is **moved and demoted, never hidden**: it sits at the point of use, typographically quieter than the number it qualifies, and rides into every view that shows that number. It is never cut for length and never folded behind a vague "show more" or a bare icon.

## Required slots — output missing any is unfinished

1. **The copy object in the source file that renders it**, in the project's copy shape, typed so a key missing a language fails the type check. A gate that walks source reaches a new copy file the moment it is written — there is nothing to register; a strings `.json` reaches no gate. Keys are flat — `errorTitle` / `errorBody`, not `error: { title, body }` — so a `Record<string, …>` type checks every one.
2. **A comment above the copy naming the code that makes each claim true**; a claim you cannot point at is not written.
3. **The gate file policing these strings, named**, plus any new assertion needed.
4. **Real text in every language the product ships**, per key, reviewed by a person who reads it. Direction, digit and spelling mechanics of a language: the project's own skill for them, if it has one.

## Never

- **Developer vocabulary** — words the reader has never met and cannot act on: a reader does not have a server and cannot act on being told one is unreachable. Keep the project's list in a test, and check the other languages' strings against the first language's list too: half-translated copy carries the original term through unchanged. Say what they can do instead.
- **Selling, praise, or reassurance with no new fact in it.**
- **A disclosure behind "show more", or cut for length.**

## Rationalizations that fail here

| Thought | Reality |
|---|---|
| "It is true, so it stays" | The bar is whether a helpful person would say it once, not whether it is true |
| "It reassures the reader" | Comfort without a new fact is empty; state the fact or cut it |
| "Trim it later" | Write it trimmed now; add back with evidence |
| "JSON now, wire it later" | Ungated copy is exactly that drift |

## The example

```ts
// Claim → code: nothing leaves the device — <the module that stores the files>.
const COPY = {
  keepACopy: {
    en: "We don't keep a copy of your files, so if this device loses them, we can't get them back for you.",
    es: "No guardamos una copia de tus archivos, así que si este dispositivo los pierde, no podemos recuperarlos por ti.",
  },
} satisfies Record<string, { en: string; es: string }>;
```

"Saved on this device only" was CUT — implied; "we can't get them back for you" survived: it makes someone take a backup.

## Common mistakes

- A success message that repeats what the screen already shows (a confirmation of an action the reader just took, with no change on screen, may stay).
- Promising behaviour ("open it on any device") that no code path backs.
- A stock button label the code contradicts — "Continue without saving" on a screen where the work IS saved on the device and only the account sync failed. The honesty test binds labels, not just sentences: trace the claim to the code path before reusing a familiar label.

**Project part:** if the project has `.claude/skill-parts/writing-ui-copy.md`, read it now; where it is more specific than this skill, it wins.
