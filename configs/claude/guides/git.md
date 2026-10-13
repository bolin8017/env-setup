# Git: commits, branches and PRs

Split out of `~/.claude/CLAUDE.md` (2026-10-13): the full rule set behind the
core lines in its Git section. The commit-message format is enforced by
`~/.claude/hooks/check_commit_msg.py`.

## Conventions

Follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/);
the list below is the whole rule set. For examples and sources read
`~/.claude/rules/conventional-commits.md` by path (it auto-loads only with
commit tooling files).

- `<type>(<scope>): <description>`, optional `!` before the colon; a blank
  line before the body and before the footers
- Types are the spec's set (`feat` minor, `fix` patch, `docs`, `style`,
  `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert` with body
  `Reverts: <sha>`); a breaking change bumps major
- Scope: optional lowercase noun for the affected area, from a small stable
  per-project set; omit it when cross-cutting or already clear
- Subject: lowercase, imperative, no trailing period; target ≤ 50 chars, hard
  cap 72 chars (Tim Pope 50/72 rule)
- Body explains **why**, not what (the diff shows what): the problem, why
  this approach, the trade-offs. Wrap at ~72; skip it only for truly obvious
  changes
- Footers: `Closes #123`, `Refs #456`, `Fixes #789`; hyphenated tokens
  (`Reviewed-by:`). Breaking changes: `feat!:` prefix or an uppercase
  `BREAKING CHANGE:` footer
- One logical change per commit; each commit should leave the tree green if at all possible (atomic commits)
- PR size: ~100 lines comfortable, ~400 needs extensive review, ~1000 usually
  too large; err small unless the project's own rules set MR granularity.
  One concern per PR. Keep together: code and its tests, small incidental
  cleanups. Keep separate: refactors vs. features or fixes, large
  test-framework additions, code vs. the config that uses it
- For non-trivial commits, prefer the `/commit-commands:commit` slash command

## GitHub workflow
- Branch naming: `<type>/<short-kebab-description>` — e.g., `feat/add-auth`, `fix/parser-empty-input`
- Squash merge by default; the squashed subject is the PR title, so the PR title follows Conventional Commits
- Delete branch after merge

## Pre-Commit self-check
Read `git diff --cached` (no stray build artifacts, IDE configs or secrets);
run the repo's linter and tests; the subject completes "If applied, this
commit will ___"; update `CLAUDE.md` / `README.md` when the change affects
architecture, commands or public-facing behavior.
