---
name: claude-md-slim
description: "Use when an instruction file that loads every session has outgrown its budget — CLAUDE.md, CLAUDE.local.md or ~/.claude/CLAUDE.md well past 200 lines, sessions that open with pages of context they rarely need, or the user says the file is too long and asks to split, tidy or reorganise it. Args: [path] (default: every memory file this session loads)."
---

Move everything a session does not always need out of a memory file, leaving a
short main file plus an index that says when to go read the rest.

**A split is a relocation, never a deletion.** Trimming stale content is a
separate decision that belongs to the user: propose candidates, do not act.

## Verified facts — build on these, don't re-derive them

From [the official memory docs](https://code.claude.com/docs/en/memory):

- Target **under 200 lines per file**. Files load in full and adherence drops
  as they grow. Over 4 MiB is skipped entirely.
- **`@path` imports do not save context.** Imported files expand at launch
  alongside the file that references them. They organise; they cost the same.
  A path inside backticks is *not* an import, which is what makes an index
  table load-on-demand.
- **`CLAUDE.local.md` loads alongside `CLAUDE.md` and is treated the same way.**
- Files in directories **above** the cwd load at launch; files in
  subdirectories load only when Claude reads files there. A worktree that
  lives under the repo root therefore still inherits the root's `CLAUDE.md`
  and `CLAUDE.local.md`.
- `.claude/rules/*.md` carrying `paths:` frontmatter load **only** when Claude
  touches a matching file — real savings, but only for content that maps onto
  file paths.

## Where each section goes

| Section | Destination |
|---|---|
| Needed in essentially every session | stays in the main file |
| Tied to specific files or directories | `.claude/rules/<topic>.md` with `paths:` |
| A whole procedure for one kind of task | its own skill |
| Everything else — per-task, per-machine, per-box detail | `.claude/local/<topic>.md`, reached through the index |

Classify by **trigger** ("what would make me need this?"), not by topic. Two
sections about the same subsystem belong in different places if one is needed
always and the other only while building.

## Procedure

1. **Measure first.** `wc -l` every memory file in play. State the starting
   number; it is what the result gets compared against.
2. **Back up** the file before touching it. A gitignored memory file is
   usually the only copy in existence.
3. **Pick the destination directory and prove it is ignored** *before* writing
   anything into it: `git check-ignore -v <path>`. Personal notes carry
   absolute paths, hostnames and drive letters; a repo that forbids those in
   tracked files will be violated the moment the split lands in the wrong
   place. Prefer a directory an existing rule already covers (`.claude/*` is
   the common one) so `.gitignore` needs no edit. If nothing covers it, ask
   before adding a rule.
   Default to `.claude/local/<topic>.md` so a later session finds the same
   layout instead of inventing a third name for it.
4. **Move text, never retype it.** Slice by line range (`sed -n 'A,Bp'`, or
   Python for anything with CRLF — see traps below) and prepend a two-line
   header saying what the file covers and when to open it.
5. **Write the index table** into the main file (see below).
6. **Write the maintenance rule** into the main file, one sentence: new detail
   goes to the matching split file, not back onto the pile. Without it the
   main file regrows.
7. **Verify all three checks** below before reporting.

## The index table

The right-hand column is a path in backticks. The left-hand column is **the
situation that sends you there**, not a summary of the contents:

| 要做什麼 | 先讀哪一份 |
| --- | --- |
| Deploy or measure on the 8 GB GPU box | `.claude/local/box-gpu8.md` |
| Build the CUDA binary | `.claude/local/build-cuda.md` |

"CUDA notes" does not make anyone open the file; "building the CUDA binary"
does. Someone who does not know a trap exists cannot look it up by name.

## Verify before reporting

- **Zero loss.** Compare programmatically, never by eye: every non-empty line
  of the backup must appear in one of the resulting files. Report the count of
  lines that moved and of lines you deliberately rewrote (headings, index).
- **Still ignored.** `git check-ignore -v` on *every* new file, plus a clean
  `git status`.
- **Still loads.** Start one throwaway session in the tree and ask it, with
  tools disabled, to quote a string that exists only in the new index:
  `claude -p "Do not use any tools. Quote the first row of the table titled X, or reply NONE."`
  Run it from a worktree or subdirectory if those are how the project is
  normally used.

## Tool traps

- **`sed` rewrites CRLF to LF.** On a CRLF file that silently changes every
  line and breaks a byte-level comparison. Slice with Python in binary mode,
  or verify line endings afterwards.
- **Git Bash heredocs eat backslashes**, so a Windows path inside an inline
  `python - <<EOF` arrives corrupted (`\r` becomes a carriage return). Write
  the script to a file and run the file.
- **Editors' escape handling.** When generating text containing Windows paths,
  use raw strings and read the result back with `repr()`.

## Common mistakes

| Mistake | Why it fails |
|---|---|
| Splitting with `@path` imports | Everything still loads at launch; the file is shorter but the session is not |
| Splitting without an index | The detail is not moved, it is lost — nothing will ever open those files |
| Deleting instead of moving | Personal memory files are frequently the only copy |
| Writing split files somewhere tracked | Absolute paths and hostnames land in version control |
| Inventing a new directory name each time | The next split scatters into a second location |
| Classifying by topic | Puts always-needed and rarely-needed content in the same file |
| Reporting line counts as proof of correctness | A short file proves nothing about what fell out of it |
