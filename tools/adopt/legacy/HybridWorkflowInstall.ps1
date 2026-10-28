<#
.SYNOPSIS
    Legacy adapter for repositories set up by an older Install-HybridWorkflow.ps1.

.DESCRIPTION
    Handles a repository that has .github\prompts\execute-step-copilot.prompt.md. The template's Copilot prompt is
    execute-step.prompt.md, so the older file is deleted.

    Contract: Adopt-Project.ps1 runs every script in tools\adopt\legacy with -Phase Detect. For each that returns $true,
    it adds the -Phase Answers hashtable to the answers before Copier runs and runs -Phase Apply after, printing
    the lines Apply returns.

.EXAMPLE
    .\HybridWorkflowInstall.ps1 -Path C:\src\app -Phase Detect
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][ValidateSet('Detect', 'Answers', 'Apply')][string]$Phase
)
$ErrorActionPreference = 'Stop'

$file = Join-Path $Path '.github\prompts\execute-step-copilot.prompt.md'

switch ($Phase) {
    'Detect' { [bool](Test-Path -LiteralPath $file -PathType Leaf) }
    'Answers' { @{} }
    'Apply' {
        Remove-Item -LiteralPath $file -Force
        'Removed .github/prompts/execute-step-copilot.prompt.md, an older Install-HybridWorkflow.ps1 name; the template''s Copilot prompt is execute-step.prompt.md.'
    }
}
