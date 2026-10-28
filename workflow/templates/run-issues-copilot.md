---
description: Take open issues from plan to landing in one Copilot session — plan, execute, review and open a draft pull request for each in turn, answer my review threads and comments, and land it once I merge
argument-hint: Issues to run, such as #42 #43, or a filter such as label:bug, a milestone or search words, and wait:<hours> to change the 24-hour wait for each merge
role: orchestrator
append-format: false
targets: VSCode, CopilotCli
command: run-issues
---
Take these issues from plan to landing, one queue entry at a time, in this session:

{{INPUT}}

An entry is one issue, or a group of up to three related issues that triage-issues printed on one `/plan-issue` line, which gets one plan, branch, pull request and release. Below, `<number>` is the number of an entry's first issue, which names its branch `issue-<number>`, and `<issues>` is the entry's references, such as `#25 #24 #26`.

This run works in the open folder, on one entry's branch at a time, with `PLAN.md` at the repository root, untracked, as every Copilot plan is. The folder holds one plan at a time, so entries run strictly one after another: the next one starts once the one before has landed and `finish-plan` has run for it, or it stopped before its `PLAN.md` was written.

You coordinate. Each stage runs as the workflow's own command does: read that command's installed file and follow its body after the front matter, using the arguments named below wherever the body refers to its request or extra instructions. The file is `.github/skills/<name>/SKILL.md` in the repository; else `.github/prompts/<name>.prompt.md`; else `~/.copilot/skills/<name>/SKILL.md`. Delegate a stage to a subagent where this command says so:

- Copilot Chat, in a Local session: the `runSubagent` tool. A planning stage runs without a named agent, on this session's model. `review-plan-diff` runs on the Copilot Reviewer agent, or on the Hybrid Reviewer when the repository has only that one, so it runs on the reviewer model.
- Copilot CLI: the general-purpose subagent. It runs on the session's model unless `/subagents` sets another, so start the session on Opus.

A subagent doesn't see this conversation: give it the repository's absolute path, the stage file to follow, its arguments and the rules below, and tell it to work only in that folder and never to switch branches. A subagent can't start subagents of its own, so `orchestrate-plan`, which delegates each step, runs in this session.

## Rules

- Ask me once, at the start, and never again in this run. Where a command says to ask me, wait for me or stop to ask, stop that issue instead, as Stop an Issue says. A subagent that reaches such a point stops and returns the question.
- Every change reaches the default branch through a pull request that I merge. Open each one as a draft. Never merge it, mark it ready for review, turn on auto-merge, resolve a review thread, force-push, or push with `--no-verify`.
- Land one entry at a time, in queue order. Each entry's branch starts from the default branch after the entry before it has landed, so its plan takes the next free `Release:` version. When a pull request outside the run lands that version, or a later one, while the entry's draft pull request is open, Review the Pull Request item 3 renumbers the entry and pushes the step to its pull request.
- Write every comment and reply to a temporary file outside the repository with your file-writing tool, pass the file to the command, and delete it afterwards.
- Switch branches only where this command says to. `PLAN.md` is untracked, so a switch carries it along: it belongs to the entry whose branch it was written on.
