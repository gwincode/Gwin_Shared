## `HANDOFF.md`: where the last session stopped

- **Start of every session:** read `HANDOFF.md` at the repo root first. It is the live state; `CLAUDE.md`
  holds conventions and lags behind it. A stale `HANDOFF.md` is a defect: fix it in your own rewrite instead
  of silently re-deriving state from `git log`.
- **End of every session:** rewrite it as the last step, even when only docs changed or no PR shipped.
  - **What moved**: what shipped (or didn't), terse and PR-linked.
  - **Next up**: remove anything already resolved.
  - **Blockers and open decisions**: including manual steps and PRs closed without merging.
  - The `Last updated` date (in the team's time zone) and the branch-state line.
- Keep every line the project's CI check parses (such as `Last updated` or `Divergence:`) in each rewrite.
- **Open state only, not a changelog.** Delete an entry once its work is merged to `main` and verified in
  production. Don't archive it or stack "previous entry" blocks. Before deleting, move any decision or root
  cause that a reader of the design docs couldn't recover into a design doc or `CLAUDE.md`.
- **Size limit: about 250 lines**, or the project's CI limit if it has one.
- **Rewriting a large file whole is dangerous.** Reproduce its content exactly; never abbreviate "to save
  space". A tool that can only write whole files (such as the GitHub connector) must not rewrite
  `HANDOFF.md` or any other large doc; only a session with a real checkout edits them.
