<#
.SYNOPSIS
    Test that workflow\Get-PlanState.ps1 starts its network calls together instead of one after another.

.DESCRIPTION
    Builds a bare origin and a clone in a scratch folder, with a plan that names two issues and a release tag, and puts a
    stand-in for gh first on PATH. Runs Get-PlanState.ps1 once with a stand-in that answers at once and once with a stand-in
    that waits before each of its five answers, then checks that it prints the same lines both times and that the delayed
    run takes less than the run without the delay plus three and a half delays: run one after another, the five calls add five
    delays. Then removes the release tag from the clone and checks that a tag only origin has is still read as published.
    Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-plan-state-concurrency-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-PlanStateConcurrency.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-plan-state-concurrency-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Invoke-Git {
    git -c user.name=template-test -c user.email=template-test@example.invalid @args
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed." }
}
function Write-Text([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n"))
}

$script = Join-Path $repoRoot 'workflow/Get-PlanState.ps1'
$delayMs = 2000

# Runs Get-PlanState.ps1 in a pwsh of its own and times it, so the time covers everything the script does.
function Measure-PlanState([string]$Path) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $lines = @(& pwsh -NoProfile -File $script -Path $Path 2>$null | ForEach-Object { "$_" })
    $watch.Stop()
    [pscustomobject]@{ Lines = $lines; Milliseconds = $watch.ElapsedMilliseconds }
}
function ConvertTo-State([string[]]$Lines) {
    $state = @{}
    foreach ($line in $Lines) {
        if ("$line" -match '^([a-z-]+): (.*)$') { $state[$Matches[1]] = $Matches[2] }
    }
    $state
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null
# The github.com folder in the origin's path makes Get-PlanState.ps1 read the host as github.
$origin = Join-Path $Work 'github.com/origin.git'
$repo = Join-Path $Work 'repo'
New-Item -ItemType Directory -Force (Split-Path -Parent $origin) | Out-Null
Invoke-Git init -q --bare -b main $origin
Invoke-Git clone -q $origin $repo 2>$null

Push-Location $repo
try {
    Write-Text (Join-Path $repo 'AGENTS.md') "# Demo`n`n## Landing`n`n- release: tag+release`n"
    Invoke-Git add AGENTS.md
    Invoke-Git commit -q -m 'Add AGENTS.md'
    Invoke-Git push -q origin HEAD:refs/heads/main
    Invoke-Git switch -q -c plan-demo
    Invoke-Git commit -q --allow-empty -m 'Plan step 1: Demo'
    Invoke-Git tag -a v0.2.0 -m v0.2.0
    Invoke-Git push -q origin v0.2.0
}
finally { Pop-Location }
[IO.File]::AppendAllText((Join-Path $repo '.git/info/exclude'), "PLAN.md`n")
Write-Text (Join-Path $repo 'PLAN.md') @'
# Plan: Demo plan

Issue: #7 #8
Release: v0.2.0

## Steps

### [ ] 1. Demo

- Done when: `exit 0`
'@

# The stand-in for gh: it waits before each answer when a delay file is next to it, and answers like GitHub would.
$bin = Join-Path $Work 'bin'
New-Item -ItemType Directory -Force $bin | Out-Null
Write-Text (Join-Path $bin 'gh.ps1') @'
$delay = Join-Path $PSScriptRoot 'delay'
if (Test-Path -LiteralPath $delay) { Start-Sleep -Milliseconds ([int][IO.File]::ReadAllText($delay)) }
if ($args[0] -eq 'pr' -and $args[1] -eq 'list') { '[]'; exit 0 }
if ($args[0] -eq 'issue' -and $args[1] -eq 'view') { if ($args[2] -eq '7') { 'OPEN' } else { 'CLOSED' }; exit 0 }
if ($args[0] -eq 'api') { 'HTTP/2.0 200 OK'; 'Content-Type: application/json'; ''; '[{"type":"pull_request"}]'; exit 0 }
if ($args[0] -eq 'release' -and $args[1] -eq 'view') { '{"tagName":"v0.2.0"}'; exit 0 }
exit 1
'@

$savedPath = $env:PATH
$env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
try {
    $quick = Measure-PlanState $repo
    Write-Text (Join-Path $bin 'delay') "$delayMs"
    $slow = Measure-PlanState $repo
    Remove-Item -LiteralPath (Join-Path $bin 'delay') -Force
    Push-Location $repo
    try { Invoke-Git tag -d v0.2.0 | Out-Null }
    finally { Pop-Location }
    $fetched = Measure-PlanState $repo
}
finally { $env:PATH = $savedPath }

$state = ConvertTo-State $slow.Lines
$expected = [ordered]@{
    host = 'github'; pr = '-'; protected = 'host'; tag = 'present'; published = 'yes'
    'issue-states' = '#7=OPEN #8=CLOSED'; 'issue-state' = 'OPEN'
}
$mismatches = foreach ($key in $expected.Keys) {
    if ("$($state[$key])" -ne "$($expected[$key])") { "$key='$($state[$key])' expected '$($expected[$key])'" }
}
Check 'answers: Get-PlanState.ps1 prints what the stand-in for gh answers' (-not $mismatches) ($mismatches -join '; ')

Check 'answers: the delayed run prints the same lines as the run without the delay' (($quick.Lines.Count -gt 0) -and (($quick.Lines -join "`n") -eq ($slow.Lines -join "`n"))) "without the delay: $($quick.Lines -join ' | '); with it: $($slow.Lines -join ' | ')"

$limit = $quick.Milliseconds + [int](3.5 * $delayMs)
Check "concurrency: five gh calls of $delayMs ms each take less than $limit ms, the run without the delay plus 3.5 delays" ($slow.Milliseconds -lt $limit) "the run without the delay took $($quick.Milliseconds) ms, the delayed run $($slow.Milliseconds) ms"

$fetchedState = ConvertTo-State $fetched.Lines
Check 'release: a release tag only the fetch brings in is still read as published' (($fetchedState['tag'] -eq 'present') -and ($fetchedState['published'] -eq 'yes')) "tag='$($fetchedState['tag'])' published='$($fetchedState['published'])'"

''
if ($failures.Count) { "Kept the work folder: $Work"; "Plan state concurrency tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Plan state concurrency tests: PASSED'
exit 0
