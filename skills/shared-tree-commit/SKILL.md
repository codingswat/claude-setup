---
name: shared-tree-commit
description: Use when committing, landing or pushing in a git checkout that several sessions share or in your own worktree, when a hook or guard refuses a git command, when a push is rejected as non-fast-forward, when a rebase conflicts or stops, or when a commit is about to touch a file another session may also have edited.
---

# Committing where others work too

Read `coding-method` §7 first (general commit-and-land steps). This adds only what a shared checkout or second worktree changes.

A shared checkout has one tree and one index; a commit takes whatever the tree holds for the paths it names. So name your paths and carry no other session's lines. In your own worktree nothing is shared, but the same read still catches a rebase that kept the wrong side.

## In a shared checkout

Each step is its own tool call. A guard judges a call before it runs, so a call that writes and commits is judged on the file as it was before the write.

1. Pull: `git pull --ff-only`.
2. Write (the Edit or Write tool, or a script whose command names the file).
3. Read the content (`coding-method` §7) of every shared file (a shared log, a memo file, a plan).
4. Commit by path (`coding-method` §7), then `git push`. A push hook that type-checks or tests runs to the end.
5. If a guard refuses, run `git diff HEAD -- <path>` again in its own call, after the refusal: HEAD or the tree may have moved; the retry is the very next call after that re-read. A read made before the refusal is not a re-read, however clean it was. Type an override flag only after that re-read, and only for lines you have read and mean to carry. An override counts only at the start of a command segment; inside a message, a heredoc or a quoted string it does nothing.

## In your own worktree

`git rev-parse --path-format=absolute --git-dir --git-common-dir` printing two different paths means a linked worktree: no shared folder, no shared index. Recipe:

1. Sync (`coding-method` §7) in its own call. A conflict: use `resolving-merge-conflicts` if you have it; by hand, that means re-applying each side's original intent, never `git merge --abort`, and never folding unrelated changes into the resolution commit.
2. Write, read the diff of every shared file, then commit by path: each in its own call.
3. Before any push, check the rebase finished: `test ! -d "$(git rev-parse --git-path rebase-merge)"`. Never push a rebase stopped on a conflict as if finished.
4. Land as `coding-method` §7 says. On `rejected … non-fast-forward`, `main` moved: step 1 again (`git fetch origin && git rebase origin/main`), then push again.

**Gates are exit codes, never pipes** (`coding-method` §7). `| grep`, `| tail` or `| head` on a commit, push or rebase step hides the exit code of git and of test runners. A test run that gates anything writes its output to a file and is judged on `$?`. A push hook that checks the pushed commit in a clean export is not affected by your uncommitted edits, for or against.

**`CONFLICT (content)` on a shared append-only file** (a log or memo file where each side adds an entry at the top; another session added one): keep both entries, yours above theirs, say so in the commit message. Then drop from the kept side any entry the other side had just archived: a rebase re-adds archived entries, so check each kept entry's heading against the archive or tombstone before `git rebase --continue`.

| The message | Meaning | Do |
|---|---|---|
| a push hook says the commit fails its check | the commit is broken (your folder may be fine) | fix, commit, push again |
| `fatal: '<branch>' is already checked out` | you tried `git checkout main` in a worktree | never needed locally; land with `git push origin HEAD:main` |
| a hook refuses a bare `git commit` while the index holds files | another session staged files | commit by path; a path commit ignores their staged files; unstage nothing |
| a hook refuses `git commit -a` or `git commit .` | a whole-tree commit | name your files |
| a guard says another session's lines are in the file | the tree holds hunks you did not write | wait for their commit, pull, read the diff again, retry |
| a guard says the history moved under your edit | HEAD moved after you wrote | pull, read the diff again, retry |

## Red flags

`git add -A`, `git commit -a`, `git stash` in a shared checkout, `git reset HEAD -- <file>` on a shared file, `git merge` or `git pull` in the shared checkout to land a worktree's branch, `git push origin <branch>` called a landing, an override typed before the diff was read, a retry straight after a refusal with no diff call between, a report claiming a check no command matches, a shared file left uncommitted at the end of a task (the next session may commit it whole).

## Done when

The push line reads `<old>..<new> HEAD -> main` (or `main -> main` from the shared checkout). A commit sitting on a branch is not landed; say which it is.

**Project part:** if the project has `.claude/skill-parts/shared-tree-commit.md`, read it now; where it is more specific than this skill, it wins.
