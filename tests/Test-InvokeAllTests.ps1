<#
.SYNOPSIS
    Test the runner that runs every test suite, on small fixture suites.

.DESCRIPTION
    Writes fixture folders of tiny Test-*.ps1 scripts, runs tests/Invoke-AllTests.ps1 on each in a child process, and
    checks the result lines, the summary line, the exit code, the logs and the -SkipDotnetBuild forwarding. Prints PASS
    or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to %TEMP%\project-template-all-tests-test.

.EXAMPLE
    .\tests\Test-InvokeAllTests.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path $env:TEMP 'project-template-all-tests-test'))
$ErrorActionPreference = 'Stop'
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
function Invoke-Runner([string]$Folder, [string[]]$RunnerArgs = @()) {
    $lines = [Collections.Generic.List[string]]::new()
    & $pwsh -NoProfile -NonInteractive -File $runner -Path $Folder -Work (Join-Path $Folder 'logs') @RunnerArgs 2>&1 | ForEach-Object { $lines.Add("$_") }
    [pscustomobject]@{ Lines = $lines.ToArray(); ExitCode = $LASTEXITCODE; Text = ($lines -join "`n") }
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$mixed = Join-Path $Work 'mixed'
$dotnet = Join-Path $Work 'dotnet'
$empty = Join-Path $Work 'empty'
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

''
if ($failures.Count) { "Runner tests: FAILED ($($failures.Count))"; exit 1 }
'Runner tests: PASSED'
exit 0
