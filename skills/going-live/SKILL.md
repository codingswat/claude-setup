---
name: going-live
description: Use before a deploy, before a repo, package or page is made public for the first time, before sharing with anyone but the owner (a private Artifact for the owner, or a push to the owner's private repo, is not sharing), or before migrating a database that holds real or owner data.
---

# Going live

The owner's yes (the explicit go-ahead before anything live or public) is the last step, never the first. In this order:

1. **Privacy check.** Check `git log`, tags, package and release metadata, docs, screenshots, logs, embedded paths, and run `npm run test:privacy` where present. The owner's real name appears nowhere; commits and releases use your publishing identity, with no AI attribution line unless the repo's own rules require AI disclosure. *Optional:* keep a list of real names and home-folder paths that tracked files must never hold, and run the check from it.
2. **Security review.** Run `/security-review`; fix what it finds (high-risk findings are non-negotiable); tell the owner what was found and fixed. Before a product's first public launch, run the accessibility audit (`a11y-audit`: check every page for keyboard use, contrast, labels and screen-reader names) once.
3. **Fresh eyes.** Before any irreversible step that faces outward or touches the owner's data (going public, deploying, migrating or deleting their data), not routine cleanup of the session's own work: one blind reviewer (opus, `briefing-subagents`) sees only the thing itself plus "how can this be bad for me, and what are the gaps?", with no briefing and no history. Blind means an empty folder outside any project (no CLAUDE.md or memory auto-loads); a session inside a project is not blind. Fix what it finds, or record in the decision log why not, before the step.
4. **The owner's yes**, after naming target, scope and consequence.
5. **After the deploy: check the live site.** The main path loads and one real action works, end to end, against the live address; the result is stated in chat with what was run. A failed check is fixed or rolled back before any other work.

A database migration: back it up first (git protects code, not data; a rollback is never data recovery). Secrets are set on the hosting service separately, never in code or files.

**Project part:** if the project has `.claude/skill-parts/going-live.md`, read it now; where it is more specific than this skill, it wins.
