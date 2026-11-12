## Analyze in a worktree of its own

An analysis or a decision record lives in its own git worktree, as a plan does, so several Claude Code sessions can work on this machine at once, and the main checkout stays as it is. A plan made from it later goes in the same worktree. Set the worktree up before you read any code:

1. Run `git rev-parse --show-toplevel`. If the path contains `/.claude/worktrees/`, this session is already in a worktree: use it, unless its `PLAN.md` has a step not yet marked `[x]`. In that case stop, because the worktree holds a plan in progress, and tell me to run this command from a new session in the main checkout.
2. Otherwise, if `git check-ignore -q .claude/worktrees/` exits non-zero, append the line `.claude/worktrees/` to `info/exclude` in the folder that `git rev-parse --path-format=absolute --git-common-dir` prints, so the main checkout doesn't list worktrees as untracked files.
3. Then, still in the main checkout, settle the clone's Git settings, because the worktree shares the clone's Git config and Claude Code refuses any change to it from a session isolated in a worktree. {{PROMPT:_git-hooks}} {{PROMPT:_push-branch-session}} Then create the worktree:
   - Name it with two to four lowercase words from the request, joined by hyphens, such as `csv-export`, that are not already a folder under `.claude/worktrees/` and not already a branch `worktree-<name>`.
   - Run `git fetch origin`.
   - Choose the base: the branch that `git symbolic-ref --short refs/remotes/origin/HEAD` prints, such as `origin/main`. If that command fails, run `git remote set-head origin --auto` and run it once more. In a clone without `origin`, the base is `HEAD`.
   - Run `git worktree add --no-track -b worktree-<name> .claude/worktrees/<name> <base>`, which never switches the main checkout's branch.
   - Switch into it with the `EnterWorktree` tool and its `path`, the worktree's absolute path. Claude Code never removes a worktree entered by path, so the worktree keeps the analysis, which is never committed, without an empty commit.
4. A worktree is a fresh checkout, without ignored files such as installed dependencies. If the build or test command needs a setup step first, such as `npm ci`, run it in the worktree and, in a plan, list it under Context for the executor.

From here on, the repository root is the worktree's root: read, write and run commands only there, never in the main checkout.

{{PROMPT:_analysis-worktree}} End your reply with the worktree's name, folder and branch, and how to go on: a planning command, such as `/plan-feature`, in this session, or from a terminal `claude --worktree <name>` and then the planning command, plans in the same worktree; `/continue-plan` lists it; and `/finish-plan <name>`, from a session in the main checkout, removes it once you no longer need it.
