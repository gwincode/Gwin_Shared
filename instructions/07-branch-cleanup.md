## Branch cleanup

- Delete a branch as soon as its PR merges. Turn on GitHub's "Automatically delete head branches"; still
  delete by hand (`git push origin --delete <branch>`) after a merge done outside GitHub's merge button, and
  clean up local copies with `git fetch --prune` and `git branch -d <branch>`.
- **Automatic deletion also deletes `staging`** after a `staging → main` release PR, because `staging` is
  that PR's head branch. Only branches covered by a protection rule or ruleset are spared, so protect
  `staging` and `main` against deletion. If `staging` is ever deleted, recreate it from `main` and record it
  in `HANDOFF.md`.
- A PR closed without merging whose branch has no further use: delete the branch too.
- Never delete `main`, `staging` or any other long-lived environment branch.
- Before deleting, confirm the PR really is merged or closed and the branch isn't the head of another open PR.
