<#
.SYNOPSIS
    Run every tests/Test-*.ps1 suite and print one result line per suite.

.DESCRIPTION
    Runs each Test-*.ps1 script in the folder, one after another, each in its own PowerShell process, and decides its
    result by its exit code. Prints PASS or FAIL and the time per suite; under a failed suite, prints its FAIL lines
    and the path of its full log. Then prints the run's wall-clock time as "Time: <m:ss>". Each suite's output goes to a log file in the work folder. Ends with
    "All tests: PASSED" and exit code 0, or "All tests: FAILED (<n>)" and exit code 1. Exits 1 when the folder has no
    Test-*.ps1 script.

.PARAMETER Path
    The folder with the Test-*.ps1 scripts. Defaults to the folder of this script.

.PARAMETER Work
    The folder for the suites' logs, deleted and recreated. Defaults to project-template-all-tests-<process ID> in the
    temp folder, the run's own: deleted when every suite passes or there is none to run, kept for the failed suites'
    logs when one fails.

.PARAMETER SkipDotnetBuild
    Pass -SkipDotnetBuild to the suites that take it, to skip the .NET build and pack.

.EXAMPLE
    .\tests\Invoke-AllTests.ps1

.EXAMPLE
    .\tests\Invoke-AllTests.ps1 -SkipDotnetBuild
#>
[CmdletBinding()]
param(
    [string]$Path = $PSScriptRoot,
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-all-tests-$PID"),
    [switch]$SkipDotnetBuild
)
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
$pwsh = (Get-Process -Id $PID).Path
function Format-Elapsed([TimeSpan]$Elapsed) { '{0}:{1:00}' -f [int][Math]::Floor($Elapsed.TotalMinutes), $Elapsed.Seconds }
$run = [Diagnostics.Stopwatch]::StartNew()

if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

$scripts = @(Get-ChildItem -LiteralPath $Path -File -Filter 'Test-*.ps1' | Sort-Object Name)
if (-not $scripts.Count) {
    "No Test-*.ps1 scripts in $Path."
    if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
    exit 1
}

$failed = 0
foreach ($script in $scripts) {
    $suiteArgs = @()
    if ($SkipDotnetBuild -and (Get-Command -Name $script.FullName).Parameters.ContainsKey('SkipDotnetBuild')) {
        $suiteArgs = @('-SkipDotnetBuild')
    }
    $lines = [Collections.Generic.List[string]]::new()
    $encoding = [Console]::OutputEncoding
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        & $pwsh -NoProfile -NonInteractive -File $script.FullName @suiteArgs 2>&1 | ForEach-Object { $lines.Add("$_") }
        $exitCode = $LASTEXITCODE
    }
    finally { [Console]::OutputEncoding = $encoding }
    $elapsed = $stopwatch.Elapsed

    $log = Join-Path $Work ($script.BaseName + '.log')
    [IO.File]::WriteAllLines($log, $lines.ToArray(), [Text.UTF8Encoding]::new($false))
    $time = Format-Elapsed $elapsed
    if ($exitCode -eq 0) {
        "PASS  $($script.Name)  $time"
    }
    else {
        "FAIL  $($script.Name)  $time"
        foreach ($line in $lines) { if ($line.StartsWith('FAIL  ')) { "  $line" } }
        "  log: $log"
        $failed++
    }
}

"Time: $(Format-Elapsed $run.Elapsed)"
''
if ($failed) { "All tests: FAILED ($failed)"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'All tests: PASSED'
exit 0
