# Attribution

## Own skills in this folder

Written from scratch, no external pack or author behind them.

- **summarize/** — the fixed report shape (status light, Problem, Story, Result, Needs-my-input)
  every task report is written in, so a non-technical reader can act on it without opening a file.
- **overnight/** — runs an unattended work session end to end: restate the queue and ask every
  question up front, work everything that needs no human input, park anything that does, and
  close with a two-section morning summary (FYI / INPUT NEEDED).
- **handing-off-live-work/** — hands a half-finished task to the next session correctly: let
  everything running finish, write down exactly what state things are in, commit it, and write
  the next session's opening prompt — in that order.
- **handover/** — writes a single self-contained `HANDOVER.md` for a developer who has never seen
  the project, complete enough to rebuild its behaviour from the document alone.

## Cherry-picked into this folder

All four skills below were cherry-picked from larger open-source packs released under the MIT
license — the skill and its own supporting files, not the surrounding plugin machinery. They are
not my original work; credit belongs to their authors, linked below. Local modifications are
noted per skill.

### From mattpocock/skills

Source: https://github.com/mattpocock/skills (MIT license)

- **wait-what/** — stop and re-explain in plain language when the user is lost.
  Modified locally: unlocked for model invocation (the original is user-invoked
  only) — in both the SKILL.md frontmatter and agents/openai.yaml — and given
  trigger guidance ("use sparingly, on real confusion signals").
- **teach/** — multi-session teaching workspace with lessons and learning
  records. Modified locally: unlocked for model invocation (frontmatter and
  agents/openai.yaml), with a "propose before starting" guardrail since it
  creates files.
- **domain-modeling/** — build a project's shared vocabulary (CONTEXT.md) and
  record decisions as they crystallise. Unmodified.

### From DietrichGebert/ponytail

Source: https://github.com/DietrichGebert/ponytail (MIT license)

- **ponytail/** — the "lazy senior dev" discipline: reuse before writing,
  standard library before dependencies, the minimum code that works.
  Modified locally: the skill file only (the always-on plugin machinery was
  deliberately not adopted); rewritten as an optional tool the session may
  apply or skip, rather than a mandate active on every task; persistence
  wording softened to match.

Why cherry-pick instead of installing the packs? Overlapping skills from
multiple packs compete for the same tasks and confuse sessions. Taking single
files keeps one clear owner per job — and the files can be reworded to fit
(see each skill's frontmatter for its current wording).

## Skills I run but do not copy here

Everything else in my personal `~/.claude/skills/` — either sourced from elsewhere, or generic
enough that I can't be confident it's my own unlabelled work, so it stays private rather than
being claimed here.

- **a11y-audit** — WCAG 2.2 accessibility scan/fix/verify pipeline. Source: cites
  https://www.w3.org/TR/WCAG22/ and related W3C/axe-core references; no single pack author named
  in the file. Locally modified: yes (the CI recipe is disabled as broken, auto-fixes turned off).
- **analogy**, **concept-fan**, **inversion**, **provocation**, **random-stimulus**, **scamper**,
  **six-hats**, **worst-idea**, with their router **lateral** — eight named creativity techniques
  (Synectics/forced analogy, de Bono's concept fan/provocation/random stimulus/six hats, Eberle's
  SCAMPER, reverse brainstorming) plus the router that picks between them. Source: each technique
  file cites its own named originator (William J.J. Gordon, Edward de Bono, Bob Eberle, or the
  d.school/IDEO "Worst Possible Idea" practice); the router's own guardrails name the install
  command `npx skills add danium/lateral-thinking` as where the pack came from. Locally modified:
  the router only (usage guidance, deferring to it over other divergent-thinking skills).
- **book-to-skill** — converts a book/document into a new skill for Claude Code, Copilot CLI,
  Amp, or Hermes Agent. Source not recorded in the skill file (a generic cross-agent tool, not
  written in an operating voice); not locally modified.
- **frontend-design** — visual/interaction design guidance for building distinctive UI. Source:
  Apache-2.0 licensed (LICENSE.txt in the folder); no specific author or URL named in the file
  beyond the license text. Locally modified: none noted in the file.
- **grill-me** / **grilling** — a relentless round-by-round interview that maps a plan or decision
  as a tree and works it to a shared understanding. Source not recorded in the skill file; not
  locally modified.
- **prototype** — builds throwaway code (a logic demo or a UI variant page) to answer one design
  question fast. Source not recorded in the skill file; not locally modified.
- **research** — dispatches a background agent to investigate a question against primary sources
  and write the findings to a file. Source not recorded in the skill file (an adapted skill —
  its own guardrails say "override upstream where they conflict" without naming the upstream).
  Locally modified: yes.
- **resolving-merge-conflicts** — works an in-progress git merge/rebase conflict to resolution
  using each side's original intent. Source not recorded in the skill file (adapted; "override
  upstream where they conflict"). Locally modified: yes (never `--abort`; show resolved hunks
  before committing; never fold unrelated changes into the merge commit).
- **retro** — a session retrospective that looks for improvements to the agent's own environment
  (navigation, automated checks, coding standards, steering files). Source not recorded in the
  skill file; its own guardrails describe it as adapted from "an unfinished, in-progress" external
  author's folder. Locally modified: yes (its vocabulary is remapped onto this setup's own files).
- **skill-security-auditor** — static scan of a skill/plugin for code-execution risk, prompt
  injection, and supply-chain issues before installing it. Source: a generic scanner tool; the
  file's own example command points at a placeholder `github.com/user/repo`, no real pack author
  named. Locally modified: yes (treated as a first pass only, never a replacement for a full
  blind review).
- **to-questionnaire** — turns a decision the user can't fully answer into an async questionnaire
  for the person who can. Source not recorded in the skill file; not locally modified.
- **wizard** — generates an interactive bash wizard that walks a human through a manual setup
  procedure (credentials, dashboards, one-off migrations). Source not recorded in the skill file;
  not locally modified.
- **writing-for-agents** — a style guide for writing any document an agent consumes (a skill, an
  `AGENTS.md`/`CLAUDE.md`, a doc reached by a pointer): context pointers, information hierarchy,
  completion criteria, leading words, pruning. Source not recorded in the skill file itself — no
  credit line — but it shares vocabulary with, and is depended on by, **retro** above, which
  explicitly describes itself as adapted from an external author's folder; treated here as likely
  adapted rather than confidently my own, so it is not copied.

**Not listed above — regenerated, not carried:** **react-router-7**, **tailwind-4**, and
**tanstack-query-5** are one-sentence reference skills generated per project straight from each
library's own current documentation for the version in use, so they're regenerated fresh rather
than copied or attributed here.
