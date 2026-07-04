---
name: repo-optimize
description: "Use when a repo needs a systematic optimization or health pass and you don't know where to start — \"this project probably has issues\", an inherited or legacy codebase, a pre-release audit, or recurring mystery bugs. Args: [quick|deep] [report|fix], default \"deep report\"."
---

Comprehensive repo review that ends in verified findings, a severity-ranked
roadmap, and (only when asked) a disciplined fix loop. Nothing enters the
report unverified; nothing gets fixed without a red test; nothing merges here.

## Modes

`$ARGUMENTS = [quick|deep] [report|fix]` — default `deep report`. Treat
unrecognized arguments as a typo: confirm with the user instead of guessing.

- `quick`: one pass over the riskiest subsystem only, dimensions 1–3.
  Riskiest = handles user data, money, auth, or external input; recent-churn
  areas rank above dormant ones.
- `deep`: one focused pass per subsystem, all applicable dimensions.
- `report`: stop after report + roadmap and wait for the user.
- `fix`: after the report is written, continue into the fix loop (the user
  opted in at invocation).

## Phase 0 — Detect (before judging anything)

Inventory the repo: languages/runtimes, platform/engine variants, and the
subsystem map — subsystems are the repo's own top-level units (packages,
apps, modules; follow the maintainers' directory structure). Critically:
record the exact build, test, and lint commands (from README, CI workflows,
Makefile/package scripts) — the fix loop depends on them. Note any existing
review-doc convention. No tests or CI? That is finding #1 and the first
roadmap item: later fixes need somewhere to put red tests.

## Phase 1 — Review

Stack-agnostic dimensions, instantiated against the detected stack:

1. Correctness & error handling — false success, swallowed errors, exit codes
2. Config & docs drift — documented knobs no code reads, stale docs,
   defaults that break the documented workflow
3. Data safety — destructive ops, backup/restore honesty, uninstall/rollback
4. Cross-platform / multi-engine parity
5. Test quality — tests that cannot fail, mock-only coverage, gaps at
   past-bug sites
6. CI & tooling hygiene
7. Security basics — committed secrets, injection, permissions

Run passes per the mode (parallel subagents per subsystem when available,
sequential otherwise). A candidate finding needs file:line plus a concrete
failure scenario ("inputs/state → wrong outcome") — not vibes.

## Phase 2 — Verify (gate before the report)

For every candidate: re-read the code at the cited lines and try to refute
it. Reproduce empirically when feasible — in a temp dir or sandbox copy,
never against live user data; mark reproduced findings `[tested]`.
Refuted → drop. Real-but-unproven → keep, severity capped at M, with a note
on what would confirm it. Security-class findings additionally get a
`security` tag and sort first within their severity band. Nothing
unverified enters the report.

## Phase 3 — Report + roadmap

Write `docs/reviews/YYYY-MM-DD-comprehensive-review.md` (follow the repo's
own review-doc convention instead if one exists):

- Cross-cutting themes first.
- Per-subsystem findings: ID (`area-N`), severity — **H** user-visible
  breakage or data loss on realistic input / **M** silent misbehavior,
  broken contract, parity divergence / **L** edge case or hygiene —
  file:line, failure scenario, fix direction, `[tested]` where reproduced.
- Roadmap: findings grouped into batches in severity order; one batch = one
  concern = one future PR. Split any batch that would exceed roughly 400
  changed lines. Prefer batches independent of each other.
- A dimension with no findings gets one line saying so — do not pad.

Commit the report on a branch and open a PR (the report follows repo
discipline too). In `report` mode STOP here: present the roadmap and wait
for approval — any explicit user go-ahead counts (a reply, or them merging
the report PR).

## Phase 4 — Fix loop (`fix` mode, or after roadmap approval)

Per roadmap batch, severity first:

1. Branch `<type>/<short-kebab>` from up-to-date main. If a batch depends on
   an earlier, still-unmerged batch, work on independent batches first and
   start the dependent one only after the user merges its prerequisite
   (when only dependent batches remain, report status and pause).
2. Red test first reproducing the finding — watch it fail for the right
   reason. Two scoped exceptions: the test-harness batch in a previously
   untested repo is the enabler and cannot test-first itself; and a batch
   with no testable runtime behavior (docs-only, CI config) is verified by
   its artifact's own check instead — the drifted claim now matches
   reality, the workflow lints and runs green. Every other batch
   tests-first, no exceptions.
3. Minimal fix; full suite + lint green locally.
4. One concern per PR. The PR body quotes the finding (ID + scenario) so it
   stands alone even before the report PR merges; wait for CI green.
5. PR shows merge conflicts → merge main *into the branch* (this is not
   merging the PR), re-run tests, push, wait for CI again.

## Hard rules

- No finding without verified file:line evidence — a plausible-sounding bug
  you did not re-read the code for is a hallucination until proven real.
- Never merge PRs and never push to main/master from this skill — even
  where a standing merge authorization exists. Merging is the user's
  decision, made outside this skill.
- Never run destructive commands against user data while reviewing.
- Report before fixes: enter the fix loop only in `fix` mode or after the
  user approves the roadmap.
