---
name: ship
description: "Use when the user wants completed work taken to merged main — e.g. 「幫我 ship」、「送出去」、「幫我 squash-merge」、「一樣幫我 merge」、「merge 後部署」 — on GitHub or GitLab repos. Args: [PR/MR number if one already exists]."
---

Take the working tree (or an existing PR/MR) all the way to: merged into
main, local main synced, branch cleaned up, post-ship deploy done. The
user's global git conventions (Conventional Commits, branch naming, squash
subject = PR title, hard rules) already govern HOW each step is done — this
skill supplies the loop and the repo-specific tail, not the rules.

## Before the loop

- Platform: `git remote get-url origin` — github.com → `gh`, GitLab host →
  `glab`.
- Dirty tree while on main → cut `<type>/<kebab>` branch first. Already on
  a feature branch → stay on it.
- Arg names an existing PR/MR (`#123` / `!34`) → skip straight to step 3.

## The loop

1. Stage exactly the intended files; run the repo's configured lint/tests
   (pre-commit self-check). Commit, `git push -u`.
2. Open the PR/MR — title = the future squash subject:
   - `gh pr create --title <t> --body <b>`
   - `glab mr create --title <t> --description <b>`
3. Watch CI to a verdict: `gh pr checks --watch` / `glab ci status --live`.
   Red → read the failing job's log, fix, push, re-watch. Never merge red,
   never bypass hooks. After 2 failed fix attempts, stop and report state.
4. Merge — authorization gate: standing authorization for THIS repo in
   memory → merge without asking; otherwise report CI green and wait for
   the user's go.
   - `gh pr merge --squash --delete-branch`
   - `glab mr merge --squash --remove-source-branch --yes`
5. Sync and clean: `git checkout main && git pull --ff-only`; delete the
   local branch if it survived; `git worktree remove <path>` for any
   worktree the branch used.
6. Post-ship deploy — only where documented:
   - env-setup: re-run the setup module covering the merged paths — e.g.
     `configs/claude/**` → `./setup.ps1 -Modules 08-ClaudeCode` (Windows) /
     `bash setup.sh --modules 08-claude-code` (Unix) — then spot-check one
     deployed file actually changed.
   - Other repos: only if the project CLAUDE.md documents a post-merge
     step; otherwise skip.
7. Report: PR/MR number, squash subject, CI result, what was deployed and
   how it was verified.

## Batches

Several independent changes → one concern per PR, shipped sequentially:
finish step 5 (main synced) before cutting the next branch. A shared
deploy (step 6) may run once after the last merge.
