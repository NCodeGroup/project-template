<#
.SYNOPSIS
    The helpers the end-to-end tests dot-source: the fixture project, its local origin and gh stand-in, the fixture
    environment, the state script, headless Claude Code and the checks.

.DESCRIPTION
    Dot-source it from a test script that has a $failures list: Check adds the name of each failed check to it.
    New-FixtureProject makes the project every end-to-end test starts from: a project made from a snapshot of the
    working tree, with a greeting function and its test, the landing policy `protect: hook`, a bare origin in a
    github.com folder that has its main branch, and the gh stand-in (gh.ps1) in a bin folder with an empty host folder.
    Its -Data adds or overrides template answers, such as code_review for a fixture that runs NCode Review.
    Each test then writes its own host state for the stand-in.
#>

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

function New-FixtureProject([string]$RepoRoot, [string]$Work, [string]$App, [string]$Origin, [string]$Bin, [hashtable]$Data = @{}) {
    if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
    $tpl = Join-Path $Work 'template-repo'
    New-Item -ItemType Directory -Force $tpl | Out-Null
    Get-ChildItem -LiteralPath $RepoRoot -Force | Where-Object Name -NotIn '.git', '.claude' | Copy-Item -Destination $tpl -Recurse -Force
    # Claude Code's plan worktrees are other checkouts, not part of the snapshot.
    $claudeCopy = New-Item -ItemType Directory -Force (Join-Path $tpl '.claude')
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot '.claude') -Force | Where-Object Name -NE 'worktrees' | Copy-Item -Destination $claudeCopy.FullName -Recurse -Force
    Push-Location $tpl
    try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Snapshot'; Invoke-Git tag v0.1.0 }
    finally { Pop-Location }

    $answers = @{ project_name = 'Fixture App'; stack = 'other'; workflow_tools = @('claude'); test_command = 'pwsh -NoProfile -File tests/Test-Greeting.ps1' }
    foreach ($key in $Data.Keys) { $answers[$key] = $Data[$key] }
    & (Join-Path $RepoRoot 'New-Project.ps1') -Path $App -Template $tpl -Ref v0.1.0 -Defaults -Data $answers | Out-Null

    New-Item -ItemType Directory -Force (Join-Path $App 'src'), (Join-Path $App 'tests') | Out-Null
    Write-Text (Join-Path $App 'src/Greeting.ps1') @'
function Get-Greeting {
    param([string]$Name)
    "Hello, $Name!"
}
'@
    Write-Text (Join-Path $App 'tests/Test-Greeting.ps1') @'
. "$PSScriptRoot/../src/Greeting.ps1"
if ((Get-Greeting -Name Ada) -ne 'Hello, Ada!') { 'FAIL  Get-Greeting -Name Ada'; exit 1 }
'PASS  Get-Greeting -Name Ada'
exit 0
'@
    $agents = Join-Path $App 'AGENTS.md'
    $agentsText = [IO.File]::ReadAllText($agents)
    if (-not $agentsText.Contains('- protect: none')) { throw 'AGENTS.md has no "- protect: none" line.' }
    [IO.File]::WriteAllText($agents, $agentsText.Replace('- protect: none', '- protect: hook'))
    $settingsPath = Join-Path $App '.claude/settings.json'
    $s = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
    $s.permissions.PSObject.Properties.Remove('ask')
    Write-Text $settingsPath ((ConvertTo-Json -InputObject $s -Depth 10) + "`n")
    Invoke-Git -C $App add src/Greeting.ps1 tests/Test-Greeting.ps1 AGENTS.md .claude/settings.json
    Invoke-Git -C $App commit -q -m 'Add the greeting function and the fixture landing policy'

    # The origin gets main by fetching: the template's pre-push hook refuses a push to main.
    # The bare origin is always named with --git-dir, never -C, which safe.bareRepository=explicit refuses.
    New-Item -ItemType Directory -Force (Split-Path -Parent $Origin) | Out-Null
    Invoke-Git init -q --bare -b main $Origin
    Invoke-Git --git-dir=$Origin fetch -q $App main:main
    Invoke-Git -C $App remote add origin $Origin
    Invoke-Git -C $App fetch -q origin
    Invoke-Git -C $App branch -q --set-upstream-to origin/main main
    Invoke-Git -C $App remote set-head origin main

    $hostDir = Join-Path $Bin 'host'
    New-Item -ItemType Directory -Force $hostDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'gh.ps1') -Destination (Join-Path $Bin 'gh.ps1')
    [IO.File]::WriteAllText((Join-Path $Bin 'gh.cmd'), "@pwsh -NoProfile -File `"%~dp0gh.ps1`" %*`r`n")
    Write-Text (Join-Path $Bin 'gh') @'
#!/usr/bin/env sh
exec pwsh -NoProfile -File "$(dirname "$0")/gh.ps1" "$@"
'@
    if (-not $IsWindows) { chmod +x (Join-Path $Bin 'gh') }
    [IO.File]::WriteAllText((Join-Path $hostDir 'origin.txt'), $Origin)
    [IO.File]::WriteAllText((Join-Path $hostDir 'main.txt'), (git --git-dir=$Origin rev-parse main))
    New-Item -ItemType Directory -Force (Join-Path $Work 'gh-config') | Out-Null
}

function Use-FixtureEnvironment([string]$Work, [string]$Bin, [scriptblock]$Body) {
    $names = 'PATH', 'GH_CONFIG_DIR', 'GH_TOKEN', 'GITHUB_TOKEN', 'CLAUDECODE'
    $saved = @{}
    foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
    try {
        $env:PATH = $Bin + [IO.Path]::PathSeparator + $env:PATH
        $env:GH_CONFIG_DIR = Join-Path $Work 'gh-config'
        foreach ($n in 'GH_TOKEN', 'GITHUB_TOKEN', 'CLAUDECODE') { [Environment]::SetEnvironmentVariable($n, $null) }
        & $Body
    }
    finally {
        foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
    }
}

function Get-State([string]$App, [string]$Path) {
    $state = @{}
    foreach ($line in (& pwsh -NoProfile -File (Join-Path $App '.template/Get-PlanState.ps1') -Path $Path 2>$null)) {
        if ("$line" -match '^([a-z-]+): (.*)$') { $state[$Matches[1]] = $Matches[2] }
    }
    $state
}

function Invoke-Claude([string]$Claude, [double]$MaxBudgetUsd, [string]$App, [string]$Work, [string]$Prompt, [string]$SessionId, [int]$Index) {
    $arguments = @('-p', $Prompt)
    if ($SessionId) { $arguments += '--resume', $SessionId }
    $arguments += '--output-format', 'json', '--permission-mode', 'bypassPermissions'
    if ($MaxBudgetUsd -gt 0) { $arguments += '--max-budget-usd', "$MaxBudgetUsd" }
    Push-Location $App
    try { $output = & $Claude @arguments | Out-String }
    finally { Pop-Location }
    [IO.File]::WriteAllText((Join-Path $Work "claude-$Index.json"), $output)
    try { $output | ConvertFrom-Json } catch { $null }
}

function Read-HostJson([string]$HostDir, [string]$Name) {
    $path = Join-Path $HostDir $Name
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { Get-Content -Raw -LiteralPath $path | ConvertFrom-Json } catch { $null }
}
