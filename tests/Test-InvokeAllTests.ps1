<#
.SYNOPSIS
    Test the runner that runs every test suite, on small fixture suites.

.DESCRIPTION
    Writes fixture folders of tiny Test-*.ps1 scripts, runs tests/Invoke-AllTests.ps1 on each in a child process, and
    checks the result lines, the summary line, the exit code, the logs and the -SkipDotnetBuild forwarding, that suites
    run at the same time at -ThrottleLimit 2 and print in name order, not the order they finish, that -Serial and
    -ThrottleLimit 1 run one at a time, and that two runs at once without -Work log to folders of their own, deleted
    when the run passes. Also checks that tests/Remove-TestWork.ps1 deletes a work folder or says it couldn't, and that
    every suite with -Work defaults to a folder of its own, kept on a failure and deleted through it on a pass, and,
    through a trap line, kept with its path printed when the suite stops with an error. Prints PASS or FAIL per check
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
trap { "Kept the work folder: $Work"; break }
$runner = Join-Path $PSScriptRoot 'Invoke-AllTests.ps1'
$pwsh = (Get-Process -Id $PID).Path
$failures = [Collections.Generic.List[string]]::new()
$trapLine = 'trap { "Kept the work folder: $Work"; break }'

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
# Each suite records the runner's default log folder, by the runner's process ID, whether it exists during the run, and
# whether the other run had started too: it marks itself ready and waits, up to a deadline, for the other's mark.
New-Fixture $where @{
    'Test-Where.ps1' = @'
$runnerId = (Get-Process -Id $PID).Parent.Id
$logs = Join-Path ([IO.Path]::GetTempPath()) "project-template-all-tests-$runnerId"
[IO.File]::WriteAllText((Join-Path $PSScriptRoot "ready-$runnerId.txt"), '')
$deadline = [DateTime]::UtcNow.AddSeconds(60)
while (@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'ready-*.txt').Count -lt 2 -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
$both = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'ready-*.txt').Count -eq 2
[IO.File]::WriteAllText((Join-Path $PSScriptRoot "where-$runnerId.txt"), "$logs|$(Test-Path -LiteralPath $logs)|$both")
exit 0
'@
}
# Two copies of one suite record when they ran: each marks itself ready and waits up to 5 s for the other's mark, so they
# overlap when run at once. Test-A then waits 500 ms more, so it finishes last. Run one at a time, the wait times out.
$pair = Join-Path $Work 'pair'
$pairScript = @'
$start = [DateTime]::UtcNow.Ticks
$name = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$other = if ($name -eq 'Test-A') { 'Test-B' } else { 'Test-A' }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot "ready-$name.txt"), '')
$deadline = [DateTime]::UtcNow.AddSeconds(5)
while (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "ready-$other.txt")) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
if ($name -eq 'Test-A') { Start-Sleep -Milliseconds 500 }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot "span-$name.txt"), "$start|$([DateTime]::UtcNow.Ticks)")
exit 0
'@
New-Fixture $pair @{ 'Test-A.ps1' = $pairScript; 'Test-B.ps1' = $pairScript }
function Invoke-PairRunner([string[]]$RunnerArgs = @()) {
    Get-ChildItem -LiteralPath $pair -File | Where-Object { $_.Name -like 'ready-*' -or $_.Name -like 'span-*' } | Remove-Item -Force
    $r = Invoke-Runner $pair $RunnerArgs
    $spans = foreach ($name in 'A', 'B') {
        $file = Join-Path $pair "span-Test-$name.txt"
        if (Test-Path -LiteralPath $file) {
            $start, $end = [IO.File]::ReadAllText($file) -split '\|'
            [pscustomobject]@{ Start = [long]$start; End = [long]$end }
        }
    }
    [pscustomobject]@{ Runner = $r; Spans = @($spans) }
}

