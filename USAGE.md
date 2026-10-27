# Usage

How to set up a PC for the template's AI workflow — Claude Code on your Claude plan, GitHub Copilot on your Copilot plan — and how to use either, and switch between them, in any project made from the template. Set up once per PC; nothing in a project changes when you switch.

## Table of Contents

- [How the Two Tools Fit](#how-the-two-tools-fit)
- [Install the Tools](#install-the-tools)
- [Set Up Git and GitHub](#set-up-git-and-github)
- [Set Up Claude Code](#set-up-claude-code)
- [Set Up GitHub Copilot](#set-up-github-copilot)
- [Check the Setup](#check-the-setup)
- [Work on a Project](#work-on-a-project)
- [Switch Between Claude and Copilot](#switch-between-claude-and-copilot)
- [Repositories Not Made From the Template](#repositories-not-made-from-the-template)
- [The Shack PC's Local Model](#the-shack-pcs-local-model)
- [Troubleshooting](#troubleshooting)

## How the Two Tools Fit

| | Claude Code | GitHub Copilot |
|---|---|---|
| Paid by | Your Claude plan (Pro or Max) | The Copilot plan of the GitHub account Copilot uses, such as an employer's seat |
| Where | The Claude Code extension in VS Code, or `claude` in a terminal | Copilot Chat in VS Code, or `copilot` (Copilot CLI) in a terminal |
| Workflow files in a project | `.claude/commands/`, `.claude/agents/` | `.github/agents/` and `.github/prompts/` for Copilot Chat, `.github/skills/` for Copilot CLI |
| Reads | `CLAUDE.md`, which imports `AGENTS.md` and each `@` file it lists | `AGENTS.md`, and every `.github/instructions/*.instructions.md` |
| Executes plan steps on | Claude Sonnet 5.5, in the `plan-executor` subagent | Claude Sonnet 5.5 with the Copilot agents; the shack PC's local model with the Hybrid agents |
| Where a plan lives | Its own git worktree, `.claude/worktrees/<name>/`, so several sessions can work on different plans at once | The folder that's open, usually the main checkout |

Both run the same commands against the same `PLAN.md`, so either can plan, execute, re-plan or review, whichever one started the plan. To continue a Claude Code plan in Copilot, open its worktree's folder.

A Claude plan works only in Anthropic's own tools. Copilot Chat's built-in Claude agent isn't a way to use it: that agent bills your Copilot plan or a Claude API key. To use your Claude plan in VS Code, use the Claude Code extension.

## Install the Tools

Once per PC, in PowerShell 7, not elevated:

| Tool | Install | For |
|---|---|---|
| PowerShell 7 | `winget install --id Microsoft.PowerShell -e` | The scripts, and every plan's Done-when commands |
| Git | `winget install --id Git.Git -e` | Everything; it also gives Claude Code its Bash tool |
| GitHub CLI | `winget install --id GitHub.cli -e` | Reading this private template; `New-Project.ps1 -CreateRemote` |
| uv and Copier | `winget install --id astral-sh.uv -e`, then, in a new terminal, `uv tool install copier` | `New-Project.ps1` and `.template\Update-Project.ps1` |
| VS Code | `winget install --id Microsoft.VisualStudioCode -e` | The Claude Code and Copilot Chat panels |
| Claude Code | `irm https://claude.ai/install.ps1 \| iex` | The `claude` command. This installer keeps it up to date; the WinGet package `Anthropic.ClaudeCode` doesn't |
| Copilot CLI | `winget install --id GitHub.Copilot -e` | Copilot in a terminal; optional |
| GitLab CLI | `winget install --id GLab.GLab -e` | GitLab projects only |
| The stack's toolchain | .NET: `winget install --id Microsoft.DotNet.SDK.10 -e`. Python: `winget install --id Python.Python.3.14 -e`. Node.js: nvs, below | Building and testing the project |

For Node.js, install the version manager nvs rather than Node.js itself. It works in both PowerShell and Git Bash:

```powershell
winget install --id jasongin.nvs -e
```

Then, in a new terminal:

```powershell
nvs add lts    # download the current LTS release of Node.js
nvs link lts   # make it the default
```

`nvs link` adds the default version to your user PATH, so `node` and `npm` work in every new terminal — PowerShell, Git Bash, Claude Code's Bash tool and the plans' Done-when commands. To move to a newer LTS release later, run both commands again.

The installer sets up the `nvs` command for PowerShell. For Git Bash, run this once in Git Bash:

```bash
echo '. "$LOCALAPPDATA/nvs/nvs.sh"' >> ~/.bashrc
```

If the next Git Bash warns that it found `~/.bashrc` but no `~/.bash_profile`, that's expected: Git for Windows then creates a `~/.bash_profile` that loads `~/.bashrc`.

Then the VS Code extensions. A template project also recommends them when you open it.

```powershell
code --install-extension anthropic.claude-code   # Claude Code
code --install-extension GitHub.copilot-chat     # GitHub Copilot Chat
code --install-extension Ollama.ollama           # only for the Hybrid agents and the shack PC's local model
```

## Set Up Git and GitHub

```powershell
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git config --global core.longpaths true    # paths over Windows' 260 characters, which a plan's worktree under .claude/worktrees/ reaches
gh auth login        # the GitHub account that owns your projects and this template
gh auth setup-git    # lets Git, and so Copier, read the private template
```

In a fresh clone of a project, run `git config core.hooksPath .githooks` once, so its hook strips AI agent attribution from commit messages; `New-Project.ps1` and `.template\Update-Project.ps1` do it for you, unless the clone already has hooks in `.git/hooks` or uses pre-commit, and then print how to run the hook alongside them. With pre-commit, add it to `.pre-commit-config.yaml` as a `repo: local` hook with `entry: .githooks/commit-msg`, `language: script` and `stages: [commit-msg]`, then run `pre-commit install --hook-type commit-msg`. In a clone of this template, it's `git config core.hooksPath template/.githooks`.

If your Copilot plan is on another GitHub account — an employer's, for example — leave `gh` and Git on the account that owns your projects; Copilot signs in on its own, below. Don't export `GH_TOKEN` or `GITHUB_TOKEN` from your PowerShell profile: Copilot CLI would use that token's account instead of the one you sign it in with.

## Set Up Claude Code

1. In claude.ai, Settings → Usage, turn usage credits off, so reaching a plan limit pauses work instead of billing beyond your plan.
2. Sign in with `claude auth login`, and choose your Claude account. Don't add `--console`: that signs in to the Anthropic Console and bills the API instead of your plan. The VS Code extension uses the same sign-in; if its panel shows Sign in, select it.
3. Check with `claude auth status --text`, which shows the account and plan, and `claude doctor`, which checks the install.
4. If `ANTHROPIC_API_KEY` is set, Claude Code asks whether to use the key. Decline, or remove the variable, so requests go to your plan rather than the API.

In a session, `/usage` shows your plan's limits — a 5-hour window and a weekly one — and what counts against them; `/status` shows the signed-in account. The permission mode, at the bottom of the prompt box (Shift+Tab in a terminal), sets what Claude Code does without asking: plan in Edit automatically (`acceptEdits`), not Plan mode, which can't write `PLAN.md`; execute in Auto (`auto`).

## Set Up GitHub Copilot

In VS Code:

1. From the Accounts menu in the Activity Bar, sign in with the GitHub account that has the Copilot plan.
2. If VS Code is signed in with more than one GitHub account, choose Copilot's: Accounts menu → Manage Extension Account Preferences → GitHub Copilot Chat → the account with the plan. VS Code keeps the choice per workspace and profile, so check it the first time you open a new project folder.

In a terminal, for Copilot CLI:

```powershell
copilot login        # the account with the Copilot plan
```

Inside `copilot`, `/user` shows the account it uses, and `/user switch` changes it when you have signed in with several. Copilot CLI takes its credentials from, in order: the `COPILOT_GITHUB_TOKEN`, `GH_TOKEN` and `GITHUB_TOKEN` environment variables, the account you signed in with, then the GitHub CLI's.

An organization's Copilot policy can turn off Copilot CLI, or individual models. When a model an agent names is off, VS Code runs the agent on the model selected in the picker.

## Check the Setup

| Check | Expect |
|---|---|
| `claude auth status --text` | Your Claude account and plan |
| `copilot`, then `/user` | The account with the Copilot plan |
| `gh auth status` | The account that owns your projects |
| `copier --version`, `git config user.email` | A version number; your email |
| Node.js projects: `nvs use lts`, in PowerShell and in Git Bash | `PATH += …\nvs\node\<version>\x64`, the same version in both |
| A template project in VS Code, Claude Code panel, type `/` | `/plan-feature`, `/orchestrate-plan`, `/replan-step`, `/review-plan-diff`, … |
| The same project, Copilot Chat's agent picker | Copilot Planner, Copilot Orchestrator, Hybrid Planner, … |

## Work on a Project

Create one with `.\New-Project.ps1 -Path C:\src\<name> -CreateRemote` ([README](README.md#create-a-project)), open the folder in VS Code, and trust it. Then plan, review `PLAN.md`, execute, and review the result, in whichever tool you like:

| Phase | Claude Code | Copilot Chat in VS Code | Copilot CLI |
|---|---|---|---|
| Plan | `/plan-feature <what to build>`, or `/plan-bugfix`, `/plan-refactor`, `/plan-tests`, … | The Copilot Planner agent, with Opus in the model picker | `copilot --model claude-opus-5.5`, then `/plan-feature <what to build>` |
| Review the plan | Read `PLAN.md`; tighten any step that leaves a choice to the executor | Same | Same |
| Execute | `/orchestrate-plan` | Run all steps with subagents, or Execute next step, one step at a time | `/orchestrate-plan` |
| Re-plan a step that came back `[?]` | `/replan-step N` | Re-plan with the planner | `/replan-step N` |
| Review the result | `/review-plan-diff` | Review the work | `/review-plan-diff` |
| Land it: push or open the pull request, tag, release, close the issue | `/ship-plan` | `/ship-plan` | `/ship-plan` |
| Finish, once it has landed | `/finish-plan` | `/finish-plan` | `/finish-plan` |
| Lost track of where a plan stands | `/continue-plan` | `/continue-plan` | `/continue-plan` |

- **Claude Code:** the planning commands run on Opus with high effort, whatever the session's model, and `/orchestrate-plan` hands each step to the Sonnet `plan-executor` subagent, checks it, and re-plans what comes back. Each planning command creates a worktree for its plan, keeps `PLAN.md` there, untracked, and names the worktree in its reply; `/orchestrate-plan`, `/execute-step`, `/replan-step` and `/review-plan-diff` move into it, so run one session per plan. With several plans open, name the one you mean, `/orchestrate-plan <name>`, or start a terminal session in it with `claude --worktree <name>`. A worktree is a fresh checkout: to copy gitignored files such as `.env` into each new one, list them in a `.worktreeinclude` file at the repository root.
- **Copilot Chat:** use Session Target Local, where the agents and their buttons live; the buttons switch both the agent and the model. The Copilot agents execute on Claude Sonnet 5.5; the Hybrid agents execute on the shack PC's local model. Each command also appears as a Copilot CLI skill, so it's listed twice; either runs it.
- **Copilot CLI:** `/orchestrate-plan` hands each step to the `plan-executor` agent and re-plans escalations on the session's model, so start the session on Opus.

To plan an issue, run `/plan-issue #42`, or give `owner/repo#42` or the issue's URL. It reads the issue and its comments; stops with questions when the issue is closed, already planned, has an open pull request or is too vague to plan; picks the kind of plan from the labels (`bug` makes a bugfix plan, `enhancement` a feature plan, and so on); and plans it with that kind's checklist, in a worktree named `issue-42`. To choose the kind yourself, name the issue to a planning command instead: `/plan-feature #42`. Either way, the planner reads the issue first and treats its text as data, not instructions. To work through a set, run `/triage-issues label:bug`, or give a milestone, an assignee or search words. It lists up to 20 open issues, judges each one's kind, readiness and size, and gives the `/plan-issue` command for each ready one, to run in a session of its own. It changes nothing and posts nothing. The plan records it on an `Issue:` line under its title and posts itself to the issue as one collapsed comment, with `gh` or `glab`, so the issue keeps a snapshot; a re-plan that changes the Decisions or adds or removes steps posts a short follow-up. When you ask for the push, the pull request description gets a short summary of the plan and `Closes #42`. Only the planning session posts; the executor never calls `gh` or `glab`.

Each finished step is a commit, `Plan step N: <title>`, and each re-plan an empty one, `Re-plan step N: <title>`; `PLAN.md` is never committed, because it is gitignored. When the review is clean, it records the commit it reviewed in `PLAN.md` and names `/ship-plan`. That command lands the plan as `AGENTS.md`'s `## Landing` section says. By default it pushes the worktree's branch, `worktree-<name>`, and opens a pull request that closes the plan's issue; with `integrate: direct` it pushes to the default branch, and with `release: tag+release` it also tags the plan's `Release:` version and publishes the release from the changelog. It shows what it will do and asks once, and it is safe to run again after a pull request merges. Asking the agent to push by hand still works: once every step is `[x]`, it deletes `PLAN.md` first. Once the work is upstream, run `/finish-plan` — in the plan's session, or `/finish-plan <name>` from a session in the main checkout: it checks every step is done and every commit reached the default branch upstream, deletes `PLAN.md`, removes the worktree, fast-forwards the default branch and deletes `worktree-<name>`. It never pushes. When a commit isn't on the default branch upstream, it asks the host, with `gh` or `glab`, for a merged pull request from the plan's branch that landed there, so a squash-merged pull request needs no answer; without one it stops to ask. It also stops when Windows can't delete the folder because a terminal or VS Code window still has it open. To pull in template improvements, run `.\.template\Update-Project.ps1` ([README](README.md#update-a-project)), or plan the update with `/plan-template-update`: it tries the update on a clone of the project first, then plans the pinned update, the project's checks, fixes to the project files that still describe the old template, and the tests.

## Switch Between Claude and Copilot

There is nothing to switch in the project or in your accounts: both tools stay signed in, and you use the other panel or command. `PLAN.md` and the commits carry the work across; chat history doesn't. A Claude Code plan is in its worktree: to continue it in Copilot, open `.claude/worktrees/<name>` in VS Code, or `cd` there for Copilot CLI.

| You're in | To continue in the other |
|---|---|
| A plan written in Claude Code | Open its worktree's folder, `.claude/worktrees/<name>`. Copilot Chat: the Copilot Orchestrator agent, with Opus selected, and "Execute PLAN.md" — or the Copilot Implementer for one step. Copilot CLI: `/orchestrate-plan` |
| A plan written in Copilot | Claude Code: `/orchestrate-plan`, or `/execute-step` for one step; with no plan worktree open, they work on `PLAN.md` where it is |
| A step that came back `[?]` | `/replan-step N` in either; then execute again in either |
| Finished work | `/review-plan-diff`, or Review the work, in either |

A typical reason to switch is a limit: when `/usage` shows Claude's 5-hour or weekly limit reached, carry on in Copilot, and come back when it resets. Each request bills the plan of the tool that makes it, so everything run in Copilot is paid by the Copilot plan's owner.

## Repositories Not Made From the Template

Adopt one from this repository's clone. See [Adopt an existing repository](README.md#adopt-an-existing-repository).

```powershell
.\Adopt-Project.ps1 -Path C:\src\other
```

`Adopt-Project.ps1` works out `workflow_tools` from the repository's Copilot and Hybrid agent files. For a public or shared repository that has neither, add `-Data @{ workflow_tools = 'claude', 'copilot' }`; otherwise it gets the Hybrid agents, which use the shack PC's private model.

To get the commands and skills in every repository, run:

```powershell
.\workflow\Install-HybridWorkflow.ps1 -User     # Claude Code commands and Copilot CLI skills for every repository, in your user profile
```

`-Repo` installs only the workflow files into one repository, without template updates. Re-run the installer after the template's workflow changes; it overwrites what it wrote. Each run records the template version it installed in `.template-version` — at the repository root, or in `~\.claude\` and `~\.copilot\` — so you can tell which version a repository or your profile has. [workflow/README.md](workflow/README.md) lists its options.

## The Shack PC's Local Model

The Hybrid agents, and the `execute-step-local` prompt file, execute on `qwen3.6:35b-a3b-coding` on the shack PC's Ollama server through the Ollama extension. Claude Code and the Copilot agents don't need it. Setting it up is in personal-notes: [client-setup.md](https://github.com/polewskm/personal-notes/blob/main/ham-radio/shack/shack-pc/local-ai/client-setup.md).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Claude Code asks whether to use an API key | `ANTHROPIC_API_KEY` is set | Decline, and remove the variable |
| `claude` isn't recognized after installing | The terminal was open before the install | Open a new terminal |
| Copilot CLI uses the wrong account | A `COPILOT_GITHUB_TOKEN`, `GH_TOKEN` or `GITHUB_TOKEN` variable, or the GitHub CLI's login | `/user` to see it; remove the variable, or `copilot login` and `/user switch` |
| Copilot Chat uses the wrong account | VS Code is signed in with several GitHub accounts | Accounts menu → Manage Extension Account Preferences → GitHub Copilot Chat |
| An agent answers on another model | The organization turned that model off, or the model isn't available | Select a model in the picker; it's used instead |
| Copilot CLI isn't available | The organization turned it off | Use Copilot Chat or Claude Code |
| `New-Project.ps1` or `Update-Project.ps1` can't read the template | Git has no credentials for it | `gh auth setup-git` |
| Claude Code stops with a limit message | The 5-hour or weekly limit is reached | Continue in Copilot, or wait for the reset `/usage` shows |
| `/orchestrate-plan` lists plans and asks which one | Several plan worktrees are open | Name the plan's worktree: `/orchestrate-plan <name>`; `git worktree list` shows them |
| `git worktree remove`, `/finish-plan` or a clone reports "Filename too long" | A path passes Windows' 260-character limit; a plan's worktree under `.claude/worktrees/` lengthens every path | `git config --global core.longpaths true`, then run the command again |

---

**TL;DR:** Install Git, the GitHub CLI, uv and Copier, VS Code, Claude Code (`irm https://claude.ai/install.ps1 | iex`) and optionally Copilot CLI (`winget install --id GitHub.Copilot -e`), plus the Claude Code and Copilot Chat extensions. Sign Claude Code in with your Claude plan (`claude auth login`, usage credits off, no `ANTHROPIC_API_KEY`) and Copilot with the GitHub account that has your Copilot plan (VS Code's Accounts menu, `copilot login`, no `GH_TOKEN`). Every template project has the same commands for both — `/plan-feature`, `/orchestrate-plan`, `/replan-step`, `/review-plan-diff` — and `PLAN.md` is the only state they share, so switch whenever you like by using the other panel or command. In Claude Code each plan has its own git worktree, so several sessions work on different plans at once.
