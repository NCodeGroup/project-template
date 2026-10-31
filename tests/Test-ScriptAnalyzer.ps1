<#
.SYNOPSIS
    Run PSScriptAnalyzer on every PowerShell script in the repository, with PSScriptAnalyzerSettings.psd1, and fail on
    any warning or error.

.DESCRIPTION
    The scripts the template ships (template/.template/*.ps1, the workflow scripts and the tools) and this repository's
    own run on people's machines and in their CI, so a warning is treated as an error. The settings file turns off the
    rules that don't fit these scripts, each with its reason; a finding that can't be fixed is suppressed where it is,
    with [Diagnostics.CodeAnalysis.SuppressMessageAttribute] and a justification. Installs the pinned PSScriptAnalyzer
    for the current user from the PowerShell Gallery when it is missing, so the first run needs the network; offline,
    Install-Module fails with its own error before any analysis. Prints each finding, then PASS or FAIL, and exits 1 on
    any finding.

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

# A control first: with these settings, a file with a known warning must be reported, or a pass below proves nothing.
$control = Join-Path ([IO.Path]::GetTempPath()) "script-analyzer-control-$PID.ps1"
[IO.File]::WriteAllText($control, "function Get-Control {`n    `$unused = 1`n}`n")
try { $controlFindings = @(Invoke-ScriptAnalyzer -Path $control -Settings $settings) }
finally { Remove-Item -LiteralPath $control -Force }
if (-not $controlFindings.Count) {
    Write-Host 'FAIL  the analyzer reports nothing for a file with a known warning, so these settings would pass anything'
    Write-Host "`nScript analyzer: FAILED"
    exit 1
}
Write-Host 'PASS  the analyzer reports the known warning in a control file'

$files = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Include *.ps1, *.psm1, *.psd1 |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
if (-not $files.Count) {
    Write-Host "FAIL  no PowerShell files under $repoRoot"
    Write-Host "`nScript analyzer: FAILED"
    exit 1
}
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
