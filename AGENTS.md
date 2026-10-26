# Project Template

Instructions for coding agents working on this repository: the project template itself, not a project made from it. [README.md](README.md) explains the repository. `PLAN.md`, when there is one, is the plan in progress. It is gitignored: never commit, stage or push it, and never use `git add -A`; stage the files a step lists. Before a push you were asked for, delete `PLAN.md` once every step is marked `[x]`; when a step is still open, keep it and say which steps remain.

## Commits

- Commits and pull requests record the people who wrote them: never add a `Co-authored-by:` trailer naming an AI agent (Copilot, Claude or any other), a `Claude-Session:` trailer, or a "Generated with" line. Claude Code's `attribution` setting (`.claude/settings.json`) and VS Code's `git.addAICoAuthor` (`.vscode/settings.json`) are off here, and the template's own hook strips any that slip through once a clone enables it: `git config core.hooksPath template/.githooks`.

## Plans

This repository keeps a plan's `Plan step N: <title>` commits on `main`: each is one verified change, and the template's workflow has no squash rule. A project that squashes them before pushing, such as one whose `main` takes changes only through pull requests, does so in its own push protocol. A plan's empty `Plan: <title>` and `Re-plan step N` commits change nothing, so drop them when the plan's branch lands: `git rebase -f --no-keep-empty main` on that branch, then, in the main checkout, `git merge --ff-only worktree-<name>`. Tagged history is never rewritten.
