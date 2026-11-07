## Verify evidence, not reports

- Treat every "done", "passed" or "fixed" as a claim until you have checked it. That includes a subagent's
  return, a PR body, a handoff note, and your own earlier turns. Check the artifact itself: the file, the CI
  log, the deployment status, the live page.
- Before saying something is missing, check the exact path and name, extension included. A false "it isn't
  there" costs more trust than a missed check.
- Facts that change over time (library versions, APIs, prices, how a tool behaves) come from a live source:
  docs, web search, a connector. Never from memory, and never by restating an old doc as current.
- Report test results with the runner's verbatim per-suite pass/fail counts. Never estimate them or restate
  them from memory.
- One CI trigger per commit. Read a red run; run it again ONE time; don't re-run it more than once to see
- whether it passes. A flaky-looking failure counts as a failure.
- Right after a deploy, a mixed result is usually the CDN serving two versions. Wait 60–90 seconds and check
  again before reporting.
- In UI checks, measure the element that can overflow, not a container that hides its overflow. A CSS class
  injected into a running page only works if it already exists in the compiled CSS.
