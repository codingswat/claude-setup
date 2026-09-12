---
name: handover
description: Write a HANDOVER.md for the current project — a complete, self-contained technical handover for a developer who has never seen the code. Use when the user invokes /handover or asks for a handover document.
---

# Writing a handover document

Produce ONE file, `HANDOVER.md`, at the repo root. The reader is a developer who has
**never seen this code, has no access to this conversation or this machine, and may not
even have the repository open** — the document alone must let them understand the
project completely: what it does, how it behaves, why it is built the way it is, and
what its limits are. Written well, it could serve as the specification for re-building
the project from scratch. Scale the depth to the project's size — a small project gets
a short document, but a short *complete* one. If the user names a specific audience or
purpose (e.g. "for porting this to TypeScript"), write for that reader; otherwise write
for a generic new developer.

## Reproduction-grade mode

The typical serious use: a proof of concept is done, and the project transfers to
another developer, environment, or framework. Then the document is a
**re-implementation specification** — the bar rises from "understand completely" to
"rebuild completely, without the source". The core logic is the asset being
transferred; the current code layout, framework and platform are incidental. Use this
mode whenever the user says the handover is for a transfer, a port, or a new
environment — and when in doubt, ask which mode is wanted. In this mode, additionally
require:

- **Exact values, always.** Every constant, threshold, cap, precision, rounding rule,
  format string and magic number, stated with its value and its reason. "Rounds to 6
  decimals (~0.11 m at the equator)", never "rounds appropriately".
- **Worked examples as parity fixtures.** For each core transformation, real inputs
  and their exact outputs, verbatim from running the code — enough that the new
  implementation can be tested against them mechanically. Say explicitly that these
  are for parity testing.
- **An invariants list: "behaviours that must survive the port."** A short numbered
  list of the properties that define correctness regardless of language or framework
  (failure semantics, ordering guarantees, escaping rules, precision propagation…).
  If a reviewer of the new implementation checks only one section, it is this one.
- **A portability map.** For every dependency and platform-specific mechanism: what it
  does, whether it transfers, and the concrete equivalent in the target environment
  (or "no equivalent — port the algorithm by hand, roughly N lines"). Separate what is
  pure logic (ports directly) from what is binding- or platform-dependent.
- **Algorithms as mathematics, not code references.** State the formula, the
  numerical-stability choices, and the edge handling in prose or pseudocode that a
  developer in any language can implement — verbatim source is illustration, not the
  spec.
- **Organise around the core, not the current file tree.** The old implementation's
  module layout is trivia; the pipeline of transformations and their contracts is the
  content.

## What a good handover reads like

Every claim is verifiable and traced to evidence. Behaviour that is subtle or easy to
get wrong on re-implementation is shown as verbatim source with a sentence on why it
matters. Tables carry enumerable facts (components, field mappings, limits, error
messages); prose carries reasoning. Deliberate design choices are distinguished from
known defects, and both from open questions. The document never says "obviously",
never assumes the reader knows the project's history, and never pads — if a section
has nothing real to say, it is omitted.

## Non-negotiable rules

1. **Complete means complete.** Everything essential to understanding the project goes
   IN the document — even when the README covers it too. Do not replace substance with
   a pointer: "see the README for the behaviour tables" fails the reader who only has
   this file. Where the project's own docs are good, distil them (shorter, reorganised
   around what a newcomer needs) rather than either copying them wholesale or hollowing
   the handover out to avoid overlap. Essential means: purpose, every user-visible
   behaviour and its edge cases, inputs and outputs with their exact formats, the key
   algorithms, the decisions, the limits.
2. **The document stands alone.** Never reference the session or conversation that
   produced it ("verified this session" → "verified at the time of writing, at commit
   X"). Never depend on files outside the repository — if an outside fact matters
   (a machine trap, an owner convention), state the fact itself. Label machine-specific
   details as such and give the portable way to check them (e.g. the command that
   reveals the Tk version, not one machine's good interpreter path).
3. **Read the code, don't recall it.** Every claim comes from files opened while
   writing or commands actually run. Run the tests and record the real count and
   result. Quote key source verbatim where behaviour is subtle.
4. **No assumed context.** Define every project-specific term at first use.
5. **What you can't determine, list — don't guess.** Close with an "Open decisions /
   not determinable from the repo" section instead of inventing answers.
6. **State the source of truth**: the commit hash and branch the document describes,
   and the test count at that commit.
7. **Check the docs against reality and report drift.** Compare the README's claims
   (module lists, commands, feature descriptions) with the actual code and git log.
   Anything out of date is a finding for the "gotchas" section — and a warning not to
   distil stale claims into the handover as fact.

## Before writing — survey the whole repo

- **Expect more than one thing.** A repo may hold several programs (an old starter CLI
  beside the real app, a Python original beside a JS port). Orient the reader across
  all of them and say which one matters.
- **Verify every command from the directory you document it in.** Test runners
  especially: `python3 -m unittest` can find completely different suites from the repo
  root vs a subfolder. A wrong-directory "OK" is the most misleading evidence there is.
- **Gather decisions from every source that exists**, in this order: `DECISIONS.md`,
  the project's `CLAUDE.md`, design specs (`docs/`, `docs/superpowers/specs/`), the
  README, and commit messages in `git log`.

  About `DECISIONS.md`: this user's projects keep a decision log by convention — a
  file where each significant choice (framework, database, architecture, dropping a
  feature, reversing an earlier decision) is recorded as three lines: **Decided**
  (what), **Why**, and **Rules out** (what the choice closes off). Older projects may
  not have one; if it is missing, say so in the handover and reconstruct the settled
  decisions from the other sources, each in that same three-part shape.

## Structure (adapt, don't pad)

1. **Header** — what this is, who it's for, source-of-truth commit + test evidence.
2. **Orientation** — everything that exists: components, paths, roles. A table works
   well. Name the project's own docs and what each adds beyond this document.
3. **Purpose & user flow** — what it does, who uses it, the user's path end to end,
   and how failure is handled (failure behaviour is usually load-bearing design).
4. **Behaviour specification** — every user-visible behaviour with its edge cases:
   inputs and their exact formats, outputs and their exact formats, worked examples
   with real values, error cases and their exact messages. This is usually the longest
   section; it is what makes the document complete rather than an overview.
5. **How to run and test it** — exact commands, exact directories, which interpreter
   or runtime, whether a server or display is needed. Every command verified.
6. **Structure & key logic** — module map (current, not the README's if that has
   drifted); the pipeline step by step; verbatim snippets for anything subtle a
   re-implementer would get wrong, each with why it matters.
7. **Key decisions** — from the sources above. For each: what, why, what it rules out.
8. **Known gotchas & limitations** — machine-specific traps (with portable checks),
   edge cases, deliberate gaps, things that look like bugs but aren't, real known
   defects labelled as such, and any doc drift found in rule 7.
9. **Open decisions** — what the code does not determine; what needs the owner.

## Final check before delivering

Read the finished document once as its intended reader and ask: **could I re-build
this project's behaviour from this document alone — and what question would I still
have to ask?** Every such question is either answerable from the repo (answer it in
the document) or genuinely open (move it to the open-decisions section). Deliver only
when that pass adds nothing more.

## After writing

- Tell the user where the file is.
- Commit it authored as the repository owner's own git identity — no
  "Co-Authored-By: Claude" line and no other AI attribution in the message — and push.
