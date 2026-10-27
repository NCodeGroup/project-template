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

## Start

1. Run `git rev-parse --show-toplevel`. When the path contains `/.claude/worktrees/`, stop and say to run this command in a new session in the main checkout.
2. Run `{{STATE_SCRIPT}}`. Below, `<default>` is its `default` value. Stop when `default` is `-`, because there is no `origin` remote, or when its `landing` line doesn't say `integrate=pull-request`: say to set `- integrate: pull-request` in the `## Landing` section of `AGENTS.md`.
3. Check that `<default>` takes changes only through pull requests. One of these must hold:
   - GitHub: `gh api "repos/{owner}/{repo}/rules/branches/<default>" --jq '[.[] | select(.type == "pull_request")] | length'` prints a number above 0, or `gh api "repos/{owner}/{repo}/branches/<default>/protection/required_pull_request_reviews"` succeeds.
   - GitLab, when `host` is `gitlab`: `glab api "projects/:id/protected_branches/<default>"` succeeds and every entry of its `push_access_levels` has `access_level` 0.
   - Locally, for a host that can't require pull requests, such as a private repository on GitHub Free: the `## Landing` section of `AGENTS.md` has `- protect: hook`, and `Test-Path (Join-Path (git rev-parse --git-path hooks) 'pre-push')` is `True`, so the template's `pre-push` hook refuses pushes to `<default>`.

   When none holds, stop. Say to require pull requests into `<default>` with a branch protection rule or ruleset, or, where the host can't, to add `- protect: hook` to the Landing section and run `git config core.hooksPath .githooks`.
4. Build the queue:
   - When the request names issues, such as `#42` or `#42 #43`, the queue is those issues in that order. Leave out an issue in another repository, such as `owner/repo#42`, and say so: this command lands only this repository's issues.
   - Otherwise delegate `triage-issues` to a subagent with `model: opus` and the request as its arguments. The queue is the ready issues, in the order of the `/plan-issue` lines it returns.
   - Leave out an issue whose folder `.claude/worktrees/issue-<number>` already exists: it holds a plan in progress, which `/continue-plan issue-<number>` shows.
   - Keep the first five. When the queue is empty, say so and stop.
5. Show the run summary, then ask me once whether to go ahead and whether to file each plan's follow-ups as issues (by default they are only listed in the issue's closing comment), and wait for my answer. The summary lists the queue (number, title, and the kind and size when triage gave them); that each issue gets a plan snapshot comment, a draft pull request that waits for my review and merge, and, after the merge, the tag, the release and the closing comment the Landing section names; when the run stops an issue; and the cost: each issue takes about one plan-issue run on Opus, one orchestrate-plan run, up to three reviews, and one more round for each set of review comments I post. `git push` may still ask for its own approval.