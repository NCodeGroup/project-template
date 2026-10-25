<#
.SYNOPSIS
    Regenerate the workflow files in template/ and at the repository root from the source templates in
    workflow/templates.

.DESCRIPTION
    Deletes the generated folders and re-runs workflow\Install-HybridWorkflow.ps1 for every tool, so a project can
    be worked on with Claude Code or GitHub Copilot at any time: the Claude Code commands and plan-executor
    subagent; both sets of VS Code agents (Copilot executes, or the shack PC's local model does) and their prompt
    files; and the Copilot CLI skills and plan-executor agent. It writes them into template/, for projects, and
    into the repository root, so this repository is worked on with the same workflow on any PC that clones it.
    Review the diff, run Test-Template.ps1, then commit, tag a new version and push; projects pick the change up
    with their .template\Update-Project.ps1.

.EXAMPLE
    .\Update-Template.ps1
    .\Update-Template.ps1 -InstallerArgs @{ FastLocalModel = 'DeepSeek V4.1 Flash (DeepInfra)' }
#>
[CmdletBinding()]
param(
    [hashtable]$InstallerArgs = @{}
)
$ErrorActionPreference = 'Stop'

$installer = Join-Path $PSScriptRoot 'workflow\Install-HybridWorkflow.ps1'
$generatedDirs = '.claude\commands', '.claude\agents', '.github\agents', '.github\prompts', '.github\skills'
foreach ($root in (Join-Path $PSScriptRoot 'template'), $PSScriptRoot) {
    foreach ($generated in $generatedDirs) {
        $dir = Join-Path $root $generated
        if (Test-Path $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    }
    & $installer -Repo $root -Variant Both -Target VSCode, Claude, CopilotCli @InstallerArgs | Select-Object -First 1
}
git -C $PSScriptRoot status --short -- template $generatedDirs.Replace('\', '/')