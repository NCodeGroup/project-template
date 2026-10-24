<#
.SYNOPSIS
    Update a project to the newest template version, from this clone. Runs template\.template\Update-Project.ps1.

.DESCRIPTION
    Every project carries its own copy of the update script as .template\Update-Project.ps1 and is normally
    updated by running that. This wrapper runs the same script, template\.template\Update-Project.ps1 — its
    single source — against the project given with -Path. Like the project's copy, it hands the update over to
    the target version's script when that differs. Get-Help template\.template\Update-Project.ps1 -Full explains
    the update.

.EXAMPLE
    .\Update-Project.ps1 -Path C:\src\qso-viewer
    .\Update-Project.ps1 -Path C:\src\qso-viewer -NoCommit
    .\Update-Project.ps1 -Path C:\src\qso-viewer -Ref v0.3.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [string]$Ref,
    [hashtable]$Data = @{},
    [switch]$NoCommit
)
& (Join-Path $PSScriptRoot 'template\.template\Update-Project.ps1') @PSBoundParameters
exit $LASTEXITCODE