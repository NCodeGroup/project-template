# Workflow

The single source of truth for the plan-and-execute workflow: the prompt and agent templates, and the PowerShell 7 scripts that install, compose and run them. Everything else — the generated files under [`../template/`](../template/), personal-notes, and any repository the installer writes into — is a consumer. The workflow itself, and how to choose between its variants, is in personal-notes' [plan-and-execute.md](https://github.com/polewskm/personal-notes/blob/main/ham-radio/shack/shack-pc/local-ai/plan-and-execute.md).

| File | Purpose |
|---|---|
| [templates/](templates/) | The 25 prompt templates, the 4 VS Code agent templates, the `plan-executor` subagent templates, the Claude Code plan-worktree sections, the issue label table, the `PLAN.md` format and an example plan ([templates/README.md](templates/README.md)) |
| [Install-HybridWorkflow.ps1](Install-HybridWorkflow.ps1) | Generate Claude Code commands and the `plan-executor` subagent, VS Code prompt files and agents (Local and Copilot variants), and Copilot CLI skills and agent from `templates/` into a repository (`-Repo`) or the user profile (`-User`). Re-running overwrites what it generated. It records the template version — `git describe` of this clone — in `.template-version`: at the repository root, or in `~\.claude\` and `~\.copilot\` for `-User`; `-NoVersionMarker` skips it, as `tools/Update-Template.ps1` does |
| [New-PlanPrompt.ps1](New-PlanPrompt.ps1) | Compose a template and a request into one prompt for any chat (`-List`, `-Copy`) |
| [Invoke-PlanSteps.ps1](Invoke-PlanSteps.ps1) | Execute `PLAN.md` step by step (local or Copilot executor); verifies each Done-when command itself, after the plan's `- Prelude:` command when it has one, commits per step (never `PLAN.md`), detects `[?]` escalations, and re-plans automatically with `-Replan claude\|copilot\|local` |
| [Get-PlanState.ps1](Get-PlanState.ps1) | Print where the plan in a folder stands, as `key: value` lines (steps, review, landing policy, whether the default branch takes changes only through pull requests, commits ahead and behind, the files that conflict with the default branch, pull request and the commit it merged as, tag, release, each issue and its state, the issues it only refers to, the follow-ups not yet filed as issues, other plan worktrees), and the workflow command to run next. `-NoFetch` skips its fetch of `origin`, for a call that an earlier call's fetch already covers. The installer copies it next to the commands; `ship-plan`, `continue-plan`, `finish-plan`, `run-issues` and `address-feedback` run it; `../tests/Test-PlanState.ps1` tests it |
| [HybridWorkflow.psm1](HybridWorkflow.psm1) | Shared template reader used by the three scripts above |

```powershell
.\workflow\Install-HybridWorkflow.ps1 -User                          # commands, skills and agents for every project, in your user profile
.\workflow\Install-HybridWorkflow.ps1 -Repo C:\src\other-repo        # workflow files only, into a repository that won't adopt the template (..\Adopt-Project.ps1 adopts one)
.\workflow\New-PlanPrompt.ps1 plan-feature "Add CSV export" -Copy    # a prompt for any chat
.\workflow\Invoke-PlanSteps.ps1 -Plan C:\src\qso-viewer\PLAN.md -Replan claude
```

After changing a template, run `.\tools\Update-Template.ps1` at the repository root to regenerate the copies under `template/` and this repository's own copies at its root, then `.\tests\Test-Template.ps1`, which fails while they differ.

---

**TL;DR:** Edit the workflow only here: `templates/` holds every prompt and agent, `Install-HybridWorkflow.ps1` installs them anywhere, `New-PlanPrompt.ps1` composes them for a chat, and `Invoke-PlanSteps.ps1` runs a plan step by step. `tools/Update-Template.ps1` turns them into the project template's generated files and this repository's own.
