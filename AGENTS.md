# Project Template

Instructions for coding agents working on this repository: the project template itself, not a project made from it. [README.md](README.md) explains the repository. `PLAN.md`, when there is one, is the plan in progress. It is gitignored: never commit, stage or push it, and never use `git add -A`; stage the files a step lists. `/ship-plan` lands a reviewed plan by the Landing section below and keeps `PLAN.md` for `/finish-plan`, which deletes it. Before a push you were asked for and make without `/ship-plan`, delete `PLAN.md` once every step is marked `[x]`; when a step is still open, keep it and say which steps remain.

## Commits

- Commits and pull requests record the people who wrote them: never add a `Co-authored-by:` trailer naming an AI agent (Copilot, Claude or any other), a `Claude-Session:` trailer, or a "Generated with" line. Claude Code's `attribution` setting (`.claude/settings.json`) and VS Code's `git.addAICoAuthor` (`.vscode/settings.json`) are off here, and the template's own hook strips any that slip through once a clone enables it: `git config core.hooksPath template/.githooks`.

## Plans

This repository keeps a plan's `Plan step N: <title>` commits on `main`: each is one verified change, and the template's workflow has no squash rule. A project that squashes them, such as one that merges its pull requests by squashing, does so in its own push protocol; taking changes only through pull requests doesn't require it, and this repository's `main` takes changes only through pull requests and keeps the step commits by merging with a merge commit or by rebasing. A plan's empty `Plan: <title>` and `Re-plan step N` commits change nothing, so drop them when the plan's branch lands. `/ship-plan` does this before it pushes: `git rebase -f --no-keep-empty` onto the branch's merge base with `origin/main`. By hand: `git rebase -f --no-keep-empty main` on that branch, then push it and open a pull request. Tagged history is never rewritten.

## Landing

`/ship-plan` pushes a reviewed plan's branch and opens a pull request into `main`, with `Closes` for the plan's issue. Merge it with a merge commit or by rebasing, not by squashing, so the plan's step commits stay on `main`. Running `/ship-plan` again after the merge tags the commit it merged as with the plan's version and publishes the GitHub release from that version's `CHANGELOG.md` section. A plan's `Release:` line names the version, and its last step writes the changelog section. This repository is public. Its ruleset, Protect main, makes every change to `main` a pull request whose `test` and `Commit attribution` checks pass, merged with a merge commit or by rebasing, and refuses force-pushes and deletion. `protect: hook` also has the template's `pre-push` hook refuse every push to `main` once a clone runs `git config core.hooksPath template/.githooks`, so a mistaken push stops before it leaves the PC. Never bypass it with `--no-verify`.

- integrate: pull-request
- release: tag+release
- changelog: CHANGELOG.md
- protect: hook
