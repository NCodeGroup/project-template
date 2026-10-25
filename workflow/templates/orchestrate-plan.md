---
description: Run PLAN.md in one session — you verify and re-plan, a cheaper subagent executes each step
argument-hint: Optional extra instructions, such as a step to start from
role: orchestrator
append-format: false
worktree: join
---
Execute `PLAN.md` as its coordinator. You are the strong reasoning model: you verify every result and do all re-planning. A cheaper, faster subagent makes every edit.

Extra instructions (may be empty): {{INPUT}}

Delegate execution to:

- Claude Code: the `plan-executor` subagent.
- Copilot CLI: the `plan-executor` custom agent (or the general-purpose subagent, with its model set through `/subagents`).
- VS Code: the Implementer agent for your setup.

For each step whose heading starts with `### [ ]`, in order:

1. Delegate the step with a self-contained task. The subagent does not see this conversation, so include the step number, the full step text copied from `PLAN.md`, the Context for the executor section, and the instruction to escalate with `[?]` instead of improvising.
2. When it returns, run the step's Done-when command yourself from the repository root.
3. Passed: make sure the step is marked `[x]`, run `git add -A` and `git commit -m "Plan step N: <title>"`, and continue with the next step.
4. Escalated (`[?]`) or failed: re-plan the step yourself — diagnose it, rewrite or split it, record any decision under Decisions, remove the Escalation line, reset it to `[ ]` — commit as "Re-plan step N", then delegate it again.
5. Stop and ask me when a step has been re-planned twice and still does not pass, or when re-planning would change the Goal or Out of scope.

Make code changes yourself only as a last resort, after a step has been re-planned twice, and say so in the summary. Finish with a table of step, result, delegations, re-plans and notes, then suggest running review-plan-diff.
