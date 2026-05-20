# Conventional Commits — Full Specification

Authoritative references — verify against these if uncertain:

- [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) — the spec this rule is based on
- [Angular commit message guidelines](https://github.com/angular/angular/blob/main/contributing-docs/commit-message-guidelines.md) — where Conventional Commits originated
- [Linux kernel — SubmittingPatches: Describe your changes](https://www.kernel.org/doc/html/latest/process/submitting-patches.html#describe-your-changes) — atomic commit principles
- [Tim Pope — A note about Git commit messages](https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html) — origin of the 50/72 rule
- [Google eng-practices — CL descriptions](https://google.github.io/eng-practices/review/developer/cl-descriptions.html) — small CL principle and "WHY not WHAT"

## Format

```
<type>[optional scope][optional !]: <description>

[optional body]

[optional footer(s)]
```

## Types

| Type | When to use | SemVer bump |
|---|---|---|
| `feat` | New user-facing feature | minor |
| `fix` | Bug fix | patch |
| `docs` | Documentation only | — |
| `style` | Formatting, whitespace — no logic change | — |
| `refactor` | Code change that's neither a fix nor a feature | — |
| `perf` | Performance improvement | — |
| `test` | Adding or fixing tests | — |
| `build` | Build system or dependencies (npm, docker, …) | — |
| `ci` | CI/CD configuration (GitHub Actions, …) | — |
| `chore` | Routine maintenance, tooling, misc | — |
| `revert` | Reverts a previous commit (body: `Reverts: <sha>`) | — |

## Subject line rules

The industry-standard **50/72 rule** (Tim Pope, 2008):

- **Target ≤ 50 chars** — GitHub truncates the subject display at column 50
- **Hard cap 72 chars** — git's own display tools wrap there
- **Imperative mood**: `add login`, not `added login` / `adds login` — answer "If applied, this commit will ___"
- **Lowercase type and description**, no trailing period
- **One logical change per commit** (Linux kernel "atomic commit" principle) — each commit should leave the tree in a green / buildable state if at all possible. This makes `git bisect` actually useful.

## Scope (optional but encouraged)

- Lowercase noun in parentheses naming the affected area: `feat(auth): …`, `fix(parser): …`
- Pick from a small, stable set per project (package name, module, feature area)
- Omit if the change is cross-cutting or the description is already clear

## Body (strongly recommended for non-trivial commits)

- Blank line between subject and body
- **Explain WHY, not WHAT** — the diff already shows what changed (Google eng-practices)
- Cover: the problem being solved, why this approach was chosen, any tradeoffs
- Wrap at ~72 chars
- Skip the body only for truly obvious changes (typo fix, dependency bump, one-line doc tweak)

## Footer

- Blank line between body and footer(s)
- Issue references: `Closes #123`, `Refs #456`, `Fixes #789`
- Breaking changes: `BREAKING CHANGE: <description>` (MUST be uppercase)
- Token format: hyphens not spaces (`Reviewed-by:`, `Co-authored-by:`, `Reported-by:`)

## Breaking changes — two equivalent forms

1. `!` before colon: `feat!: drop support for Node 18`
2. Footer form: normal type then `BREAKING CHANGE: drop support for Node 18`

Either bumps the **major** version under semantic versioning.

## PR / CL sizing (from Google eng-practices)

- **~100 lines is comfortable; ~400 lines requires extensive review; ~1000 lines is usually too large**
- One PR = **one concern** — don't bundle unrelated changes
- **Keep together**: code + its tests; small incidental cleanups (rename, typo) alongside a feature/fix
- **Keep separate**: refactors vs. features or bug fixes; large test-framework additions; code vs. the config that uses it
- Err on the side of too small rather than too large

## Examples

### Good — with body

```
feat(docker): mount host project dir and switch to HTTPS git auth

Previously the Docker run mode required either copying the repo into
the image (broke incremental runs) or mounting ~/.ssh read-write
(security risk, flaky under WSL agent forwarding).

HTTPS + PAT reuses the existing GITHUB_TOKEN from .env, so no new
secret surface. Tradeoff: PAT now needs `repo` scope instead of
`public_repo`. Documented in .env.example.

Closes #12
```

### Good — trivial change, body omitted

```
fix: typo in README installation section
```

### Good — breaking change

```
feat(api)!: drop /v1 endpoints

The /v1 API has been deprecated since 2025-06. All active clients
have migrated to /v2 based on access logs from the past 30 days.

BREAKING CHANGE: /api/v1/* is removed. Clients must use /api/v2/*.
```

### Bad — reasons noted

| Bad | Why |
|---|---|
| `fix: bug` | No information |
| `feat: stuff` | Not descriptive |
| `Fix: Add login` | Capital type, capital description, wrong verb |
| `feat: added new login feature.` | Past tense, trailing period |
| `update files` | No type prefix |
