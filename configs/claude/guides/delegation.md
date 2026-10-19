# Delegation and orchestration

Split out of `~/.claude/CLAUDE.md` (2026-09-29). Read before dispatching any
subagent (choosing its model/effort, writing its prompt), before running a
multi-agent batch on shared machines, or when writing an agent definition.

- **Model routing.** Weekly quota first (user ruling 2026-10-19, replacing
  the 2026-09-23 split): the session model keeps the judgement (hypotheses,
  root cause, design, verification verdicts) and writes dispatches that spell
  out every step, the check for it and where to stop; subagents execute.
  `haiku` for read-only fact gathering, wording review and note updates;
  `sonnet` for measurements and experiments, well-specified code and machine
  configuration. Give a subagent the session model only when its steps
  cannot be written down in advance. `effort` is the only thinking lever
  (no "thinking off", no
  "think carefully" lines). Opus 5.5 `medium` matches Opus 5 `high`; keep
  `xhigh`/`max` for measured gains. Sonnet 5.5 at `low`/`medium` may stop to
  check in or skip checks, so multistep sonnet agent definitions carry a
  keep-working and a real-check paragraph.
- **Orchestration: no idle machines, no idle agents.** When delegating to
  subagents that drive shared machines: each agent writes a STATUS line every
  5 minutes (including "waiting for X until HH:MM"), reports any failed run
  within 5 minutes instead of at batch end, and never lets a machine sit
  idle when a next step is already planned. The orchestrator patrols (a
  background loop watching STATUS freshness and machine reservations) and
  kills and re-dispatches an agent that is stuck or ignores directives.
  Give each dispatch a time budget (`budget 40 min`); models pace to it. A
  subagent that returns with open items and no stated blocker has reported,
  not finished: send it the open items, at most 2-3 times, then escalate.
  Aborting a batch means stopping the driver and all its child processes,
  releasing the machine reservation only after confirming its holder is
  gone, and removing any queue entry the batch left behind. Rules given to
  subagents must not contradict this file; when two rule sources conflict,
  the user-level rule wins and the agent asks (user ruling 2026-09-16).
