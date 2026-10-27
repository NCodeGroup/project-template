<#
.SYNOPSIS
    Install the plan-and-execute workflow into a repository or your user profile.

.DESCRIPTION
    Safe to re-run; overwrites the files it generates from templates\.

    Variants (VS Code agents):
      Local    Hybrid Planner / Local Implementer / Hybrid Reviewer / Hybrid Orchestrator
               — Opus plans and reviews, the shack PC's local model executes.
      Copilot  Copilot Planner / Copilot Implementer / Copilot Reviewer / Copilot Orchestrator
               — Opus plans and reviews, Claude Sonnet 5.5 executes (-CopilotExecutorModel).

    Targets and where they write:
      VSCode      -Repo: .github\agents\<variant agents>.agent.md, .github\prompts\<template>.prompt.md
                  -User: ~\.copilot\agents (Copilot harness)
      Claude      -Repo: .claude\commands\<template>.md, .claude\agents\plan-executor.md
                  -User: ~\.claude\commands, ~\.claude\agents
      CopilotCli  -Repo: .github\skills\<template>\SKILL.md, .github\agents\plan-executor.agent.md
                  -User: ~\.copilot\skills, ~\.copilot\agents

    Version file: records the template version it installed in .template-version, one line: git describe of this
    clone (the newest v* tag, -<n>-g<sha> past it, -dirty with uncommitted changes), or "unknown" outside a Git
    checkout. -Repo writes it at the repository root; -User writes it in ~\.claude\ (Claude) and ~\.copilot\
    (VSCode, CopilotCli). -NoVersionMarker skips it, as tools\Update-Template.ps1 does, because a project made
    from the template renders its own .template-version from .copier-answers.yml.

    The installer also writes Get-PlanState.ps1, which /ship-plan, /continue-plan and /finish-plan run, to .template\ (-Repo), or to ~\.claude\ and ~\.copilot\ (-User).

    Claude Code commands of templates with a "worktree" field start with a section that puts the plan in a git worktree of its own (create), moves the session into it (join), or removes it once the work is pushed (finish): templates\_claude-worktree-*.md.

    A template's "targets" field limits it to the targets it names, such as "targets: Claude" for run-issues, which only Claude Code gets; without it a template goes to every target.

    VS Code model names use "<model name> (<vendor>)"; the Settings dropdown for
    chat.planAgent.defaultModel lists the exact names. Copilot CLI uses model IDs such as
    claude-sonnet-5.5 (see `copilot help config`); Claude Code uses aliases such as sonnet or full model IDs such as claude-sonnet-5-5.

.EXAMPLE
    .\Install-HybridWorkflow.ps1 -User
    .\Install-HybridWorkflow.ps1 -Repo C:\src\my-project
    .\Install-HybridWorkflow.ps1 -Repo . -Variant Copilot -CopilotExecutorModel 'Claude Haiku 5.5 (copilot)'
#>
param(
    [string]$Repo,
    [switch]$User,
    [ValidateSet('Local', 'Copilot', 'Both')][string]$Variant = 'Both',
    [ValidateSet('VSCode', 'Claude', 'CopilotCli')][string[]]$Target = @('VSCode', 'Claude', 'CopilotCli'),
    [string]$PlannerModel = 'Claude Opus 5.5 (copilot)',
    [string]$ReviewerModel = 'Claude Sonnet 5.5 (copilot)',
    [string]$LocalModel = 'qwen3.6:35b-a3b-coding (ollama-models)',
    [string]$FastLocalModel = 'ornith:9b (ollama-models)',
    [string]$CopilotExecutorModel = 'Claude Sonnet 5.5 (copilot)',
    [string]$CopilotFastModel = 'Claude Haiku 5.5 (copilot)',
    [string]$ClaudeExecutorModel = 'claude-sonnet-5-5',
    [string]$CliExecutorModel = 'claude-sonnet-5.5',
    [switch]$NoVersionMarker
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'HybridWorkflow.psm1') -Force
if (-not $Repo -and -not $User) { throw 'Specify -Repo <path>, -User, or both.' }
$templateDir = Get-HybridTemplateDir

