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
    The scratch folder, deleted and recreated unless -CheckOnly. Defaults to project-template-run-issues-e2e in the temp folder.

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
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'MaxBudgetUsd', Justification = 'Invoke-Claude, a nested function, passes it to claude.')]
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) 'project-template-run-issues-e2e'),
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

if (-not $CheckOnly) {
    if (-not (Get-Command $Claude -ErrorAction SilentlyContinue)) { throw 'Claude Code CLI not found: install it, or pass -Claude <path>' }

    function Invoke-Claude([string]$Prompt, [string]$SessionId, [int]$Index) {
        $arguments = @('-p', $Prompt)
        if ($SessionId) { $arguments += '--resume', $SessionId }
        $arguments += '--output-format', 'json', '--permission-mode', 'bypassPermissions'
        if ($MaxBudgetUsd -gt 0) { $arguments += '--max-budget-usd', "$MaxBudgetUsd" }
        Push-Location $app
        try { $output = & $Claude @arguments | Out-String }
        finally { Pop-Location }
        [IO.File]::WriteAllText((Join-Path $Work "claude-$Index.json"), $output)
        try { $output | ConvertFrom-Json } catch { $null }
    }

    $script:cost = 0.0
    $script:sessionId = ''
    Use-FixtureEnvironment {
        $first = Invoke-Claude '/run-issues #1 wait:0' '' 1
        Check 'Claude Code run 1 returned a session' ($first -and $first.session_id) 'no session_id in the output'
        if ($first -and $first.total_cost_usd) { $script:cost += [double]$first.total_cost_usd }
        $script:sessionId = if ($first) { "$($first.session_id)" } else { '' }
        $prs = @(Get-Content -Raw -LiteralPath (Join-Path $hostDir 'prs.json') | ConvertFrom-Json)
        if ($prs.Count -eq 0 -and $first -and $first.session_id) {
            $second = Invoke-Claude 'Yes, go ahead with the run you summarized.' $first.session_id 2
            Check 'Claude Code run 2 returned a session' ($second -and $second.session_id) 'no session_id in the output'
            if ($second -and $second.total_cost_usd) { $script:cost += [double]$second.total_cost_usd }
        }
    }
    "Cost: $script:cost USD"
    "Fixture: $app"
    "Continue the session from $app with: claude --resume $script:sessionId"
}

function Read-HostJson([string]$Name) {
    $path = Join-Path $hostDir $Name
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { Get-Content -Raw -LiteralPath $path | ConvertFrom-Json } catch { $null }
}

Use-FixtureEnvironment {
    Invoke-Git -C $app fetch -q origin
    $mainBefore = if (Test-Path -LiteralPath (Join-Path $hostDir 'main.txt')) { ([IO.File]::ReadAllText((Join-Path $hostDir 'main.txt'))).Trim() } else { '' }
    $callsPath = Join-Path $hostDir 'calls.log'
    $calls = if (Test-Path -LiteralPath $callsPath) { @(Get-Content -LiteralPath $callsPath) } else { @() }

    $unsupported = @($calls | Where-Object { $_ -match '^UNSUPPORTED' })
    Check 'the stand-in saw only supported gh calls' ($unsupported.Count -eq 0) ($unsupported -join '; ')
    $forbidden = @($calls | Where-Object { $_ -match '^FORBIDDEN' })
    Check 'no gh call merged or readied a pull request' ($forbidden.Count -eq 0) ($forbidden -join '; ')

    $comments = @(Read-HostJson 'comments.json')
    $snapshot = @($comments | Where-Object { $_ -and $_.kind -eq 'issue' -and $_.number -eq 1 -and "$($_.body)" -match '^Plan snapshot\.' })
    Check 'issue #1 has a plan snapshot comment' ($snapshot.Count -ge 1) "comments: $(@($comments | Where-Object { $_ }).Count)"

    $prs = @(Read-HostJson 'prs.json' | Where-Object { $_ })
    $pr = if ($prs.Count -eq 1) { $prs[0] } else { $null }
    $prOk = $pr -and $pr.isDraft -eq $true -and $pr.headRefName -eq 'worktree-issue-1' -and $pr.baseRefName -eq 'main' -and "$($pr.body)" -match '(?m)^Closes #1\s*$'
    Check 'one draft pull request from worktree-issue-1 into main closes #1' ([bool]$prOk) "pull requests: $($prs.Count)$(if ($pr) { "; isDraft=$($pr.isDraft) head=$($pr.headRefName) base=$($pr.baseRefName)" })"

    $mainNow = "$(git -C $origin rev-parse main 2>$null)".Trim()
    Check 'origin main is unchanged' ($mainNow -and $mainNow -eq $mainBefore) "main is '$mainNow', expected '$mainBefore'"

    $subjects = @(git -C $origin log --format=%s main..worktree-issue-1 2>$null)
    $logCode = $LASTEXITCODE
    $stepOk = $logCode -eq 0 -and @($subjects | Where-Object { $_ -match '^Plan step \d+: ' }).Count -ge 1 -and @($subjects | Where-Object { $_ -match '^Plan: ' }).Count -eq 0
    Check 'origin has the plan''s step commits and no empty Plan: commit' $stepOk $(if ($logCode) { 'no worktree-issue-1 branch on origin' } else { "subjects: $($subjects -join ' | ')" })

    $null = pwsh -NoProfile -File (Join-Path $app '.template/Test-CommitAttribution.ps1') -Root $app -Base $mainBefore -Head origin/worktree-issue-1 2>&1
    Check 'the pull request''s commits carry no AI attribution' ($LASTEXITCODE -eq 0) "exit code $LASTEXITCODE"

    $noTree = "no worktree at $worktree"
    if (Test-Path -LiteralPath $worktree) {
        $st = Get-State $worktree
        $stepsOk = "$($st['steps'])" -match '^(\d+)/\1 open=0 escalated=- failed=-$'
        Check 'every step of the plan is done and reviewed' ($stepsOk -and $st['reviewed'] -eq 'current') "steps='$($st['steps'])' reviewed='$($st['reviewed'])'"
        Check 'the state script waits on the pull request' ("$($st['next'])" -like 'wait pull request #*') "next='$($st['next'])'"
        Push-Location $worktree
        try {
            $out = "$(pwsh -NoProfile -Command ". ./src/Greeting.ps1; (Get-Greeting) -eq 'Hello, world!' -and (Get-Greeting -Name '') -eq 'Hello, world!' -and (Get-Greeting -Name Ada) -eq 'Hello, Ada!'")".Trim()
            $null = pwsh -NoProfile -File tests/Test-Greeting.ps1
            $testCode = $LASTEXITCODE
        }
        finally { Pop-Location }
        Check 'Get-Greeting greets the world on the branch' ($out -eq 'True' -and $testCode -eq 0) "output='$out' test exit code $testCode"
    }
    else {
        Check 'every step of the plan is done and reviewed' $false $noTree
        Check 'the state script waits on the pull request' $false $noTree
        Check 'Get-Greeting greets the world on the branch' $false $noTree
    }
}

''
if ($failures.Count) { "Run-issues end-to-end: FAILED ($($failures.Count))"; exit 1 }
'Run-issues end-to-end: PASSED'
exit 0
