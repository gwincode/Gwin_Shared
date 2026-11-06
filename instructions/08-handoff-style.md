## Handoff style

- Every handoff and PR summary ends with where the work goes next: predict what the next actor (an agent, a
  reviewer or the owner) will do with it, and recommend the step after that.
- When code work finishes, end the final reply with one fenced **handoff copy block** the owner can read on
  its own: PR link, version, what changed, verbatim test counts, caveats, and what the reviewer should check.
  Deliver it without being asked.
- **Four next steps.** At the end of each task that changes something, give the owner four possible next
  steps, best first. For each step, give a short ASD-STE100 explanation: what it does and why.
  - Show the steps as clickable cards or buttons when the interface has them. If not, use a numbered list.
  - When a step is a separate task, recommend that it starts in a new session, to use fewer tokens. Keep a
    step in the current session only when it needs this session's context (for example, to commit the work
    that this session did).