$utf8 = New-Object Text.UTF8Encoding $false
$written = [Collections.Generic.List[string]]::new()
function Q([string]$s) { '"' + $s.Replace('\', '\\').Replace('"', '\"') + '"' }
function Write-Generated([string]$Path, [string]$Content) {
    New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
    [IO.File]::WriteAllText($Path, ($Content.TrimEnd() + "`n"), $utf8)
    $written.Add($Path)
}
function Expand-Token([string]$Text, [hashtable]$Tokens) {
    foreach ($k in $Tokens.Keys) { $Text = $Text.Replace("{{$k}}", [string]$Tokens[$k]) }
    $Text
}
# Renders an agent-style template: front matter tokens, then includes in the body.
function Get-RenderedFile([string]$Path, [hashtable]$Tokens) {
    $f = Read-HybridTemplateFile $Path
    Expand-Token "---`n$($f.FrontMatter)`n---`n$(Expand-HybridInclude $f.Body)" $Tokens
}
# The template version of this clone: the newest v* tag, -<n>-g<sha> past it, -dirty with uncommitted changes.
function Get-TemplateVersion {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return 'unknown' }
    $version = git -C $PSScriptRoot describe --tags --always --dirty --match 'v[0-9]*' 2>$null
    if ($LASTEXITCODE -or -not $version) { return 'unknown' }
    "$version".Trim()
}

$variants = [ordered]@{}
if ($Variant -in 'Local', 'Both') {
    $variants.Local = @{
        Tokens = @{
            PLANNER_AGENT = 'Hybrid Planner'; IMPLEMENTER_AGENT = 'Local Implementer'; REVIEWER_AGENT = 'Hybrid Reviewer'; ORCHESTRATOR_AGENT = 'Hybrid Orchestrator'
            EXECUTOR_LABEL = 'the local model on the shack PC'; EXECUTOR_MODEL = $LocalModel; FAST_EXECUTOR_MODEL = $FastLocalModel
        }
        Files  = @{ planner = 'hybrid-planner'; implementer = 'local-implementer'; reviewer = 'hybrid-reviewer'; orchestrator = 'hybrid-orchestrator' }
    }
}
if ($Variant -in 'Copilot', 'Both') {
    $variants.Copilot = @{
        Tokens = @{
            PLANNER_AGENT = 'Copilot Planner'; IMPLEMENTER_AGENT = 'Copilot Implementer'; REVIEWER_AGENT = 'Copilot Reviewer'; ORCHESTRATOR_AGENT = 'Copilot Orchestrator'
            EXECUTOR_LABEL = ($CopilotExecutorModel -replace '\s*\([^)]*\)\s*$', ''); EXECUTOR_MODEL = $CopilotExecutorModel; FAST_EXECUTOR_MODEL = $CopilotFastModel
        }
        Files  = @{ planner = 'copilot-planner'; implementer = 'copilot-implementer'; reviewer = 'copilot-reviewer'; orchestrator = 'copilot-orchestrator' }
    }
}
foreach ($v in $variants.Values) { $v.Tokens.PLANNER_MODEL = $PlannerModel; $v.Tokens.REVIEWER_MODEL = $ReviewerModel }

$claudeRole = @{
    planner      = "model: opus`neffort: high"
    analyst      = "model: opus`neffort: high"
    orchestrator = "model: opus`neffort: high"
    reviewer     = "model: sonnet`neffort: high"
    executor     = 'model: inherit'
}
# Claude Code only: the section that puts a plan in a worktree of its own (create), moves the session to it (join), or removes it (finish).
function Get-ClaudeWorktreeSection([string]$Kind) {
    $path = Join-Path $templateDir "_claude-worktree-$Kind.md"
    if (-not (Test-Path -LiteralPath $path)) { throw "Unknown worktree value '$Kind'; use create, join or finish." }
    (Read-HybridTemplateFile $path).Body.TrimEnd()
}
$vscodeModel = @{ planner = $PlannerModel; analyst = $PlannerModel; orchestrator = $PlannerModel; reviewer = $ReviewerModel }
$skillInput = 'the request given after the command name'

$templates = Get-HybridTemplateList
$agentTemplates = Get-ChildItem $templateDir -Filter '*.agent.md' -File

$dest = @()
if ($Repo) {
    $root = (Resolve-Path $Repo).Path
    $dest += [pscustomobject]@{ Scope = 'repo'; Agents = "$root\.github\agents"; Prompts = "$root\.github\prompts"; Skills = "$root\.github\skills"; ClaudeCommands = "$root\.claude\commands"; ClaudeAgents = "$root\.claude\agents"; CopilotVersionFile = "$root\.template-version"; ClaudeVersionFile = "$root\.template-version"; ClaudeStateFile = "$root\.template\Get-PlanState.ps1"; CopilotStateFile = "$root\.template\Get-PlanState.ps1"; ClaudeStateScript = 'pwsh -NoProfile -File .template/Get-PlanState.ps1'; CopilotStateScript = 'pwsh -NoProfile -File .template/Get-PlanState.ps1' }
}
if ($User) {
    $dest += [pscustomobject]@{ Scope = 'user'; Agents = "$HOME\.copilot\agents"; Prompts = $null; Skills = "$HOME\.copilot\skills"; ClaudeCommands = "$HOME\.claude\commands"; ClaudeAgents = "$HOME\.claude\agents"; CopilotVersionFile = "$HOME\.copilot\.template-version"; ClaudeVersionFile = "$HOME\.claude\.template-version"; ClaudeStateFile = "$HOME\.claude\Get-PlanState.ps1"; CopilotStateFile = "$HOME\.copilot\Get-PlanState.ps1"; ClaudeStateScript = 'pwsh -NoProfile -File "$HOME/.claude/Get-PlanState.ps1"'; CopilotStateScript = 'pwsh -NoProfile -File "$HOME/.copilot/Get-PlanState.ps1"' }
}

$version = if (-not $NoVersionMarker) { Get-TemplateVersion }
foreach ($d in $dest) {
    if ('VSCode' -in $Target) {
        foreach ($v in $variants.Values) {
            foreach ($a in $agentTemplates) {
                $role = $a.Name -replace '\.agent\.md$'
                Write-Generated (Join-Path $d.Agents "$($v.Files[$role]).agent.md") (Get-RenderedFile $a.FullName $v.Tokens)
            }
        }
        if ($d.Prompts) {
            foreach ($t in $templates) {
                if ('VSCode' -notin $t.Targets) { continue }
                $promptModels = [Collections.Generic.List[object]]::new()
                if ($t.Role -ne 'executor') { $promptModels.Add([pscustomobject]@{ Suffix = ''; Model = $vscodeModel[$t.Role] }) }
                else {
                    if ($variants.Copilot) { $promptModels.Add([pscustomobject]@{ Suffix = ''; Model = $CopilotExecutorModel }) }
                    if ($variants.Local) { $promptModels.Add([pscustomobject]@{ Suffix = $(if ($variants.Copilot) { '-local' } else { '' }); Model = $LocalModel }) }
                }
                foreach ($m in $promptModels) {
                    $body = Get-HybridPromptText -Name $t.Name -Placeholder "`${input:details:$($t.ArgumentHint)}" -StateScript $d.CopilotStateScript
                    $fm = "---`ndescription: $(Q $t.Description)`nargument-hint: $(Q $t.ArgumentHint)`nagent: agent`nmodel: $(Q $m.Model)`n---`n"
                    Write-Generated (Join-Path $d.Prompts "$($t.Name)$($m.Suffix).prompt.md") ($fm + $body)
                }
            }
        }
    }
    if ('Claude' -in $Target) {
        foreach ($t in $templates) {
            if ('Claude' -notin $t.Targets) { continue }
            $body = Get-HybridPromptText -Name $t.Name -Placeholder '$ARGUMENTS' -StateScript $d.ClaudeStateScript
            $hint = $t.ArgumentHint
            if ($t.Worktree) { $body = (Get-ClaudeWorktreeSection $t.Worktree) + "`n`n## Task`n`n" + $body }
            if ($t.Worktree -in 'join', 'finish') { $hint += "; the plan's worktree name when several are open" }
            $fm = "---`ndescription: $(Q $t.Description)`nargument-hint: $(Q "[$hint]")`n$($claudeRole[$t.Role])`ndisable-model-invocation: true`n---`n"
            Write-Generated (Join-Path $d.ClaudeCommands "$($t.Name).md") ($fm + $body)
        }
        Write-Generated (Join-Path $d.ClaudeAgents 'plan-executor.md') (Get-RenderedFile "$templateDir\plan-executor.claude.md" @{ CLAUDE_EXECUTOR_MODEL = $ClaudeExecutorModel })
    }
    if ('CopilotCli' -in $Target) {
        foreach ($t in $templates) {
            if ('CopilotCli' -notin $t.Targets) { continue }
            $body = Get-HybridPromptText -Name $t.Name -Placeholder $skillInput -StateScript $d.CopilotStateScript
            $fm = "---`nname: $($t.Name)`ndescription: $(Q $t.Description)`n---`n"
            Write-Generated (Join-Path $d.Skills "$($t.Name)\SKILL.md") ($fm + $body)
        }
        Write-Generated (Join-Path $d.Agents 'plan-executor.agent.md') (Get-RenderedFile "$templateDir\plan-executor.cli.md" @{ CLI_EXECUTOR_MODEL = $CliExecutorModel })
    }
    $stateFiles = @(
        if ('VSCode' -in $Target -or 'CopilotCli' -in $Target) { $d.CopilotStateFile }
        if ('Claude' -in $Target) { $d.ClaudeStateFile }
    ) | Select-Object -Unique
    foreach ($file in $stateFiles) { Write-Generated $file ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Get-PlanState.ps1'))) }
    if ($version) {
        $versionFiles = @(
            if ('VSCode' -in $Target -or 'CopilotCli' -in $Target) { $d.CopilotVersionFile }
            if ('Claude' -in $Target) { $d.ClaudeVersionFile }
        ) | Select-Object -Unique
        foreach ($file in $versionFiles) { Write-Generated $file $version }
    }
}

"Wrote $($written.Count) files (variant: $Variant; targets: $($Target -join ', ')):"
$written | ForEach-Object { "  $_" }
