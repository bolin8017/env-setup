# Global Claude Code Guidelines

<!-- Maintainer notes. Claude Code strips block-level HTML comments before it
injects this file, so these lines cost no context.
- Every session and every subagent except the built-in Explore and Plan loads
  this file; keep it under 200 lines (tests/test_claude_assets.sh checks).
- Goal/verification discipline is covered by the TDD and verification skills;
  it is deliberately not repeated here.
- Git Conventions below carries every normative commit rule. The full spec in
  rules/conventional-commits.md is path-scoped, so it no longer loads into
  every session. Never @import it here: imports expand at launch. -->

## Communication
- Always respond in Traditional Chinese (繁體中文), written as natural Taiwan
  Mandarin — like a person from Taiwan wrote it, not a translation.
- **Full rules live in `~/.claude/output-styles/tw-native.md`** (the `tw-native`
  output style, selected globally), authoritative for word choice, banned
  metaphors, invented abbreviations, AI boilerplate, punctuation and reply
  structure. Edit tone rules there, not here.
- **Subagents load this file but never an output style**, so the baseline
  below is what travels with delegated work. Before producing more than a
  couple of paragraphs of Chinese — a report, an issue comment, a document —
  read the output style file and follow it in full. The built-in Explore and
  Plan load neither, so state the language requirement in the delegation
  prompt when their text will be quoted rather than rewritten.
- **Language-policy review of Chinese prose goes to the `tw-docs-reviewer`
  subagent** (`~/.claude/agents/tw-docs-reviewer.md`; its frontmatter pins
  `model: sonnet`, `effort: low`, so never pass the Agent tool's `model`
  parameter on that call: it beats the frontmatter). Dispatch it with
  `subagent_type: tw-docs-reviewer` for every Chinese text that will be
  published: Markdown files, reports, READMEs, MR/PR descriptions, issue
  bodies and issue comments. Write the text to a file first, review, then
  push or post; re-review after edits. English text is out of scope. An
  orchestrator passes this rule on to every subagent it spawns (user ruling
  2026-09-16). It is a wording fixer only: fact checking, if needed, is a
  separate agent at normal effort. Every other subagent keeps the session's
  default model and effort (user ruling 2026-08-26). There is no per-subagent
  switch for extended thinking; `effort: low` is the only lever, so do not
  promise "thinking off".
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
  - No invented Chinese renderings of English terms: gate, baseline and
    the like stay in English; a CLI `--flag` is 參數. Keeping the English
    word does not excuse you from explaining it the first time it appears
    in Chinese prose. File names, JSON keys, env vars and code keep the
    English words regardless.
  - A project's own term rulings (which words that project bans, and what
    to write instead) live in that project's versioned rubric, typically
    `.claude/hooks/` or `.claude/rules/`. Read it before writing Chinese
    prose in that repo. They are deliberately not listed here: this file
    and the output style both ship from a public repo, and a project-scoped
    reviewer reads the project rubric first anyway.
  - Don't borrow a term the project already gives a fixed meaning to for
    something else: say the plain thing instead. Never write 「凍結」 in
    Chinese prose (user finds the translation jarring): say
    已定案／不再改動／固定, or keep English "frozen" when quoting
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
  reverse) → ask before proceeding. Implementation-level choices (which
  library, pattern, code structure) → decide autonomously following
  mainstream conventions, then state the assumption where the reader will
  look (commit body, PR description, final summary) instead of asking first.
- **Search before building.** Before adding a dependency, designing a
  non-trivial component, or when stuck on a problem that smells already
  solved: check how mainstream open-source projects and Google's engineering
  guides handle it. Prefer a well-maintained package (actively maintained,
  widely adopted, license-compatible) over hand-rolling anything non-trivial;
  hand-roll only utilities so small and edge-case-free that a dependency
  costs more than it saves. When outside practice shaped a decision, cite the
  source in one line of the commit/PR body.
- **YAGNI governs scale.** Mainstream practice informs the approach;
  simplicity decides how much of it to adopt — the minimal subset that
  solves the stated problem. No speculative features, no abstractions for
  single-use code, no config knobs nobody asked for.
- **Surgical changes.** Every changed line should trace to the request. Don't
  refactor or reformat adjacent code that isn't broken; match existing style
  even if you'd do it differently. Remove only the symbols your own change
  orphaned — flag pre-existing dead code instead of deleting it.
- **No error is not evidence.** A signal and the fact it claims can diverge
  silently: a copy that reports success on a truncated file, a counter that
  structurally cannot see one class of I/O, a probe attached to a launcher
  process instead of the worker, a lock or reservation released while the
  resource is still in use, a restore that reports completion without
  verifying. Verify every claim that matters against an independent
  measurement (compare sizes after copying, read the value a tool prints
  rather than its exit code, sample the whole process tree, read the lock's
  owner record), and remember a check is only as strong as the assumption
  behind it; when that assumption changes, the check stays silent
  (user rulings 2026-09-16).
- **Orchestration: no idle machines, no idle agents.** When delegating to
  subagents that drive shared machines: each agent writes a STATUS line every
  5 minutes (including "waiting for X until HH:MM"), reports any failed run
  within 5 minutes instead of at batch end, and never lets a machine sit
  idle when a next step is already planned. The orchestrator patrols (a
  background loop watching STATUS freshness and machine reservations) and
  kills and re-dispatches an agent that is stuck or ignores directives.
  Aborting a batch means stopping the driver and all its child processes,
  releasing the machine reservation only after confirming its holder is
  gone, and removing any queue entry the batch left behind. Rules given to
  subagents must not contradict this file; when two rule sources conflict,
  the user-level rule wins and the agent asks (user ruling 2026-09-16).

## Hard rules — never do these without an explicit user request
- Do NOT use `--no-verify` to bypass pre-commit / commit-msg hooks
- Do NOT `--amend` a commit that has already been pushed to a shared branch
- Do NOT `git push --force`; if a force update is truly needed, use `--force-with-lease` and ask first
- Do NOT stage or commit files containing secrets: `.env`, `*.pem`, `credentials.json`, anything matching `*_token*` / `*_secret*` / `*_key*`
- Do NOT add a `Co-Authored-By: Claude` trailer to commits
- Do NOT push directly to `main` / `master` — always open a PR
- Do NOT merge an MR/PR into a protected branch, change GitLab/GitHub project
  settings (protected branches, squash defaults, merge gates, runners), tag a
  release, or promote develop into main without the user's explicit go for
  that specific action. Daily feature branches and MRs targeting develop are
  autonomous; merging them is not (user ruling 2026-09-16; three tiers:
  autonomous / needs explicit go / never)

## New repositories
- When creating a repo, read and follow "Project layout for a new repo" in
  `~/.claude/commands/init-rules.md` (user ruling 2026-09-16).

## Git Conventions

Follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/);
the list below is the whole rule set. `~/.claude/rules/conventional-commits.md`
adds the type table, examples and sources but loads by itself only for commit
tooling files (commitlint, commit and PR/MR templates): read it by path when a
case is unclear.

- `<type>(<scope>): <description>`, optional `!` before the colon; a blank
  line before the body and before the footers
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
  `ci`, `chore`, `revert` (body: `Reverts: <sha>`)
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
  too large; err small. One concern per PR. Keep together: code and its
  tests, small incidental cleanups. Keep separate: refactors vs. features or
  fixes, large test-framework additions, code vs. the config that uses it
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