$p = Invoke-PairRunner @('-ThrottleLimit', '2')
$ok = ($p.Spans.Count -eq 2) -and ($p.Runner.ExitCode -eq 0)
$a, $b = $p.Spans
Check 'parallel: suites run at the same time' ($ok -and ($a.Start -lt $b.End) -and ($b.Start -lt $a.End)) $p.Runner.Text
$printedA = [array]::IndexOf($p.Runner.Lines, ($p.Runner.Lines -match '^PASS  Test-A\.ps1  ')[0])
$printedB = [array]::IndexOf($p.Runner.Lines, ($p.Runner.Lines -match '^PASS  Test-B\.ps1  ')[0])
Check 'parallel: results print in name order, not the order suites finish' ($ok -and ($a.End -gt $b.End) -and ($printedA -ge 0) -and ($printedA -lt $printedB)) $p.Runner.Text

$p = Invoke-PairRunner @('-Serial')
$a, $b = $p.Spans
Check 'serial: -Serial runs one suite at a time' (($p.Spans.Count -eq 2) -and ($p.Runner.ExitCode -eq 0) -and ($a.End -le $b.Start)) $p.Runner.Text

$p = Invoke-PairRunner @('-ThrottleLimit', '1')
$a, $b = $p.Spans
Check 'throttle: -ThrottleLimit 1 runs one suite at a time' (($p.Spans.Count -eq 2) -and ($p.Runner.ExitCode -eq 0) -and ($a.End -le $b.Start)) $p.Runner.Text

$r = Invoke-Runner $mixed
Check 'mixed: exits 1 and ends with the failed count' (($r.ExitCode -eq 1) -and ($r.Lines[-1] -eq 'All tests: FAILED (2)')) $r.Text
Check 'mixed: prints a PASS line for the passing suite' ($r.Lines -match '^PASS  Test-Pass\.ps1  \d+:\d\d$').Count $r.Text
Check 'mixed: prints a FAIL line for the failing suite' ($r.Lines -match '^FAIL  Test-Fail\.ps1  \d+:\d\d$').Count $r.Text
Check 'mixed: prints a FAIL line for the suite that throws' ($r.Lines -match '^FAIL  Test-Throw\.ps1  \d+:\d\d$').Count $r.Text
Check 'mixed: shows the failed suite''s FAIL line indented' ($r.Lines -contains '  FAIL  two  detail') $r.Text
Check 'mixed: runs only Test-*.ps1 scripts' (-not $r.Text.Contains('Helper.ps1')) $r.Text
$log = Join-Path $mixed 'logs\Test-Fail.log'
Check 'mixed: writes the suite output to its log' ((Test-Path -LiteralPath $log) -and ([IO.File]::ReadAllText($log).Contains('Fail tests: FAILED (1)'))) $r.Text
Check 'mixed: prints the run''s wall-clock time before the summary' ((@($r.Lines -match '^Time: \d+:\d\d$').Count -eq 1) -and ($r.Lines[-3] -match '^Time: \d+:\d\d$')) $r.Text

$r = Invoke-Runner $dotnet @('-SkipDotnetBuild')
$log = Join-Path $dotnet 'logs\Test-Dotnet.log'
Check 'dotnet: -SkipDotnetBuild passes and reaches only the suite that takes it' (($r.ExitCode -eq 0) -and ($r.Lines[-1] -eq 'All tests: PASSED') -and (Test-Path -LiteralPath $log) -and ([IO.File]::ReadAllText($log).Contains('skip: True'))) $r.Text

$r = Invoke-Runner $empty
Check 'empty: exits 1 and says no suites were found' (($r.ExitCode -eq 1) -and ($r.Lines -match '^No Test-\*\.ps1 scripts in').Count) $r.Text

