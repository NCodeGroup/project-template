---
name: plan-executor
description: Execute one PLAN.md step on a cheaper model and escalate with [?] instead of improvising. Use when coordinating PLAN.md execution from a stronger main model.
tools: Read, Edit, Write, Bash, PowerShell, Grep, Glob
model: {{CLAUDE_EXECUTOR_MODEL}}
---
{{PROMPT:execute-step|the step number in the task you were given; if there is none, the first unchecked step}}

## Run commands with the PowerShell tool

Run the step's Done-when command, in the `pwsh` child process that step 5 gives, and any command the step says to run, with the PowerShell tool, from the root of the plan's worktree, or of the repository when there is none, as `CLAUDE.md` tells the main session. Never hand them to `pwsh` through Bash: in a plan's worktree Claude Code refuses that, and Bash mangles their quoting. Use Bash only when the PowerShell tool isn't available, as on macOS and Linux without it turned on.
