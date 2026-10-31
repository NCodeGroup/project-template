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

    Before it analyzes the repository, it runs itself on a folder holding one file with a known warning, and fails unless
    that run reports the warning and exits 1: a pass then shows the whole gate works, the settings and the exit code too.

.PARAMETER Path
    The folder to analyze, the repository by default. The control run uses it for its fixture folder.

.PARAMETER NoControl
    Skips the control run; the control run itself passes it.

.EXAMPLE
    .\tests\Test-ScriptAnalyzer.ps1
#>
param(
    [string]$Path,
    [switch]$NoControl
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Path) { $Path = $repoRoot }
$version = '1.25.0'

if (-not (Get-Module -ListAvailable PSScriptAnalyzer | Where-Object { $_.Version -eq [version]$version })) {
    Install-Module PSScriptAnalyzer -RequiredVersion $version -Scope CurrentUser -Force -AcceptLicense
}
Import-Module PSScriptAnalyzer -RequiredVersion $version

$settings = Join-Path $repoRoot 'PSScriptAnalyzerSettings.psd1'

if (-not $NoControl) {
    # The control: this script, run on a folder with one known warning, must print a FAIL line for it and exit 1.
    $fixture = Join-Path ([IO.Path]::GetTempPath()) "script-analyzer-control-$PID"
    New-Item -ItemType Directory -Force $fixture | Out-Null
    try {
        [IO.File]::WriteAllText((Join-Path $fixture 'Control.ps1'), "function Get-Control {`n    `$unused = 1`n}`n")
        $controlOutput = & pwsh -NoProfile -File $PSCommandPath -Path $fixture -NoControl 2>&1 | Out-String
        $controlExit = $LASTEXITCODE
    }
    finally { Remove-Item -LiteralPath $fixture -Recurse -Force }
    if ($controlExit -ne 1 -or $controlOutput -notmatch 'FAIL  Control\.ps1:2 PSUseDeclaredVarsMoreThanAssignments') {
        Write-Host "FAIL  run on a file with a known warning, the gate printed no FAIL line for it or didn't exit 1 (exit $controlExit)"
        Write-Host $controlOutput
        Write-Host "`nScript analyzer: FAILED"
        exit 1
    }
    Write-Host 'PASS  the gate reports a known warning in a control file and exits 1'
}

$files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Include *.ps1, *.psm1, *.psd1 |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
if (-not $files.Count) {
    Write-Host "FAIL  no PowerShell files under $Path"
    Write-Host "`nScript analyzer: FAILED"
    exit 1
}
$findings = @($files | ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Settings $settings })

foreach ($f in $findings) {
    $relative = [IO.Path]::GetRelativePath($Path, $f.ScriptPath)
    Write-Host "FAIL  ${relative}:$($f.Line) $($f.RuleName): $($f.Message)"
}
if ($findings.Count) {
    Write-Host "`nScript analyzer: FAILED ($($findings.Count) finding(s) in $($files.Count) files)"
    exit 1
}
Write-Host "PASS  $($files.Count) files, no warnings or errors"
Write-Host "`nScript analyzer: PASSED"
