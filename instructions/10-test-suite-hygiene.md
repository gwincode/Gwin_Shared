## Test-suite hygiene (for suites that share live data or accounts)

- Tear down what a test creates in a `finally` block (or the framework's equivalent), not at the end of the
  happy path, so cleanup still runs when a step throws or CI kills the job.
- State another suite reads is a **shared fixture**, not scratch data. Don't delete it; create and remove
  your own fixture instead. Before adding rows next to a shared fixture, search the suites for an unscoped
  delete on that table.
- When narrowing a broad cleanup, first list everything it was silently removing and decide whether any check
  depends on it.
- If suites share fixtures, their run order matters: keep it fixed and explicit.
- Don't stack test re-runs against live services; repeated sign-ins can trip rate limits. Trigger, wait,
  decide.
