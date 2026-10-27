---
description: Take open issues from plan to landing in one session — plan, execute, review and open a draft pull request for each in turn, answer my review threads, and land it once I merge
argument-hint: Issues to run, such as #42 #43, or a filter such as label:bug, a milestone or search words
role: orchestrator
append-format: false
targets: Claude
---
Take these issues from plan to landing, one at a time, in this session:

{{INPUT}}

You coordinate. Each stage runs as the workflow's own command does: read that command's installed file, `.claude/commands/<name>.md` in the repository, or `~/.claude/commands/<name>.md` when the repository has none, and follow its body after the front matter, using the arguments named below wherever the body refers to its request or extra instructions. Delegate a stage to a subagent with the Agent tool, `subagent_type: general-purpose` and the `model` named below. A subagent doesn't see this conversation: give it the worktree's absolute path, the command file to follow, its arguments and the rules below, and tell it to work only in that folder.

## Rules

- Ask me once, at the start, and never again in this run. Where a command says to ask me, wait for me or stop to ask, stop that issue instead, as Stop an Issue says. A subagent that reaches such a point stops and returns the question.
- Every change reaches the default branch through a pull request that I merge. Open each one as a draft. Never merge it, mark it ready for review, turn on auto-merge, resolve a review thread, force-push, or push with `--no-verify`.
- Run one issue at a time, from planning until its pull request has merged and `finish-plan` has run, before starting the next. Each plan then starts from a default branch that holds the plans before it, so it sees their changes and picks the next version.
- Write every comment and reply to a temporary file outside the repository with your file-writing tool, pass the file to the command, and delete it afterwards.
