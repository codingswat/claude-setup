---
name: shared-tree-commit
description: Use when committing, landing or pushing in a shared git checkout or a seat's own worktree, when a git guard refuses a command (a pathspec, dangerous-git, heavy-suite, or channel-size guard, a commit-size ceiling, a pre-push type-check), or when a push is rejected as non-fast-forward.
---

# Committing in a shared tree

## Overview

When several sessions or people share one working tree and one git index, a commit takes
whatever the working tree currently holds for the paths you name — so the discipline is
two-fold: name your own paths, and never carry another session's lines into your commit. A
seat working in its own worktree instead follows **In your own worktree** below.

## The recipe (shared root folder)

1. Pull, in its own step: `git pull --ff-only`.
2. Write, in its own step: an editor tool, or a shell command that names the exact file.
3. Read the content before staging: `git diff HEAD -- <path>` for every shared/channel file
   (a live notes file, a decision log, a mistakes ledger, a plan file — anything several
   sessions append to). Every hunk in that diff should be yours — if it isn't, stop.
4. Commit by path, in its own step: `git commit <path> <path> -m "…"`, then `git push`. If a
   pre-push check runs a type-check (or similar) and refuses on failure, let it finish —
   don't bypass it.
5. If a guard refuses: re-read `git diff HEAD -- <path>` again, in a fresh step, right after
   the refusal (the branch tip or the tree may have moved since your first read) — the retry
   is the very next thing you do, not something done later.

The write and the commit are separate steps on purpose: a guard evaluating a command judges
the file as it stood *before* that command ran, so a single step that both writes and
commits is judged on stale content.

## In your own worktree

A seat with its own worktree shares no folder and no index with anyone else, so whole-index
guards and provenance checks that watch the shared root don't apply there. Attribution
rules, file-size bands, and a pre-push type-check still apply everywhere. The recipe
becomes:

1. Sync, in its own step: `git fetch origin && git rebase origin/main`. On a conflict,
   resolve it by re-applying each side's original intent — never `git merge --abort`, and
   never fold unrelated changes into the conflict-resolution commit. On a shared channel
   file, keep both entries (yours above theirs) and say so in your commit message.
2. Write, in its own step.
3. Read the content: `git diff HEAD -- <path>` for every channel file — every hunk should be
   yours by construction; this catches a rebase that accidentally kept the wrong side of a
   conflict.
4. Commit by path: `git commit <path> <path> -m "…"`.
5. Land it: `git push origin HEAD:main`. On "non-fast-forward," repeat step 1, then push
   again — never `--force`, never `--no-verify`. This direct push is for a repo you alone
   own; a team repo, branch protection, or required reviews mean you follow that repo's own
   workflow (a pull request), never a direct push to main.

**Gate every chained step on its actual exit code, never by piping its output through
something else** (`| grep`, `| tail`, `| head` hide the real exit code of the command
before the pipe). A test run that gates anything should write its own output to a file and
be judged on its own exit status. After a rebase, check that no conflict is still open
(for example, that git reports no in-progress rebase directory) before treating the rebase
as finished — a rebase stopped mid-conflict should never get pushed as if it succeeded. A
pre-push hook that exports the exact commit being pushed into a clean folder and
type-checks it there is checking the commit, not your working folder — your own uncommitted
edits can neither block nor pass it, and this kind of hook is usually opt-in per repo, not
automatic everywhere you clone.

| The message | Meaning | Do |
|---|---|---|
| `rejected … non-fast-forward` | The shared branch moved since your rebase | `git fetch origin && git rebase origin/main`, then push again |
| A conflict on a shared channel file | Another session landed an entry at the same spot | Keep both entries, yours above theirs; continue the rebase; say so |
| `pre-push … typecheck failed on commit …` | The pushed COMMIT doesn't type-check (your folder may be fine) | Fix it, commit again, push again |
| `fatal: '<branch>' is already checked out` | You tried to check out the shared branch inside your own worktree | You never need it locally — land with `git push origin HEAD:main` |

## When a guard speaks

| The message | Meaning | Do |
|---|---|---|
| `commit-pathspec-guard`: no paths, index already holds files | Something else got staged | Commit by path — a pathspec commit ignores whatever else is staged; don't unstage anything |
| `commit-pathspec-guard`: `-a` / `.` refused | A whole-tree sweep was attempted | Name your files instead |
| A provenance / "no record" refusal | This session never wrote that file, or wrote it before committing | Re-read the diff again after the refusal; if every hunk really is yours, set `SWEEP=1` for that one commit; otherwise stop |
| A "changed since you read it" refusal | Another session's lines are now in the file too | Wait for their commit, pull, re-read the diff, retry |
| `channel-size-guard` refusal | The file crossed its size band (for example, 9,000 words for a notes file, with a lower target to sweep down to) | Archive resolved entries down toward the lower target first, then write |
| `block-dangerous-git` refusal | `reset --hard`, `clean`, a force-push, deleting a branch, and similar | State the target, scope and consequence, get an explicit yes, then set `GITGUARD=1` for that one command |
| `heavy-suite-guard` refusal | Another session is already running a full suite | Wait; a single targeted test file is exempt. If you must run anyway, after the owner's yes, set `SUITE_OK=1` for that one command |
| Pre-commit ceiling refusal | Your commit adds an unusually large number of lines to a shared file in one go — only checked when the channel conf (`~/.claude/hooks/channel-ceiling.conf`, set up by the installer's opt-in) is present | Confirm it's deliberate (a genuine sweep), read the diff, then set `SWEEP=1` for that one commit |

An override flag only counts at the very start of a command segment — one written inside a
commit message, a heredoc, or a quoted string does nothing.

## Report

Record what you actually did, in the commit message body, below the subject line — a slot
with nothing to report says "none," it never just disappears:

- Pulled/synced: what the command actually said
- Wrote: which path, and what the entry says
- Diff read: which step(s), what the hunks were
- Guard: the refusal text, unedited, or "none"
- Committed: the command as typed, override prefix included if used

In chat, one sentence is enough: "Landed on main: `<old>..<new>`" (or "committed on the
branch `<hash>`, not landed," or the guard's refusal in plain words).

## Red flags

A whole-tree add or commit in a shared folder; stashing in a shared folder; resetting a
shared file back to HEAD; merging or pulling in the shared root to land a worktree's branch;
calling a push to a side branch a "landing"; using an override before actually reading the
diff; retrying immediately after a refusal with no fresh diff read in between; a shared file
left uncommitted at the end of a session (the next session's cleanup will end up rewriting
it); claiming a check ran when no command actually backs that claim.

## Done when

The push shows the branch moving forward on the shared branch (never sideways), the commit
body carries the audit lines above, and the chat's result names the landing range in one
sentence. A commit still sitting only on a side branch is not done.
