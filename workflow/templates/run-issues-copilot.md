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

## Start

1. Run `git rev-parse --show-toplevel`. When the path contains `/.claude/worktrees/`, stop and say to run this command in the main checkout. When `PLAN.md` exists at the repository root, stop: a plan is in progress here, and `/continue-plan` shows where it stands. When `git status --porcelain` prints anything, stop and list it, because the run switches branches.
2. Run `{{STATE_SCRIPT}}`. Below, `<default>` is its `default` value. Stop when `default` is `-`, because there is no `origin` remote, or when its `landing` line doesn't say `integrate=pull-request`: say to set `- integrate: pull-request` in the `## Landing` section of `AGENTS.md`.
3. Check that `<default>` takes changes only through pull requests: the state script's `protected` value must be `host`, because the host requires pull requests into `<default>` (a GitHub ruleset or branch protection rule that requires a pull request, or a GitLab protected branch nobody can push to), or `hook`, because the `## Landing` section of `AGENTS.md` has `- protect: hook` and Git runs the template's `pre-push` hook, which refuses pushes to `<default>`.

   When it is anything else, stop. Say to require pull requests into `<default>` with a branch protection rule or ruleset, or, where the host can't, to add `- protect: hook` to the Landing section and run `git config core.hooksPath .githooks`, or, in a clone that uses pre-commit or hooks of its own, to save `#!/usr/bin/env sh` and `exec .githooks/pre-push "$@"` as `.git/hooks/pre-push`, or as `.git/hooks/pre-push.legacy` when pre-commit installed its pre-push hook. When it is `unknown`, also say that `gh` or `glab` is missing, or the host is neither GitHub nor GitLab.
4. Build the queue:
   - First take a `wait:<hours>` word, such as `wait:72`, out of the request. It sets the wait limit: how long Review the Pull Request waits for a merge with nothing to answer, 24 hours when the request has no such word. The bullets below read the rest of the request.
   - When the request names issues, such as `#42` or `#42 #43`, the queue is those issues in that order, one entry each. Leave out an issue in another repository, such as `owner/repo#42`, and say so: this command lands only this repository's issues.
   - Otherwise delegate `triage-issues` to a subagent, as above, with the request as its arguments. The queue has one entry per `/plan-issue` line it returns, in that order, holding the issues that line names.
   - Leave out an entry when the branch `issue-<number>` already exists for any of its issues, locally or on `origin` (`git rev-parse --verify --quiet refs/heads/issue-<number>`, or `git ls-remote --exit-code --heads origin issue-<number>`), or the folder `.claude/worktrees/issue-<number>` does: it holds a plan in progress, which `/continue-plan` shows.
   - Keep the first five entries. When the queue is empty, say so and stop.
5. Show the run summary, then ask me once whether to go ahead, and wait for my answer. The summary lists the queue, each entry with its issues (number, title, and the kind and size when triage gave them); that each issue gets a plan snapshot comment, a draft pull request that waits for my review and merge, for up to the wait limit, in hours, with nothing to answer, and, after the merge, the tag, the release, a closing comment on each issue, and an issue labelled with the `landing` line's `follow-up-label` for each follow-up its plan lists, in this repository or in the one the `landing` line's `follow-ups` names, unless I answer that I want none filed, or, when that line says `follow-ups=none`, the follow-ups listed in the report instead; when the run stops an issue; and the cost: each issue takes about one plan-issue run on Opus, one orchestrate-plan run, up to three reviews, and one more round for each set of review comments I post, and a check every five minutes while its draft pull request waits. Say that entries run one after another in this folder, each planned only once the one before has landed, and that a stop after an entry's `PLAN.md` is written ends the run, leaving that entry for `/continue-plan`. Say too that an entry whose draft pull request is open moves to the next free version, with one more step and one more review, when a pull request outside the run takes its version, and that its pull request then merges with a merge commit, not by rebasing. When the `landing` line's `gate` isn't `none`, say that the gate runs before each push and that a failing gate stops the entry. Say that the run must not stop for approvals: in Copilot Chat, choose the Bypass Approvals or Autopilot permission level; in Copilot CLI, run `/allow-all`, or start the session with `copilot --allow-all`. `git push` may still ask for its own approval.

## Run Each Issue

For each entry in the queue, in order:

1. Create its branch: run `git fetch origin`, then `git switch --no-track -c issue-<number> origin/<default>`. `--no-track` leaves the branch without an upstream until `ship-plan` pushes it, so `ship-plan` drops the plan's empty commits.
2. Plan: delegate `plan-issue` to a subagent, as above, with the arguments `<issues>`. When it returns without a `PLAN.md` at the repository root, stop this entry with its reason.
3. Then run `{{STATE_SCRIPT}}` after every stage, and act on its `next` value:
   - `orchestrate-plan`: follow `orchestrate-plan` yourself, in this session, so the executor it names for this tool executes each step: in Copilot Chat the Copilot Implementer, or the Local Implementer when the repository has only the Hybrid agents; in Copilot CLI the `plan-executor` agent.
   - `review-plan-diff`: delegate `review-plan-diff` to a subagent, as above. A review that adds fix steps makes `next` `orchestrate-plan` again. Count the reviews since the plan was written, or since the last round of my review comments: when the third review still adds fix steps, stop this issue.
   - `ship-plan`: follow `ship-plan` yourself with the extra instructions `draft`. The answer I gave at the start is the answer its item 4 asks for: show the landing summary and go on without asking. Unless I said at the start that I want none filed, file the follow-ups; when I did, tell it to treat every follow-up as one to drop.
   - A value starting with `wait`: the draft pull request is open. Go on with Review the Pull Request, below.
   - `finish-plan`: follow `finish-plan` yourself. It deletes `PLAN.md`, switches to `<default>`, fast-forwards it and deletes `issue-<number>`. The entry is done: go on with the next entry.
   - Anything else, such as `replan-step 2` or a value starting with `none`: stop this issue with that value.

   When a stage leaves `next` as it was, stop this issue: the stage made no progress.
