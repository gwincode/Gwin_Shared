# Gwin_Shared

Central shared repository for AI coding tool configuration: instructions, scripts, plugins, hooks, skills, agents, commands, and MCP configs. Tool-agnostic where possible; tool-specific pieces are labeled.

## Layout

| Folder | What goes here |
| --- | --- |
| [`instructions/`](instructions/) | The shared rules every project follows ([`RULES.md`](instructions/RULES.md) is the index). Installed into projects with `gwinrules`. |
| [`skills/`](skills/) | Agent skills — one folder per skill, each with a `SKILL.md`. |
| [`plugins/`](plugins/) | Plugins (e.g. Claude Code plugins with `.claude-plugin/plugin.json`). |
| [`hooks/`](hooks/) | Hook scripts and example `settings.json` hook snippets. |
| [`agents/`](agents/) | Subagent definitions (`*.md` with frontmatter). |
| [`commands/`](commands/) | Slash commands (`*.md`). |
| [`mcp/`](mcp/) | MCP server configs (`.mcp.json` examples) — **no secrets**. |
| [`scripts/`](scripts/) | Helper scripts (install/sync, setup, utilities). |

## Conventions

- **No secrets.** Use environment variables or placeholders like `${GITHUB_TOKEN}`. Keep local overrides in `*.local.*` files (git-ignored).
- One item per folder (e.g. `skills/my-skill/SKILL.md`) with a short README or frontmatter description.
- Note which tools an item supports (Claude Code, Cursor, Copilot, Codex, …) at the top of its file.
- Scripts should ship both PowerShell (`.ps1`) and POSIX (`.sh`) versions where practical.

## Share it: one-shot install

To set up someone else's project (shared rules and the agent pipeline in one pass), give them
[`INSTALL-PROMPT.md`](INSTALL-PROMPT.md). They paste the part between its two lines into Claude Code in their
project. In a cloud session, check that `git clone` of Gwin_Shared and the kit works before step 3. If it
fails, stop and show the error. This repo and the pipeline kit it installs,
[gwin-claude-agent-pipeline-kit](https://github.com/gwincode/gwin-claude-agent-pipeline-kit), are both public.

## Which path to use

- **A project (rules and agent pipeline):** use [`INSTALL-PROMPT.md`](INSTALL-PROMPT.md). It runs `gwinrules`,
  then installs the pipeline kit.
- **Only the shared rules in a project:** run `gwinrules` (next section).
- **Your own machine:** run `install.sh` / `install.ps1`. They only link personal skills, agents and
  commands into `~/.claude`. They do not install rules or the pipeline.

## Shared rules in a project: `gwinrules`

Run this inside each project to copy the rules into that project's own repo, so local sessions, cloud
sessions and other machines all read the same thing:

```powershell
cd C:\code\MyProject
C:\code\Gwin_Shared\scripts\gwinrules.ps1          # preview
C:\code\Gwin_Shared\scripts\gwinrules.ps1 -Apply   # write
```

```bash
/path/to/Gwin_Shared/scripts/gwinrules.sh [--project DIR] [--apply] [--force] [--uninstall]
```

It copies `instructions/*.md` into `<project>/.claude/gwin-shared/`, stamping each copy with the
Gwin_Shared commit and a content hash, and adds one marked block to the project's `CLAUDE.md` that imports
`.claude/gwin-shared/RULES.md`. It previews until you pass `-Apply`, never commits, and leaves hand-edited
copies alone unless you pass `-Force`. Commit the result in the project. Re-run it after the rules change.

If the folder is not a git repo, or the repo has no GitHub remote, it warns **LOCAL ONLY**: the rules then
work only on this computer, because Claude cloud sessions and other computers get them from GitHub. It
refuses to install into your home folder or a drive root.

Check that every rule can fire with `gwinrules --check` (`-Check` in PowerShell). It writes nothing. It reports
PASS, FIX, BLOCKED or ASK for each thing the rules depend on: copies loaded and committed, a staging branch and
its protection, `HANDOFF.md`, `.env` protection, release notes, `gh`, and model pins. It exits 1 if anything is
not PASS. `--staging NAME` sets the staging branch name.

Edit rules here, never in a project's copy. A project overrides a shared rule only by saying so explicitly in
its own `CLAUDE.md`. Pipeline agents (`po`, `code`, `qa`, `reviewer`) come from
[gwin-claude-agent-pipeline-kit](https://github.com/gwincode/gwin-claude-agent-pipeline-kit), installed and
committed per project.

## Personal extras on this machine: `install`

Clone once, then run the installer to link `skills/`, `agents/` and `commands/` into Claude Code (default target `~/.claude`). Because items are linked, a `git pull` updates them everywhere.

```powershell
./scripts/install.ps1 -WhatIf                        # preview
./scripts/install.ps1                                # install into ~/.claude
./scripts/install.ps1 -Target C:\code\Proj\.claude   # install into a project
./scripts/install.ps1 -Uninstall                     # remove what it linked
```

```bash
scripts/install.sh --dry-run
scripts/install.sh [--target DIR] [--copy] [--force] [--uninstall]
```

It never touches existing items it didn't link unless you pass `-Force` / `--force`. On Windows, folders are linked as junctions (no admin needed); file symlinks need Developer Mode, and without it files are copied (refresh copies with `-Force`).

Other tools' config locations, for manual linking or copying:

- Claude Code: `~/.claude/skills/`, `~/.claude/agents/`, `~/.claude/commands/`, `~/.claude/settings.json` (hooks)
- Project-level: `<repo>/.claude/`, `<repo>/AGENTS.md`, `<repo>/.github/copilot-instructions.md`
