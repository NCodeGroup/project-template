<#
.SYNOPSIS
    Print where the plan in a folder stands, and the workflow command to run next.

.DESCRIPTION
    Reads the Git repository that contains the folder and prints one "key: value" line per fact, in a fixed order:
    folder, worktree, branch, default, host, plan, issue, release, steps, reviewed, landing, ahead, behind, landed,
    pr, tag, published, issue-state, dirty, plans and next. A fact that does not apply prints "-". With an origin
    remote, the script first fetches it, ignoring a failure.

.PARAMETER Path
    A folder inside the repository. Defaults to the current folder.

.EXAMPLE
    .\Get-PlanState.ps1
#>
[CmdletBinding()]
param([string]$Path = '.')
$ErrorActionPreference = 'Stop'

function Read-Lines([string]$File) {
    ([IO.File]::ReadAllText($File) -split "`r?`n")
}

Push-Location -LiteralPath $Path
try {
    $folder = (& git rev-parse --show-toplevel 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -or -not $folder) { throw "Not a Git repository: $Path" }
    $folder = $folder -replace '\\', '/'

    $worktree = if ($folder -match '/\.claude/worktrees/([^/]+)$') { $Matches[1] } else { '-' }

    $branch = (& git branch --show-current 2>$null | Out-String).Trim()
    if (-not $branch) { $branch = '-' }

    $originUrl = (& git remote get-url origin 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -or -not $originUrl) {
        $hostName = 'none'
    }
    else {
        $hostName = if ($originUrl -match 'gitlab') { 'gitlab' } elseif ($originUrl -match 'github\.com') { 'github' } else { 'other' }
        & git fetch origin --prune --tags --quiet 2>$null | Out-Null
    }

    if ($hostName -eq 'none') { $default = '-' }
    else {
        $ref = (& git symbolic-ref --short refs/remotes/origin/HEAD 2>$null | Out-String).Trim()
        $default = if ($LASTEXITCODE -or -not $ref) { 'main' } else { $ref -replace '^origin/', '' }
    }

    # PLAN.md
    $plan = '-'; $issue = '-'; $release = '-'; $steps = '-'; $reviewed = '-'
    $planFile = Join-Path $folder 'PLAN.md'
    if (Test-Path -LiteralPath $planFile) {
        $lines = Read-Lines $planFile
        foreach ($line in $lines) { if ($line -match '^# Plan:\s*(.+)$') { $plan = $Matches[1].Trim(); break } }
        foreach ($line in $lines) { if ($line -match '^Issue:\s*(\S.*)$') { $issue = $Matches[1].Trim(); break } }
        foreach ($line in $lines) { if ($line -match '^Release:\s*(\S+)') { $release = $Matches[1]; break } }

        $done = 0; $total = 0; $open = 0; $escalated = @(); $failed = @()
        foreach ($line in $lines) {
            if ($line -match '^### \[([ xX!?])\] (\d+)\.') {
                $total++
                switch -CaseSensitive ($Matches[1]) {
                    { $_ -in 'x', 'X' } { $done++ }
                    ' ' { $open++ }
                    '?' { $escalated += $Matches[2] }
                    '!' { $failed += $Matches[2] }
                }
            }
        }
        $escText = if ($escalated) { $escalated -join ',' } else { '-' }
        $failText = if ($failed) { $failed -join ',' } else { '-' }
        $steps = "$done/$total open=$open escalated=$escText failed=$failText"

        foreach ($line in $lines) {
            if ($line -match '^Reviewed:\s*([0-9a-f]{7,40})\s*$') {
                $sha = $Matches[1]
                $reviewTree = (& git rev-parse "${sha}^{tree}" 2>$null | Out-String).Trim()
                $reviewOk = -not $LASTEXITCODE
                $headTree = (& git rev-parse 'HEAD^{tree}' 2>$null | Out-String).Trim()
                $reviewed = if ($reviewOk -and $reviewTree -eq $headTree) { 'current' } else { 'stale' }
                break
            }
        }
    }

    # Landing policy from AGENTS.md
    $integrate = 'pull-request'; $releasePolicy = 'none'; $changelog = 'CHANGELOG.md'
    $agents = Join-Path $folder 'AGENTS.md'
    if (Test-Path -LiteralPath $agents) {
        $inLanding = $false
        foreach ($line in (Read-Lines $agents)) {
            if ($line -match '^## Landing\s*$') { $inLanding = $true; continue }
            if ($inLanding -and $line -match '^## ') { break }
            if ($inLanding -and $line -match '^- (integrate|release|changelog):\s*(\S+)') {
                switch ($Matches[1]) {
                    'integrate' { $integrate = $Matches[2] }
                    'release' { $releasePolicy = $Matches[2] }
                    'changelog' { $changelog = $Matches[2] }
                }
            }
        }
    }
    $landing = "integrate=$integrate release=$releasePolicy changelog=$changelog"

    # Position against the default branch
    $ahead = '-'; $behind = '-'; $landed = '-'
    if ($default -ne '-') {
        $ahead = (& git rev-list --count "origin/$default..HEAD" 2>$null | Out-String).Trim()
        $behind = (& git rev-list --count "HEAD..origin/$default" 2>$null | Out-String).Trim()
        if (-not $ahead) { $ahead = '-' }
        if (-not $behind) { $behind = '-' }
        & git merge-base --is-ancestor HEAD "origin/$default" 2>$null | Out-Null
        $landed = if ($LASTEXITCODE -eq 0) { 'yes' } else { 'no' }
    }

    $tag = '-'
    if ($release -ne '-') {
        & git rev-parse -q --verify "refs/tags/$release" 2>$null | Out-Null
        $tag = if ($LASTEXITCODE -eq 0) { 'present' } else { 'absent' }
    }

    $status = (& git status --porcelain 2>$null | Out-String).Trim()
    $dirty = if ($status) { 'yes' } else { 'no' }

    # Other plan worktrees
    $others = @()
    foreach ($line in (& git worktree list --porcelain 2>$null)) {
        if ("$line" -match '^worktree (.+)$') {
            $wtPath = $Matches[1] -replace '\\', '/'
            if ($wtPath -match '/\.claude/worktrees/([^/]+)$') {
                $name = $Matches[1]
                $wtPlan = Join-Path $wtPath 'PLAN.md'
                if ($name -ne $worktree -and (Test-Path -LiteralPath $wtPlan)) {
                    $title = '-'
                    foreach ($l in (Read-Lines $wtPlan)) { if ($l -match '^# Plan:\s*(.+)$') { $title = $Matches[1].Trim(); break } }
                    $others += "$name=$title"
                }
            }
        }
    }
    $plans = if ($others) { $others -join '; ' } else { '-' }

    Write-Output "folder: $folder"
    Write-Output "worktree: $worktree"
    Write-Output "branch: $branch"
    Write-Output "default: $default"
    Write-Output "host: $hostName"
    Write-Output "plan: $plan"
    Write-Output "issue: $issue"
    Write-Output "release: $release"
    Write-Output "steps: $steps"
    Write-Output "reviewed: $reviewed"
    Write-Output "landing: $landing"
    Write-Output "ahead: $ahead"
    Write-Output "behind: $behind"
    Write-Output "landed: $landed"
    Write-Output 'pr: -'
    Write-Output "tag: $tag"
    Write-Output 'published: -'
    Write-Output 'issue-state: -'
    Write-Output "dirty: $dirty"
    Write-Output "plans: $plans"
    Write-Output 'next: -'
}
finally { Pop-Location }
