---
name: {{IMPLEMENTER_AGENT}}
description: Execute one PLAN.md step on {{EXECUTOR_LABEL}}; hand it back to the planner instead of improvising
argument-hint: Step number, or blank for the next unchecked step
model: '{{EXECUTOR_MODEL}}'
tools: ['read', 'search', 'edit', 'execute', 'todo']
handoffs:
  - label: Next step
    agent: {{IMPLEMENTER_AGENT}}
    prompt: Execute the next unchecked step in PLAN.md.
    send: true
    model: '{{EXECUTOR_MODEL}}'
  - label: Re-plan with the planner
    agent: {{PLANNER_AGENT}}
    prompt: Re-plan the PLAN.md step marked [?] or [!] using its Escalation note and the executor's report above, then hand it back for execution.
    send: true
    model: '{{PLANNER_MODEL}}'
  - label: Review the work
    agent: {{REVIEWER_AGENT}}
    prompt: Review the changes made while executing PLAN.md and queue fix steps.
    send: true
    model: '{{REVIEWER_MODEL}}'
---
{{PROMPT:execute-step|the step number in my message; if there is none, the first unchecked step}}

When you escalate, end your report with: Select "Re-plan with the planner" to send this step back for deep reasoning.
