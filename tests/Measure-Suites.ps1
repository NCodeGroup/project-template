<#
.SYNOPSIS
    Time the test suites it names, one at a time, and fail one that fails or is slower than -MaxSeconds.

.DESCRIPTION
    Runs each named suite in its own PowerShell process, one run at a time, so that the runs do not compete for the
    processor and the times can be compared from one run to the next. Without -Name it takes every Test-*.ps1 script in
    -Path, sorted by name. A suite's time is the median of its -Repeat runs. Prints one line per suite: "FAIL" with the
    first non-zero exit code when a run failed, "SLOW" when the time is over -MaxSeconds, else "PASS", each followed by
    the time in seconds. With -Repeat above 1 the line ends with every run's time. Then prints the sum of the times as
    "Total: <seconds>s". Ends with "Measure: PASSED" and exit code 0, or "Measure: FAILED (<n>)" and exit code 1.

    This script is deliberately not named Test-*.ps1, so that Invoke-AllTests.ps1 does not run it as a suite.

.PARAMETER Name
    The file names of the suites to run, in the order to run them. Defaults to every Test-*.ps1 script in -Path.

.PARAMETER Path
    The folder with the suites. Defaults to the folder of this script.

.PARAMETER Repeat
    How many times to run each suite. The median of the runs is the suite's time. Defaults to 1.

.PARAMETER MaxSeconds
    The longest time in seconds a suite may take before it counts as failed. 0, the default, sets no limit.

.PARAMETER SkipDotnetBuild
    Pass -SkipDotnetBuild to the suites that take it, to skip the .NET build and pack.

.EXAMPLE
    .\tests\Measure-Suites.ps1 -Name Test-InvokeAllTests.ps1 -MaxSeconds 60

.EXAMPLE
    .\tests\Measure-Suites.ps1 -Name Test-Adoption.ps1 -Repeat 3 -SkipDotnetBuild
#>
[CmdletBinding()]
param(
    [string[]]$Name,
    [string]$Path = $PSScriptRoot,
    [ValidateRange(1, 20)][int]$Repeat = 1,
    [ValidateRange(0, 3600)][double]$MaxSeconds = 0,
    [switch]$SkipDotnetBuild
)
$ErrorActionPreference = 'Stop'
$pwsh = (Get-Process -Id $PID).Path
$culture = [Globalization.CultureInfo]::InvariantCulture
function Format-Seconds([double]$Seconds) { [string]::Format($culture, '{0:0.0}', $Seconds) }

if (-not $PSBoundParameters.ContainsKey('Name')) {
    $Name = @(Get-ChildItem -LiteralPath $Path -File -Filter 'Test-*.ps1' | Sort-Object Name | ForEach-Object { $_.Name })
}

$failed = 0
$total = 0.0
foreach ($suite in $Name) {
    $file = Join-Path $Path $suite
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        "FAIL  $suite  not found in $Path"
        $failed++
        continue
    }

    # Pass the switch only to the suites that take it, as Invoke-AllTests.ps1 does.
    $suiteArgs = @()
    if ($SkipDotnetBuild -and (Get-Command -Name $file).Parameters.ContainsKey('SkipDotnetBuild')) { $suiteArgs = @('-SkipDotnetBuild') }

    $times = @()
    $exitCode = 0
    for ($run = 0; $run -lt $Repeat; $run++) {
        $stopwatch = [Diagnostics.Stopwatch]::StartNew()
        & $pwsh -NoProfile -NonInteractive -File $file @suiteArgs *> $null
        $code = $LASTEXITCODE
        $stopwatch.Stop()
        $times += $stopwatch.Elapsed.TotalSeconds
        if ($code -ne 0 -and $exitCode -eq 0) { $exitCode = $code }
    }

    # The median shrugs off one run that a busy PC slowed down, which a mean would not.
    $sorted = @($times | Sort-Object)
    $median = [double]$sorted[[Math]::Floor(($sorted.Count - 1) / 2)]
    $total += $median
    $seconds = Format-Seconds $median

    if ($exitCode -ne 0) {
        $line = "FAIL  $suite  ${seconds}s  exit $exitCode"
        $failed++
    }
    elseif ($MaxSeconds -gt 0 -and $median -gt $MaxSeconds) {
        $line = "SLOW  $suite  ${seconds}s  limit $([string]::Format($culture, '{0}', $MaxSeconds))s"
        $failed++
    }
    else {
        $line = "PASS  $suite  ${seconds}s"
    }
    if ($Repeat -gt 1) { $line += '  runs: ' + (($times | ForEach-Object { Format-Seconds $_ }) -join ' ') }
    $line
}

"Total: $(Format-Seconds $total)s"
''
if ($failed) { "Measure: FAILED ($failed)"; exit 1 }
'Measure: PASSED'
exit 0
