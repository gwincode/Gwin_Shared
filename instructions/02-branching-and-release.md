## Branching and release

Branch names below are the defaults (`staging`, `main`); a project with different names says so in its own
`CLAUDE.md`.

- **Every change goes through a pull request**, including small, docs-only and agent-driven ones. The PR is
  the record.
- **Staging first.** Branch off `staging` and open the PR against `staging`. Nothing goes straight to `main`.
  Merging to `staging` and `main` together is allowed only when the owner explicitly authorizes it for that
  change.
- **The author never merges.** The session or agent that wrote a change pushes its branch and opens the PR,
  but never merges it, to `staging` or `main`.
- **Fresh-context review before merging to `staging`.** A context that did not write the diff (a new session,
  or a reviewer subagent given only the PR) re-verifies it: re-run the tests, probe the edge cases, check the
  release-note claims against the code. The review prompt says "return a verdict", never "merge".
- **Release to `main` is owner-only**, after the owner has tested on `staging`. No exceptions, not even
  docs-only changes. Prepare the release PR, state exactly what will happen, and wait for an explicit yes.
- **Release often**: whenever `staging` is green and verified, so `main` never drifts far behind.
- After every release, confirm the production deployment finished and spot-check the live app.
- Never rewrite history on a shared branch. Never force-push `main` or `staging`.
- **Other owner-only actions**: applying a production migration; deleting user data, or branches and files
  this session didn't create; any payment, purchase or transfer. Prepare it, state exactly what will happen,
  and wait for an explicit yes.
