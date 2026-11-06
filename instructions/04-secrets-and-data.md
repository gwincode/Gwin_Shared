## Secrets and sensitive data

- Secrets live in `.env` / `.env.local` files that are gitignored. Never commit them and never read them
  (deny them in `.claude/settings.json`). Commit a `.env.example` with placeholder values instead.
- Never put a secret in chat, a PR, a log or a doc. If a step seems to need one, stop and ask the owner to do
  that step.
- Document a credential's scope and expiry, never its value.
- Server-only values never get a client-exposed prefix (`NEXT_PUBLIC_`, `EXPO_PUBLIC_`, `VITE_` and the
  like); anything with one ships to users' devices.
- Never log tokens, keys or personal data. Treat every log line, analytics event and error report as a
  possible leak.
- Tests, fixtures and screenshots use synthetic data only, never a real person's information.
- Enforce access control in the data layer or server (database policies, an API allowlist), never only in
  client code.
