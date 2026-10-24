<#
.SYNOPSIS
    Regenerate the workflow files in template/ from the source templates in workflow/templates.

.DESCRIPTION
    Deletes the four generated folders and re-runs workflow\Install-HybridWorkflow.ps1 into template/ for
    Configuration G: the Local variant's VS Code agents and prompt files, and the Claude Code commands and
    plan-executor subagent. Review the diff, run Test-Template.ps1, then commit, tag a new version and push;
    projects pick the change up with their .template\Update-Project.ps1.

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
$template = Join-Path $PSScriptRoot 'template'
foreach ($generated in '.claude\commands', '.claude\agents', '.github\agents', '.github\prompts') {
    $dir = Join-Path $template $generated
    if (Test-Path $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
}

& $installer -Repo $template -Variant Local -Target VSCode, Claude @InstallerArgs | Select-Object -First 1
git -C $PSScriptRoot status --short -- template