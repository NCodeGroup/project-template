<#
.SYNOPSIS
    Test the coverage check every project gets, template/.template/Test-Coverage.ps1.

.DESCRIPTION
    Runs the script with pwsh -NoProfile -File and -Root set to a fixture folder, and checks its exit code and output.
    Prints PASS or FAIL per check and exits 1 on any failure (ADR-0024).
      branches     A Cobertura report with absolute file names, 2 of 2 lines and 1 of 2 branches, fails the default
                   branch minimum, and passes with -Branches 50.
      excluded     Uncovered lines of test code and of the template's files don't count.
      merge        Two Cobertura reports that each cover one of two lines merge to full coverage.
      lcov         An lcov.info at the root, 9 of 10 lines and 8 of 10 branches, passes the defaults.
      coverage.py  A report with relative file names and a <source> is read, and a failure names the least covered files.
      no-report    No report fails and says so.
      no-code      A report with only test files passes, saying it measures no code.
      no-branches  A report without branch data passes, saying no branches were measured.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-coverage-test-<process ID> in the temp
    folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-Coverage.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-coverage-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repoRoot 'template/.template/Test-Coverage.ps1'
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function New-Folder([string]$Name) {
    $path = Join-Path $Work $Name
    New-Item -ItemType Directory -Force $path | Out-Null
    $path
}
function Write-Fixture([string]$Path, [string]$Text) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Text)
}
# A Cobertura line: number, hits and, for a branch line, its condition coverage such as '50% (1/2)'.
function New-Line([int]$Number, [int]$Hits, [string]$Condition = '') {
    if ($Condition) { "<line number=`"$Number`" hits=`"$Hits`" branch=`"True`" condition-coverage=`"$Condition`"/>" }
    else { "<line number=`"$Number`" hits=`"$Hits`" branch=`"False`"/>" }
}
function New-Class([string]$FileName, [string[]]$Lines) {
    "<class name=`"c`" filename=`"$FileName`"><methods/><lines>$($Lines -join '')</lines></class>"
}
function New-Cobertura([string[]]$Classes, [string]$Source = '') {
    $sources = if ($Source) { "<sources><source>$Source</source></sources>" } else { '' }
    "<?xml version=`"1.0`" ?>`n<coverage version=`"1`">$sources<packages><package name=`"p`"><classes>$($Classes -join '')</classes></package></packages></coverage>"
}
function Invoke-Coverage([string]$Root, [string[]]$Extra = @()) {
    $out = & pwsh -NoProfile -File $script -Root $Root @Extra 2>&1 | Out-String
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $out }
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

# branches: absolute file names, 2 of 2 lines and 1 of 2 branches.
$dir = New-Folder 'branches'
Write-Fixture (Join-Path $dir 'coverage.xml') (New-Cobertura @(New-Class (Join-Path $dir 'src/Calc.cs') @((New-Line 1 3 '50% (1/2)'), (New-Line 2 1))))
$r = Invoke-Coverage $dir
Check 'branches: 1 of 2 branches fails the default minimum' ($r.ExitCode -eq 1 -and $r.Output.Contains('Branch coverage: 50.0%') -and $r.Output.Contains('Coverage: FAILED')) $r.Output
$r = Invoke-Coverage $dir @('-Branches', '50')
Check 'branches: -Branches 50 passes' ($r.ExitCode -eq 0 -and $r.Output.Contains('Statement coverage: 100.0%') -and $r.Output.Contains('Coverage: PASSED')) $r.Output

# excluded: uncovered test code and template files.
$dir = New-Folder 'excluded'
Write-Fixture (Join-Path $dir 'coverage.xml') (New-Cobertura @(
        (New-Class (Join-Path $dir 'src/Calc.cs') @((New-Line 1 1), (New-Line 2 1))),
        (New-Class (Join-Path $dir 'tests/Demo.Tests/UnitTest1.cs') @((New-Line 1 0), (New-Line 2 0))),
        (New-Class (Join-Path $dir '.template/Update-Project.ps1') @((New-Line 1 0), (New-Line 2 0)))))
$r = Invoke-Coverage $dir
Check 'excluded: test code and the template''s files don''t count' ($r.ExitCode -eq 0 -and $r.Output.Contains('Statement coverage: 100.0%') -and $r.Output.Contains('2 of 2 lines')) $r.Output

# merge: two reports that each cover one of two lines.
$dir = New-Folder 'merge'
$file = Join-Path $dir 'src/Calc.cs'
Write-Fixture (Join-Path $dir 'artifacts/test-results/a/a.cobertura.xml') (New-Cobertura @(New-Class $file @((New-Line 1 1), (New-Line 2 0))))
Write-Fixture (Join-Path $dir 'artifacts/test-results/b/b.cobertura.xml') (New-Cobertura @(New-Class $file @((New-Line 1 0), (New-Line 2 2))))
$r = Invoke-Coverage $dir
Check 'merge: two reports merge line by line' ($r.ExitCode -eq 0 -and $r.Output.Contains('Statement coverage: 100.0%')) $r.Output

# lcov: 9 of 10 lines and 8 of 10 branches.
$dir = New-Folder 'lcov'
$lcov = [Collections.Generic.List[string]]::new()
$lcov.Add('TN:'); $lcov.Add('SF:src/app.js')
1..10 | ForEach-Object { $lcov.Add("DA:$_,$(if ($_ -eq 10) { 0 } else { 1 })") }
1..10 | ForEach-Object { $lcov.Add("BRDA:$_,0,0,$(if ($_ -eq 9) { '-' } elseif ($_ -eq 10) { 0 } else { 4 })") }
$lcov.Add('end_of_record')
Write-Fixture (Join-Path $dir 'lcov.info') (($lcov -join "`n") + "`n")
$r = Invoke-Coverage $dir
Check 'lcov: 9 of 10 lines and 8 of 10 branches pass the defaults' ($r.ExitCode -eq 0 -and $r.Output.Contains('Statement coverage: 90.0% (9 of 10 lines)') -and $r.Output.Contains('Branch coverage: 80.0% (8 of 10 branches)')) $r.Output

# coverage.py: relative file names and a <source> that is the fixture root.
$dir = New-Folder 'coveragepy'
Write-Fixture (Join-Path $dir 'coverage.xml') (New-Cobertura @(
        (New-Class 'pkg/mod.py' @((New-Line 1 1), (New-Line 2 1 '100% (2/2)'), (New-Line 3 1), (New-Line 4 0))),
        (New-Class 'pkg/test_mod.py' @((New-Line 1 0), (New-Line 2 0)))) $dir)
$r = Invoke-Coverage $dir
Check 'coverage.py: a report with relative names and a source is read' ($r.ExitCode -eq 1 -and $r.Output.Contains('Statement coverage: 75.0% (3 of 4 lines)') -and $r.Output.Contains('Branch coverage: 100.0% (2 of 2 branches)') -and $r.Output.Contains('  pkg/mod.py: 1 of 4 lines uncovered')) $r.Output

# no-report.
$dir = New-Folder 'noreport'
$r = Invoke-Coverage $dir
Check 'no-report: no report fails and says so' ($r.ExitCode -eq 1 -and $r.Output.Contains('No coverage report')) $r.Output

# no-code: a report with only test files.
$dir = New-Folder 'nocode'
Write-Fixture (Join-Path $dir 'coverage.xml') (New-Cobertura @(New-Class (Join-Path $dir 'tests/test_app.py') @((New-Line 1 0))))
$r = Invoke-Coverage $dir
Check 'no-code: a report with only test files passes' ($r.ExitCode -eq 0 -and $r.Output.Contains('measure no code')) $r.Output

# no-branches: a report without branch data.
$dir = New-Folder 'nobranches'
Write-Fixture (Join-Path $dir 'coverage.xml') (New-Cobertura @(New-Class (Join-Path $dir 'src/Calc.cs') @((New-Line 1 1), (New-Line 2 1))))
$r = Invoke-Coverage $dir
Check 'no-branches: a report without branch data passes' ($r.ExitCode -eq 0 -and $r.Output.Contains('no branches measured') -and $r.Output.Contains('Coverage: PASSED')) $r.Output

''
if ($failures.Count) { "Kept the work folder: $Work"; "Coverage tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Coverage tests: PASSED'
exit 0
