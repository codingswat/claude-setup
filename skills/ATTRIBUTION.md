# Attribution

All four skills in this folder were cherry-picked from larger open-source
packs released under the MIT license — the skill and its own supporting files,
not the surrounding plugin machinery. They are not my original
work; credit belongs to their authors, linked below. Local modifications are
noted per skill.

## From mattpocock/skills

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

## From DietrichGebert/ponytail

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
