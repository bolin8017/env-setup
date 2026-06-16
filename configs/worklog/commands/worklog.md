---
description: Append today's work to the worklog-inbox and push (curated into the vault later)
---

Record today's work into the shared work-log inbox for later curation into the
obsidian vault. Raw, fast capture — not a polished note.

Read this machine's settings from `~/.config/worklog/config` (deployed by
env-setup's `10-worklog` module): `WORKLOG_SOURCE`, `WORKLOG_INBOX_REPO`,
`WORKLOG_INBOX_PATH`. If that file is missing, tell the user to run
`./setup.sh --modules 10-worklog` in their env-setup checkout first, then stop.

Steps:
1. **Lazy clone:** if `$WORKLOG_INBOX_PATH` has no `.git`, clone the inbox now
   (you are authenticated at this point) — `gh repo clone "$WORKLOG_INBOX_REPO"
   "$WORKLOG_INBOX_PATH"` for an owner/collaborator account, or via the
   `github-worklog` SSH remote if this machine uses a deploy key. If the clone
   fails on auth, tell the user how to authenticate (`gh auth login`) or set up a
   deploy key — do NOT fabricate an entry.
2. `git -C "$WORKLOG_INBOX_PATH" pull -q`.
3. Today's date `YYYY-MM-DD`. Target file `$WORKLOG_SOURCE/<date>.md`. Append a
   new `---`-separated entry if it exists, else create it from `_TEMPLATE.md`.
4. Fill from THIS session + recent activity — pull real refs with
   `git -C <repo> log --oneline -8` for the repos you touched. Sections:
   重點/做了什麼, 決策/學到, 卡關/解法, 待辦/下一步, refs. Set `project:`.
   Raw bullets, zh-TW prose, identifiers in English. Be concrete.
5. Commit + push:
   `git -C "$WORKLOG_INBOX_PATH" add -A`
   `git -C "$WORKLOG_INBOX_PATH" commit -m "log($WORKLOG_SOURCE): <date> <topic>"`
   `git -C "$WORKLOG_INBOX_PATH" push -q`
6. Report the entry path + a 1–2 line summary of what was logged.

`$ARGUMENTS` may carry a topic hint or extra notes. Never write secrets/tokens
into the inbox (private, but treat as as-if-public for credentials).
