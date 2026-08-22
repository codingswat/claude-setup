# Decision log

Every significant choice gets three lines: **Decided** (what), **Why**, and **Rules out**
(what this closes off). Newest at the bottom. Check here before proposing changes —
settled decisions aren't relitigated without saying so explicitly.

---

**Decided (2026-08-18):** This repo is a curated snapshot, never a live mirror of the
private config.
**Why:** The private config carries machine details, personal context, and settings that
don't belong in public; curation is the privacy boundary.
**Rules out:** Auto-syncing this repo from the config repo; treating it as a backup.

**Decided (2026-08-18, narrowed 2026-08-22):** No email address of any kind appears in a
tracked file; the installer writes the user's own identity into a local config file instead.
**Why:** The owner publishes pseudonymously; addresses stay out of file contents even where
one already appears in commit metadata.
**Rules out:** Publishing any address or machine path in a tracked file.

**Decided (2026-08-18):** Machine details, private repo names, the exact folder layout,
and the domain-specific glossary entries are stripped from the public copies.
**Why:** An independent pre-publication security review found they add up to targeting
information and deanonymization-by-aggregation, without helping any reader adopt the setup.
**Rules out:** Re-adding "just interesting" personal detail to the public snapshot; the
pattern gets published, the specifics don't.

**Decided (2026-08-18):** A second, fully blind review (an agent given only the repo and
"how can this be bad for me?") runs before publication, in addition to the briefed
security review.
**Why:** The blind reviewer caught real folder paths still hardcoded in the hook scripts —
files the briefed review under-weighted — plus a stale hook copy that contradicted the
rulebook it shipped with.
**Rules out:** Treating one review pass as sufficient for anything permanent; shipping
hook scripts without re-copying them from the live versions at publish time.

**Decided (2026-08-18):** Created private; flips public only after the owner's explicit
go, an identity audit of the git history, and a security review.
**Why:** Global rules 15 and 20 — public git history is permanent.
**Rules out:** Publishing on assembly; treating "built for public" as "public now".

**Decided (2026-08-22):** The repo installs itself — `install.sh` plus a repo-root
`CLAUDE.md` that tells a Claude Code session how to set it up and then walk the user
through personalising their rulebook.
**Why:** The goal is friends actually running this, not reading it. Nobody hand-edits
`settings.json` to register two hooks; without an installer the realistic outcome is that
people read the repo and install nothing.
**Rules out:** Documentation-only distribution; any install step that requires editing a
shipped script by hand.

**Decided (2026-08-22):** No personal paths or identities are hardcoded in shipped scripts.
The SessionStart hook reads its project roots from `hooks/project-roots.conf`, and the Stop
hook reads its git identity and mirror folder from `hooks/backup.conf` — both written by the
installer, neither present in the repo.
**Why:** Placeholders inside scripts leak the owner's layout, and adopters have to edit code
to use them. Config files fix both at once, and an absent config is a safe default (no
interview; the backup hook exits doing nothing).
**Rules out:** Shipping any script that must be edited before it works, or that names a real
folder.

**Decided (2026-08-22):** The personal sections of the rulebook are published as a
fill-in-the-blanks form (`TEMPLATE-CLAUDE.md`) that states what each blank changes, and the
lived rulebook keeps only notes where those sections were.
**Why:** Two reasons, and the second is the stronger one. Privacy: identity, machine and
project detail are exactly what cannot be un-published. Usefulness: a rulebook full of
someone else's preferences is worse than none, because adopters inherit answers without
noticing they were answers.
**Rules out:** Publishing a filled-in personal rulebook as the thing to copy.

**Decided (2026-08-22):** The multi-chat roles pattern is published as a generic document
written from scratch, with no project, domain, or business detail from where it was learned.
**Why:** It is the most transferable thing in the setup and the least available elsewhere —
but the file it was learned in is full of things that cannot go public.
**Rules out:** Copying any project's real role charter into the public repo.

**Decided (2026-08-22):** Repo goes public only after three review rounds, not one. A
multi-agent sweep (41 findings, 28 refuted, 13 fixed) was followed by a single fresh-eyes
agent that found four more blockers the sweep had missed — including a hook that would stage
a user's entire home directory when `~/.claude` sits inside a larger git repo. Each fix was
reproduced as a failure first and then shown closed, with a control proving the guard still
allows correct setups through. Those runs happened in the authoring session against throwaway
home directories; this repo ships no test suite, so treat the claim as reported, not proven —
per rule 3, reproduce anything you intend to rely on.
**Why:** Global rules 20 and 21. The second round finding blockers after the first round
declared itself finished is the evidence for why rule 21 exists.
**Rules out:** Treating any single review pass as sufficient; publishing further changes
without re-running the same checks.

**Decided (2026-08-22):** The auto-backup hook refuses to run unless `~/.claude` is the ROOT
of its own git repository.
**Why:** `git rev-parse --is-inside-work-tree` walks upward, so with `$HOME` as a git repo it
answers "true" for `~/.claude` and `git add -A` stages the whole home directory. A
`.gitignore` only governs its own subtree, so the allowlist cannot protect `~/.ssh` or
`~/.aws` — reproduced, committing `id_rsa` and `.aws-creds`.
**Rules out:** Any backup path that trusts an ancestor repository.
