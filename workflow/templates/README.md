# Plan-and-Execute Templates

Source templates for the plan-and-execute workflow — the single source of truth for every prompt and agent file. They are tool-neutral: [Install-HybridWorkflow.ps1](../Install-HybridWorkflow.ps1) turns them into Claude Code commands and subagents, VS Code prompt files and custom agents, and Copilot CLI skills and agents; [New-PlanPrompt.ps1](../New-PlanPrompt.ps1) composes them for pasting into any chat; [Invoke-PlanSteps.ps1](../Invoke-PlanSteps.ps1) runs `execute-step` and `replan-step` from them. The workflow itself, and how to choose between its variants, is in personal-notes' [plan-and-execute.md](https://github.com/polewskm/personal-notes/blob/main/ham-radio/shack/shack-pc/local-ai/plan-and-execute.md).

## Prompt Templates

Each prompt has a small front-matter header (`description`, `argument-hint`, `role`, `append-format`) and a body with one `{{INPUT}}` placeholder for your request. Planning templates with `append-format: true` get [_plan-format.md](_plan-format.md) appended, so every plan comes out in the same parseable shape.

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
| [replan-step.md](replan-step.md) | planner | Updated `PLAN.md` | Re-plan a step the executor escalated (`[?]`) or failed (`[!]`), then hand it back |
| [orchestrate-plan.md](orchestrate-plan.md) | orchestrator | Commits, updated `PLAN.md` | Run the whole plan in one session: the strong model verifies and re-plans, a cheaper subagent executes |
| [analyze-architecture.md](analyze-architecture.md) | analyst | `ANALYSIS.md` | Explain a codebase or subsystem with evidence, risks and follow-ups |
| [analyze-decision.md](analyze-decision.md) | analyst | ADR file | Compare options for a design decision and record it |
| [review-code.md](review-code.md) | reviewer | Findings in chat | Review a branch, PR or folder in depth |
| [review-plan-diff.md](review-plan-diff.md) | reviewer | Fix steps in `PLAN.md` | Check the executor's work against the plan |
| [execute-step.md](execute-step.md) | executor | Code changes or an escalation | Run one step on the cheap model; escalate with `[?]` instead of improvising |

| Role | Claude Code command | VS Code prompt file model | Copilot CLI skill |
|---|---|---|---|
| planner, analyst, orchestrator | `model: opus`, `effort: high` | Planner model (Opus 5.5) | Session model — start the session on Opus |
| reviewer | `model: sonnet`, `effort: high` | Reviewer model (Sonnet 5.5) | Session model |
| executor | `model: inherit` (the session's model) | Local model, plus `execute-step-copilot` on the Copilot executor model | Session model |

## Agent Templates

The four VS Code agent templates are variant-neutral; the installer renders each into a Local set and a Copilot set:

| Template | Local variant (`-Variant Local`) | Copilot variant (`-Variant Copilot`) | Does |
|---|---|---|---|
| [planner.agent.md](planner.agent.md) | Hybrid Planner | Copilot Planner | Plans on Opus, re-plans steps that come back; buttons to execute, execute fast, or run all |
| [implementer.agent.md](implementer.agent.md) | Local Implementer (qwen3.6) | Copilot Implementer (Auto) | Executes one step, escalates with `[?]`; buttons for next step, re-plan with the planner, review |
| [reviewer.agent.md](reviewer.agent.md) | Hybrid Reviewer | Copilot Reviewer | Reviews on Sonnet and queues fix steps; buttons to execute the fixes or re-plan |
| [orchestrator.agent.md](orchestrator.agent.md) | Hybrid Orchestrator | Copilot Orchestrator | Opus runs every step through implementer subagents, verifies each, re-plans escalations itself |

| Template | Installed as | For |
|---|---|---|
| [plan-executor.claude.md](plan-executor.claude.md) | `.claude/agents/plan-executor.md` | Claude Code subagent (`model: sonnet` by default) that `orchestrate-plan` delegates to |
| [plan-executor.cli.md](plan-executor.cli.md) | `.github/agents/plan-executor.agent.md` | Copilot CLI custom agent (`model: claude-sonnet-5.5` by default) that `orchestrate-plan` delegates to |

## Other Files

| File | Purpose |
|---|---|
| [_plan-format.md](_plan-format.md) | The PLAN.md handoff contract: writing rules for a weaker executor plus the exact Markdown structure the step runner parses |
| [PLAN.example.md](PLAN.example.md) | A complete three-step plan for the demo project that personal-notes' `New-AgentTestRepo.ps1` creates — the format in practice, and the runner's test fixture |

## Template Syntax

| Token | Where | Replaced with |
|---|---|---|
| `{{INPUT}}` | Prompt bodies | Your request; `$ARGUMENTS` in Claude Code commands; `${input:details:<hint>}` in VS Code prompt files; a description of the command's argument in Copilot CLI skills |
| `{{PROMPT:name\|input}}` | Agent bodies | The body of prompt `name` with `{{INPUT}}` set to `input` |
| `{{PLANNER_AGENT}}`, `{{IMPLEMENTER_AGENT}}`, `{{REVIEWER_AGENT}}`, `{{ORCHESTRATOR_AGENT}}`, `{{EXECUTOR_LABEL}}` | Agent templates | Agent names and the executor description for the variant being installed |
| `{{PLANNER_MODEL}}`, `{{REVIEWER_MODEL}}`, `{{EXECUTOR_MODEL}}`, `{{FAST_EXECUTOR_MODEL}}` | Agent front matter | `-PlannerModel`, `-ReviewerModel`, and `-LocalModel`/`-FastLocalModel` (Local) or `-CopilotExecutorModel`/`-CopilotFastModel` (Copilot) |
| `{{CLAUDE_EXECUTOR_MODEL}}`, `{{CLI_EXECUTOR_MODEL}}` | `plan-executor` templates | `-ClaudeExecutorModel`, `-CliExecutorModel` |

To add a prompt template, create `<name>.md` with the same four header fields; `New-PlanPrompt.ps1 -List` and the installer pick it up automatically.

New projects get generated copies of these files under `template/` ([What a Project Gets](../../README.md#what-a-project-gets)). After changing a template here, run `Update-Template.ps1` and `Test-Template.ps1` at the repository root, then commit, tag and push a new version; projects pick it up with `Update-Project.ps1`.

---

**TL;DR:** Sixteen prompts (planning, analysis, review, orchestration, re-planning, execution) and four variant-neutral VS Code agents, written once and installed into Claude Code, VS Code and Copilot CLI by `Install-HybridWorkflow.ps1`. Every planning prompt ends with the same PLAN.md contract, and the executor prompt escalates with `[?]` instead of improvising, so any planner and any executor can be combined.
