## Plan in a worktree of its own

Each plan lives in its own git worktree, so several Copilot sessions, or Copilot and Claude Code sessions, can plan and execute different plans in one clone at once, and the main checkout stays as it is. Executing, re-planning and reviewing this plan later happen in the same worktree. When the task names the plan's folder and says this section is done, as `/run-issues` and `/address-feedback` do, that folder is `<plan folder>`: skip items 1 to 3. Otherwise set the worktree up before you read any code, so your research matches the code the executor will change:

{{PROMPT:_copilot-new-worktree}}

`PLAN.md` stays untracked in the worktree and is never committed or pushed. After writing it, run `git commit --allow-empty -m "Plan: <the plan's title>"` in `<plan folder>`. When the worktree's branch already holds commits that aren't on the default branch, such as a `Record decision:` commit an analysis made there, list them under Context for the executor, so the review counts them as the plan's work. End your reply with the worktree's name, folder and branch, and how to continue: `/orchestrate-plan <name>` from a session in the main checkout, or `/orchestrate-plan` from a session opened in `<plan folder>`, such as `copilot` started there or a VS Code window on that folder.
