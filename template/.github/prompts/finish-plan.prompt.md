---
description: "Finish a plan whose work is pushed — retire PLAN.md, fast-forward the default branch, delete the plan's branch"
argument-hint: "Optional extra instructions"
agent: agent
model: "Claude Sonnet 5.5 (copilot)"
---
Finish the plan whose work is already pushed or merged: retire `PLAN.md`, bring the default branch up to date, and delete the plan's branch. Never push, merge, rebase or reset in this command: when a check fails, stop and say what is left to do.

Extra instructions (may be empty): ${input:details:Optional extra instructions}

1. Check the plan is done. When `PLAN.md` exists and has a step heading that doesn't start with `### [x]`, stop and list those steps. Run `git status --porcelain`: when it lists any file, stop and list the files.
2. Check the work is upstream. Run `git fetch origin --prune`. The default branch is the output of `git symbolic-ref --short refs/remotes/origin/HEAD` without its `origin/` prefix, or `main` when that command fails. The plan's branch is the output of `git branch --show-current`. Run `git merge-base --is-ancestor HEAD origin/<default branch>`; when it exits zero, the check passed. When it exits non-zero, the commits may have landed as new ones, as a squash merge or a merge queue lands a pull request, so ask the host. When `git remote get-url origin` contains `gitlab`, run `glab mr list --source-branch <plan's branch> --merged --output json` and take each merge request's merge commit from `merge_commit_sha`, or `squash_commit_sha` when that is empty, and its head from `sha`; otherwise run `gh pr list --head <plan's branch> --state merged --json number,mergeCommit,headRefOid` and take each pull request's merge commit from `mergeCommit.oid` and its head from `headRefOid`. The check passed when one of them has a merge commit for which `git merge-base --is-ancestor <merge commit> origin/<default branch>` exits zero, and a head that is the commit `git rev-parse HEAD` prints or has the same tree (`git rev-parse <head>^{tree}` prints what `git rev-parse HEAD^{tree}` prints); say which one. Otherwise — the CLI is missing or fails, or finds no such pull request — show `git log --oneline origin/<default branch>..HEAD` and stop to ask me whether to push those commits first or whether they reached the default branch another way.
3. Retire the plan: delete `PLAN.md` when it exists.
4. Fast-forward the default branch: run `git switch <default branch>`, then `git pull --ff-only`. When either fails, stop and report the error.
5. When the plan's branch is not empty and not the default branch, delete it with `git branch -d <plan's branch>`. When `-d` refuses, use `git branch -D <plan's branch>` only if step 2 passed or I confirmed the commits reached the default branch. When `origin/<plan's branch>` still exists, say so and leave it: deleting it is a push.
6. Finish with the range `git pull` printed (or "already up to date"), the default branch's commit (`git log --oneline -1`), and the branches deleted.
