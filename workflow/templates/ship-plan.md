---
description: Land a reviewed plan as AGENTS.md's Landing section says: push it or open its pull request, tag and publish its release, close its issue
argument-hint: Optional extra instructions
role: reviewer
append-format: false
worktree: join
---
Land the plan in `PLAN.md` the way this repository's Landing policy says: push its commits to the default branch or open its pull request, tag and publish its release, comment on and close its issue, and file the follow-ups I pick. Run it again at any time: each stage checks whether it is done and skips it, so a run that stopped partway, or a pull request that has merged since, carries on where it left off. Never force-push, rebase onto a moved default branch, move or delete a tag, or delete a release.

Extra instructions (may be empty): {{INPUT}}

1. Read the state: run `{{STATE_SCRIPT}}` from the repository root. It prints `key: value` lines. Below, `<default>` is its `default` value, `<branch>` its `branch` and `<version>` its `release`. Stop and say what to run instead when `plan` is `-`; when `dirty` is `yes`; when `steps` shows an open, escalated or failed step (run orchestrate-plan, or replan-step); when `reviewed` isn't `current`, because the work changed since its last clean review or never had one (run review-plan-diff); or when `next` is `finish-plan`, because everything is done (run finish-plan).
2. Read the policy from the `landing` line: `integrate` is `direct` or `pull-request`, `release` is `none`, `tag` or `tag+release`, and `changelog` names the changelog file. Read `PLAN.md`'s title, `Issue:` line, Goal, Decisions and `## Follow-ups`. When `release` isn't `none`, stop when `<version>` is `-`, because the plan has no `Release:` line, or when the changelog's first `## ` heading isn't `## <version>`. When `tag` is `present`, it must already point at the commit this plan lands; otherwise stop, because a tag is never moved.
3. With `integrate: direct`, stop when `behind` is more than 0: the default branch moved since the plan branched, so bring it in, run the checks and the review again, then ship. With `integrate: pull-request`, `behind` doesn't matter, because the pull request merges it.
4. Show the landing summary, then ask me once whether to go ahead and wait for my answer. The summary lists: the commits to land (`git log --oneline origin/<default>..HEAD`), and the empty `Plan:` and `Re-plan step` commits among them that will be dropped; where they go, the default branch or a pull request from `<branch>`; the tag and the release; what the issue gets; and each follow-up, so I can pick the ones to file as issues. After my yes, run every stage below without asking again. `git push` may still ask for its own approval.
