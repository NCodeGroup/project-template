## Plan in a worktree of its own

Each plan lives in its own git worktree, so several Claude Code sessions can plan and execute different plans on this machine at once. Executing, re-planning and reviewing this plan later happen in the same worktree. Set it up before you read any code, so your research matches the code the executor will change:

1. Run `git rev-parse --show-toplevel`. If the path contains `/.claude/worktrees/`, this session is already in a worktree: use it, unless its `PLAN.md` has a step not yet marked `[x]`. In that case stop, because the worktree holds a plan in progress, and tell me to start the new plan from a new session in the main checkout.
2. Otherwise, if `git check-ignore -q .claude/worktrees/` exits non-zero, append the line `.claude/worktrees/` to `info/exclude` in the folder that `git rev-parse --path-format=absolute --git-common-dir` prints, so the main checkout doesn't list worktrees as untracked files.
3. Then name the worktree: two to four lowercase words from the request, joined by hyphens, such as `csv-export`, and not already a folder under `.claude/worktrees/`. Create the worktree and switch into it with the `EnterWorktree` tool and that `name`.
4. A worktree is a fresh checkout, without ignored files such as installed dependencies. If the build or test command needs a setup step first, such as `npm ci`, run it in the worktree and list it under Context for the executor.

From here on, the repository root is the worktree's root: read, write and run commands only there, never in the main checkout.

After writing `PLAN.md`, commit it in the worktree: `git add PLAN.md`, then `git commit -m "Plan: <the plan's title>"`. End your reply with the worktree's name and branch, and how to continue: `/orchestrate-plan` in this session; from a new session, `/orchestrate-plan <name>`; or from a terminal, `claude --worktree <name>` and then `/orchestrate-plan`. If Claude Code asks on exit whether to keep the worktree, keep it.
