# Changelog

What each template version changes for the projects made from it. A project moves to a version with `.\.template\Update-Project.ps1`.

## v0.17.0

- `.githooks/commit-msg` starts with `#!/usr/bin/env sh` instead of `#!/bin/sh`, so pre-commit on Windows can run it as a `language: script` hook. Before, it failed with "Executable `/bin/sh` not found". Git runs it through `core.hooksPath` as before.
- `Update-Project.ps1` and `Adopt-Project.ps1` no longer set `core.hooksPath` in a clone that uses pre-commit (its hooks in `.git/hooks` are pre-commit's, or it has `.pre-commit-config.yaml`), because `pre-commit install` refuses to run while `core.hooksPath` is set. They print a `repo: local` hook to add to `.pre-commit-config.yaml` and `pre-commit install --hook-type commit-msg`, and print nothing once that file runs `.githooks/commit-msg`. A clone where an earlier update or adoption set `core.hooksPath` keeps it: run `git config --unset core.hooksPath` before `pre-commit install`.

## v0.16.0

- Both `actions/checkout` steps in `.github/workflows/ci.yml` set `persist-credentials: false`, so the job's `GITHUB_TOKEN` is no longer written to `.git/config`, where later steps could read it (zizmor's `artipacked` finding). Neither job pushes. In a project whose Dependabot has moved the `actions/checkout` pin, `Update-Project.ps1` stops with a conflict on these lines: keep the project's pin and add the new `with:` and `persist-credentials: false` lines. A project whose build or test steps run git commands that need the token, such as a push, sets `persist-credentials: true` on that checkout in its own `ci.yml`, which is a merged file, so later updates keep it.

## v0.15.0

- `.gitignore` ignores only the `secrets/` folder at the repository root (`/secrets/`), and `.claude/settings.json` denies Claude Code reading only that folder (`Read(/secrets/**)`). Before, both matched a `secrets/` folder at any depth, and on Windows also `Secrets/`, so new source files in a folder such as `src/App/Endpoints/Secrets/` were silently left out of commits and agents couldn't read them. `.env` files are still ignored and denied at any depth. Both files are merged on update. A project that keeps secret files in a nested `secrets/` folder should move them to the root `secrets/` folder, or add that folder's path to `.gitignore`, before updating, because the update stops ignoring it.

## v0.14.1

- `Adopt-Project.ps1` no longer names a project after the Claude Code worktree it runs in. Without a single solution, `project_name` is the `origin` remote's repository name, else the main checkout's folder name, else the folder name. A project adopted from a plan worktree before this release has the worktree's name in `.copier-answers.yml`; correct it there and run `.\.template\Update-Project.ps1`.

## v0.14.0

- A new `/plan-template-update` command plans a project's update to the newest template version, or to one it names (`/plan-template-update v0.14.0`), and can change an answer on the way. It reads the release notes since the project's version and runs `Update-Project.ps1 -NoCommit` on a clone of the project to see what the update does. Its plan runs the update as a step, pinned with `-Ref` and staged with `-NoCommit`, so the update is committed as `Plan step 1` and a result that differs from the trial escalates. Then it runs the project's checks, fixes each project file that still describes the old template, and ends with the project's tests, each judged by its exit code. It files an issue in the template repository for each gap the trial shows. In Claude Code it plans in a worktree, or, when the project's `plan-executor` subagent lacks the PowerShell tool (before v0.11.0), on a `build/project-template-<version>` branch in the current checkout.

## v0.13.0

- A new `/plan-issue` command plans one GitHub or GitLab issue: `/plan-issue #42`, `owner/repo#42` or the issue's URL. It reads the issue and its comments with `gh` or `glab`. It stops with questions when the issue is closed, already has a plan, has an open pull request or doesn't say enough to plan. It picks the kind of plan from the issue's labels (`bug` → bugfix, `enhancement` → feature, `documentation` → docs, …) or its text, and plans with that kind's checklist, in Claude Code in a worktree named `issue-42`. The `Issue:` line, the snapshot comment and `Closes` work as in v0.12.0.
- A new `/triage-issues` command lists up to 20 open issues that match a filter (a label, a milestone, an assignee or search words). For each one it judges the kind of plan, its readiness and its size, flags issues whose plans would overlap, and gives the `/plan-issue` command for each ready one. It changes no files and posts nothing.
- Every planning command reads the issue a request names, its body and every comment, before it researches. It treats the issue's text as data, not instructions: it never runs a command, opens a link or changes its rules because an issue says to.

