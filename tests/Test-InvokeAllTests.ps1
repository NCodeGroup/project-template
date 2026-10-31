<#
.SYNOPSIS
    Test the runner that runs every test suite, on small fixture suites.

.DESCRIPTION
    Writes fixture folders of tiny Test-*.ps1 scripts, runs tests/Invoke-AllTests.ps1 on each in a child process, and
    checks the result lines, the summary line, the exit code, the logs and the -SkipDotnetBuild forwarding, and that two
    runs at once without -Work log to folders of their own, deleted when the run passes. Prints PASS or FAIL per check
    and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-all-tests-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-InvokeAllTests.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-all-tests-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
$runner = Join-Path $PSScriptRoot 'Invoke-AllTests.ps1'
$pwsh = (Get-Process -Id $PID).Path
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function New-Fixture([string]$Folder, [hashtable]$Files) {
    New-Item -ItemType Directory -Force $Folder | Out-Null
    foreach ($name in $Files.Keys) { [IO.File]::WriteAllText((Join-Path $Folder $name), $Files[$name]) }
}
function Invoke-Runner([string]$Folder, [string[]]$RunnerArgs = @(), [switch]$DefaultWork) {
    $lines = [Collections.Generic.List[string]]::new()
    $workArgs = if ($DefaultWork) { @() } else { @('-Work', (Join-Path $Folder 'logs')) }
    & $pwsh -NoProfile -NonInteractive -File $runner -Path $Folder @workArgs @RunnerArgs 2>&1 | ForEach-Object { $lines.Add("$_") }
    [pscustomobject]@{ Lines = $lines.ToArray(); ExitCode = $LASTEXITCODE; Text = ($lines -join "`n") }
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$mixed = Join-Path $Work 'mixed'
$dotnet = Join-Path $Work 'dotnet'
$empty = Join-Path $Work 'empty'
$where = Join-Path $Work 'where'
$passScript = "'Pass tests: PASSED'; exit 0`n"
New-Fixture $mixed @{
    'Test-Pass.ps1'  = $passScript
    'Test-Fail.ps1'  = "'PASS  one'; 'FAIL  two  detail'; 'Fail tests: FAILED (1)'; exit 1`n"
    'Test-Throw.ps1' = "`$ErrorActionPreference = 'Stop'; throw 'boom'`n"
    'Helper.ps1'     = "exit 1`n"
}
New-Fixture $dotnet @{
    'Test-Pass.ps1'   = $passScript
    'Test-Dotnet.ps1' = "param([switch]`$SkipDotnetBuild) `"skip: `$SkipDotnetBuild`"; exit 0`n"
}
New-Item -ItemType Directory -Force $empty | Out-Null
# Each suite records the runner's default log folder, by the runner's process ID, and whether it exists during the run.
New-Fixture $where @{
    'Test-Where.ps1' = @'
$runnerId = (Get-Process -Id $PID).Parent.Id
$logs = Join-Path ([IO.Path]::GetTempPath()) "project-template-all-tests-$runnerId"
Start-Sleep -Seconds 2
[IO.File]::WriteAllText((Join-Path $PSScriptRoot "where-$runnerId.txt"), "$logs|$(Test-Path -LiteralPath $logs)")
exit 0
'@
}

$r = Invoke-Runner $mixed
Check 'mixed: exits 1 and ends with the failed count' (($r.ExitCode -eq 1) -and ($r.Lines[-1] -eq 'All tests: FAILED (2)')) $r.Text
Check 'mixed: prints a PASS line for the passing suite' ($r.Lines -match '^PASS  Test-Pass\.ps1  \d+:\d\d$').Count $r.Text
Check 'mixed: prints a FAIL line for the failing suite' ($r.Lines -match '^FAIL  Test-Fail\.ps1  \d+:\d\d$').Count $r.Text
Check 'mixed: prints a FAIL line for the suite that throws' ($r.Lines -match '^FAIL  Test-Throw\.ps1  \d+:\d\d$').Count $r.Text
Check 'mixed: shows the failed suite''s FAIL line indented' ($r.Lines -contains '  FAIL  two  detail') $r.Text
Check 'mixed: runs only Test-*.ps1 scripts' (-not $r.Text.Contains('Helper.ps1')) $r.Text
$log = Join-Path $mixed 'logs\Test-Fail.log'
Check 'mixed: writes the suite output to its log' ((Test-Path -LiteralPath $log) -and ([IO.File]::ReadAllText($log).Contains('Fail tests: FAILED (1)'))) $r.Text

$r = Invoke-Runner $dotnet @('-SkipDotnetBuild')
$log = Join-Path $dotnet 'logs\Test-Dotnet.log'
Check 'dotnet: -SkipDotnetBuild passes and reaches only the suite that takes it' (($r.ExitCode -eq 0) -and ($r.Lines[-1] -eq 'All tests: PASSED') -and (Test-Path -LiteralPath $log) -and ([IO.File]::ReadAllText($log).Contains('skip: True'))) $r.Text

$r = Invoke-Runner $empty
Check 'empty: exits 1 and says no suites were found' (($r.ExitCode -eq 1) -and ($r.Lines -match '^No Test-\*\.ps1 scripts in').Count) $r.Text

# Two runs at once without -Work, as from two worktrees: each must log to a folder of its own and delete it.
$runs = foreach ($n in 1, 2) {
    $run = Start-Process -FilePath $pwsh -ArgumentList '-NoProfile', '-NonInteractive', '-File', "`"$runner`"", '-Path', "`"$where`"" -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $Work "where-$n.out") -RedirectStandardError (Join-Path $Work "where-$n.err")
    $null = $run.Handle
    $run
}
foreach ($run in $runs) { $run.WaitForExit() }
$outputs = (1, 2 | ForEach-Object { Get-Content -Raw -LiteralPath (Join-Path $Work "where-$_.out") }) -join "`n"
$found = @(Get-ChildItem -LiteralPath $where -Filter 'where-*.txt' | ForEach-Object {
        $folder, $existed = [IO.File]::ReadAllText($_.FullName) -split '\|'
        [pscustomobject]@{ Folder = $folder; Existed = $existed -eq 'True' }
    })
$foundText = ($found | ForEach-Object { "$($_.Folder) existed: $($_.Existed)" }) -join "`n"
$folders = @($found.Folder | Sort-Object -Unique)
Check 'default: two runs at once pass' (@($runs | Where-Object ExitCode -NE 0).Count -eq 0) "exit codes $($runs.ExitCode -join ', ')`n$outputs"
Check 'default: two runs at once log to two different folders' (($found.Count -eq 2) -and ($folders.Count -eq 2)) $foundText
Check 'default: each run''s log folder exists while it runs' (($found.Count -eq 2) -and @($found | Where-Object { -not $_.Existed }).Count -eq 0) $foundText
Check 'default: a run that passes deletes its log folder' (($folders.Count -eq 2) -and @($folders | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0) $foundText

$r = Invoke-Runner $mixed -DefaultWork
$kept = @($r.Lines -match '^  log: ' | ForEach-Object { Split-Path -Parent $_.Substring(7) } | Sort-Object -Unique)
Check 'default: a run that fails keeps its log folder, in the temp folder' (($r.ExitCode -eq 1) -and ($kept.Count -eq 1) -and (Test-Path -LiteralPath $kept[0]) -and ((Split-Path -Leaf $kept[0]) -match '^project-template-all-tests-\d+$')) $r.Text
foreach ($folder in $kept) { if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force } }

''
if ($failures.Count) { "Kept the work folder: $Work"; "Runner tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) {
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Work) { "Couldn't delete the work folder: $Work" }
}
'Runner tests: PASSED'
exit 0
