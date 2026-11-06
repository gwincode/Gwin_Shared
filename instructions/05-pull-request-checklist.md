## Pull request checklist (do every item that applies)

1. **Version and release notes.** Bump the version (semver: features raise the minor number, fixes the patch)
   and add an entry to the project's release-notes file (`CHANGELOG.md` unless `CLAUDE.md` names another),
   written for users, not developers. Read the current version on the actual base branch right before
   bumping, after merging the latest base into your branch; a number from a design doc or prompt is not
   authoritative. State the version you took in the PR body.
2. **Architecture.** Update the project's architecture diagram when an integration, service, table or flow
   changes.
3. **Regression scenarios** for every UI, UX, data or behavior change: (a) write scenarios that cover it,
   (b) get the owner's approval (approving the design counts), (c) show them passing with verbatim runner
   output, and (d) add them to the project's regression list, plus an automated test wherever the behavior is
   testable. A PR that claims no scenarios apply says why, and review challenges that claim.
4. **Test every PR.** When the session can't reach live services, take the real numbers from the CI run log.
   Never merge, and never report counts, without verbatim per-suite PASS/FAIL output.
5. **Design doc.** Commit the feature's design doc in the PR and add its row to the project's design-doc index
   if it has one. The repo copy is the permanent record.
6. **Handoff on the PR.** Post a paste-ready summary on the PR itself (what changed, verified results, a short
   list of what to check), then rewrite `HANDOFF.md`.
7. **Code style.** Match the surrounding code's naming, idiom and density. Comment only on constraints the
   code can't express. Money is exact decimals or integer cents, never floating point.
8. **Commits** use the imperative mood: "Add X", "Fix Y".