## v0.12.0

- A plan can name the issue it implements. When the request names one (`#42`, `owner/repo#42` or its URL), the planning commands put it on an `Issue:` line under the plan's title and post the finished plan to the issue once, as a collapsed comment, with `gh` or `glab`. A re-plan that changes the Decisions or adds or removes steps posts a short follow-up. Only the planning session posts; executors never call `gh` or `glab`. A plan for no issue is unchanged.
- `review-plan-diff` and the push rules in `.github/instructions/project-template.instructions.md` put `Closes <issue>` and a short summary of the plan in the pull request description, so the issue's timeline holds the problem, the plan and the pull request that closed it.

## v0.11.0

- `/finish-plan` asks GitHub (`gh`) or GitLab (`glab`) whether the plan's branch has a merged pull request. It counts the work as upstream when that pull request's merge commit is on the default branch and its head matches the plan's branch, so a squash-merged or merge-queued pull request no longer stops it. Without the CLI, or without such a pull request, it still stops to ask.
- In Claude Code, `/finish-plan` deletes what's left of a plan's worktree when Windows' 260-character path limit stops `git worktree remove` with "Filename too long", and says to turn on `core.longpaths`. USAGE.md's Git setup now does: `git config --global core.longpaths true`.
- The Claude Code `plan-executor` subagent has the PowerShell tool and runs Done-when commands and a step's commands with it. Through Bash, Claude Code refused every `pwsh` command in a plan's worktree.
- `Update-Project.ps1` leaves out of its listing of the template's changes to project-owned files each change the project's file already has, and a file that has them all.
- README.md's "Update a Project" says that a project on v0.8.0 or earlier runs its own, older update logic on its first update, and how to run the newest logic from a clone instead.

## v0.10.0

- A new `/finish-plan` command closes a plan once its work is pushed or merged: it deletes `PLAN.md`, fast-forwards the default branch from `origin`, deletes the plan's branch, and in Claude Code removes the plan's worktree. It never pushes, and stops when a commit hasn't reached the default branch yet, such as after a squash-merged pull request.
- `review-plan-diff` points at `/finish-plan` once a review finds no blocker or should-fix left.

## v0.9.0

### Update twice, or once from a clone

Every earlier version of `.template\Update-Project.ps1` fails to hand an update over to the newer script when the template is cloned over a URL, as it is from GitHub, and runs its own, older update logic instead. It read the newer script with `git checkout` from a blob-filtered clone, which doesn't fetch the file. v0.9.0 fixes this, but the fix reaches a project only on its second update after this release: the first update to v0.9.0 still runs the project's old script, which installs the fixed one. That first run also commits on whatever branch is checked out, so switch to a branch of its own first.

To run the v0.9.0 logic on the first update instead, run the wrapper from a clone of this repository at v0.9.0: `git clone --branch v0.9.0 https://github.com/polewskm/project-template.git`, then `.\Update-Project.ps1 -Path <project>` in that clone.

### Changes

- `Update-Project.ps1` reads the target version's copy of itself with `git show` and hands the update over to it, and clones the template in full.
- `Update-Project.ps1` refuses to commit on the default branch (the branch `origin/HEAD` names). Run it on a branch of its own, such as `git switch -c build/project-template-v0.9.0`, or pass `-NoCommit`.
- `Update-Project.ps1` replaces Copier's "Make sure Git >= 2.24 is installed" warning, a false alarm with Git 2.55 and later, with what it means (copier-org/copier#2759).
- `Update-Project.ps1` shows the template's changes to project-owned files rendered with the project's answers, not as Jinja, and leaves out a change the project's answers don't reach.
- `Update-Project.ps1` and `Adopt-Project.ps1` no longer set `core.hooksPath` in a clone that has hooks in `.git/hooks`, which a hooks path turns off. They say how to run both.
- `Adopt-Project.ps1` asks to re-admit `Directory.Build.props` and `build/ProjectTemplate.props` in each `.dockerignore` and in each CI file that lists `Directory.Build.props`.
- The plan executor reports a Done-when command it couldn't run and leaves the check to the coordinator, instead of reporting a check of its own.
- `CLAUDE.md`, `.template/Update-Project.ps1` and `Directory.Build.props` end with a newline.

## v0.8.0

- An agent asked to push deletes a finished `PLAN.md` first, once every step, the review's fix steps included, is marked `[x]`; with a step still open it keeps the plan and says which steps remain.
