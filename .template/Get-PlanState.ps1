<#
.SYNOPSIS
    Print where the plan in a folder stands, and the workflow command to run next.

.DESCRIPTION
    Reads the Git repository that contains the folder and prints one "key: value" line per fact, in a fixed order:
    folder, worktree, branch, default, host, plan, issue, release, steps, reviewed, landing, ahead, behind, landed,
    pr, tag, published, issue-state, dirty, plans and next. A fact that does not apply prints "-". With an origin
    remote, the script first fetches it, ignoring a failure, unless -NoFetch is given.

.PARAMETER Path
    A folder inside the repository. Defaults to the current folder.

.PARAMETER NoFetch
    Skip the fetch of origin, and read ahead, behind and landed from the remote refs the last fetch left. Every
    worktree of a repository shares those refs, so a second call for another worktree needs no fetch of its own.

.EXAMPLE
    .\Get-PlanState.ps1

.EXAMPLE
    .\Get-PlanState.ps1 -Path .claude/worktrees/csv-export -NoFetch
#>
[CmdletBinding()]
param([string]$Path = '.', [switch]$NoFetch)
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
        if (-not $NoFetch) { & git fetch origin --prune --tags --quiet 2>$null | Out-Null }
    }

    if ($hostName -eq 'none') { $default = '-' }
    else {
        $ref = (& git symbolic-ref --short refs/remotes/origin/HEAD 2>$null | Out-String).Trim()
        $default = if ($LASTEXITCODE -or -not $ref) { 'main' } else { $ref -replace '^origin/', '' }
    }

    # PLAN.md
    $plan = '-'; $issue = '-'; $release = '-'; $steps = '-'; $reviewed = '-'
    $done = 0; $total = 0; $open = 0; $escalated = @(); $failed = @()
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

    # Pull request or merge request
    $pr = '-'; $prNumber = ''; $prState = ''
    if ($hostName -in 'github', 'gitlab' -and $branch -ne '-' -and $branch -ne $default) {
        $cli = if ($hostName -eq 'github') { 'gh' } else { 'glab' }
        $pr = 'unknown'
        if (Get-Command $cli -ErrorAction SilentlyContinue) {
            $json = if ($hostName -eq 'github') {
                & gh pr list --head $branch --state all --limit 1 --json number,state 2>$null | Out-String
            }
            else {
                & glab mr list --source-branch $branch --all --output json 2>$null | Out-String
            }
            if ($LASTEXITCODE -eq 0) {
                try {
                    $items = @($json | ConvertFrom-Json -ErrorAction Stop)
                    if ($items.Count -eq 0) { $pr = '-' }
                    elseif ($hostName -eq 'github') {
                        $prNumber = "$($items[0].number)"; $prState = "$($items[0].state)".ToUpperInvariant()
                        $pr = "$prNumber $prState"
                    }
                    else {
                        $prNumber = "$($items[0].iid)"
                        $prState = switch ("$($items[0].state)") { 'opened' { 'OPEN' } 'merged' { 'MERGED' } 'closed' { 'CLOSED' } default { "$($items[0].state)".ToUpperInvariant() } }
                        $pr = "$prNumber $prState"
                    }
                }
                catch { $pr = 'unknown'; $prNumber = ''; $prState = '' }
            }
        }
    }
    if ($prState -eq 'MERGED') { $landed = 'yes' }

    # Release published on the host
    $published = '-'
    if ($releasePolicy -eq 'tag+release' -and $tag -eq 'present') {
        $published = 'unknown'
        if ($hostName -in 'github', 'gitlab') {
            $cli = if ($hostName -eq 'github') { 'gh' } else { 'glab' }
            if (Get-Command $cli -ErrorAction SilentlyContinue) {
                if ($hostName -eq 'github') { & gh release view $release --json tagName 2>$null | Out-Null }
                else { & glab release view $release 2>$null | Out-Null }
                $published = if ($LASTEXITCODE -eq 0) { 'yes' } else { 'no' }
            }
        }
    }

    # State of the linked issue
    $issueState = '-'
    if ($issue -ne '-') {
        $issueState = 'unknown'
        $numbers = [regex]::Matches($issue, '\d+')
        if ($hostName -in 'github', 'gitlab' -and $numbers.Count -gt 0) {
            $issueNumber = $numbers[$numbers.Count - 1].Value
            $repoArgs = @()
            if ($issue -match '^(?<r>[^\s/#:]+/[^\s/#:]+)#\d+') { $repoArgs = @('--repo', $Matches['r']) }
            elseif ($issue -match '^https?://[^/\s]+/(?<r>.+?)/(?:-/)?issues/\d+') { $repoArgs = @('--repo', $Matches['r']) }
            $cli = if ($hostName -eq 'github') { 'gh' } else { 'glab' }
            if (Get-Command $cli -ErrorAction SilentlyContinue) {
                if ($hostName -eq 'github') {
                    $out = (& gh issue view $issueNumber @repoArgs --json state --jq .state 2>$null | Out-String).Trim()
                    if ($LASTEXITCODE -eq 0 -and $out) { $issueState = $out.ToUpperInvariant() }
                }
                else {
                    $out = & glab issue view $issueNumber @repoArgs --output json 2>$null | Out-String
                    if ($LASTEXITCODE -eq 0) {
                        try {
                            $issueState = switch ("$(($out | ConvertFrom-Json -ErrorAction Stop).state)") { 'opened' { 'OPEN' } 'closed' { 'CLOSED' } default { 'unknown' } }
                        }
                        catch { $issueState = 'unknown' }
                    }
                }
            }
        }
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

    # Next command
    $next = $null
    if ($dirty -eq 'yes') { $next = 'none uncommitted changes: commit or discard them first' }
    elseif ($plan -ne '-') {
        if ($escalated.Count -or $failed.Count) {
            $lowest = ($escalated + $failed | ForEach-Object { [int]$_ } | Sort-Object | Select-Object -First 1)
            $next = "replan-step $lowest"
        }
        elseif ($open -gt 0) { $next = 'orchestrate-plan' }
        elseif ($total -eq 0) { $next = 'none the plan has no steps' }
        elseif ($reviewed -ne 'current') { $next = 'review-plan-diff' }
        elseif ($landed -ne 'yes') {
            if ($hostName -eq 'none') { $next = 'none no origin remote to land on' }
            elseif ($prState -eq 'OPEN') { $next = "wait pull request #$prNumber is open: run ship-plan again once it merges" }
            else { $next = 'ship-plan' }
        }
        elseif (($releasePolicy -ne 'none' -and $tag -eq 'absent') -or $published -eq 'no' -or $issueState -eq 'OPEN') { $next = 'ship-plan' }
        else { $next = 'finish-plan' }
    }
    else {
        if ($branch -ne '-' -and $branch -ne $default -and $landed -eq 'yes') { $next = 'finish-plan' }
        elseif ($plans -ne '-') {
            $names = $others | ForEach-Object { ($_ -split '=', 2)[0] }
            $next = "none no plan in this folder; open plans: $($names -join ', ')"
        }
        else { $next = 'none no plan in this folder' }
    }

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
    Write-Output "pr: $pr"
    Write-Output "tag: $tag"
    Write-Output "published: $published"
    Write-Output "issue-state: $issueState"
    Write-Output "dirty: $dirty"
    Write-Output "plans: $plans"
    Write-Output "next: $next"
}
finally { Pop-Location }
