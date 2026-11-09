# HANDOFF

Living status note for this repo. Update it after every prompt, so the next session (or person) can pick up without re-reading the chat.

Named `HANDOFF.md` to match what `gwinrules --check` looks for.

## Current state

- **Branch:** `claude/admiring-fermi-vysbwv`
- **PR:** [gwincode/Gwin_Shared#4](https://github.com/gwincode/Gwin_Shared/pull/4), marked ready by the user and then merged into `main` at their request. It contains the ASCII loader, the status line install, the `--loader` flag, and this file.
- **Next change:** a merged PR is finished and cannot take new work. Restart this branch from the latest `main` (`git fetch origin main && git checkout -B claude/admiring-fermi-vysbwv origin/main`) and open a new PR.
- **Session:** `GS PR#4/ascii-loader`
- **Also cloned (read-only, shallow):** `gwincode/gwin-claude-agent-pipeline-kit` at `/home/user/gwincode/gwin-claude-agent-pipeline-kit` (HEAD `2201746`, `main`). This session cannot push to it. Nothing has been changed there.

## What's in the repo

| Area | Item | Status |
| --- | --- | --- |
| `scripts/` | `ascii-loader.sh` / `.ps1`: command line for the loader (`--demo`, `--demo-fail`, `STEPS_FILE`) | Done. Thin wrappers over the library |
| `scripts/` | `ascii-loader-lib.sh` / `.ps1`: the loader as a library (`loader_init` / `loader_step` / `loader_done`; `Initialize-Loader` / `Invoke-LoaderStep` / `Invoke-LoaderBlock` / `Complete-Loader`) | Done. Reviewed and hardened (see below) |
| `scripts/` | `install.sh` / `install.ps1`: link skills, agents, commands; install the token status line; `--loader` / `-Loader` for the ASCII view | Done. Plain output unchanged (diffed against a saved baseline) |
| `plugins/cc-token-statusline/` | Vendored from Alfafis/cc-token-statusline v0.4.5 (MIT). Only the status line scripts, plus `LICENSE` | Done |
| `HANDOFF.md` | This file | Kept up to date each prompt |

## Decisions

- **Statusline is on by default for `~/.claude`.** Opt out with `--no-statusline` / `-NoStatusline`. Skipped for `--target`, because a status line is a personal setting.
- **The plugin is vendored, not fetched at install time.** Installs stay offline and reproducible. Trade-off: updates are manual. To refresh, copy the newer `scripts/` and `.claude-plugin/plugin.json` from upstream and bump the version note in `plugins/README.md`.
- **Only the status line is kept** from the plugin. Its hooks and slash commands are not installed by this repo's installer.
- **PowerShell uses `py -3` before `python`.** A bare `python` can be a Microsoft Store stub that prints an ad.
- **`--loader` is opt-in.** Plain output stays the default, so logs and CI keep working. Off a terminal, `--loader` prints plain lines too.
- **The loader is a sourceable library**, so installers can run their own shell functions as steps. Shell steps run in a background subshell (animated). PowerShell steps that are external processes are animated; in-process script blocks run synchronously (a block cannot run in the background in the same session), which is fine for quick link operations.
- **Exit code 10 means "skipped"** in a loader step, shown as `[SKIP]` and counted as success (for example, a conflicting file left alone without `--force`).

## Loader review: what was found and fixed

Each was reproduced before fixing and re-tested after.

- Ctrl-C / SIGTERM did not exit, so an interrupt was reported as a failed step, left the child running, and exited 1. Now stops the step and its descendants, restores the cursor, exits 130.
- Temp log folders leaked on success. Now removed unless a step failed (the folder is then named in the summary).
- A steps-file line without ` | ` was executed as a command. Now every line is validated before anything runs.
- A long label wrapped and corrupted the display. Everything drawn is now cut to the terminal width.
- Result-line width was off by a few columns at narrow widths. Fixed.
- PowerShell: a one-line note collapsed to its last character (a function returning one item unrolls to a string). Fixed with `@()`.
- PowerShell: `$Host.UI.RawUI.WindowSize` reported a stale 80 on a pseudo-terminal. Now uses `[Console]::WindowWidth` first.
- PowerShell: `-WhatIf` leaked into the loader's own bookkeeping and stopped the status line step from running. Fixed with `-WhatIf:$false` on the library's cmdlets.
- `install.sh --help` printed code lines (my own earlier line-count slip). Now prints exactly the header comment.
- Hardening, not a confirmed bug: step stdin is closed; `NO_COLOR` and `TERM=dumb` are respected; fractional `sleep` falls back to `sleep 1`.

## Open items

- **Verify on Windows** (PowerShell 7 and Windows Terminal): `scripts\ascii-loader.ps1 -Demo`, `scripts\install.ps1 -WhatIf`, then `scripts\install.ps1 -Loader`. The PowerShell code is tested under `pwsh` on Linux only. The link loop uses junctions, which are Windows-only, so it was exercised with `-Copy` instead.
- A stray `/steps.txt` exists at the filesystem root from an early test command. It is outside the repo. The user should delete it with `rm /steps.txt` (the safety check blocked me from doing it).
- Decide whether the status line should also be offered by `INSTALL-PROMPT.md` (per-project install). Currently personal-only.
- The PowerShell interrupt path (Ctrl-C) was tested with SIGINT and restores the cursor and leaves no processes, but its exit code was not observed.
- Shell interrupt handling needs `pgrep` to stop grandchildren; without it only the step itself is stopped.

## Log

- **Prompt 1:** Built the ASCII loader (sh + ps1), tested both, committed, pushed, opened draft PR #4, subscribed to PR activity.
- **Prompt 2:** Watched PR #4 events. CI green, nothing to act on.
- **Prompt 3:** Created this handoff file. Installed the `cc-token-statusline` badge into the sandbox `~/.claude`. Vendored it into `plugins/`. Wired it into `install.sh` and `install.ps1` (default on, opt-out flag, personal target only). Documented it.
- **Prompt 4:** "continue" after switching the session model. State check only; added the loader-in-installers follow-up to Open items.
- **Prompt 5:** Added `--loader` / `-Loader` to both installers. Reviewed the loader code against real probes, fixed nine issues (listed above), split it into a library plus thin command-line wrappers, and verified plain-mode installer output is unchanged against saved baselines.
- **Prompt 6 (mid-turn):** Cloned `gwincode/gwin-claude-agent-pipeline-kit` read-only into `/home/user/gwincode/`. Also cleaned up four of my own test processes that a test-harness mistake had left stopped.
- **Prompt 7:** User marked PR #4 ready for review, then asked to merge it. CI was green and the PR mergeable with no review threads. Updated this file (PR state, next-change note) and merged with a merge commit, matching the repo's history.
