# Test results (PC tester)

This branch holds only test results, written by the PC tester: the owner's Windows PC running this repo's own tests, unattended.

- **Get a commit tested:** push it to a branch under `ci/`, for example `git push origin HEAD:ci/my-change`. Heads under 48 hours old are picked up within a few minutes.
- **Read the result:** one file per tested commit in `results/`, named `<day>-<first 8 characters of the commit>.md`: GREEN or RED, the commands that ran, and the last lines of their output.

Never merge this branch into `main`.
