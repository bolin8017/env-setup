---
name: pickup
description: "Use at the START of a session to take over work a previous session handed off with /handoff — the user says /pickup, 「接手」, or asks to continue where the last session left off. Args: [--name <line>]."
---

Read the baton a previous session wrote with /handoff and continue its work.

## Locating the baton

Batons live in `<auto-memory dir>/../handoffs/` (sibling of the auto-memory
directory listed in your system prompt; fall back to the project's
`.claude/handoffs/`). Selection:

- `--name <line>` → `handoff-<line>.md`.
- No name → the most recently modified `handoff*.md`, excluding `*.done.md`.
  If several lines are pending, name the one you picked and list the others
  so the user can redirect.
- Check the primary location first; if it is missing or has no matching
  baton, check the fallback before concluding.
- Nothing found → say so plainly, list whatever batons DO exist (pending or
  done), and ask what to work on. Do not invent a continuation.

## Steps

1. Read the baton. Restate in a few lines: the tasks, the in-flight state,
   and the already-made decisions you will NOT reopen. This is the contract
   for the session — the user corrects it here if the baton is stale.
2. **Verify the baton against reality before acting** — it describes the
   past: named branches still exist? PRs still open/unmerged? File pointers
   still valid? Baton older than 7 days? Flag every mismatch instead of
   executing blindly.
3. Mark the baton taken: rename it to `<file>.done.md` (replacing any
   previous `.done.md` of that line). The content stays recoverable; the
   line stops matching future no-name pickups. If step 2 surfaced a major
   mismatch that awaits the user's decision, delay the rename until the
   direction is confirmed — a line nobody actually picked up must keep
   matching.
4. Work the tasks. Honor the baton's decision log — re-opening a recorded
   decision needs new information plus the user's say-so, not fresh-context
   amnesia.
