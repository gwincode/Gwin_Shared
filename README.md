# Gwin_Shared

Central shared repository for AI coding tool configuration: instructions, scripts, plugins, hooks, skills, agents, commands, and MCP configs. Tool-agnostic where possible; tool-specific pieces are labeled.

## Layout

| Folder | What goes here |
| --- | --- |
| [`instructions/`](instructions/) | Shared rules and prompts (global coding standards, per-tool instruction files such as `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `copilot-instructions.md`). |
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

## Using it

Clone once, then link or copy what you need into each tool's config location, for example:

- Claude Code: `~/.claude/skills/`, `~/.claude/agents/`, `~/.claude/commands/`, `~/.claude/settings.json` (hooks)
- Project-level: `<repo>/.claude/`, `<repo>/AGENTS.md`, `<repo>/.github/copilot-instructions.md`
