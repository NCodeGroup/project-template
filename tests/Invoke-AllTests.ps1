<#
.SYNOPSIS
    Run every tests/Test-*.ps1 suite and print one result line per suite.

.DESCRIPTION
    Runs each Test-*.ps1 script in the folder in its own PowerShell process, up to -ThrottleLimit at once, and decides
    its result by its exit code. Once every suite has finished, prints PASS or FAIL and the time per suite in name
    order; under a failed suite, prints its FAIL lines and the path of its full log. Then prints the run's wall-clock
    time as "Time: <m:ss>". Each suite's output goes to a log file in the work folder. While the suites run,
    COPIER_CACHE_DIR points at the copier-cache folder in the work folder. Ends with
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

.PARAMETER ThrottleLimit
    How many suites run at once. Defaults to the processor count.

.PARAMETER Serial
    Run one suite at a time, as -ThrottleLimit 1 does.

.EXAMPLE
    .\tests\Invoke-AllTests.ps1

.EXAMPLE
    .\tests\Invoke-AllTests.ps1 -SkipDotnetBuild

.EXAMPLE
    .\tests\Invoke-AllTests.ps1 -Serial
#>
[CmdletBinding()]
param(
    [string]$Path = $PSScriptRoot,
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-all-tests-$PID"),
    [switch]$SkipDotnetBuild,
    [ValidateRange(1, 1024)][int]$ThrottleLimit = [Environment]::ProcessorCount,
    [switch]$Serial
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
# Run the suites up to the limit at once, then print their results in name order.
$limit = if ($Serial) { 1 } else { $ThrottleLimit }
$encoding = [Console]::OutputEncoding
# The suites' Copier mirrors go in this run's folder, deleted with it, not in the user's cache: each suite's snapshot has a URL of its own, so each run would leave a mirror there.
$copierCache = $env:COPIER_CACHE_DIR
$env:COPIER_CACHE_DIR = Join-Path $Work 'copier-cache'
try {
    $results = @($scripts | ForEach-Object -ThrottleLimit $limit -Parallel {
            $script = $_
            $suiteArgs = @()
            if ($using:SkipDotnetBuild -and (Get-Command -Name $script.FullName).Parameters.ContainsKey('SkipDotnetBuild')) { $suiteArgs = @('-SkipDotnetBuild') }
            $stopwatch = [Diagnostics.Stopwatch]::StartNew()
            $lines = @(& $using:pwsh -NoProfile -NonInteractive -File $script.FullName @suiteArgs 2>&1 | ForEach-Object { "$_" })
            [pscustomobject]@{ Script = $script; Lines = $lines; ExitCode = $LASTEXITCODE; Elapsed = $stopwatch.Elapsed }
        })
}
finally { [Console]::OutputEncoding = $encoding; $env:COPIER_CACHE_DIR = $copierCache }

foreach ($result in @($results | Sort-Object { $_.Script.Name })) {
    $script = $result.Script
    $lines = $result.Lines
    $log = Join-Path $Work ($script.BaseName + '.log')
    [IO.File]::WriteAllLines($log, [string[]]$lines, [Text.UTF8Encoding]::new($false))
    $time = Format-Elapsed $result.Elapsed
    if ($result.ExitCode -eq 0) {
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
