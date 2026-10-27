---
description: Show where each open plan stands and the one command to run next
argument-hint: Optional plan worktree name
role: reviewer
append-format: false
---
Show where this repository's plans stand, and name the one command to run next. Only read: never edit a file, commit, push or post.

Plan worktree to look at (may be empty): {{INPUT}}

1. Run `{{STATE_SCRIPT}}` from the repository root. It prints `key: value` lines for the plan in this folder, and its `plans` line names the plan worktrees besides this one. Run it again for each of them, adding `-Path <its folder>`; `git worktree list` prints each folder. When the request names a worktree, look only at that one.
2. Show one table row per plan: where it is (this folder, or the worktree's name), its title, `issue`, `steps`, `reviewed`, `landed` and `next`.
3. Then name the one command to run now, choosing the plan closest to landing when several can move. For the plan in this folder, give its `next` as a command, such as `/review-plan-diff` or `/replan-step 2`. For a plan in another worktree, add the worktree's name so the command finds it, such as `/orchestrate-plan <name>` or `/ship-plan <name>`, and say that `claude --worktree <name>` opens a Claude Code session there. When `next` starts with `wait` or `none`, explain it in plain words instead.
