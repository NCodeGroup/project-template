---
description: Take every open comment and discussion on one pull request, from anyone or any bot, judge each against the code, plan and execute the fixes, push them to the pull request's branch and reply to each one
argument-hint: The pull request, such as #42, owner/repo#42 or its URL, and optionally only:<login> or exclude:<login> to take or leave one author's comments
role: orchestrator
append-format: false
targets: VSCode, CopilotCli
command: address-feedback
---
Address the open comments and discussions on this pull request, in this session:

{{INPUT}}

{{PROMPT:_copilot-stages}}

{{PROMPT:_address-feedback-body}}

## Checkout

The run works in this folder, on a branch of its own, `feedback-<number>`, made from the pull request's branch, with `PLAN.md` at the repository root, untracked, as every Copilot plan is. Switch branches only where this section says to: `PLAN.md` is untracked, so a switch carries it along, and it belongs to `feedback-<number>`. `orchestrate-plan` hands each step to the executor it names for this tool: in Copilot Chat the Copilot Implementer, or the Local Implementer when the repository has only the Hybrid agents; in Copilot CLI the `plan-executor` agent. An earlier run on a pull request is still open, for Start item 3, when the branch `feedback-<number>` exists, which `git rev-parse --verify --quiet refs/heads/feedback-<number>` shows by printing a commit and `/continue-plan` shows once it is checked out, or when the folder `.claude/worktrees/feedback-<number>` exists, which a Claude Code run leaves.

1. Start item 1: run `git rev-parse --show-toplevel`. When the path contains `/.claude/worktrees/`, stop and say to run this command in the main checkout. When `PLAN.md` exists at the repository root, stop: a plan is in progress here, and `/continue-plan` shows where it stands. When `git status --porcelain` prints anything, stop and list it, because the run switches branches. Note `<return>`, the branch `git branch --show-current` prints, which the run switches back to at its end; stop and say to check out a branch when it prints nothing, or a name that fails Start item 3's check for `<head>`. In the run summary Start item 6 shows, also say that the run must not stop for approvals: in Copilot Chat, choose the Bypass Approvals or Autopilot permission level; in Copilot CLI, run `/allow-all`, or start the session with `copilot --allow-all`. `git push` may still ask for its own approval.
2. Plan item 1: run `git fetch origin "refs/heads/<head>"`, then `git switch --no-track -c feedback-<number> "origin/<head>"`.
3. Reply's end: when `git status --porcelain` prints nothing and `git rev-parse HEAD` equals `git rev-parse "origin/<head>"`, delete `PLAN.md` when it exists, then run `git switch "<return>"` and `git branch -D feedback-<number>`: its commits are on the pull request's branch. Otherwise leave `feedback-<number>` checked out as it is.
4. Stop: when the run stopped before its `PLAN.md` was written, after Plan item 1 created `feedback-<number>`, and `git status --porcelain` prints nothing, run `git switch "<return>"` and `git branch -D feedback-<number>`. Otherwise leave the branch checked out as it is, with its commits and `PLAN.md`, so `/continue-plan` in a new session in this folder picks it up.
