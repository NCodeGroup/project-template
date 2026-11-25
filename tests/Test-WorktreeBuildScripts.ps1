<#
.SYNOPSIS
    Test that template/build/dod.ps1 and template/build/Update-PublicApi.ps1 work from a plan's worktree, offline.

.DESCRIPTION
    Copies both scripts into fixture repositories and runs each in this process with stand-ins for dotnet and pwsh, so
    that nothing builds. Run from a plan's worktree, under .claude/worktrees/, dod.ps1 finds the test project and runs
    the Coverage stage, and Update-PublicApi.ps1 records the packable project's API. Run in a repository whose own
    .claude, bin, obj and artifacts folders hold projects, both skip those. Prints PASS or FAIL per check and exits 1
    on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-worktree-build-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-WorktreeBuildScripts.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-worktree-build-test-$PID")
)
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Write-Text([string]$Path, [string]$Text) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function New-Fixture([string]$Root, [string[]]$Projects) {
    foreach ($name in 'dod.ps1', 'Update-PublicApi.ps1') {
        New-Item -ItemType Directory -Force (Join-Path $Root 'build') | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot "template/build/$name") -Destination (Join-Path $Root "build/$name")
    }
    Write-Text (Join-Path $Root '.copier-answers.yml') "coverage_gate: true`n"
    Write-Text (Join-Path $Root 'Demo.slnx') "<Solution />`n"
    foreach ($relative in $Projects) { Write-Text (Join-Path $Root $relative) "<Project />`n" }
}
function Invoke-Stubbed {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Stand-ins for the build tools, seen only by the script this function runs.')]
    param([string]$Script)
    $calls = [Collections.Generic.List[string]]::new()
    function dotnet { $calls.Add("dotnet $args"); if ($args[0] -eq 'msbuild') { 'true' } elseif ($args[0] -eq 'test') { 'Total: 1' }; $global:LASTEXITCODE = 0 }
    function pwsh { $calls.Add("pwsh $args"); $global:LASTEXITCODE = 0 }
    $output = & $Script 2>&1 | Out-String
    [pscustomobject]@{ Output = $output; Calls = @($calls) }
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

$worktree = Join-Path $Work 'repo/.claude/worktrees/wt'
New-Fixture $worktree @('src/Demo/Demo.csproj', 'tests/Demo.Tests/Demo.Tests.csproj')
$plain = Join-Path $Work 'plain'
New-Fixture $plain @(
    'src/Demo/Demo.csproj',
    '.claude/worktrees/other/src/Other/Other.csproj',
    '.claude/worktrees/other/tests/Other.Tests/Other.Tests.csproj',
    'src/Demo/bin/Debug/Copy.csproj',
    'src/Demo/obj/Gen.csproj',
    'artifacts/Old.Tests/Old.Tests.csproj'
)

$run = Invoke-Stubbed (Join-Path $worktree 'build/dod.ps1')
Check 'dod.ps1 from a worktree: finds the test project and runs the Coverage stage' `
($run.Output.Contains('== Coverage') -and ($run.Calls -join "`n").Contains('--collect Code Coverage;Format=cobertura')) $run.Output

$run = Invoke-Stubbed (Join-Path $plain 'build/dod.ps1')
Check "dod.ps1 outside a worktree: skips test projects under the repository's own .claude, bin, obj and artifacts folders" `
($run.Output.Contains('Definition of Done: PASSED') -and -not $run.Output.Contains('== Coverage') -and -not ($run.Calls -join "`n").Contains('--collect')) $run.Output

$run = Invoke-Stubbed (Join-Path $worktree 'build/Update-PublicApi.ps1')
Check "Update-PublicApi.ps1 from a worktree: records the packable project's API" `
($run.Output.Contains('src/Demo/Demo.csproj: added 0 entries to PublicAPI.Unshipped.txt.') -and (Test-Path -LiteralPath (Join-Path $worktree 'src/Demo/PublicAPI.Shipped.txt'))) $run.Output

$run = Invoke-Stubbed (Join-Path $plain 'build/Update-PublicApi.ps1')
$msbuildCalls = @($run.Calls | Where-Object { $_.StartsWith('dotnet msbuild ') })
Check "Update-PublicApi.ps1 outside a worktree: skips projects under the repository's own .claude, bin and obj folders" `
($msbuildCalls.Count -eq 1 -and $run.Output.Contains('src/Demo/Demo.csproj: added 0 entries') -and $run.Output -notmatch 'Other|Copy\.csproj|Gen\.csproj') ($run.Output + ($run.Calls -join "`n"))

if ($failures.Count) { "Kept the work folder: $Work"; "Worktree build script tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Worktree build script tests: PASSED'
exit 0
