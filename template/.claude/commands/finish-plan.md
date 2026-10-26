---
description: "Finish a plan whose work is pushed — retire PLAN.md, fast-forward the default branch, delete the plan's branch"
argument-hint: "[Optional extra instructions; the plan's worktree name when several are open]"
model: sonnet
effort: high
disable-model-invocation: true
---
## Finish the plan's worktree

Each plan lives in its own git worktree under `.claude/worktrees/<name>/`, on the branch `worktree-<name>`. This command also removes that worktree, so the task below runs in two places: its steps 1 to 3 in the worktree, and its steps 4 and 5 in the main checkout.

1. Find the worktree. When the command's arguments name one, run `git worktree list --porcelain`, find the `worktree` path under `.claude/worktrees/` with that folder name, and use it — even when this session is already in a different worktree. Otherwise run `git rev-parse --show-toplevel`: when the path contains `/.claude/worktrees/`, this session is in it. Otherwise list the plan worktrees the same way; with several and none named, list them with their branches and stop to ask which one; with none, do the whole task where this session is.
2. Do the task's steps 1 to 3 in the worktree: in it, as written; from the main checkout, with `git -C <worktree path>`, deleting `<worktree path>/PLAN.md`. Never switch into the worktree with the `EnterWorktree` tool: Claude Code doesn't remove a worktree entered that way. The plan's branch is `worktree-<name>`, even when `git branch --show-current` prints nothing.
3. Then remove the worktree. In it: call the `ExitWorktree` tool with `action: "remove"` and `discard_changes: true`, because the task's checks showed nothing is lost and the tool can't check that itself; it returns the session to the main checkout even when it says it kept the worktree. From the main checkout: run `git worktree remove <worktree path>`.
4. When git says the worktree is locked by `claude session <name> (pid <N>)`, check whether that process runs (`Get-Process -Id <N>`). When it runs, stop and ask me to end that session. When it doesn't, run `git worktree unlock <worktree path>` and remove the worktree again. When removing fails with "Permission denied", "Access is denied" or a folder in use, stop and ask me to close the terminals, editors and sessions open in that folder, then run this command again.
5. In the main checkout, run `git worktree list --porcelain`. When the worktree is still listed — `ExitWorktree` doesn't remove a worktree this session entered with a `path`, and may refuse for other reasons — run `git worktree remove <worktree path>`, and go back to item 4 when git reports a lock or a folder in use. Then run `git worktree prune`. When the worktree's folder is still there and empty, delete it; when it still holds files, stop and list them.
6. Do the task's steps 4 and 5 in the main checkout. When it isn't on the default branch, run `git fetch origin <default branch>:<default branch>` instead of switching and pulling: it only fast-forwards, and leaves the work checked out there alone. Delete `worktree-<name>` only after that fast-forward; when `ExitWorktree` already deleted it, skip that.

From here on, never run commands in the removed worktree's folder.

## Task

Finish the plan whose work is already pushed or merged: retire `PLAN.md`, bring the default branch up to date, and delete the plan's branch. Never push, merge, rebase or reset in this command: when a check fails, stop and say what is left to do.

Extra instructions (may be empty): $ARGUMENTS

1. Check the plan is done. When `PLAN.md` exists and has a step heading that doesn't start with `### [x]`, stop and list those steps. Run `git status --porcelain`: when it lists any file, stop and list the files.
2. Check the work is upstream. Run `git fetch origin --prune`. The default branch is the output of `git symbolic-ref --short refs/remotes/origin/HEAD` without its `origin/` prefix, or `main` when that command fails. The plan's branch is the output of `git branch --show-current`. Run `git merge-base --is-ancestor HEAD origin/<default branch>`: when it exits non-zero, show `git log --oneline origin/<default branch>..HEAD` and stop to ask me whether to push those commits first or whether they reached the default branch another way, such as a squash-merged pull request.
3. Retire the plan: delete `PLAN.md` when it exists.
4. Fast-forward the default branch: run `git switch <default branch>`, then `git pull --ff-only`. When either fails, stop and report the error.
5. When the plan's branch is not empty and not the default branch, delete it with `git branch -d <plan's branch>`. When `-d` refuses, use `git branch -D <plan's branch>` only if step 2 passed or I confirmed the commits reached the default branch. When `origin/<plan's branch>` still exists, say so and leave it: deleting it is a push.
6. Finish with the range `git pull` printed (or "already up to date"), the default branch's commit (`git log --oneline -1`), and the branches deleted.
