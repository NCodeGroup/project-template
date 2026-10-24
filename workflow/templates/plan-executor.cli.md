---
name: plan-executor
description: Execute one PLAN.md step on a cheaper model and escalate with [?] instead of improvising. Use when coordinating PLAN.md execution from a stronger main model.
model: {{CLI_EXECUTOR_MODEL}}
user-invocable: false
---
{{PROMPT:execute-step|the step number in the task you were given; if there is none, the first unchecked step}}
