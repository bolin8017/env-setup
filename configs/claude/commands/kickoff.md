---
description: Start a dev session — take over a handoff line, clarify open questions with the user first, then dispatch work to models by difficulty
argument-hint: --name <line> [--domain <field>] [extra notes...]
---

Session opener. Arguments: `$ARGUMENTS`

Parse the arguments:
- `--name <line>` — the handoff line to pick up (required; if missing, ask).
- `--domain <field>` — the expert domain; default `diffusion`.
- Anything else — extra notes from the user for this session; treat them as
  part of the task description.

## Session contract (in force for the whole session)

1. **Domain stance.** Act as an expert in the given domain. Solve problems the
   way the domain's mainstream does: check how the reference implementations
   and widely adopted open-source projects of that field handle it (for
   diffusion: diffusers, ComfyUI, sd.cpp, the original papers' code) before
   designing your own, and cite the source in one line when it shaped a
   decision.
2. **Documents.** Chinese prose that will be published (Markdown, reports,
   READMEs, MR/PR descriptions, issue bodies and comments) is drafted by a
   subagent on `model: sonnet`, written to a file first, then reviewed by
   `tw-docs-reviewer` (never pass `model` on that call — its frontmatter pins
   it) before it is pushed or posted. Re-review after edits.
3. **Obsidian notes.** Updates to the Obsidian vault go through the
   `obsidian-tracker` subagent, never hand-edited here.
4. **Model routing by difficulty** (the rule in `~/.claude/CLAUDE.md`,
   spelled out):
   - `haiku` — mechanical work: file/log search, renames, bulk formatting,
     collecting numbers from existing outputs.
   - `sonnet` — document drafting, routine code changes with a clear spec,
     test writing, straightforward reviews.
   - session model (omit `model`) — design decisions, debugging with unknown
     cause, numerical/precision issues, anything touching the domain's core
     algorithm, and final verification of claims.
   When unsure between two tiers, pick the higher one. State the tier you
   chose in one line when dispatching.

## Steps

1. Invoke the `pickup` skill with `--name <line>`. Do its steps 1–3 (restate,
   verify against reality, mark taken) but **do not start step 4 (working the
   tasks)** yet.
2. **Clarify before acting.** List the open questions that must be settled
   before work can start: requirement-level ambiguity, scope, conflicting or
   stale baton items, missing measurements, anything destructive. For each
   question give your recommended answer and why, so the user can just
   confirm. Group them; number them so the user can answer by number. Skip
   implementation-level choices — decide those yourself per the Execution
   Policy.
3. **Wait for the user's confirmation.** Do not dispatch agents, edit code or
   run long jobs until the user confirms (answering the questions counts).
4. After confirmation, give a short dispatch plan: each task, its model tier
   from the routing table, and what can run in parallel. Then execute it
   autonomously to completion per the Execution Policy.
