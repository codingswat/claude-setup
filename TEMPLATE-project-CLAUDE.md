# Template: a per-project CLAUDE.md

**Where this goes:** the root of a project folder, as `CLAUDE.md`. Claude Code loads it
automatically for every session in that project, *on top of* your global
`~/.claude/CLAUDE.md`.

**The split that matters:** the global file is about **you** — how to talk to you, what
permission you give, what process is enforced. This file is about **the project** — what it
is, how to run it, how to test it, and the rules that only apply here. Don't repeat the
global rules in here; they are already loaded.

Delete these instructions and everything in angle brackets as you fill it in.

---

# <Project name> — project rules

<One or two sentences: what this is and who uses it. Be concrete. "Internal tool for the
support team to look up order history" beats "a web application".>

<If the project is not public yet, say so — it changes how Claude weighs risk.>

## The stack

- <Framework and version. Say versions out loud if they matter; otherwise they get
  "helpfully" modernised.>
- <Backend, database, ORM.>
- <Any hard constraint: licences you cannot use, platforms you must support, a language
  whose text direction or encoding is a real requirement rather than an afterthought.>

## Run it

- `<command>` — starts <what> at <exact URL>
- <Anything that must already be running first: a database, a queue, a service.>
- <Where configuration lives, and the reminder that it is never committed.>

*Why this section earns its place: without an exact command and URL, "it works" is a claim
nobody can check. With it, you can look at the thing yourself in ten seconds.*

## Test it

- `<command>` — the full suite.
- <Which tests are slow, which need network, which need real credentials.>
- <Anything visual also gets checked in a real window — headless tests have passed while the
  actual screen was broken.>

## Project-specific rules

<This is the valuable part. Rules that are true *here* and would be wrong elsewhere. Real
examples of the shape:>

- <"The design system is X — use its components, not plain HTML elements, even where a native
  element would work. Visual consistency wins.">
- <"The calculation engine is pure: no AI, no network, no randomness. AI lives only in the
  input-parsing layer, and it never does arithmetic.">
- <"User files are never stored on the server; they are processed and discarded.">
- <"Every user-facing string exists in all supported languages. Layout is tested in each
  direction, not assumed.">

## Where things are

- `docs/specs/` — feature specs, written before building
- `DECISIONS.md` — the decision log. Check it before proposing changes; settled decisions
  are not re-argued without saying so explicitly
- `CONTEXT.md` — the domain glossary: what this project's words actually mean
- <Anything gitignored that matters — real customer data, private examples, credentials —
  and the hard rule that it must never be committed.>
