<#
.SYNOPSIS
    Run /run-issues end to end in headless Claude Code on a fixture project with a local origin and a gh stand-in, and check the draft pull request it leaves.

.DESCRIPTION
    Makes a fixture project from the template, gives it a local origin under a github.com folder and a stand-in for gh,
    runs /run-issues #1 wait:0 in headless Claude Code, and checks what the loop left behind: a plan snapshot comment,
    a draft pull request that closes the issue, the step commits on origin, a reviewed plan, and working code.
    It costs model usage, so Invoke-AllTests.ps1 doesn't run it; run it by hand. CI runs only its fixture setup
    (-SetupOnly), so a template change that breaks the fixture still fails CI. Prints PASS or FAIL per check and exits
    1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated unless -CheckOnly. Defaults to %TEMP%\project-template-run-issues-e2e.

.PARAMETER SetupOnly
    Build the fixture and check it, without calling a model.

.PARAMETER CheckOnly
    Check the fixture of an earlier run again, without building it or calling a model.

.PARAMETER Claude
    The Claude Code CLI. Defaults to claude.

.PARAMETER MaxBudgetUsd
    The most each claude call may spend, passed as --max-budget-usd. 0 passes nothing. Defaults to 30.

.EXAMPLE
    .\tests\e2e\Test-RunIssues.ps1

.EXAMPLE
    .\tests\e2e\Test-RunIssues.ps1 -SetupOnly
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path $env:TEMP 'project-template-run-issues-e2e'),
    [switch]$SetupOnly,
    [switch]$CheckOnly,
    [string]$Claude = 'claude',
    [double]$MaxBudgetUsd = 30
)
$ErrorActionPreference = 'Stop'
if ($SetupOnly -and $CheckOnly) { throw '-SetupOnly and -CheckOnly can''t be used together.' }
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
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

$app = Join-Path $Work 'app'
$origin = Join-Path $Work 'github.com/fixture/app.git'
$bin = Join-Path $Work 'bin'
$hostDir = Join-Path $bin 'host'
$worktree = Join-Path $app '.claude/worktrees/issue-1'

if (-not $CheckOnly) {
    if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
    $tpl = Join-Path $Work 'template-repo'
    New-Item -ItemType Directory -Force $tpl | Out-Null
    Get-ChildItem -LiteralPath $repoRoot -Force | Where-Object Name -NotIn '.git', '.claude' | Copy-Item -Destination $tpl -Recurse -Force
    # Claude Code's plan worktrees are other checkouts, not part of the snapshot.
    $claudeCopy = New-Item -ItemType Directory -Force (Join-Path $tpl '.claude')
    Get-ChildItem -LiteralPath (Join-Path $repoRoot '.claude') -Force | Where-Object Name -NE 'worktrees' | Copy-Item -Destination $claudeCopy.FullName -Recurse -Force
    Push-Location $tpl
    try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Snapshot'; Invoke-Git tag v0.1.0 }
    finally { Pop-Location }

    & (Join-Path $repoRoot 'New-Project.ps1') -Path $app -Template $tpl -Ref v0.1.0 -Defaults -Data @{ project_name = 'Fixture App'; stack = 'other'; workflow_tools = @('claude'); test_command = 'pwsh -NoProfile -File tests/Test-Greeting.ps1' } | Out-Null

    New-Item -ItemType Directory -Force (Join-Path $app 'src'), (Join-Path $app 'tests') | Out-Null
    Write-Text (Join-Path $app 'src/Greeting.ps1') @'
function Get-Greeting {
    param([string]$Name)
    "Hello, $Name!"
}
'@
    Write-Text (Join-Path $app 'tests/Test-Greeting.ps1') @'
. "$PSScriptRoot/../src/Greeting.ps1"
if ((Get-Greeting -Name Ada) -ne 'Hello, Ada!') { 'FAIL  Get-Greeting -Name Ada'; exit 1 }
'PASS  Get-Greeting -Name Ada'
exit 0
'@
    $agents = Join-Path $app 'AGENTS.md'
    $agentsText = [IO.File]::ReadAllText($agents)
    if (-not $agentsText.Contains('- protect: none')) { throw 'AGENTS.md has no "- protect: none" line.' }
    [IO.File]::WriteAllText($agents, $agentsText.Replace('- protect: none', '- protect: hook'))
    $settingsPath = Join-Path $app '.claude/settings.json'
    $s = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
    $s.permissions.PSObject.Properties.Remove('ask')
    Write-Text $settingsPath ((ConvertTo-Json -InputObject $s -Depth 10) + "`n")
    Invoke-Git -C $app add src/Greeting.ps1 tests/Test-Greeting.ps1 AGENTS.md .claude/settings.json
    Invoke-Git -C $app commit -q -m 'Add the greeting function and the fixture landing policy'

    # The origin gets main by fetching: the template's pre-push hook refuses a push to main.
    New-Item -ItemType Directory -Force (Split-Path -Parent $origin) | Out-Null
    Invoke-Git init -q --bare -b main $origin
    Invoke-Git -C $origin fetch -q $app main:main
    Invoke-Git -C $app remote add origin $origin
    Invoke-Git -C $app fetch -q origin
    Invoke-Git -C $app branch -q --set-upstream-to origin/main main
    Invoke-Git -C $app remote set-head origin main

    New-Item -ItemType Directory -Force $hostDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'gh.ps1') -Destination (Join-Path $bin 'gh.ps1')
    [IO.File]::WriteAllText((Join-Path $bin 'gh.cmd'), "@pwsh -NoProfile -File `"%~dp0gh.ps1`" %*`r`n")
    Write-Text (Join-Path $bin 'gh') @'
#!/usr/bin/env sh
exec pwsh -NoProfile -File "$(dirname "$0")/gh.ps1" "$@"
'@
    if (-not $IsWindows) { chmod +x (Join-Path $bin 'gh') }
    $issueBody = @'
## What
`Get-Greeting` in `src/Greeting.ps1` returns `Hello, !` when `-Name` is empty or missing. It should return `Hello, world!`.

## Done when
- `Get-Greeting` and `Get-Greeting -Name ''` return `Hello, world!`
- `Get-Greeting -Name Ada` still returns `Hello, Ada!`
- `tests/Test-Greeting.ps1` checks all three
'@
    $issues = @{
        '1' = @{
            number    = 1
            title     = 'Greet the world when no name is given'
            body      = $issueBody.Replace("`r`n", "`n")
            state     = 'OPEN'
            url       = 'https://github.com/fixture/app/issues/1'
            labels    = @(@{ name = 'enhancement' })
            assignees = @()
            author    = @{ login = 'fixture-owner' }
        }
    }
    Write-Text (Join-Path $hostDir 'issues.json') (ConvertTo-Json -InputObject $issues -Depth 10)
    Write-Text (Join-Path $hostDir 'prs.json') '[]'
    Write-Text (Join-Path $hostDir 'comments.json') '[]'
    [IO.File]::WriteAllText((Join-Path $hostDir 'origin.txt'), $origin)
    [IO.File]::WriteAllText((Join-Path $hostDir 'main.txt'), (git -C $origin rev-parse main))
    New-Item -ItemType Directory -Force (Join-Path $Work 'gh-config') | Out-Null
}

