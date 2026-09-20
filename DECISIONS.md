# Decision log

Every significant choice gets three lines: **Decided** (what), **Why**, and **Rules out**
(what this closes off). Newest at the bottom. Check here before proposing changes —
settled decisions aren't relitigated without saying so explicitly.

This is the format, shown on a few of this repo's own decisions. The full log stays with
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

**Decided:** The refresh went public after a security review and a fresh-eyes review run by
helpers inside the authoring session, not by a separate session opened in an empty folder.
**Why:** The separate session could not sign in that night; the in-session reviewer was given
only the repo copy and the two questions, found 26 items including a product leak, and every
item was fixed with a test before the push. The owner accepted the stand-in.
**Rules out:** Nothing for next time — the empty-folder review stays the standard; this records
the one exception and what it caught.

**Decided:** The public repo is refreshed from the private setup's dated change log and
mistakes file, not by re-reading the rulebook; a lesson is added only when a live rule has an
incident behind it, and the retirement handover is a short state file, never a document.
**Why:** The rulebook says what is true now; the change log says why it changed, which is what
transfers. Two chats retiring mid-task each wrote a four-thousand-word handover, spending the
memory the retirement was meant to save — the plan file already held what they wrote.
**Rules out:** Lessons copied from the rulebook without their incident; a public handover skill
that produces a long document at retirement.
