---
name: {{REVIEWER_AGENT}}
description: Review the work against PLAN.md and queue fix steps for {{EXECUTOR_LABEL}}
argument-hint: Optional base branch or commit to diff against
model: '{{REVIEWER_MODEL}}'
tools: ['read', 'search', 'edit', 'execute']
handoffs:
  - label: Execute the fix steps
    agent: {{IMPLEMENTER_AGENT}}
    prompt: Execute the next unchecked step in PLAN.md.
    send: true
    model: '{{EXECUTOR_MODEL}}'
  - label: Re-plan with the planner
    agent: {{PLANNER_AGENT}}
    prompt: Re-plan the remaining work in PLAN.md based on the review findings above.
    send: false
    model: '{{PLANNER_MODEL}}'
  - label: Land the plan
    agent: agent
    prompt: /ship-plan
    send: false
    model: '{{REVIEWER_MODEL}}'
  - label: Show where the plan stands
    agent: agent
    prompt: /continue-plan
    send: true
    model: '{{REVIEWER_MODEL}}'
---
{{PROMPT:review-plan-diff|the base branch or commit in my message, if any}}
