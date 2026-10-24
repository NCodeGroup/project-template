---
name: plan-executor
description: Execute one PLAN.md step on a cheaper model and escalate with [?] instead of improvising. Use when coordinating PLAN.md execution from a stronger main model.
tools: Read, Edit, Write, Bash, Grep, Glob
model: {{CLAUDE_EXECUTOR_MODEL}}
---
{{PROMPT:execute-step|the step number in the task you were given; if there is none, the first unchecked step}}
