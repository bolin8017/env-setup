# Laptop Gaps: Output Styles, Git Defaults, WT Font Size — Design Spec (2026-08-20)

**Status:** APPROVED 2026-08-20 by the user (three of six candidates from a
laptop audit; the corporate-CA, glab and Windows build-tools candidates were
declined as company-specific).

## Problem

An audit of a Windows laptop that has run env-setup since 2026-06 found
configuration the user maintains by hand because the repo has no slot for it:

1. `~/.claude/output-styles/tw-native.md` — the authoritative tone rules that
   `~/.claude/CLAUDE.md` points at — exists only on that machine. The three
   `claude-as` profile dirs do not have it, and the deployed `CLAUDE.md` is 53
   lines ahead of `configs/claude/CLAUDE.md`; the next module-08 run would
   overwrite it (backup aside). The 2026-07-03 harness spec listed
   output-styles sync as a non-goal because nothing needed syncing then.
2. Two git defaults set by hand: `rerere.enabled=true` and a global ignore
   entry `**/.claude/settings.local.json` (Claude Code's per-machine settings
   file, which otherwise shows up as untracked in every repo). The `core.git`
   comment in `config.yaml` promises "git defaults (user, aliases, delta
   pager)" that neither engine implements.
3. Windows Terminal `profiles.defaults.font.size` set to 14 by hand;
   `Merge-WtSettings` manages only `font.face`.

## Goals

- Output styles deploy like rules/commands/agents: drop a file in
  `configs/claude/output-styles/`, re-run setup, it lands in `~/.claude` and
  every declared profile on both engines; `outputStyle` is selected through
  the existing whitelisted settings merge.
- `core.git` sets exactly the two defaults above, idempotently, and uninstall
  reverts only what setup set.
- `windows.windows_terminal_font_size` manages `font.size` the way
  `font.face` is managed today.
- Nothing company-specific enters the (public) repo: the vendored tone files
  keep every rule but swap project-derived examples for neutral ones.

## Non-goals

- Git identity / `includeIf` splits (01-Core states it configures no identity;
  unchanged), aliases, delta.
- VS Code settings (a new managed target; declined).
- Merging `outputStyle` into profile dirs' `settings.json` — the settings
  merge is deliberately per-profile manual; a profile selects the style once
  with `/output-style tw-native`.

## Design

### 1. Output styles

- `configs/claude/output-styles/tw-native.md` (+ neutralised examples) and
  the updated `configs/claude/CLAUDE.md` (same neutralisation for its two
  project examples).
- Flag `claude_code.sync_output_styles` (default true). Unix:
  `_sync_claude_output_styles` mirrors `_sync_claude_rules`; Windows:
  `Sync-ClaudeDir -SubDir 'output-styles'`. Both join the single asset list
  (`_sync_claude_assets` / `Sync-ClaudeAssets`) so profiles get it.
- Uninstall: `output-styles` joins the per-file `remove_managed_file` /
  `Remove-ManagedFile` loops (pristine copies only).
- `configs/claude/settings.json` gains `"outputStyle": "tw-native"`;
  `settings_merge_keys` gains `outputStyle`.
- Tests: frontmatter guardrails (`name` + `description`) for
  `output-styles/*.md` in both asset test files; dispatch cases in
  `ClaudeCode.Tests.ps1` / `test_modules.sh`; sync+uninstall roundtrip in
  `test_uninstall.sh`.
- Docs: `config.yaml` mapping comment + flag, `configs/claude/README.md`
  table + "Adding an asset", project `CLAUDE.md` tree.

### 2. Git defaults (`core.git`, both engines)

- Global ignore: resolve the file git reads — `core.excludesFile` if set,
  else `$XDG_CONFIG_HOME/git/ignore`, else `~/.config/git/ignore` — and
  append a marker-delimited block:
  ```
  # >>> env-setup managed >>>
  **/.claude/settings.local.json
  # <<< env-setup managed <<<
  ```
  Idempotent (block present → skip). Uninstall strips the block
  (`strip_block_from_file` on Unix; a PowerShell equivalent added to
  `lib/Uninstall.psm1`).
- `rerere.enabled`: set to `true` only when unset; record
  `~/.env-setup/.git-rerere-set`; uninstall unsets only when the marker
  exists (same pattern as `.claude-bin-path-added`).
- `config.yaml` / `.example` comment corrected; README table row updated.
- Tests: sandboxed `HOME` + `GIT_CONFIG_GLOBAL`; run twice → one block;
  pre-set rerere untouched; uninstall removes block and unsets only marked
  rerere.

### 3. Windows Terminal font size

- `Merge-WtSettings -FontSize <int>`; 0/omitted leaves `font.size` alone.
- `windows.windows_terminal_font_size: 14`, flat sibling key (precedent:
  `windows_terminal_default_profile`), gated by `windows.windows_terminal`.
- Tests in `WindowsTerminal.Tests.ps1` (sets, preserves, omits) and
  `Shell.Tests.ps1` (config wiring).

## Delivery

Three PRs in this order (each: branch → PR → CI green → squash-merge):
`feat(claude-code)` output styles (carries this spec), `feat(core)` git
defaults, `feat(windows)` WT font size. Then deploy on the laptop with
`setup.ps1 -Modules 01-Core,06-Shell,08-ClaudeCode` after copying the
machine's `config.local.yaml` into the dev checkout.
