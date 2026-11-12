1. Run `git rev-parse --show-toplevel`. `<plan folder>` is the path it prints until item 3 changes it.
   - When the environment variable `GITHUB_ACTIONS` is `true`, this session is Copilot's cloud agent, whose runner keeps only the commits pushed from its clone: work in this checkout, on the branch it is on, create no worktree, and go on with item 4.
   - When the path contains `/.claude/worktrees/`, or `git rev-parse --path-format=absolute --git-dir` and `git rev-parse --path-format=absolute --git-common-dir` print different paths, this session is already in a worktree: use it, unless its `PLAN.md` has a step not yet marked `[x]`. In that case stop, because the worktree holds a plan in progress, and tell me to run this command from a new session in the main checkout. Otherwise settle the clone's Git settings as item 3 says, create no worktree, and go on with item 4.
2. Otherwise, if `git check-ignore -q .claude/worktrees/` exits non-zero, append the line `.claude/worktrees/` to `info/exclude` in the folder that `git rev-parse --path-format=absolute --git-common-dir` prints, so the main checkout doesn't list worktrees as untracked files.
3. Then, still in the main checkout, which you only read, settle the clone's Git settings before the worktree exists, because the worktree shares the clone's Git config. {{PROMPT:_git-hooks}} {{PROMPT:_push-branch-session}} Then create the worktree:
   - Name it with two to four lowercase words from the request, joined by hyphens, such as `csv-export`, that are not already a folder under `.claude/worktrees/` and not already a branch `worktree-<name>`.
   - Run `git fetch origin`.
   - Choose the base: the branch that `git symbolic-ref --short refs/remotes/origin/HEAD` prints, such as `origin/main`. If that command fails, run `git remote set-head origin --auto` and run it once more. In a clone without `origin`, the base is `HEAD`.
   - Run `git worktree add --no-track -b worktree-<name> .claude/worktrees/<name> <base>`, which never switches the main checkout's branch.
   - `<plan folder>` is now the new worktree's absolute path.
4. A worktree is a fresh checkout, without ignored files such as installed dependencies. If the build or test command needs a setup step first, such as `npm ci`, run it in the worktree and, in a plan, list it under Context for the executor.

From here on, `<plan folder>` is the repository root: read, write and run commands only there, never in the main checkout. {{PROMPT:_copilot-plan-folder}}
