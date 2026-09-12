# Decision log

Every significant choice gets three lines: **Decided** (what), **Why**, and **Rules out**
(what this closes off). Newest at the bottom. Check here before proposing changes —
settled decisions aren't relitigated without saying so explicitly.

This is the format, shown on three of this repo's own decisions. The full log stays with
the private setup; a decision log is for the people working on a thing, not its readers.

---

**Decided:** This repo is a curated snapshot, never a live mirror of the private config.
**Why:** The private config carries machine details, personal context, and settings that
don't belong in public; curation is the privacy boundary.
**Rules out:** Auto-syncing this repo from the config repo; treating it as a backup.

**Decided:** No personal paths or identities are hardcoded in shipped scripts. Each hook
reads what it needs from a small config file the installer writes, never present in the repo.
**Why:** Placeholders inside scripts leak the owner's layout, and adopters have to edit code
to use them. Config files fix both at once, and an absent config is a safe default.
**Rules out:** Shipping any script that must be edited before it works, or that names a real
folder.

**Decided:** The rulebook is published as lessons, not verbatim. Each lesson carries the
incident behind it, the one sentence to copy, and what enforces it.
**Why:** A rulebook full of someone else's preferences is worse than none — adopters inherit
answers without noticing they were answers. The incident is what transfers.
**Rules out:** Publishing a filled-in personal rulebook as the thing to copy.
