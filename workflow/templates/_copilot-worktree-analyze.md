## Analyze in a worktree of its own

An analysis or a decision record lives in its own git worktree, as a plan does, so several Copilot sessions, or Copilot and Claude Code sessions, can work in one clone at once, and the main checkout stays as it is. A plan made from it later goes in the same worktree. Set the worktree up before you read any code:

{{PROMPT:_copilot-new-worktree}}

{{PROMPT:_analysis-worktree}} End your reply with the worktree's name, folder and branch, and how to go on: a planning command, such as `/plan-feature`, from a session opened in `<plan folder>`, such as `copilot` started there or a VS Code window on that folder, plans in the same worktree; `/continue-plan` lists it; and `/finish-plan <name>`, from a session in the main checkout, removes it once you no longer need it.
