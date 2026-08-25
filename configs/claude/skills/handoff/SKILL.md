---
name: handoff
description: "Use when the user says the current session should wrap up and a NEW session will continue the work — e.g. 「這個 session 收尾，下個 session 繼續做 X」. Writes the baton the next session's /pickup reads. Args: --name <line> (required; derived from the work if omitted) [next-session tasks...]."
---

Wrap up the current session and write a machine-executable baton for the
next one. The baton is a file, not chat prose — a fresh session cannot read
this conversation.

## Where batons live

`<auto-memory dir>/../handoffs/` — derive it from the auto-memory directory
listed in your system prompt (its sibling; e.g.
`~/.claude/projects/<project>/handoffs/`). Create it if missing. If the
session has no auto-memory directory, fall back to `.claude/handoffs/` in
the project and warn that it may need a .gitignore entry.

File naming: **always** `handoff-<line>.md` — every baton carries a line
name, so parallel task threads never clobber each other and a later
`/pickup` can be aimed at exactly one of them. `--name <line>` supplies it
(letters/digits/-/_ only — an invalid name is not sanitized silently: ask
the user for a valid one). No `--name` given? Derive a short kebab slug
from the work itself — the branch, the issue number, the main task (e.g.
`auth-refactor-142`) — and state the name you chose in your reply before
writing the file. Never write a bare `handoff.md`: an unnamed baton is
exactly what makes the next session's `/pickup` take the wrong one.

## Steps

1. **Wrap-up check — report, do not act.** Run and summarize: `git status`
   (uncommitted/untracked), unpushed commits (`git log @{u}..` per local
   branch), open PRs and their CI state, still-running background tasks.
   A check the environment cannot answer (no gh, offline) is skipped and
   said so — never guessed. Surface what the user might be about to lose;
   let them decide. Do not commit, merge, or kill anything on your own.
2. **Distill the baton** into the file:

   ```markdown
   # Handoff — <YYYY-MM-DD> <repo> line: <name>
   ## 本 session 完成（含驗證狀態）
   - <what merged/landed, how it was verified>
   ## 進行中（精確狀態）
   - <branch, failing test, exact next micro-step>
   ## 下個 session 的任務
   - <the user's stated tasks, plus unfinished task-list items>
   ## 已做的決策（不要重新討論）
   - <choice + one-line why; include REJECTED hypotheses/approaches>
   ## 指標
   - <PR #s, file:line pointers, commands that matter>
   ```

   The "已做的決策" section is the highest-value part: a fresh session
   re-litigates anything not written down — record negative knowledge
   (what was ruled out) explicitly. No tasks given in the args and none
   stated by the user? Infer the open threads from the conversation and
   task list, and show the inference for confirmation before writing.
3. **Split durable from transient.** Lessons that outlive this handoff
   (project facts, machine quirks, user feedback) go to auto-memory as
   usual; the baton holds only the one-shot continuation state. Do both —
   they are different files with different lifetimes.
4. **Tell the user how to resume**: next session, type
   `/pickup --name <line>` — always with the name, never a bare `/pickup`,
   which resolves to whichever baton happens to be newest. Also print the
   fallback one-liner `請讀 <full path> 接手` in case the skill is
   unavailable there.

Never put secrets or tokens in a baton. Overwrite an existing baton of the
same line only after folding anything still relevant from it into the new
one.
