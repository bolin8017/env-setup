# Repository documents

Split out of `~/.claude/CLAUDE.md` (2026-09-29). Read before creating a repo
or writing a versioned document (instruction files, intent.md, decisions.md,
reports) in any repo.

## Repository documents (user ruling 2026-09-16)
- New repo: scaffold per "Project layout for a new repo" in
  `~/.claude/commands/init-rules.md`.
- Every repo: versioned files carry no absolute paths, user accounts or
  intranet addresses (machine facts go to `CLAUDE.local.md` and
  `.claude/local/<machine>.md`); only the user changes `intent.md`'s order or
  constraints; reversed `decisions.md` rows are annotated, not deleted;
  reports name the machine by description (never an IP) and put a column
  legend under every table; root instruction file stays under ~200 lines.
