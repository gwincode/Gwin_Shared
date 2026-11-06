## Model routing

Applies to development sessions and subagents, not to any model an app uses at runtime. A session can't
switch its own model: when a trigger below fires, say so and let the owner switch (or, in a pipeline, let the
orchestrator relaunch the agent on the stronger model). Which model each pipeline agent uses is set per
project, in its agent files.

- **Default: Sonnet (high effort).** Don't escalate without cause. Stay on Sonnet for bug fixes, small
  features, test writing, refactors of one or two files, CI triage, lint fixes, dependency bumps, docs,
  comments and commit messages.
- **Escalate to Opus (xhigh effort) when** Sonnet failed or needed two or more retries; debugging spans
  several services or repos; the work is an architecture decision or large refactor; or the task must hold
  context across many steps.
- **Escalate to Fable only when all are true:** Opus at xhigh already failed or clearly struggled; the task is
  long-horizon (a multi-hour or multi-day autonomous run); and the cost is justified compared with splitting
  the task smaller.
- Say which trigger applied when escalating. Log which model handled each task and whether it succeeded first
  try, so routing can be tuned from real data. Never run routine work on Opus or Fable "to be safe".
