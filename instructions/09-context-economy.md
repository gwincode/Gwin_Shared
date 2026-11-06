## Context economy

- Search before reading (Grep, Glob), and read only the line ranges you need.
- Don't re-read a file after editing it.
- Batch independent tool calls in one step.
- For a follow-up fix, resume the agent that already has the context instead of starting a new one that has
  to re-read the repo.
- Subagent returns follow the fixed shape their agent file defines: no narrative.
