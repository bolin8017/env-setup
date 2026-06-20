# Global Claude Code Guidelines

## Communication
- Always respond in Traditional Chinese (繁體中文)
- Code, commit messages, PR titles/bodies, and inline comments remain in English

## Working approach — before writing code
- **Surface assumptions, don't bury them.** Before non-trivial work, state
  assumptions and tradeoffs. If multiple interpretations exist, present them —
  don't silently pick one. If something is unclear, ask before implementing.
- **Simplicity first (YAGNI).** Write the minimum that solves the stated
  problem. No speculative features, no abstractions for single-use code, no
  config knobs nobody asked for. If a senior engineer would call it
  overcomplicated, simplify.
- **Surgical changes.** Every changed line should trace to the request. Don't
  refactor or reformat adjacent code that isn't broken; match existing style
  even if you'd do it differently. Remove only the symbols your own change
  orphaned — flag pre-existing dead code instead of deleting it.
- Goal/verification discipline is already covered by TDD + verification skills;
  not repeated here.

## Hard rules — never do these without an explicit user request
- Do NOT use `--no-verify` to bypass pre-commit / commit-msg hooks
- Do NOT `--amend` a commit that has already been pushed to a shared branch
- Do NOT `git push --force`; if a force update is truly needed, use `--force-with-lease` and ask first
- Do NOT stage or commit files containing secrets: `.env`, `*.pem`, `credentials.json`, anything matching `*_token*` / `*_secret*` / `*_key*`
- Do NOT add a `Co-Authored-By: Claude` trailer to commits
- Do NOT push directly to `main` / `master` — always open a PR

## Git Conventions

Follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/). Full
spec, examples, industry references, and PR sizing rules live in
@~/.claude/rules/conventional-commits.md.

**TL;DR:**
- Format: `<type>(<scope>): <description>` — lowercase, imperative, no period
- Subject: target ≤ 50 chars, hard cap 72 chars (Tim Pope 50/72 rule)
- Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`
- Body explains **why**, not what — the diff already shows what
- Breaking changes: `feat!:` prefix or `BREAKING CHANGE:` footer
- One logical change per commit; each commit should leave the tree green if at all possible (atomic commits)
- For non-trivial commits, prefer the `/commit-commands:commit` slash command

## GitHub workflow
- Branch naming: `<type>/<short-kebab-description>` — e.g., `feat/add-auth`, `fix/parser-empty-input`
- Squash merge by default; the squashed subject MUST be the PR title, and the PR title itself MUST follow Conventional Commits
- Delete branch after merge

## Pre-Commit self-check
Before drafting any commit message, verify:
- Read `git diff --cached` (not just `git status`) — know exactly what's staged
- No accidentally-staged files (build artifacts, IDE configs, secrets)
- If linter / tests are configured for the repo, run them
- Subject answers: "If applied, this commit will ___"
- `CLAUDE.md` / `README.md` updated if the change affects architecture, commands, or public-facing behavior