# Two runs at once without -Work, as from two worktrees: each must log to a folder of its own and delete it.
$runs = foreach ($n in 1, 2) {
    $run = Start-Process -FilePath $pwsh -ArgumentList '-NoProfile', '-NonInteractive', '-File', "`"$runner`"", '-Path', "`"$where`"" -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $Work "where-$n.out") -RedirectStandardError (Join-Path $Work "where-$n.err")
    # Reading the handle keeps ExitCode available after the process exits.
    $null = $run.Handle
    $run
}
foreach ($run in $runs) { $run.WaitForExit() }
$outputs = (1, 2 | ForEach-Object { Get-Content -Raw -LiteralPath (Join-Path $Work "where-$_.out") }) -join "`n"
$found = @(Get-ChildItem -LiteralPath $where -Filter 'where-*.txt' | ForEach-Object {
        $folder, $existed, $both = [IO.File]::ReadAllText($_.FullName) -split '\|'
        [pscustomobject]@{ Folder = $folder; Existed = $existed -eq 'True'; Both = $both -eq 'True' }
    })
$foundText = ($found | ForEach-Object { "$($_.Folder) existed: $($_.Existed) both running: $($_.Both)" }) -join "`n"
$folders = @($found.Folder | Sort-Object -Unique)
Check 'default: two runs at once pass' (@($runs | Where-Object ExitCode -NE 0).Count -eq 0) "exit codes $($runs.ExitCode -join ', ')`n$outputs"
Check 'default: the two runs overlap' (($found.Count -eq 2) -and @($found | Where-Object { -not $_.Both }).Count -eq 0) $foundText
Check 'default: two runs at once log to two different folders' (($found.Count -eq 2) -and ($folders.Count -eq 2)) $foundText
Check 'default: each run''s log folder exists while it runs' (($found.Count -eq 2) -and @($found | Where-Object { -not $_.Existed }).Count -eq 0) $foundText
Check 'default: a run that passes deletes its log folder' (($folders.Count -eq 2) -and @($folders | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0) $foundText

$r = Invoke-Runner $mixed -DefaultWork
$kept = @($r.Lines -match '^  log: ' | ForEach-Object { Split-Path -Parent $_.Substring(7) } | Sort-Object -Unique)
Check 'default: a run that fails keeps its log folder, in the temp folder' (($r.ExitCode -eq 1) -and ($kept.Count -eq 1) -and (Test-Path -LiteralPath $kept[0]) -and ((Split-Path -Leaf $kept[0]) -match '^project-template-all-tests-\d+$')) $r.Text
foreach ($folder in $kept) { if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force } }

$run = Start-Process -FilePath $pwsh -ArgumentList '-NoProfile', '-NonInteractive', '-File', "`"$runner`"", '-Path', "`"$empty`"" -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $Work 'empty-default.out') -RedirectStandardError (Join-Path $Work 'empty-default.err')
# Reading the handle keeps ExitCode available after the process exits.
$null = $run.Handle
$run.WaitForExit()
$emptyLogs = Join-Path ([IO.Path]::GetTempPath()) "project-template-all-tests-$($run.Id)"
$output = Get-Content -Raw -LiteralPath (Join-Path $Work 'empty-default.out')
Check 'default: a run that finds no suites exits 1 and deletes its log folder' (($run.ExitCode -eq 1) -and $output.Contains('No Test-*.ps1 scripts in') -and -not (Test-Path -LiteralPath $emptyLogs)) "$emptyLogs`n$output"

# tests/Remove-TestWork.ps1 deletes a passing run's own folder, and only says so when it can't.
$cleanup = Join-Path $PSScriptRoot 'Remove-TestWork.ps1'
$gone = Join-Path $Work 'cleanup-gone'
New-Fixture (Join-Path $gone 'sub') @{ 'file.txt' = 'x' }
$out = @(& $cleanup $gone)
Check 'cleanup: deletes the work folder and prints nothing' ((-not (Test-Path -LiteralPath $gone)) -and ($out.Count -eq 0)) ($out -join "`n")

