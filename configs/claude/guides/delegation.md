# Delegation and orchestration

Read before dispatching any subagent (choosing its model/effort, writing its
prompt), before running a multi-agent batch on shared machines, or when
writing an agent definition.

- **Model routing.** Weekly quota first (user ruling 2026-10-19): the
  session model keeps the judgement (hypotheses,
  root cause, design, verification verdicts) and writes dispatches that spell
  out every step, the check for it and where to stop; subagents execute.
  `haiku` for read-only fact gathering, wording review and note updates;
  `sonnet` for measurements and experiments, well-specified code and machine
  configuration. Give a subagent the session model only when its steps
  cannot be written down in advance. `effort` is the only thinking lever
  (no "thinking off", no "think carefully" lines): set it in the agent
  definition and keep `xhigh`/`max` for measured gains. A sonnet or haiku
  agent at `low`/`medium` may stop to check in or skip checks, so multistep
  agent definitions carry a keep-working and a real-check paragraph.
- **Context economy.** A subagent's tool output stays in its own context;
  only its final message reaches the parent (code.claude.com sub-agents
  doc, "Isolate high-volume operations"), and every parent turn re-reads the
  whole conversation at the cached rate (costs doc). So every dispatch names
  the file that takes the full result and keeps the final message to the
  file path, the verdict and the blockers. Web research needing more than a
  couple of searches or a long page goes to `web-researcher` (haiku), which
  quotes and links every claim; before a decision rests on one of its
  claims, open that source yourself. Hooks cannot batch completion
  notifications: SubagentStop can block a subagent from stopping or add
  context, not delay or merge what the parent receives (hooks doc). A batch
  of independent agents that should report once is a dynamic workflow
  (`parallel()` waits for all, intermediate results stay out of context),
  which needs the user's opt-in.
- **Orchestration: no idle machines, no idle agents.** When delegating to
  subagents that drive shared machines: each agent writes a STATUS line every
  5 minutes (including "waiting for X until HH:MM"), reports any failed run
  within 5 minutes instead of at batch end, and never lets a machine sit
  idle when a next step is already planned. The orchestrator patrols (a
  background loop watching STATUS freshness and machine reservations) and
  interrupts an agent that is stuck or ignores directives: stop it, then
  message it so it resumes with its own context; re-dispatch a new agent
  only when the old one cannot be resumed (user rulings 2026-10-14 onward).
  Give each dispatch a time budget (`budget 40 min`); models pace to it. A
  subagent that returns with open items and no stated blocker has reported,
  not finished: send it the open items, at most 2-3 times, then escalate.
  Aborting a batch means stopping the driver and all its child processes,
  releasing the machine reservation only after confirming its holder is
  gone, and removing any queue entry the batch left behind. Rules given to
  subagents must not contradict this file; when two rule sources conflict,
  the user-level rule wins and the agent asks (user ruling 2026-09-16).
