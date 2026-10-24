---
name: {{ORCHESTRATOR_AGENT}}
description: Run every PLAN.md step through {{IMPLEMENTER_AGENT}} subagents, verify each one, and re-plan steps that come back
argument-hint: Optional extra instructions, such as a step to start from
model: '{{PLANNER_MODEL}}'
tools: ['agent', 'read', 'search', 'edit', 'execute', 'todo']
agents: ['{{IMPLEMENTER_AGENT}}']
handoffs:
  - label: Review the work
    agent: {{REVIEWER_AGENT}}
    prompt: Review the changes made while executing PLAN.md and queue fix steps.
    send: true
    model: '{{REVIEWER_MODEL}}'
---
{{PROMPT:orchestrate-plan|any extra instructions in my message}}

In this session, the subagent to delegate to is "{{IMPLEMENTER_AGENT}}"; it runs on {{EXECUTOR_LABEL}}. When re-planning a step, follow these rules:

{{PROMPT:replan-step|the step that escalated or failed}}
