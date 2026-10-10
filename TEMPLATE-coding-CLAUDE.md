# Template: coding rules for every project in your projects folder

**Where this goes:** the folder that holds your projects (the one the installer asked about,
for example `~/projects`), as `CLAUDE.md`. Claude Code loads every `CLAUDE.md` from the folder
a session starts in and from each folder above it, so a file here binds every project inside
that folder, and nothing outside it: a chat started in your home folder about something else
never loads it.

**Why a third file:** the global rulebook (`~/.claude/CLAUDE.md`) loads in every session,
coding or not, so every line in it costs attention everywhere. The path from an idea to landed
code matters only for building work, so it lives here. The detail of each step lives in the
skill for that step, which loads only when the step starts. This file holds only the order.

**What it needs:** the three skills it leans on most ship in this repo (`coding-method`,
`testing-method`, `going-live`). Three steps name skills this repo does not ship (`grilling`,
`research`, `retro`), and `coding-method` names a few more; [skills/ATTRIBUTION.md](skills/ATTRIBUTION.md)
says where each comes from. Without one, the chat does that step by hand, as described. The
map's step numbers are its own; `coding-method`'s sections (§) are numbered separately.

Delete these instructions as you adopt it.

---

# Coding rules — every project in this folder

Every code change follows `coding-method`, and its tests follow `testing-method`, in every
project, with one chat or several. The chat starts the skill each step names by itself; I never
have to name one. Every coding rule has a moment, so each lives in the skill for that moment,
not in this file. Optional rules bind only a project whose own CLAUDE.md names them.

## From need to done

This covers building work that lands in a repo. A chat starts at the step that fits and skips
none after it; a one-line fix goes through every step, quickly.

| # | Step | Starts when | Run by | Done when |
|---|---|---|---|---|
| 1 | Idea | I name a want or a problem | `grilling` (questions until the idea is clear) | one sentence I agree with, or an idea issue |
| 2 | Research | a decision needs a fact not in hand | `research` (a helper reads primary sources and writes notes) | each claim cited to its source |
| 3 | Decide | more than one sensible way | a pick page (a button under each option), the chat's own pick stress-tested first | I pressed; the answer written once |
| 4 | Plan | before any code | `coding-method` §1–2 | every touched file named from a read this session; every behaviour has a refuse/allow line; a screen or spec has my yes |
| 5 | Build, test first | the plan is written | `coding-method` §3–4 with `testing-method` | each behaviour fails, then passes, judged by exit code with its test count reported; the smallest change |
| 6 | Review | tests pass, before the records | `coding-method` §5 | each plan line quoted (match, or why not); every finding fixed or answered |
| 7 | Land | the review is answered | `coding-method` §6–7 | the records ride the same commit; the change is on main |
| 8 | Deploy or share | the change goes live, public, or to anyone but me | `going-live` | its checks passed, my yes, the live site checked after |
| 9 | Look back | a phase or a big build has landed | `retro` (what slowed the work or let a mistake through) | findings in chat; rule changes proposed, never made |

Off the path: a problem put off is a parked issue, an idea an idea issue, each with what wakes
it (on a public repo, a security problem never goes in a public issue); a chat ending mid-task
hands off (`handing-off-live-work`); after landing, the chat cleans up.

The chat copies these steps into its own to-do list, and a skipped step stays there, marked
with its reason.

<!-- FILL THIS IN (optional)
Rules that bind only the projects that ask for them, one line each, for example:
- "No code under a licence that could force me to publish my own source, in anything shipped."
- "Write down what is kept where; raw uploads are never stored for good."
A project opts in by naming the rule in its own CLAUDE.md.
-->
