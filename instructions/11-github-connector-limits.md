## GitHub connector limits (reference, as of 2026-10)

- The GitHub MCP connector can't write anything under `.github/workflows/` (403). This isn't grantable from
  the org's settings. Workflow files are written by a session with real git.
- It also gets 403 reading checks and commit status. Read CI with `gh pr checks <n>`, or the PR's Checks tab
  in a browser.
- It writes files whole, so it must not edit `HANDOFF.md` or other large docs (see the handoff rules).
- Its merge API always creates a merge commit; a fast-forward needs real git.
