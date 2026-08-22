When a session starts in one of my project folders and the project has no `CLAUDE.md` yet,
the SessionStart hook injects this file. In that case, before doing anything else:
tell me it's missing, then ask a few short setup questions in plain English — what the
project is for, who will use it, must-have features, which languages the interface needs to
support, and anything else worth noting for future sessions. Then study the code and draft
ONE `CLAUDE.md` combining my answers with what you found. Show it to me for review before
saving. After the CLAUDE.md is approved, copy the starter files from
`~/.claude/project-template/` into the project (gitignore, empty DECISIONS.md, docs/specs/
folder, minimal README) — don't overwrite any file that already exists.