function Use-FixtureEnvironment([scriptblock]$Body) {
    $names = 'PATH', 'GH_CONFIG_DIR', 'GH_TOKEN', 'GITHUB_TOKEN', 'CLAUDECODE'
    $saved = @{}
    foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
    try {
        $env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
        $env:GH_CONFIG_DIR = Join-Path $Work 'gh-config'
        foreach ($n in 'GH_TOKEN', 'GITHUB_TOKEN', 'CLAUDECODE') { [Environment]::SetEnvironmentVariable($n, $null) }
        & $Body
    }
    finally {
        foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
    }
}
function Get-State([string]$Path) {
    $state = @{}
    foreach ($line in (& pwsh -NoProfile -File (Join-Path $app '.template/Get-PlanState.ps1') -Path $Path 2>$null)) {
        if ("$line" -match '^([a-z-]+): (.*)$') { $state[$Matches[1]] = $Matches[2] }
    }
    $state
}

if (-not $CheckOnly) {
    Use-FixtureEnvironment {
        $st = Get-State $app
        $ok = $st['host'] -eq 'github' -and $st['default'] -eq 'main' -and $st['protected'] -eq 'hook' -and $st['landing'] -like '*integrate=pull-request*' -and $st['next'] -eq 'none no plan in this folder'
        Check 'fixture: the state script sees a GitHub origin whose main takes only pull requests' $ok "host='$($st['host'])' default='$($st['default'])' protected='$($st['protected'])' landing='$($st['landing'])' next='$($st['next'])'"
        $title = "$(gh issue view 1 --json title --jq .title)".Trim()
        Check 'fixture: gh on PATH is the stand-in' ($title -eq 'Greet the world when no name is given') "title='$title'"
        $null = pwsh -NoProfile -File (Join-Path $app 'tests/Test-Greeting.ps1')
        Check 'fixture: the fixture test passes' ($LASTEXITCODE -eq 0) "exit code $LASTEXITCODE"
    }
}

if ($SetupOnly) {
    ''
    if ($failures.Count) { "Run-issues end-to-end setup: FAILED ($($failures.Count))"; exit 1 }
    'Run-issues end-to-end setup: PASSED'
    exit 0
}
