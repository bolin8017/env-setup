Analyze the current project and set up Claude Code memory management, aligning with the official guidance at https://code.claude.com/docs/en/memory.

## Quick start: prefer `/init` for first-time setup

If the project has no `CLAUDE.md` yet, **suggest running `/init`** first — it auto-detects build/test commands and conventions. Setting `CLAUDE_CODE_NEW_INIT=1` enables the interactive multi-stage flow that also offers skills and hooks setup. This command complements `/init` by structuring path-scoped rules afterwards.

## Memory layer model

Claude Code reads `CLAUDE.md` files from four layers (broadest to most specific):

1. **Managed** (org-wide, IT-deployed) — `/etc/claude-code/CLAUDE.md` (Linux/WSL), `/Library/Application Support/ClaudeCode/CLAUDE.md` (macOS), `C:\Program Files\ClaudeCode\CLAUDE.md` (Windows)
2. **User** (cross-project personal) — `~/.claude/CLAUDE.md`, `~/.claude/rules/*.md`
3. **Project** (team-shared, version-controlled) — `./CLAUDE.md` or `./.claude/CLAUDE.md`, `./.claude/rules/*.md`
4. **Local** (per-machine personal, gitignored) — `./CLAUDE.local.md`

All discovered files are **concatenated** into context; they do not override one another. Subdirectory `CLAUDE.md` files load **lazily** when Claude reads files in that directory.

## Steps

### 1. Inspect project structure

Read to understand the codebase:

- Package files (`package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`, etc.)
- Existing `CLAUDE.md`, `AGENTS.md`, `README.md`, `.editorconfig`, linter configs
- Directory structure and file extensions
- CI/CD configuration
- `.gitignore`

### 2. Check existing setup

Report what already exists (check both project locations):

- [ ] `./CLAUDE.md` **or** `./.claude/CLAUDE.md`
- [ ] `./CLAUDE.local.md` (personal, must be in `.gitignore`)
- [ ] `./AGENTS.md` (compatibility for other agent tools)
- [ ] `./.claude/rules/` with path-specific rules
- [ ] `.gitignore` excludes `.claude/settings.local.json` and `CLAUDE.local.md`
- [ ] `@path` imports in `CLAUDE.md` for key reference files

### 3. Bootstrap or extend project `CLAUDE.md`

If absent, create at `./CLAUDE.md` (preferred) or `./.claude/CLAUDE.md`. Team-shared content goes here: architecture, build/test commands, naming conventions, common workflows.

**Target < 200 lines** (official guidance — longer files consume more context and reduce adherence).

If `AGENTS.md` already exists, do NOT duplicate it. Either:

- Create `CLAUDE.md` with `@AGENTS.md` as the first line, then append Claude-specific instructions below; OR
- Symlink: `ln -s AGENTS.md CLAUDE.md` (Linux / macOS only — Windows needs admin or developer mode)

### 4. Create or update `.claude/rules/`

For each distinct file group, create a rule file with `paths` frontmatter so it only loads when Claude touches matching files:

```yaml
---
paths:
  - "src/api/**/*.ts"
  - "tests/api/**/*.ts"
---
```

Rules should capture:

- Naming conventions actually used in the codebase (observe, don't invent)
- Code patterns and idioms found in existing files
- Linter / formatter config that's already in place
- Testing conventions
- Build and CI requirements

**Unconditional rules** (no `paths` frontmatter) load at session start with the same priority as `.claude/CLAUDE.md` — use sparingly to preserve context budget. Prefer path-scoped rules.

**Do NOT duplicate content already in `CLAUDE.md`** — rules complement it with path-specific guidance.

### 5. Update `.gitignore`

Ensure these patterns are excluded:

- `.claude/settings.local.json` (machine-local permissions)
- `CLAUDE.local.md` (personal project notes)

The `.claude/rules/` directory and `.claude/CLAUDE.md` **should be committed** — they are team-shared.

### 6. Add `@path` imports to `CLAUDE.md`

If key reference files exist (README, config examples, API docs), add `@path/to/file` imports so Claude loads them automatically:

```markdown
For project overview, see @README.md. Available commands: @package.json.
```

Notes:

- Relative paths resolve relative to the file containing the import (not the working directory)
- Maximum recursion depth: **5 hops**
- Cross-worktree shared content: import from `~` (e.g., `@~/.claude/my-shared-notes.md`)

### 7. Summary

Print a table of what was created / updated and what was already in place.

## Guidelines

- **Observe, don't invent**: extract rules from existing code patterns; don't impose new conventions
- **Be specific and verifiable**: "use 2-space indent" beats "format code properly"; "run `pnpm test` before commit" beats "test your changes"
- **Keep rules small**: each file ≤ 30 lines, one topic per file
- **Avoid duplication**: don't repeat what's in `CLAUDE.md`, `README`, or linter configs
- **Maintainer notes**: HTML comments (`<!-- ... -->`) in `CLAUDE.md` are stripped before context injection — safe place for notes that shouldn't burn tokens
- **Cross-project personal rules**: put machine-wide preferences in `~/.claude/CLAUDE.md` or `~/.claude/rules/`, not in any project repo
- **Respect existing setup**: if `CLAUDE.md` / rules already look good, say so and only suggest what's missing
