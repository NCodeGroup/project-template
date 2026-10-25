# Project Template

Instructions for coding agents working on this repository: the project template itself, not a project made from it. [README.md](README.md) explains the repository. `PLAN.md`, when there is one, is the plan in progress.

## Commits

- Commits and pull requests record the people who wrote them: never add a `Co-authored-by:` trailer naming an AI agent (Copilot, Claude or any other), a `Claude-Session:` trailer, or a "Generated with" line. Claude Code's `attribution` setting (`.claude/settings.json`) and VS Code's `git.addAICoAuthor` (`.vscode/settings.json`) are off here, and the template's own hook strips any that slip through once a clone enables it: `git config core.hooksPath template/.githooks`.
