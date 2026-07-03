---
name: weekly-review
description: Summarize the past week of worklog entries into a weekly review note in the obsidian vault. Use on the curator machine, typically at end of week; complements /worklog (capture) and /worklog-sync (curation).
---

Aggregate the past week's work into one weekly review note in the obsidian
vault. This is a synthesis pass — /worklog captures raw entries and
/worklog-sync routes them into the vault; this skill reads what landed and
writes the week's summary.

Read `~/.config/worklog/config` (deployed by env-setup's `10-worklog` module)
for `WORKLOG_INBOX_PATH`, `WORKLOG_VAULT_REPO`, `WORKLOG_VAULT_PATH`,
`WORKLOG_ROLE`. If the file is missing, tell the user to run
`./setup.sh --modules 10-worklog` first, then stop. If `WORKLOG_ROLE` is not
`curator`, explain that the vault lives on the curator machine and stop.

Steps:

1. **Sync sources.** `git -C "$WORKLOG_VAULT_PATH" pull -q`; also
   `git -C "$WORKLOG_INBOX_PATH" pull -q` when the inbox clone exists — raw
   entries not yet curated still count for the week.
2. **Determine the week.** Default: the ISO week containing today, Monday to
   Sunday. `$ARGUMENTS` may name another week (`2026-W26`) or a date range.
3. **Collect the week's material.**
   - Vault day logs: `2-Areas 領域/職涯/群聯電子/日誌/<date> 工作日誌.md` for
     each date in the week (and any project pages modified this week —
     `git -C "$WORKLOG_VAULT_PATH" log --since=<monday> --name-only` shows
     them).
   - Uncurated inbox entries for the week's dates (`*/YYYY-MM-DD.md`), if any
     — include them, and note at the end that they still need /worklog-sync.
4. **Synthesize** into `2-Areas 領域/職涯/群聯電子/日誌/<year>-W<ww> 週回顧.md`
   (check the vault's `CLAUDE.md` / `_meta/taxonomy.md` first — if they define
   a different home or template for weekly notes, follow that instead).
   Sections: 本週重點 (3-5 bullets), 專案進展 (per project, link the pages),
   決策與學到, 卡關與未解, 下週優先. zh-TW prose, identifiers in English,
   tags `職涯/群聯` + `類型/日誌`. Link day logs with `[[...]]`.
5. **Commit + push** the vault: `content: <year>-W<ww> weekly review`.
6. **Report** the note path, the week's headline in 1-2 lines, and any
   uncurated inbox entries found in step 3.

Never write secrets/tokens into the vault. If the week has no material at
all, say so instead of fabricating a review.
