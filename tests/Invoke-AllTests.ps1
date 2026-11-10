<#
.SYNOPSIS
    Run every tests/Test-*.ps1 suite and every end-to-end fixture setup CI runs, and print one result line per run.

.DESCRIPTION
    Runs each Test-*.ps1 script in the folder in its own PowerShell process, up to -ThrottleLimit at once, and decides
    its result by its exit code. It then runs each "run: ./tests/e2e/<script>.ps1 ... -SetupOnly ..." line of
    .github/workflows/test-template.yml in the parent of -Path, with that line's arguments and -Work e2e-<n> in the
    work folder, and prints those results after the suites, in the workflow's order, named "e2e/<script> <arguments>";
    with no such file it runs only the suites. Once every run has finished, prints PASS or FAIL and the time per run;
    under a failed run, prints its FAIL lines and the path of its full log. Then prints the run's wall-clock
    time as "Time: <m:ss>". Each run's output goes to a log file in the work folder. While the runs run,
    COPIER_CACHE_DIR points at the copier-cache folder in the work folder. Ends with
    "All tests: PASSED" and exit code 0, or "All tests: FAILED (<n>)" and exit code 1. Exits 1 when the folder has no
    Test-*.ps1 script.

.PARAMETER Path
    The folder with the Test-*.ps1 scripts. Defaults to the folder of this script.

.PARAMETER Work
    The folder for the logs of the suites and setups, deleted and recreated. Defaults to
    project-template-all-tests-<process ID> in the temp folder, the run's own: deleted when every suite and setup
    passes or there is no suite to run, kept for the logs of failed ones when one fails.

.PARAMETER SkipDotnetBuild
    Pass -SkipDotnetBuild to the suites that take it, to skip the .NET build and pack.

.PARAMETER ThrottleLimit
    How many suites and setups run at once. Defaults to the processor count.

.PARAMETER Serial
    Run one suite or setup at a time, as -ThrottleLimit 1 does.

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

# The runs: the suites in name order, then the fixture setups CI runs, in the workflow's order.
$jobs = [Collections.Generic.List[object]]::new()
foreach ($script in $scripts) {
    $jobArguments = @()
    if ($SkipDotnetBuild -and (Get-Command -Name $script.FullName).Parameters.ContainsKey('SkipDotnetBuild')) { $jobArguments = @('-SkipDotnetBuild') }
    $jobs.Add([pscustomobject]@{ Index = $jobs.Count; Name = $script.Name; File = $script.FullName; Arguments = $jobArguments; Log = $script.BaseName })
}
$root = Split-Path -Parent (Get-Item -LiteralPath $Path).FullName
$workflow = Join-Path $root '.github/workflows/test-template.yml'
if (Test-Path -LiteralPath $workflow -PathType Leaf) {
    $n = 0
    foreach ($match in [regex]::Matches([IO.File]::ReadAllText($workflow), '(?m)^\s*run: \./(?<script>tests/e2e/[\w.-]+\.ps1)(?<args>(?: [\w-]+)*)\s*$')) {
        $file = $match.Groups['script'].Value
        $text = $match.Groups['args'].Value
        $setupArgs = @($text -split ' ' | Where-Object { $_ })
        if ($setupArgs -notcontains '-SetupOnly') { continue }
        $n++
        $jobs.Add([pscustomobject]@{
                Index     = $jobs.Count
                Name      = "e2e/$(Split-Path -Leaf $file)$text"
                File      = Join-Path $root $file
                Arguments = $setupArgs + @('-Work', (Join-Path $Work "e2e-$n"))
                Log       = ("e2e $([IO.Path]::GetFileNameWithoutExtension($file))$text" -replace '[^\w]+', '-')
            })
    }
}

$failed = 0
# Run the suites and setups up to the limit at once, then print their results in order.
$limit = if ($Serial) { 1 } else { $ThrottleLimit }
$encoding = [Console]::OutputEncoding
# The suites' Copier mirrors go in this run's folder, deleted with it, not in the user's cache: each suite's snapshot has a URL of its own, so each run would leave a mirror there.
$copierCache = $env:COPIER_CACHE_DIR
$env:COPIER_CACHE_DIR = Join-Path $Work 'copier-cache'
try {
    $results = @($jobs | ForEach-Object -ThrottleLimit $limit -Parallel {
            $job = $_
            $jobArgs = @($job.Arguments)
            $stopwatch = [Diagnostics.Stopwatch]::StartNew()
            $lines = @(& $using:pwsh -NoProfile -NonInteractive -File $job.File @jobArgs 2>&1 | ForEach-Object { "$_" })
            [pscustomobject]@{ Job = $job; Lines = $lines; ExitCode = $LASTEXITCODE; Elapsed = $stopwatch.Elapsed }
        })
}
finally { [Console]::OutputEncoding = $encoding; $env:COPIER_CACHE_DIR = $copierCache }

foreach ($result in @($results | Sort-Object { $_.Job.Index })) {
    $lines = $result.Lines
    $log = Join-Path $Work ($result.Job.Log + '.log')
    [IO.File]::WriteAllLines($log, [string[]]$lines, [Text.UTF8Encoding]::new($false))
    $time = Format-Elapsed $result.Elapsed
    if ($result.ExitCode -eq 0) {
        "PASS  $($result.Job.Name)  $time"
    }
    else {
        "FAIL  $($result.Job.Name)  $time"
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
