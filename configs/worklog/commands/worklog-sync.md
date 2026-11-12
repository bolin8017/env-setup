---
description: Pull worklog-inbox and curate raw entries into the obsidian vault (routed by source)
---

Curate raw work-logs from the inbox into the obsidian-notes vault, then clear the
consumed entries. **Route each entry by its SOURCE folder + content.** This
command is for `WORKLOG_ROLE=curator` machines (the vault lives here).

Read `~/.config/worklog/config` for `WORKLOG_INBOX_PATH`, `WORKLOG_VAULT_REPO`,
`WORKLOG_VAULT_PATH`, `WORKLOG_ROLE`. If `WORKLOG_VAULT_PATH` has no `.git`, clone
`$WORKLOG_VAULT_REPO` into it (lazy) first.

Steps:
1. `git -C "$WORKLOG_INBOX_PATH" pull -q`.
2. Pending = `*/YYYY-MM-DD.md` under the source folders. List them; if several or
   ambiguous, confirm with the user.
3. Route + curate per source, following the vault `CLAUDE.md` + `_meta/taxonomy.md`:
   - **work / Phison sources** → `2-Areas 領域/職涯/群聯電子/`: day log →
     `日誌/<date> 工作日誌.md` (tags `職涯/群聯` + `類型/日誌`); substantial topic →
     `專案/<name>.md` (tags `職涯/群聯` + `類型/專案`); wire into `_群聯電子 MOC`.
   - **personal / research sources** → `1-Projects 專案/`: per-project page with a
     unique name (e.g. `ai-daily-report.md`); tag by topic 領域 + `類型/專案`
     (or `類型/日誌`). Unique filenames — links resolve by filename.
   - **else** → route by content; ask if unclear.
   If `$WORKLOG_INBOX_PATH/sources.yaml` exists, prefer its source→home mapping.
   Merge same-day entries only if they share a vault home.
4. Commit + push the vault (`docs(vault): ...` message, since the commit-message
   hook accepts Conventional Commits types only; direct-to-master allowed per
   the vault's repo CLAUDE.md).
5. Delete the consumed raw entries from the inbox and commit + push the inbox
   (`chore: clear curated logs`) so they are not re-processed.
6. Report what was curated (and where) and what was cleared.

`$ARGUMENTS` may name a specific date/source to process, or extra framing.
