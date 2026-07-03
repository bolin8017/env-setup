# Claude Config Harness — Design Spec (2026-07-03)

**Status:** DRAFT — awaiting user approval (approach choice A/B/C pending; A
is drafted here as the recommendation).

## Problem

`configs/claude/` is the source of truth for the user's global Claude Code
setup, deployed to every machine by module 08 on both engines. Today it holds
three markdown files (`CLAUDE.md`, `rules/conventional-commits.md`,
`commands/init-rules.md`), an empty `agents/`, `settings.json`, and a
placeholder `mcp-servers.json`. The sync machinery is solid (idempotent,
whitelisted merges, backups), but the harness has three gaps:

1. **Mechanism:** no `~/.claude/skills/` sync — skills are the successor
   format to commands and the user's ecosystem (superpowers, worklog) is
   skill-centric. No CI validation of the claude assets: a typo'd
   `settings_merge_keys` entry, an `enabledPlugins` entry whose marketplace is
   missing from `marketplaces:`, or invalid JSON only surfaces on the next
   fresh-machine install.
2. **Content quality:** `commands/init-rules.md` has no YAML frontmatter, so
   its `/help` description is a truncated first line.
   `rules/conventional-commits.md` (127 lines) is an unconditional rule — it
   loads into context at the start of *every* session, git-related or not,
   and its TL;DR already lives in `CLAUDE.md`.
3. **Maintainability:** the harness contract (what deploys where, how to add
   a file) exists only in config.yaml comments and module code.

## Goals

- Every markdown asset carries correct frontmatter and earns its context cost.
- Adding a rule / command / skill = drop a file in `configs/claude/` and
  re-run setup (or wait for self-update), on both platforms.
- CI catches broken claude assets before they reach a machine.
- The harness is documented where a contributor will look.

## Non-goals (YAGNI)

- Hooks sync, output-styles sync, agent template library (approach C) —
  no current need; the `agents/` dir stays as-is until one appears.
- Any change to the settings-merge or MCP-merge semantics (already sound;
  known bugs in the PS twin are tracked in the 2026-07-03 review, PR batch 4).

## Design (approach A)

### A1. Content: existing files

- **`commands/init-rules.md`** — add frontmatter:
  ```yaml
  ---
  description: Analyze the project and scaffold CLAUDE.md + path-scoped .claude/rules
  argument-hint: (no arguments)
  ---
  ```
  Body unchanged (it is already high quality).
- **`rules/conventional-commits.md`** — keep as the full spec (it is the
  authoritative reference the user wants on every machine), but stop loading
  it unconditionally twice-over:
  - `CLAUDE.md` keeps the TL;DR and the pointer line; the pointer becomes a
    plain path reference, not an `@import` (avoids concatenating the full
    spec on top of the rule's own unconditional load).
  - Option (user to confirm): trim the Examples section (~40 lines) from the
    rule, since the tables already encode the same information.
- **`CLAUDE.md`** — no structural change; fix only the import-vs-rule
  double-load above.

### A2. Content: new files

- **`configs/claude/README.md`** (not deployed; repo documentation):
  deployment map (file → destination → config flag → engines), how to add a
  rule/command/skill/agent, how the settings whitelist merge works, and the
  uninstall contract (managed-file semantics).
- **Optional, user to pick:** 1–2 new commands/skills that match the user's
  actual workflow. Candidate: `/weekly-review` — aggregate the worklog inbox
  into a weekly vault summary (bridges the existing module 10 curator-vault
  design). No speculative additions beyond what the user confirms.

### A3. Mechanism: `sync_skills` (both engines)

- Source layout: `configs/claude/skills/<name>/SKILL.md` (+ optional support
  files in the same folder).
- Bash: `_sync_claude_skills` in `modules/08-claude-code.sh`, modeled on
  `_sync_claude_commands` but copying **directories** recursively via the
  dry-run/deploy wrappers (per-file `deploy_config` so user-modified files
  are still detected and preserved).
- PowerShell: `Sync-ClaudeSkills` in `modules/08-ClaudeCode.ps1`, same
  semantics via `Deploy-Config`.
- Config: `claude_code.sync_skills: true` added to `config.yaml` +
  `config.yaml.example` (documented alongside the other sync flags).
- Uninstall: both engines remove managed skill files in reverse
  (`remove_managed_file` / `Remove-ManagedFile` per file, then prune empty
  skill dirs), additive files preserved — identical contract to
  commands/rules.
- Ship one seed skill only if the user picks one in A2; otherwise the dir
  ships with `.gitkeep` like `agents/`.

### A4. Validation tests

New `tests/test_claude_assets.sh` + `tests/ClaudeAssets.Tests.ps1`
(both wired into run_all.sh / existing Pester CI lanes):

1. `settings.json` and `mcp-servers.json` parse as JSON.
2. Every `claude_code.settings_merge_keys` entry exists as a top-level key in
   `configs/claude/settings.json` (typo guard for the whitelist).
3. Every `enabledPlugins` key's `@marketplace` suffix appears in
   `claude_code.marketplaces` (fresh-install resolvability guard;
   `claude-plugins-official` counts via its `anthropics/` entry).
4. Every `commands/*.md` and `skills/*/SKILL.md` has parseable YAML
   frontmatter with a non-empty `description`.
5. Rules with `paths:` frontmatter (if any are added later) have valid glob
   lists.

### Error handling

Sync functions follow the module's existing degradation ladder: missing
source dir → warn + continue; jq/JSON preconditions unchanged. Validation
tests are pure static checks — no network, no HOME mutation (sandbox rules
from the test framework apply).

### Testing

- Unit: the two validation suites above are themselves the feature's tests.
- `test_modules.sh` / `ClaudeCode.Tests.ps1` gain a `sync_skills` deploy +
  uninstall roundtrip case (sandboxed HOME), mirroring the existing
  commands-sync cases.
- Dry-run: `setup.sh --dry-run --modules 08-claude-code` and
  `./setup.ps1 -DryRun -Modules 08-ClaudeCode` must show skill deploys
  without mutating.

## Alternatives considered

- **B — content only:** lowest risk, leaves the skills gap and zero-validation
  problem in place. Rejected as primary because the validation tests are the
  highest leverage-per-line item in the whole harness.
- **C — full platform (hooks/output-styles/agent templates):** no current
  consumer for any of it; classic YAGNI. Revisit when a real hook or agent
  need appears.

## Open questions (blocking implementation)

1. Approach confirmation: A as specced, or B/C?
2. Trim the Examples section from `conventional-commits.md`? (context savings
   vs. keeping worked examples on every machine)
3. Which, if any, new command/skill to seed (`/weekly-review` candidate)?
