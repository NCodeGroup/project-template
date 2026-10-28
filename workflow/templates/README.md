# Plan-and-Execute Templates

Source templates for the plan-and-execute workflow — the single source of truth for every prompt and agent file. They are tool-neutral: [Install-HybridWorkflow.ps1](../Install-HybridWorkflow.ps1) turns them into Claude Code commands and subagents, VS Code prompt files and custom agents, and Copilot CLI skills and agents; [New-PlanPrompt.ps1](../New-PlanPrompt.ps1) composes them for pasting into any chat; [Invoke-PlanSteps.ps1](../Invoke-PlanSteps.ps1) runs `execute-step` and `replan-step` from them. The workflow itself, and how to choose between its variants, is in personal-notes' [plan-and-execute.md](https://github.com/polewskm/personal-notes/blob/main/ham-radio/shack/shack-pc/local-ai/plan-and-execute.md).

## Prompt Templates

Each prompt has a small front-matter header (`description`, `argument-hint`, `role`, `append-format`, and optionally `worktree`, `targets` and `command`) and a body with one `{{INPUT}}` placeholder for your request. Planning templates with `append-format: true` get [_plan-format.md](_plan-format.md) appended, so every plan comes out in the same parseable shape. `targets: Claude` limits a template to the installer targets it names, comma-separated from `VSCode`, `Claude` and `CopilotCli`; without it a template goes to all three. `New-PlanPrompt.ps1 -List` shows each template's targets. `command` names the command, prompt file and skill a template installs as, when that differs from its file name: `run-issues-copilot.md` has `targets: VSCode, CopilotCli` and `command: run-issues`, so `/run-issues` runs it in Copilot while `run-issues.md` stays Claude Code's. The installer stops when two templates install the same command for the same target.

| Template | Role | Produces | Use it to |
|---|---|---|---|
| [plan-feature.md](plan-feature.md) | planner | `PLAN.md` | Build something new |
| [plan-bugfix.md](plan-bugfix.md) | planner | `PLAN.md` | Reproduce, prove the root cause, fix test-first |
| [plan-refactor.md](plan-refactor.md) | planner | `PLAN.md` | Restructure without changing behavior |
| [plan-tests.md](plan-tests.md) | planner | `PLAN.md` | Cover risky, untested code |
| [plan-migration.md](plan-migration.md) | planner | `PLAN.md` | Upgrade a dependency, framework or API |
| [plan-performance.md](plan-performance.md) | planner | `PLAN.md` | Measure, then optimize with a benchmark gate |
| [plan-security.md](plan-security.md) | planner | `PLAN.md` | Find weaknesses and harden with proof tests |
| [plan-docs.md](plan-docs.md) | planner | `PLAN.md` | Supply the facts so the executor writes the docs |
| [handoff-plan.md](handoff-plan.md) | planner | `PLAN.md` | Convert a plan already discussed in chat (plan mode, the Plan agent) into the handoff |
| [plan-issue.md](plan-issue.md) | planner | `PLAN.md` | Plan one GitHub or GitLab issue, or up to three related ones in one plan: read it and its comments, check that it's ready, pick the kind of plan from its labels, and plan it with that kind's checklist |
| [plan-template-update.md](plan-template-update.md) | planner | `PLAN.md` | Update the project to a newer template version: read the release notes, try `Update-Project.ps1` on a clone, and plan the pinned update, the checks, the project files that still describe the old template, and the gate |
| [replan-step.md](replan-step.md) | planner | Updated `PLAN.md` | Re-plan a step the executor escalated (`[?]`) or failed (`[!]`), then hand it back |
| [orchestrate-plan.md](orchestrate-plan.md) | orchestrator | Commits, updated `PLAN.md` | Run the whole plan in one session: the strong model verifies and re-plans, a cheaper subagent executes |
| [run-issues.md](run-issues.md) | orchestrator | Draft pull requests, replies to review threads and comments, landed plans, a table in chat | Claude Code: take the issues a request names, or the ready groups a filter finds, from plan to landing one at a time, running the next ahead while a pull request waits — plan, execute, review, open a draft pull request, answer my review threads and comments, and land it once I merge; runs only when the default branch takes changes through pull requests alone |
| [run-issues-copilot.md](run-issues-copilot.md) | orchestrator | Draft pull requests, replies to review threads and comments, landed plans, a table in chat | Copilot Chat and Copilot CLI, installed as `run-issues`: the same autopilot in the open folder, one entry at a time, each on a branch `issue-<number>`, without running ahead; it plans and reviews in subagents and executes in its own session |
| [analyze-architecture.md](analyze-architecture.md) | analyst | `ANALYSIS.md` | Explain a codebase or subsystem with evidence, risks and follow-ups |
| [analyze-decision.md](analyze-decision.md) | analyst | ADR file | Compare options for a design decision and record it |
| [triage-issues.md](triage-issues.md) | analyst | Findings in chat | List a set of open issues (a label, a milestone, a search), judge which are ready to plan, and group overlapping ones, at most three, and give one `/plan-issue` command per group |
| [review-code.md](review-code.md) | reviewer | Findings in chat | Review a branch, PR or folder in depth |
| [review-plan-diff.md](review-plan-diff.md) | reviewer | Fix steps in `PLAN.md` | Check the executor's work against the plan |
| [ship-plan.md](ship-plan.md) | reviewer | Pushed commits or a pull request, a tag, a release, closed issues | Land a reviewed plan as `AGENTS.md`'s Landing section says, in stages that skip what's done, so it can run again after a pull request merges |
| [continue-plan.md](continue-plan.md) | reviewer | A table in chat | Show where each open plan stands and the one command to run next; changes nothing |
| [finish-plan.md](finish-plan.md) | reviewer | Deleted `PLAN.md`, a fast-forwarded default branch | Close a plan whose work is pushed or merged: retire it, update the default branch, delete its branch and, in Claude Code, its worktree |
| [execute-step.md](execute-step.md) | executor | Code changes or an escalation | Run one step on the cheap model; escalate with `[?]` instead of improvising |

