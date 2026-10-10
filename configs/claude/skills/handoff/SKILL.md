---
name: handoff
description: "Use when the user says the current session should wrap up and a NEW session will continue the work — e.g. 「這個 session 收尾，下個 session 繼續做 X」「這個session準備先到一個段落」「交接給 <session 名稱>」. Settles open questions with the user, then either writes the baton the next session's /pickup reads, or — with --to <session name> — sends the whole handoff straight to an already-open session as a message (no file; that session starts working without /kickoff). Updates the Obsidian notes. Args: [--to <session name>] [--name <line>] [--domain <field>] [next-session tasks...]."
---

Wrap up the current session and write a machine-executable baton for the
next one. The baton is a file, not chat prose — a fresh session cannot read
this conversation. Its job is that the user never has to repeat, in the
next session, anything already said in this one.

## Completeness requirement (user ruling 2026-10-10)

The user's words, binding on both modes:

> 交接內容要詳細且完整，確保下一個 Session 接手後，不會出現任何資訊落差。凡是我曾經告訴你、討論過、做過決策、修改過、確認過，或目前仍在進行中的事情，都要完整同步，不要遺漏任何重要資訊。尤其是那些沒有明確寫進最終結論、但會影響後續工作的上下文、我的偏好、需求變更、已排除的方案、目前進度與待辦事項，也必須一併交接。目標是讓下一個 Session 可以直接無縫接續工作，不需要我重新解釋背景或重複提供已經說過的資訊。

How to apply it:
- Detail beats brevity here. A long baton is fine; a missing fact makes
  the user repeat themselves, which is the failure this skill exists to
  prevent. When unsure whether something matters, include it.
- Build the baton from a sweep of the **whole** conversation, from the
  first message (and any compaction summary) to now, not from what is
  in recent turns or memory of the outcome. Walk it once per category:
  what the user told you, discussed, decided, changed, confirmed, and
  what is still in progress; plus the context behind conclusions,
  preferences, requirement changes (old → new, with date), rejected
  approaches and why, current progress, and every open to-do, including
  small ones never promoted to a task.
- Before finishing step 3, re-read the baton against that sweep and add
  whatever is missing. Facts already recorded elsewhere (repo docs,
  auto-memory, an issue) still get a one-line pointer in the baton, so the
  next session knows they exist and where.

## Two modes

- **File mode** (no `--to`): write `handoff-<line>.md`; the next session
  runs `/kickoff --name <line>`. Everything below describes this mode.
- **Direct mode** (`--to <session name>`): the user has already opened the
  next session and named it (`claude -n <name>`). Do handoff and kickoff in
  one go: send the baton to that session as a message and write no baton
  file. Steps 1, 2, 4 and 5 are unchanged; steps 3 and 6 are replaced by
  the "Direct mode" section at the end. A bare session name as the only
  argument (it matches a session `ListAgents` shows) means `--to` it.

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
   ## 使用者偏好與需求變更
   - <each preference the user showed (said outright or by correcting
     you) and each requirement change, as old → new with the date and
     the reason the user gave; include ones that never reached a final
     conclusion>
   ## 背景脈絡（沒寫進結論但會影響後續）
   - <discussion, constraints, half-formed ideas, open threads and
     "we'll come back to this" items that shape later work but appear in
     no decision or task below>
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
   ## 其他待辦（還沒排進任務的）
   - <small follow-ups, promises made to the user, things to check later>
   ## 已做的決策（不要重新討論）
   - <choice + one-line why; every step-2 ruling; everything the user
     confirmed>
   ## 已排除的方案（不要再提）
   - <each REJECTED hypothesis/approach: what it was, why it was ruled out,
     and what evidence or ruling settled it>
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

   Carry forward from the baton this session picked up: 工作方式,
   使用者偏好與需求變更, 已做的決策 and 已排除的方案 still apply unless the
   user changed them, so fold every entry in; from 背景脈絡, 其他待辦 and
   the task list, keep every item not yet resolved. Nothing drops out just
   because this session did not touch it. 已做的決策 and 已排除的方案 are
   the highest-value parts: a fresh session re-litigates anything not
   written down, so record negative knowledge (what was ruled out)
   explicitly.