# A file held open (Windows) or a folder without write permission (elsewhere) keeps the folder from being deleted.
$held = Join-Path $Work 'cleanup-held'
$heldDir = Join-Path $held 'locked'
New-Fixture $heldDir @{ 'held.txt' = 'x' }
if (-not $IsWindows -and (id -u) -eq '0') { 'SKIP  cleanup: a folder it can''t delete (root can delete any file)' }
else {
    $handle = $null
    if ($IsWindows) { $handle = [IO.File]::Open((Join-Path $heldDir 'held.txt'), 'Open', 'Read', 'None') } else { chmod 555 $heldDir }
    $threw = ''
    try { $out = @(& $cleanup $held) }
    catch { $threw = "$_" }
    finally { if ($handle) { $handle.Dispose() } else { chmod 755 $heldDir } }
    Check 'cleanup: a folder it can''t delete prints its path and doesn''t fail the run' ((-not $threw) -and ($out -contains "Couldn't delete the work folder: $held") -and (Test-Path -LiteralPath $held)) "$threw$($out -join "`n")"
}

# A suite that stops with an error keeps its folder and says where, through the trap line every suite has.
$crash = Join-Path $Work 'crash'
$crashWork = Join-Path $crash 'work'
New-Fixture $crash @{ 'Test-Crash.ps1' = "param([string]`$Work)`n`$ErrorActionPreference = 'Stop'`n$trapLine`nNew-Item -ItemType Directory -Force `$Work | Out-Null`nthrow 'boom'`n" }
$lines = @(& $pwsh -NoProfile -NonInteractive -File (Join-Path $crash 'Test-Crash.ps1') -Work $crashWork 2>&1 | ForEach-Object { "$_" })
$code = $LASTEXITCODE
Check 'crash: a suite that stops with an error keeps its folder and prints its path' (($code -ne 0) -and ($lines -contains "Kept the work folder: $crashWork") -and (Test-Path -LiteralPath $crashWork)) ($lines -join "`n")

# Every suite with -Work (but Test-CommitAttribution.ps1, which always deletes its folder) works in a folder of its own
# by default, keeps it and says where when a check fails or the suite stops with an error (the trap line), and deletes
# it through Remove-TestWork.ps1 when all pass.
$suites = @(Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter 'Test-*.ps1' | Where-Object Name -NE 'Test-CommitAttribution.ps1' | ForEach-Object {
        $ast = [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null)
        $param = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Work' }
        if ($param) { [pscustomobject]@{ Name = $_.Name; Default = "$($param.DefaultValue)"; Text = [IO.File]::ReadAllText($_.FullName) } }
    })
Check 'suites: finds the suites that take -Work' ($suites.Name -contains 'Test-Template.ps1') ($suites.Name -join ', ')
foreach ($suite in $suites) {
    $missing = @(
        if ($suite.Default -notmatch '-\$PID"\)$') { "a default named for its process ID ($($suite.Default))" }
        if (-not $suite.Text.Contains('$ownWork = -not $PSBoundParameters.ContainsKey(''Work'')')) { '$ownWork' }
        if ($suite.Text -notmatch '(?m)^if \(\$failures\.Count\) \{ "Kept the work folder: \$Work"; ') { 'Kept the work folder' }
        if (-not $suite.Text.Contains('if ($ownWork) { & (Join-Path $PSScriptRoot ''Remove-TestWork.ps1'') $Work }')) { 'Remove-TestWork.ps1' }
        if (-not $suite.Text.Contains($trapLine)) { 'trap' }
    )
    Check "suites: $($suite.Name) keeps its own folder on a failure or an error and deletes it on a pass" ($missing.Count -eq 0) "missing: $($missing -join ', ')"
}
$attribution = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Test-CommitAttribution.ps1'), [ref]$null, [ref]$null)
$default = "$(($attribution.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Work' }).DefaultValue)"
Check 'suites: Test-CommitAttribution.ps1 works in a folder named for its process ID by default' ($default -match '-\$PID"\)$') $default

''
if ($failures.Count) { "Kept the work folder: $Work"; "Runner tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Runner tests: PASSED'
exit 0
