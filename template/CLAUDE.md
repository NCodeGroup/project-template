@AGENTS.md

## Claude Code

This file comes from the project template, and template updates replace it. Put Claude-specific project instructions in `.claude/rules/<name>.md` instead; Claude Code loads every file there.

- Run Done-when commands and other `PLAN.md` commands with the PowerShell tool, from the repository root.
- Executing a plan: `/orchestrate-plan` delegates each step to the `plan-executor` subagent, verifies it with the step's Done-when command, and re-plans escalations itself.
- Re-planning one escalated or failed step: `/replan-step N`. Reviewing finished work against the plan: `/review-plan-diff`.