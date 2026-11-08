<#
.SYNOPSIS
    The helpers the end-to-end tests dot-source: the fixture project, its local origin and the gh and glab stand-ins, the fixture
    environment, the state script, the headless runner in Agent.ps1 and the checks.

.DESCRIPTION
    Dot-source it from a test script that has a $failures list: Check adds the name of each failed check to it.
    It dot-sources Agent.ps1, the headless runner.
    Every fixture has both tools' commands (workflow_tools claude and copilot), so each test runs under either tool.
    Test-InstalledCommand checks that both tools' copies of a command hold what the setup reads from one.
    New-FixtureProject makes the project every end-to-end test starts from: a project made from a snapshot of the
    working tree, with a greeting function and its test, the landing policy `protect: hook`, a bare origin in a
    github.com folder that has its main branch, and the gh and glab stand-ins (gh.ps1, glab.ps1) in a bin folder with an empty host folder; Copy-StandIn copies a stand-in with the tests/StandInLog.ps1 it dot-sources. It keeps Copier's mirrors in a copier-cache folder in the work folder.
    Its -Data adds or overrides template answers, such as code_review for a fixture that runs NCode Review.
    Its -Landing sets keys of the Landing section in AGENTS.md, such as max-review-rounds.
    Each test then writes its own host state for the stand-in.
#>

. (Join-Path $PSScriptRoot 'Agent.ps1')

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Test-InstalledCommand([string]$App, [string]$Name, [string]$What, [string[]]$Text) {
    $problems = [Collections.Generic.List[string]]::new()
    foreach ($tool in 'claude', 'copilot') {
        $path = Get-CommandFile $App $tool $Name
        if (-not (Test-Path -LiteralPath $path)) { $problems.Add("$path is missing"); continue }
        $content = Get-Content -Raw -LiteralPath $path
        foreach ($item in $Text) {
            if ($item -and -not $content.Contains($item)) { $problems.Add("${path}: no '$item'") }
        }
    }
    Check "fixture: the Claude Code and Copilot copies of /$Name hold $What" ($problems.Count -eq 0) ($problems -join '; ')
}
function Invoke-Git {
    git -c user.name=template-test -c user.email=template-test@example.invalid @args
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed." }
}
function Write-Text([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n"))
}

function Copy-StandIn([string]$Name, [string]$Destination) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "$Name.ps1") -Destination (Join-Path $Destination "$Name.ps1")
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'StandInLog.ps1') -Destination (Join-Path $Destination 'StandInLog.ps1')
}

function New-FixtureProject([string]$RepoRoot, [string]$Work, [string]$App, [string]$Origin, [string]$Bin, [hashtable]$Data = @{}, [hashtable]$Landing = @{}) {
    if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
    $tpl = Join-Path $Work 'template-repo'
    $null = & (Join-Path $RepoRoot 'tests/New-TemplateSnapshot.ps1') $tpl

    $answers = @{ project_name = 'Fixture App'; stack = 'other'; workflow_tools = @('claude', 'copilot'); test_command = 'pwsh -NoProfile -File tests/Test-Greeting.ps1' }
    foreach ($key in $Data.Keys) { $answers[$key] = $Data[$key] }
    # The fixture keeps Copier's mirrors in its work folder, not in the user's cache, unless COPIER_CACHE_DIR is already set.
    $copierCache = $env:COPIER_CACHE_DIR
    if (-not $copierCache) { $env:COPIER_CACHE_DIR = Join-Path $Work 'copier-cache' }
    try { & (Join-Path $RepoRoot 'New-Project.ps1') -Path $App -Template $tpl -Ref v0.1.0 -Defaults -Data $answers | Out-Null }
    finally { $env:COPIER_CACHE_DIR = $copierCache }

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
    $agentsText = $agentsText.Replace('- protect: none', '- protect: hook')
    foreach ($key in $Landing.Keys) {
        $pattern = "(?m)^- $([regex]::Escape($key)): .*$"
        if ($agentsText -notmatch $pattern) { throw "AGENTS.md has no ""- ${key}:"" line." }
        $agentsText = $agentsText -replace $pattern, "- ${key}: $($Landing[$key])"
    }
    [IO.File]::WriteAllText($agents, $agentsText)
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
    Copy-StandIn gh $Bin
    [IO.File]::WriteAllText((Join-Path $Bin 'gh.cmd'), "@pwsh -NoProfile -File `"%~dp0gh.ps1`" %*`r`n")
    Write-Text (Join-Path $Bin 'gh') @'
#!/usr/bin/env sh
exec pwsh -NoProfile -File "$(dirname "$0")/gh.ps1" "$@"
'@
    if (-not $IsWindows) { chmod +x (Join-Path $Bin 'gh') }
    Copy-StandIn glab $Bin
    [IO.File]::WriteAllText((Join-Path $Bin 'glab.cmd'), "@pwsh -NoProfile -File `"%~dp0glab.ps1`" %*`r`n")
    Write-Text (Join-Path $Bin 'glab') @'
#!/usr/bin/env sh
exec pwsh -NoProfile -File "$(dirname "$0")/glab.ps1" "$@"
'@
    if (-not $IsWindows) { chmod +x (Join-Path $Bin 'glab') }
    [IO.File]::WriteAllText((Join-Path $hostDir 'origin.txt'), $Origin)
    [IO.File]::WriteAllText((Join-Path $hostDir 'main.txt'), (git --git-dir=$Origin rev-parse main))
    New-Item -ItemType Directory -Force (Join-Path $Work 'gh-config') | Out-Null
    New-Item -ItemType Directory -Force (Join-Path $Work 'glab-config') | Out-Null
}

function Use-FixtureEnvironment([string]$Work, [string]$Bin, [scriptblock]$Body) {
    $names = 'PATH', 'GH_CONFIG_DIR', 'GLAB_CONFIG_DIR', 'GH_TOKEN', 'GITHUB_TOKEN', 'GITLAB_TOKEN', 'CLAUDECODE', 'COPILOT_GITHUB_TOKEN'
    $saved = @{}
    foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
    try {
        $env:PATH = $Bin + [IO.Path]::PathSeparator + $env:PATH
        $env:GH_CONFIG_DIR = Join-Path $Work 'gh-config'
        $env:GLAB_CONFIG_DIR = Join-Path $Work 'glab-config'
        foreach ($n in 'GH_TOKEN', 'GITHUB_TOKEN', 'GITLAB_TOKEN', 'CLAUDECODE', 'COPILOT_GITHUB_TOKEN') { [Environment]::SetEnvironmentVariable($n, $null) }
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

function Read-HostJson([string]$HostDir, [string]$Name) {
    $path = Join-Path $HostDir $Name
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { Get-Content -Raw -LiteralPath $path | ConvertFrom-Json } catch { $null }
}
