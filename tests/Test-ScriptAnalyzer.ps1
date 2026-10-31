<#
.SYNOPSIS
    Run PSScriptAnalyzer on every PowerShell script in the repository, with PSScriptAnalyzerSettings.psd1, and fail on
    any warning or error.

.DESCRIPTION
    The scripts the template ships (template/.template/*.ps1, the workflow scripts and the tools) and this repository's
    own run on people's machines and in their CI, so a warning is treated as an error. The settings file turns off the
    rules that don't fit these scripts, each with its reason; a finding that can't be fixed is suppressed where it is,
    with [Diagnostics.CodeAnalysis.SuppressMessageAttribute] and a justification. Installs the pinned PSScriptAnalyzer
    for the current user when it is missing. Prints each finding, then PASS or FAIL, and exits 1 on any finding.

.EXAMPLE
    .\tests\Test-ScriptAnalyzer.ps1
#>
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$version = '1.25.0'

if (-not (Get-Module -ListAvailable PSScriptAnalyzer | Where-Object { $_.Version -eq [version]$version })) {
    Install-Module PSScriptAnalyzer -RequiredVersion $version -Scope CurrentUser -Force -AcceptLicense
}
Import-Module PSScriptAnalyzer -RequiredVersion $version

$settings = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'
$files = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include *.ps1, *.psm1, *.psd1 |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }
$findings = @($files | ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Settings $settings })

foreach ($f in $findings) {
    $relative = [IO.Path]::GetRelativePath($repoRoot, $f.ScriptPath)
    Write-Host "FAIL  ${relative}:$($f.Line) $($f.RuleName): $($f.Message)"
}
if ($findings.Count) {
    Write-Host "`nScript analyzer: FAILED ($($findings.Count) finding(s) in $($files.Count) files)"
    exit 1
}
Write-Host "PASS  $($files.Count) files, no warnings or errors"
Write-Host "`nScript analyzer: PASSED"