4. **Split durable from transient.** Lessons that outlive this handoff go
   to auto-memory as usual; machine facts (access limits, flaky network,
   tunnels, which machine is off-limits until when) go to the project's
   `CLAUDE.local.md` / `.claude/local/<machine>.md`. The baton still
   names each such fact in one line with where it was written, so the
   next session knows it exists; it does not copy the full text.
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

## Direct mode (`--to <session name>`)

Replaces steps 3 and 6. The receiving session has none of this
conversation and will not run `/kickoff` or `/pickup`, so the message has
to carry what those two would have given it.

D1. **Find the target before composing.** Call `ListAgents` and match
    `<session name>` exactly. Not listed, or two rows share the name: stop
    and tell the user what is listed — do not guess, and do not fall back
    to file mode without asking. Never send to a subagent of this session.
D2. **Hand over or stop what this session is running** (per the step-2
    answers): subagents and background jobs die with this session or keep
    reporting to it, and cannot be re-parented. For each one either finish
    and collect it now, stop it, or describe it in the message as "running
    detached on <machine>, check <path>" with the exact files and
    processes the receiver must watch. Nothing may be left that only this
    session can see.
D3. **Compose the message** — the step-3 baton, same sections in the same
    order, with these changes:
    - First paragraph, in this order: who is handing over to whom; that
      the user has confirmed the content (the step-2 rulings are final —
      the receiver must not ask them again); that no baton file exists and
      none should be written; that this session stops acting on MRs,
      issues and machines once the message is sent.
    - Then the **session contract**, copied from `~/.claude/commands/kickoff.md`
      ("Session contract" section, items 1–4: domain stance with the
      `--domain` value or `diffusion`, who drafts and who reviews documents,
      Obsidian through `obsidian-tracker`, model routing by difficulty).
      Read that file when composing; do not paraphrase it from memory.
    - Then what the receiver does first, replacing kickoff steps 1–4:
      (a) verify the message against reality before acting — branches,
      MRs/PRs, pipelines, machine locks, running jobs — and flag every
      mismatch; (b) ask the user only about questions that are new (a
      mismatch found in (a), or something this message marks as still
      open); with none, start on the task list without waiting; (c) start
      its own patrols, since none are handed over.
    - Paths the receiver needs (scratchpads, helper scripts, status files)
      are written out in full; an older baton worth reading is given by
      path, not summarised from memory.
    - The last line is `session: <tool>/<this session's id>` so the
      receiver and any later audit can tell who sent it.
    Write it in the language the user works in. Plain text only; no
    secrets or tokens.
D4. **Send it** with `SendMessage` to the name exactly as `ListAgents`
    printed it. One message if it fits; otherwise numbered parts
    (`[1/3]`…), each self-contained enough to be read in order, the last
    one ending with "end of handoff". Do not ask the receiver to reply
    unless `ListAgents` shows it can message back.
D5. **Confirm delivery, then stop.** Report to the user: the target name,
    how many parts were sent, and the one-line fallback to paste into the
    new session if the message did not show up there (`請照上一個
    session <this session's name or id> 傳來的交接訊息接手`, plus the
    transcript path if known). After the send, take no further action on
    the handed-over work — a second actor on the same MRs and machines is
    exactly what the handoff is meant to prevent.

Steps 4 (memory and machine notes) and 5 (Obsidian) run before D4, so the
message can say they are done. Step 5 has no baton path to pass in this
mode: give `obsidian-tracker` the composed message text instead (a draft
in the session scratchpad is fine — it is working material, not a baton).
A direct handoff leaves no `handoff-*.md`;
if the user later wants a record, the sent text is in this session's
transcript.
