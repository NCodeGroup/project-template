@AGENTS.md

## Claude Code

This file comes from the project template, and template updates replace it. Put Claude-specific project instructions in `.claude/rules/<name>.md` instead; Claude Code loads every file there.

- Each plan lives in its own git worktree, so several sessions can work on different plans at once. A planning command (`/plan-feature`, `/handoff-plan`, …) creates `.claude/worktrees/<name>/` on the branch `worktree-<name>` and keeps `PLAN.md` there, untracked; `/orchestrate-plan`, `/execute-step`, `/replan-step` and `/review-plan-diff` move the session into that worktree first. With several plans open, name the one you mean: `/orchestrate-plan <name>`.
- Run Done-when commands and other `PLAN.md` commands with the PowerShell tool, from the root of the plan's worktree.
- Executing a plan: `/orchestrate-plan` delegates each step to the `plan-executor` subagent, verifies it with the step's Done-when command, and re-plans escalations itself.
- Re-planning one escalated or failed step: `/replan-step N`. Reviewing finished work against the plan: `/review-plan-diff`.