| Role | Claude Code command | VS Code prompt file model | Copilot CLI skill |
|---|---|---|---|
| planner, analyst, orchestrator | `model: opus`, `effort: high` | Planner model (Opus 5.5) | Session model — start the session on Opus |
| reviewer | `model: sonnet`, `effort: high` | Reviewer model (Sonnet 5.5) | Session model |
| executor | `model: inherit` (the session's model) | Copilot executor model (`execute-step`), plus `execute-step-local` on the local model when both variants are installed | Session model |

### Claude Code Plan Worktrees

In Claude Code only, each plan lives in its own git worktree, so several sessions can work on different plans on one machine at once. A template's `worktree` field says what its Claude Code command does with the plan's worktree. The installer puts the matching section before the command's body, followed by a `## Task` heading:

| `worktree` | Section | Templates | The command |
|---|---|---|---|
| `create` | [_claude-worktree-create.md](_claude-worktree-create.md) | The `plan-*` templates and `handoff-plan` | Creates `.claude/worktrees/<name>/` with the `EnterWorktree` tool before it researches, plans there, keeps `PLAN.md` untracked, and marks the worktree with an empty `Plan: <title>` commit so Claude Code asks before removing it |
| `join` | [_claude-worktree-join.md](_claude-worktree-join.md) | `orchestrate-plan`, `execute-step`, `replan-step`, `review-plan-diff`, `ship-plan` | Moves the session into the plan's worktree — the one its arguments name, or the only one — before it starts; with no plan worktree, works on a `PLAN.md` in the current checkout |
| `finish` | [_claude-worktree-finish.md](_claude-worktree-finish.md) | `finish-plan` | Finds the plan's worktree — the session's own, the one its arguments name, or the only one — without entering it, removes it with the `ExitWorktree` tool or `git worktree remove`, clears a stale lock or a leftover folder, including one Windows' path limit left behind, and fast-forwards the default branch in the main checkout |

A command without the field works where the session is. `run-issues` has no field: it makes each issue's worktree itself with `git worktree add`, enters it with `EnterWorktree` and its `path`, and removes it through `finish-plan`. `run-issues-copilot` has none either: it works in the open folder, on a branch `issue-<number>` per entry. VS Code prompt files, Copilot CLI skills, the agents and `New-PlanPrompt.ps1` never get a section. The `plan-executor` subagent inherits the orchestrator's worktree; `isolation: worktree` would give it a worktree of its own instead.

## Agent Templates

The four VS Code agent templates are variant-neutral; the installer renders each into a Local set and a Copilot set:

| Template | Local variant (`-Variant Local`) | Copilot variant (`-Variant Copilot`) | Does |
|---|---|---|---|
| [planner.agent.md](planner.agent.md) | Hybrid Planner | Copilot Planner | Plans on Opus, re-plans steps that come back; buttons to execute, execute fast, or run all |
| [implementer.agent.md](implementer.agent.md) | Local Implementer (qwen3.6) | Copilot Implementer (Claude Sonnet 5.5) | Executes one step, escalates with `[?]`; buttons for next step, re-plan with the planner, review |
| [reviewer.agent.md](reviewer.agent.md) | Hybrid Reviewer | Copilot Reviewer | Reviews on Sonnet and queues fix steps; buttons to execute the fixes, re-plan, land the plan with `/ship-plan`, or show where it stands with `/continue-plan` |
| [orchestrator.agent.md](orchestrator.agent.md) | Hybrid Orchestrator | Copilot Orchestrator | Opus runs every step through implementer subagents, verifies each, re-plans escalations itself |

| Template | Installed as | For |
|---|---|---|
| [plan-executor.claude.md](plan-executor.claude.md) | `.claude/agents/plan-executor.md` | Claude Code subagent (`model: claude-sonnet-5-5` by default) that `orchestrate-plan` delegates to |
| [plan-executor.cli.md](plan-executor.cli.md) | `.github/agents/plan-executor.agent.md` | Copilot CLI custom agent (`model: claude-sonnet-5.5` by default) that `orchestrate-plan` delegates to |

## Other Files

| File | Purpose |
|---|---|
| [_plan-format.md](_plan-format.md) | The PLAN.md handoff contract: writing rules for a weaker executor plus the exact Markdown structure the step runner parses |
| [_issue-kinds.md](_issue-kinds.md) | The table that maps an issue's labels to a kind of plan, included in `plan-issue` and `triage-issues` |
| [PLAN.example.md](PLAN.example.md) | A complete three-step plan for the demo project that personal-notes' `New-AgentTestRepo.ps1` creates — the format in practice, and the runner's test fixture |
| [_claude-worktree-create.md](_claude-worktree-create.md), [_claude-worktree-join.md](_claude-worktree-join.md), [_claude-worktree-finish.md](_claude-worktree-finish.md) | The Claude Code plan-worktree sections ([Claude Code Plan Worktrees](#claude-code-plan-worktrees)) |

## Template Syntax

| Token | Where | Replaced with |
|---|---|---|
| `{{INPUT}}` | Prompt bodies | Your request; `$ARGUMENTS` in Claude Code commands; `${input:details:<hint>}` in VS Code prompt files; a description of the command's argument in Copilot CLI skills |
| `{{PROMPT:name\|input}}` | Agent bodies | The body of prompt `name` with `{{INPUT}}` set to `input` |
| `{{BODY:name\|input}}` | Prompt bodies | The body of prompt `name` with `{{INPUT}}` set to `input`, without the plan format; `plan-issue` uses it to include each `plan-*` checklist |
| `{{PLANNER_AGENT}}`, `{{IMPLEMENTER_AGENT}}`, `{{REVIEWER_AGENT}}`, `{{ORCHESTRATOR_AGENT}}`, `{{EXECUTOR_LABEL}}` | Agent templates | Agent names and the executor description for the variant being installed |
| `{{PLANNER_MODEL}}`, `{{REVIEWER_MODEL}}`, `{{EXECUTOR_MODEL}}`, `{{FAST_EXECUTOR_MODEL}}` | Agent front matter | `-PlannerModel`, `-ReviewerModel`, and `-LocalModel`/`-FastLocalModel` (Local) or `-CopilotExecutorModel`/`-CopilotFastModel` (Copilot) |
| `{{CLAUDE_EXECUTOR_MODEL}}`, `{{CLI_EXECUTOR_MODEL}}` | `plan-executor` templates | `-ClaudeExecutorModel`, `-CliExecutorModel` |
| `{{STATE_SCRIPT}}` | Prompt bodies | The command that runs `Get-PlanState.ps1`: `pwsh -NoProfile -File .template/Get-PlanState.ps1`, or the copy in `~\.claude\` or `~\.copilot\` for `-User` |

To add a prompt template, create `<name>.md` with the same four header fields, plus `worktree: create` when its Claude Code command writes a new `PLAN.md`, `worktree: join` when it works on one, or `worktree: finish` when it closes one; `New-PlanPrompt.ps1 -List` and the installer pick it up automatically.

New projects get generated copies of these files under `template/` ([What a Project Gets](../../README.md#what-a-project-gets)). After changing a template here, run `tools/Update-Template.ps1` and `tests/Test-Template.ps1` from the repository root, then commit, tag and push a new version; projects pick it up with `Update-Project.ps1`.

---

**TL;DR:** Twenty-four prompts (planning, issue triage, template updates, analysis, review, orchestration, autopilot, re-planning, execution, finishing) and four variant-neutral VS Code agents, written once and installed into Claude Code, VS Code and Copilot CLI by `Install-HybridWorkflow.ps1`. Every planning prompt ends with the same PLAN.md contract, and the executor prompt escalates with `[?]` instead of improvising, so any planner and any executor can be combined.
