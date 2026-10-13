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

1. **Domain stance.** Act as an expert in the given domain and apply the
   evidence and root-cause rules of `~/.claude/CLAUDE.md` with that field's
   reference implementations (for diffusion: diffusers, ComfyUI, sd.cpp, the
   original papers' code).
2. **Obsidian notes.** Updates to the Obsidian vault go through the
   `obsidian-tracker` subagent, never hand-edited here.
3. Published Chinese prose follows `~/.claude/CLAUDE.md` Communication and
   the project's instruction files; model routing follows
   `~/.claude/guides/delegation.md`. State the tier you chose in one line
   when dispatching.

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
   A task whose requirement is unclear goes through
   `superpowers:brainstorming` with the user first (Execution Policy,
   Requirements first); one with clear acceptance needs no spec round.
3. **Wait for the user's confirmation.** Do not dispatch agents, edit code or
   run long jobs until the user confirms (answering the questions counts).
4. After confirmation, give a short dispatch plan: each task, its model tier
   from `~/.claude/guides/delegation.md`, and what can run in parallel.
   Then execute it autonomously to completion per the Execution Policy.
