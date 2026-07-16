# configs/claude — the Claude Code harness

Source of truth for the personal, cross-machine Claude Code setup. Module 08
(`08-claude-code.sh` / `08-ClaudeCode.ps1`) deploys these assets on every
machine; uninstall removes only pristine copies (user-edited files are always
preserved by byte-compare). This README is repo documentation — it is NOT
deployed.

## Deployment map

| Source | Destination | Config flag | Semantics |
|---|---|---|---|
| `CLAUDE.md` | `~/.claude/CLAUDE.md` | `claude_code.sync_global_md` | copy (overwrite-protected) |
| `rules/*.md` | `~/.claude/rules/` | `claude_code.sync_rules` | additive per-file copy |
| `commands/*.md` | `~/.claude/commands/` | `claude_code.sync_commands` | additive per-file copy |
| `agents/*.md` | `~/.claude/agents/` | `claude_code.sync_agents` | additive per-file copy |
| `skills/<name>/` | `~/.claude/skills/<name>/` | `claude_code.sync_skills` | additive per-dir copy |
| `settings.json` | `~/.claude/settings.json` | (whitelist) | jq/PS merge of `settings_merge_keys` only; other keys preserved |
| `mcp-servers.json` | `~/.claude.json` `mcpServers` | `claude_code.sync_mcp_servers` | merge; no-op while the source declares no servers |

"Additive" means files that exist only on the machine (user-created rules,
commands, skills) are never touched.

## Adding an asset

- **Rule** — drop `rules/<topic>.md`. No `paths:` frontmatter = loaded into
  every session at start; keep those rare and short. Prefer `paths:` scoping.
- **Command** — drop `commands/<name>.md` with frontmatter
  (`description:` required — it is the `/help` text; `argument-hint:` if it
  takes arguments).
- **Skill** — create `skills/<name>/SKILL.md` with `name:` + `description:`
  frontmatter; support files live in the same folder. Skills load on demand,
  so they cost no session context until invoked.
- **Agent** — drop `agents/<name>.md` (subagent definition).

Then re-run `./setup.sh --modules 08-claude-code` (or `./setup.ps1 -Modules
08-ClaudeCode`), or just wait for shell-startup self-update to roll it out.

## Plugin dependency patch

After installing `enabledPlugins`, module 08 runs a self-detecting workaround
for the **episodic-memory** plugin: its lockfile nests `onnxruntime-common`
under `onnxruntime-node/` instead of hoisting it, so the plugin's SessionStart
hook fails to resolve the module (`Failed with non-blocking status code:
node:internal/modules/...`). The step hoists the nested copy to top-level
`node_modules` via a symlink (Unix) / NTFS junction (Windows). It is a no-op
when the plugin is absent or already patched, and re-applies after a plugin
update regenerates the cache. Remove it once the plugin declares
`onnxruntime-common` as a direct dependency upstream.

## Guardrails

`tests/test_claude_assets.sh` + `tests/ClaudeAssets.Tests.ps1` run in CI and
check: JSON assets parse; every `settings_merge_keys` entry exists in
`settings.json`; every `enabledPlugins` entry's `@marketplace` suffix appears
in `claude_code.marketplaces` (fresh-install resolvability); commands and
skills carry frontmatter with a description; every skill dir has a `SKILL.md`.

## Context-budget conventions

- `~/.claude/rules/*.md` without `paths:` frontmatter loads in EVERY session —
  the full conventional-commits spec already costs ~90 lines per session;
  think twice before adding more unconditional rules.
- Don't `@import` a rule file from `CLAUDE.md`: rules auto-load, so an import
  duplicates the content in context.
