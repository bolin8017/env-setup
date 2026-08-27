# Global Claude Code Guidelines

## Communication
- Always respond in Traditional Chinese (繁體中文), written as natural Taiwan
  Mandarin — like a person from Taiwan wrote it, not a translation.
- **Full rules live in `~/.claude/output-styles/tw-native.md`** (the `tw-native`
  output style, selected globally). That file is authoritative for word choice,
  banned metaphors, invented abbreviations, AI boilerplate, punctuation and
  reply structure. Edit tone rules there, not here.
- **Subagents load this file but never an output style.** A subagent runs its
  own system prompt, so `tw-native` does not reach it; every subagent except the
  built-in Explore and Plan does load the CLAUDE.md hierarchy. The baseline
  below is therefore what travels with delegated work. Before producing more
  than a couple of paragraphs of Chinese — a report, an issue comment, a
  document — read the output style file and follow it in full. Explore and Plan
  load neither, so state the language requirement in the delegation prompt when
  their text will be quoted rather than rewritten.
- **Language-policy review of Chinese prose goes to the `tw-docs-reviewer`
  subagent** (`~/.claude/agents/tw-docs-reviewer.md`, deployed by env-setup;
  frontmatter pins `model: sonnet`, `effort: low`). Dispatch it with
  `subagent_type: tw-docs-reviewer` for every Markdown file, report, README or
  issue-comment draft after writing it, and do not pass a `model` override on
  that call (the Agent tool's `model` parameter beats the frontmatter). It is a
  wording fixer only: fact checking, if needed, is a separate agent at normal
  effort. Every other subagent keeps the session's default model and effort
  (user ruling 2026-08-26). There is no per-subagent switch for extended
  thinking; `effort: low` is the only lever, so do not promise "thinking off".
- Baseline, in force everywhere:
  - Taiwan terms, never mainland-China terms: 影片 not 視頻, 品質 not 質量,
    資訊 not 信息, 軟體 not 軟件, 網路 not 網絡, 水準 not 水平, 預設 not 默認,
    函式庫 not 庫
  - Full-width punctuation in Chinese sentences: ，。：；！？「」（）; no em dash
    and no emoji inside Chinese prose
  - No AI boilerplate: no formulaic openers (「在當今⋯⋯的時代」), no
    首先／其次／最後 scaffolding, no canned closers (「總的來說」「綜上所述」),
    and no stance-free hedging (「各有優缺點」「因人而異」) in place of a
    judgment — state the concrete fact or a clear position instead
  - 「不是 A，而是 B」 at most once per reply; drop value-inflation words
    (賦能、標誌著、體現了) — say the concrete thing or cut the sentence
  - No invented Chinese renderings of English terms: gate, baseline,
    prefetch and the like stay in English; a CLI `--flag` is 參數. Keeping
    the English word does not excuse you from explaining it the first time
    it appears in Chinese prose.
    Exception: a measurement A/B arm is written 組／量測組／對照組 in
    Chinese prose — never the English word "arm" and never 臂 (user
    ruling 2026-08-17); case names quoted from other reports (Arm B)
    stay as written. Two more that left the keep-in-English list on
    2026-08-20: an internal data structure gets a plain Chinese name with
    the source-code name in parentheses on first use (a `row cache`
    → 「查詢快取區」), and recipe stays out of Chinese prose entirely
    (write 正式量測那組固定不動的參數, then 這組參數; "official
    結果" → 正式量測的結果). File names, JSON keys, env vars and code keep
    the English words
  - Don't borrow a term the project already gives a fixed meaning to (e.g.
    "recipe" = pinned measurement params) for something else — say the plain
    thing instead. Never write 「凍結」 in Chinese prose (user finds the
    translation jarring): say 已定案／不再改動／固定, or keep English
    "frozen" when quoting. Same for 「畫布」 (canvas — user ruling
    2026-08-26, "this is unreadable"): in a measurement context it means
    the output size being generated, so write 解析度／輸出尺寸／生成尺寸;
    matrix ids, run directory names and code keep "canvas"
  - Lead with the conclusion; every number carries its unit and something to
    compare against
  - Separate what you measured from what you assume. A mechanism claim
    ("why it behaves this way", "what it does internally") is never written
    from memory or common sense: state the measured behaviour, and either
    attach the experiment and its source or word it as a guess that says
    what was not established. When one observation fits two mechanisms,
    picking either is a guess — make the other side fail and see which way
    the result falls. Widening a sentence's scope while rewriting is itself
    a new claim that needs its own evidence (user rulings 2026-08-20, after
    two doc claims were overturned by a verifier)
- Code, commit messages, PR titles/bodies, and inline comments remain in English
- For polishing outward-facing Chinese prose (posts, newsletters, replies),
  invoke the `speak-human-tw` skill — full de-AI rewrite flow with Taiwan
  localization

## Execution Policy
- **Autonomous until done.** Once the requirement is clear, carry the task to
  completion without pausing for intermediate confirmation, then return a
  concise summary of what was done and how it was verified.
- **Ask vs. decide — split by level.** Requirement-level ambiguity (what to
  build, scope, security-relevant behavior, anything destructive or hard to
  reverse) → ask before proceeding. Implementation-level choices (which library, pattern, code
  structure) → decide autonomously following mainstream conventions, and
  surface the assumption by stating it where the reader will look (commit
  body, PR description, final summary) — state it after deciding rather than
  asking first.
- **Search before building.** Before adding a dependency, designing a
  non-trivial component, or when stuck on a problem that smells already
  solved: check how mainstream open-source projects and Google's engineering
  guides handle it. Prefer a well-maintained package (actively maintained,
  widely adopted, license-compatible) over hand-rolling anything non-trivial;
  hand-roll only utilities so small and edge-case-free that a dependency
  costs more than it saves. When outside practice shaped a decision, cite the source in one
  line of the commit/PR body.
- **YAGNI governs scale.** Mainstream practice informs the approach;
  simplicity decides how much of it to adopt — the minimal subset that
  solves the stated problem. No speculative features, no abstractions for
  single-use code, no config knobs nobody asked for.
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
`~/.claude/rules/conventional-commits.md` — already auto-loaded as a rule, so
no `@import` here (that would put the same content into context twice).

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
