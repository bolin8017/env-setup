---
name: handoff
description: "Use when the user says the current session should wrap up and a NEW session will continue the work — e.g. 「這個 session 收尾，下個 session 繼續做 X」「這個session準備先到一個段落」. Settles open questions with the user, writes the baton the next session's /pickup reads, and updates the Obsidian notes. Args: --name <line> (required; derived from the work if omitted) [next-session tasks...]."
---

Wrap up the current session and write a machine-executable baton for the
next one. The baton is a file, not chat prose — a fresh session cannot read
this conversation. Its job is that the user never has to repeat, in the
next session, anything already said in this one.

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
   branch), open PRs/MRs and their CI state, still-running background
   tasks and subagents (what each is doing, its last STATUS time, which
   machine it holds). A check the environment cannot answer (no gh,
   offline) is skipped and said so — never guessed. Do not commit, merge,
   or kill anything on your own.
2. **Settle every open question before writing anything.** List them,
   numbered, each with your recommended answer and a one-line reason:
   - decisions still waiting for a user ruling;
   - conclusions of this session that contradict the repo, an issue, or an
     earlier baton;
   - claims made without an independent measurement (they go to the
     baton's 待驗證 list unless the user rules otherwise);
   - what to do with each still-running agent or job (let it finish, stop
     it, hand it over) and each unmerged branch from step 1;
   - the next-session tasks you inferred, if the user gave none.
   Wait for the answers; do not write the baton or the notes until every
   item is answered. Nothing to ask? Say so in one line and continue.
3. **Write the baton**:

   ```markdown
   # Handoff — <YYYY-MM-DD> <repo> line: <name>
   ## 工作方式（接手後直接照做，使用者不會再講一次）
   - <every standing instruction the user gave in this session or inherited
     from the previous baton, in the user's own words with its date: role
     and domain, orchestrator duties, model tiers, who drafts and who
     reviews documents, how Obsidian is updated, clarify-first, how
     verification is done, authorization scope (what may be merged, closed,
     posted)>
   ## Agent 管理（每個 session 都要做）
   <the block below, verbatim, plus this project's patrol script path and
   machine-reservation command if it has them>
   ## 待驗證（接手後先做）
   - <each claim not yet independently verified: what to check, how, and
     what result counts as pass>
   ## 本 session 完成（含驗證狀態）
   - <what merged/landed, how it was verified>
   ## 進行中（精確狀態）
   - <branch, running agents and jobs with their machines, exact next
     micro-step>
   ## 下個 session 的任務（照順序做）
   - <each task: goal; done-criteria and how to verify; starting point
     (file:line, branch, command); which tasks it depends on; model tier
     (haiku / sonnet / session model)>
   ## 已做的決策（不要重新討論）
   - <choice + one-line why; include REJECTED hypotheses/approaches and
     every step-2 ruling>
   ## 指標
   - <PR/MR #s, file:line pointers, commands that matter>
   ```

   Fixed block for the Agent 管理 section:

   ```markdown
   - 派出去的每個 agent 每 5 分鐘在 STATUS 寫一行；在等東西也要寫「等 X，預計 HH:MM」。
   - orchestrator 開背景巡查，每 10 分鐘看一次每個 agent 的 STATUS 和機器占用。
   - STATUS 超過 15 分鐘沒更新就 SendMessage 提醒一次；下一輪還是沒動，或同一個錯誤連續出現兩次，就 TaskStop 砍掉，用同名加 b 重派。新的 prompt 要寫進卡住的原因和已經做完的部分。
   - 任何 agent 閒置都不能超過 1 小時：prompt cache 只保留 1 小時，超過之後再叫它，整段 context 要重新計費。快到 1 小時還沒有下一步，就先把它的結果收回來、把它關掉，之後有事改派新的 agent，prompt 裡附上精簡的前情。
   - 機器不能閒置：下一步已經排好就馬上派。砍 agent 時連它的子程序一起停，確認持有者已經不在才釋放機器，留下的排隊項目要清掉。
   ```

   Carry forward: the 工作方式 and 已做的決策 sections of the baton this
   session picked up still apply unless the user changed them; fold them
   in. The 已做的決策 section is the highest-value part: a fresh session
   re-litigates anything not written down — record negative knowledge
   (what was ruled out) explicitly.
4. **Split durable from transient.** Lessons that outlive this handoff go
   to auto-memory as usual; machine facts (access limits, flaky network,
   tunnels, which machine is off-limits until when) go to the project's
   `CLAUDE.local.md` / `.claude/local/<machine>.md`. The baton holds only
   the one-shot continuation state plus the two standing sections above.
5. **Update the Obsidian notes** after the baton is written: dispatch
   `obsidian-tracker` with the project name, the baton path, the PRs/MRs
   merged this session, and the step-2 rulings. It reads the vault path
   from `WORKLOG_VAULT_PATH` in `~/.config/worklog/config` unless the
   project's `CLAUDE.local.md` names one. Skipped or failed? Say so.
6. **Tell the user how to resume**: next session, type
   `/kickoff --name <line>` (or `/pickup --name <line>`) — always with the
   name, never bare, which resolves to whichever baton happens to be
   newest. Also print the fallback one-liner `請讀 <full path> 接手` in
   case the skill is unavailable there.

Never put secrets or tokens in a baton. Overwrite an existing baton of the
same line only after folding anything still relevant from it into the new
one.
