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
}

if ($SetupOnly) {
    ''
    if ($failures.Count) { "Run-issues end-to-end setup: FAILED ($($failures.Count))"; exit 1 }
    'Run-issues end-to-end setup: PASSED'
    exit 0
}
