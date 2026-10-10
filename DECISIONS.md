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

**Decided:** The 20 September documents-only refresh landed after a blind review run by a helper inside the landing session, briefed with only the branch and the two questions, not by a separate session in an empty folder.
**Why:** The change touched documents and one skill, no scripts; the helper checked every count and every added line for private names, paths and product details, and its four findings were fixed before the landing.
**Rules out:** Nothing for next time; the empty-folder review stays the standard for anything that ships a script.

**Decided:** The 21 September hooks and skills refresh landed after two blind attack rounds and a re-attack run by helpers inside the landing session (38 holes closed, each with a failing test first), with the owner's empty-folder review scheduled as a follow-up rather than as the gate.
**Why:** The owner chose to land overnight and review in the morning; the in-session attackers reproduced every finding for real and the fixes each carry a two-sided test, which is the evidence the empty-folder review would have asked for.
**Rules out:** Nothing for next time; the empty-folder review before a script goes public stays the standard, and this entry records the second exception and what the attackers caught.

**Decided:** The 29–30 September refresh brought a week of the private setup into the kit: three new lessons and seven updated, eight skills refreshed, the command guards, git hooks, session hooks and the opt-in multi-chat group re-implemented in the kit's own code, one new default guard (a helper launch must name its model), and the installer updated. Two larger guards from the private setup (private files kept out of the chat, tests not quietly skipped) were left for a later refresh.
**Why:** The owner asked for the kit to be brought up to date and chose the full refresh; the two larger guards were new features rather than a refresh, and would have doubled what the reviewers had to test.
**Rules out:** Copying private scripts verbatim; every change was rewritten with conf files for anything site-specific, and a word-list check refused any private name, project or path in an added line.

**Decided:** The refresh went public after one blind attack round (two attackers, each given only a clean copy and two questions: slip past each guard or make it refuse honest work, and how installing this can hurt someone), a fix round for every blocker and major finding, and then a review by a fresh session opened in an empty folder, whose five serious findings about this refresh's code were fixed with a failing test first.
**Why:** The owner chose two review passes instead of four: the attackers already looked for security harm, and the empty-folder review read the fixed version. Guards are tested against honest mistakes and honest work wrongly refused, not against deliberate bypass.
**Rules out:** Nothing for next time; the empty-folder review stays the standard, and this time it ran as the last gate. Findings recorded but not fixed in this refresh (pre-existing design, or small): the starter rules' standing push permission with the key check opt-in, the context-floors skill's wrap-up for one-chat users, guards failing closed when the only python is broken, and the review's medium and small items — each is a candidate for the next refresh.

**Decided:** The 10 October refresh brought the private setup's new coding path into the kit: a nine-step map from an idea to landed code (a new template for the projects folder), the three skills it leans on (`coding-method`, `testing-method`, `going-live`), twelve skills refreshed (a helper brief gains a sixth slot carrying the privacy, secrets and authorship lines; the small model's job list widened; a waiting helper checks back at most every four and a half minutes), five new lessons and four updated, and two skills retired (the handover document, and the write-less skill whose one rule now sits in `coding-method`). The guard and hook changes the private setup made since 29 September were left for a later refresh.
**Why:** The owner asked for the kit to carry the new setup once it had landed privately on 10 October. The documents and skills needed a privacy check, a security review and one blind reviewer; the guard changes are code that needs its own break round, and would have doubled what the reviewers had to test.
**Rules out:** Shipping the private helper-agent definitions (the brief now says what any helper type needs); flipping `wait-what` to model-invoked because the private copy did — the kit keeps it user-invoked, as decided in the 29 September refresh.
