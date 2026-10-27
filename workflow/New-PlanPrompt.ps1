<#
.SYNOPSIS
    Compose a plan-and-execute prompt from a template, for pasting into any AI tool.

.DESCRIPTION
    Reads a template from templates\, appends the PLAN.md format for planning templates, fills in
    the task, and prints the prompt (or copies it with -Copy). -List shows each template's role, the installer targets it goes to, and its description. Use it for manual handoffs: paste into
    Claude Code, claude.ai, Copilot Chat or Copilot CLI (`copilot -i (.\New-PlanPrompt.ps1 ...)`).

.EXAMPLE
    .\New-PlanPrompt.ps1 -List
    .\New-PlanPrompt.ps1 plan-feature "Add CSV export to the QSO log viewer" -Copy
    .\New-PlanPrompt.ps1 execute-step 3
#>
param(
    [Parameter(Position = 0)][string]$Template,
    [Parameter(Position = 1)][string]$Task = '',
    [switch]$Copy,
    [switch]$List
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'HybridWorkflow.psm1') -Force

if ($List -or -not $Template) {
    Get-HybridTemplateList | Format-Table Name, Role, @{ Name = 'Targets'; Expression = { $_.Targets -join ', ' } }, Description -AutoSize | Out-String -Width 200
    return
}

$prompt = Get-HybridPromptText -Name $Template -Placeholder $Task
if ($Copy) {
    Set-Clipboard -Value $prompt
    "Copied '$Template' prompt ($($prompt.Length) characters) to the clipboard."
}
else { $prompt }
