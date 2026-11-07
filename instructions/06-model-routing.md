## Model routing

Applies to development sessions and subagents, not to any model an app uses at runtime. A session can't
switch its own model or effort: when a trigger below fires, say so and let the owner switch (or, in a
pipeline, let the orchestrator relaunch the agent with the new setting). Which model and effort each pipeline
agent uses is set per project, in its agent files. Model names change often, so this rule uses three tiers.
Each project maps the tiers to current model names in one place (its agent files or its `CLAUDE.md`), and only
that mapping changes when new models ship.

- **Tiers.** *Standard* is the balanced, everyday model. *Advanced* is the next model up in capability.
  *Frontier* is the most capable model the owner has access to. If a project has no mapping, ask the owner
  which model fills each tier. Do not guess from names.
- **Raise effort before you raise the tier.** More effort costs less than a bigger model and often fixes the
  problem. Climb one step at a time, in this order:
  1. Standard, medium effort. This is the default.
  2. Standard, high effort.
  3. Advanced, high effort.
  4. Advanced, xhigh effort.
  5. Frontier.
- **Stay on step 1** for bug fixes, small features, test writing, refactors of one or two files, CI triage,
  lint fixes, dependency bumps, docs, comments and commit messages.
- **Move to step 2 when** one attempt failed; the logic is subtle (concurrency, money, security, data
  migrations); or the change touches several files that depend on each other.
- **Move to step 3 when** step 2 failed or needed two or more retries; debugging spans several services or
  repos; the work is an architecture decision or large refactor; or the task must hold context across many
  steps.
- **Move to step 4 when** step 3 clearly struggled on a hard, open-ended problem.
- **Move to step 5 only when all are true:** step 4 already failed or clearly struggled; the task is
  long-horizon (a multi-hour or multi-day autonomous run); and the cost is justified compared with splitting
  the task smaller.
- **Start higher when the task is clearly hard.** A pipeline planning agent (such as `po`) may start at step 3
  because planning is where mistakes cost the most. Record any such start in the project's agent files.
- **Pin versions in agent files.** Use the full model ID, not a short alias, so a new release can't change a
  model silently. Review the pins when a new model ships.
- Say which trigger applied when you move up. Log which model and effort handled each task and whether it
  succeeded first try, so routing can be tuned from real data. Never run routine work above step 1 "to be
  safe".
