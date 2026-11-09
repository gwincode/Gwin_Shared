# HANDOFF

Living status note for this repo. Update it after every prompt, so the next session (or person) can pick up without re-reading the chat.

Named `HANDOFF.md` to match what `gwinrules --check` looks for.

## Current state

- **Branch:** `claude/admiring-fermi-vysbwv`
- **Open PR:** [gwincode/Gwin_Shared#4](https://github.com/gwincode/Gwin_Shared/pull/4) (draft), "Add lo-fi ASCII install loader (sh + ps1)". CI (`sandbox-install`) green on the last push. No review threads. Mergeable.
- **Session:** `GS PR#4/ascii-loader`

## What's in the repo

| Area | Item | Status |
| --- | --- | --- |
| `scripts/` | `ascii-loader.sh` / `.ps1`: animated ASCII install loader, `--demo` / `-Demo` | Pushed (PR #4). Windows animation not yet verified on a real Windows console |
| `scripts/` | `install.sh` / `install.ps1`: now also install the token status line | Done locally; tested with a throwaway HOME (sh) and an isolated copy (ps1). Not yet committed |
| `plugins/cc-token-statusline/` | Vendored from Alfafis/cc-token-statusline v0.4.5 (MIT). Only the status line scripts, plus `LICENSE` | Done locally; not yet committed |
| `plugins/README.md`, `scripts/README.md` | Document the plugin and the new installer step | Done locally; not yet committed |
| `HANDOFF.md` | This file | New |

## Decisions

- **Statusline is on by default for `~/.claude`.** Opt out with `--no-statusline` / `-NoStatusline`. It is skipped for `--target` because a status line is a personal setting.
- **The plugin is vendored, not fetched at install time.** That keeps installs offline and reproducible. Trade-off: updates are manual. To refresh, copy the newer `scripts/` and `.claude-plugin/plugin.json` from upstream and bump the version note in `plugins/README.md`.
- **Only the status line is kept.** The plugin's hooks and slash commands are not installed by this repo's installer.
- **PowerShell uses `py -3` before `python`.** A bare `python` can be a Microsoft Store stub that prints an ad.

## Open items

- Commit and push the installer, plugin, and handoff changes to PR #4.
- Verify the animated loader and the statusline badge on Windows (PowerShell 7 and Windows Terminal).
- A stray `/steps.txt` exists at the filesystem root from an earlier test command. It is outside the repo. The user should delete it with `rm /steps.txt`.
- Decide whether the statusline should also be offered by `INSTALL-PROMPT.md` (per-project install). Currently it is personal-only.

## Log

- **Prompt 1:** Built the ASCII loader (sh + ps1), tested both, committed, pushed, opened draft PR #4, subscribed to PR activity.
- **Prompt 2:** Watched PR #4 events. CI green, nothing to act on.
- **Prompt 3 (this one):** Created this handoff file. Installed the `cc-token-statusline` badge into the sandbox `~/.claude`. Vendored it into `plugins/`. Wired it into `install.sh` and `install.ps1` (default on, opt-out flag, personal target only). Documented in `plugins/README.md` and `scripts/README.md`.
