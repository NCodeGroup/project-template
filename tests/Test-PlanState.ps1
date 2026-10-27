<#
.SYNOPSIS
    Test that workflow\Get-PlanState.ps1 reads where a plan stands and names the next command.

.DESCRIPTION
    Builds a bare origin and a clone in a scratch folder, then walks a plan through its life: no plan, open steps, an
    escalated step, finished steps, a review, a stale review, the Landing section of AGENTS.md, a push to the default
    branch, a tag, an upstream commit, an upstream commit read with and without -NoFetch, a second plan worktree, no plan, and uncommitted changes, then merged GitHub pull requests and GitLab merge requests, then the issues of a one-issue plan and a group plan, read through stand-ins for gh and glab. After each move it runs
    Get-PlanState.ps1 and compares the key: value lines it prints with what the state should be. Prints PASS or FAIL
    per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to %TEMP%\project-template-plan-state-test.

.EXAMPLE
    .\tests\Test-PlanState.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path $env:TEMP 'project-template-plan-state-test'))
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Invoke-Git {
    git -c user.name=template-test -c user.email=template-test@example.invalid @args
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed." }
}

$script = Join-Path $repoRoot 'workflow/Get-PlanState.ps1'
function Get-State([string]$Path, [switch]$NoFetch) {
    $state = @{}
    $extra = @(if ($NoFetch) { '-NoFetch' })
    foreach ($line in (& pwsh -NoProfile -File $script -Path $Path @extra 2>$null)) {
        if ("$line" -match '^([a-z-]+): (.*)$') { $state[$Matches[1]] = $Matches[2] }
    }
    $state
}
function Test-State([hashtable]$State, [hashtable]$Expected) {
    $mismatches = foreach ($key in $Expected.Keys) {
        if ("$($State[$key])" -ne "$($Expected[$key])") { "$key='$($State[$key])' expected '$($Expected[$key])'" }
    }
    [pscustomobject]@{ Ok = -not $mismatches; Detail = $mismatches -join '; ' }
}
function Write-Text([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n"))
}
function Add-Commit([string]$Dir, [string]$File, [string]$Message) {
    Push-Location $Dir
    try { Write-Text (Join-Path $Dir $File) "$File`n"; Invoke-Git add $File; Invoke-Git commit -q -m $Message }
    finally { Pop-Location }
}
function Get-Head([string]$Dir) {
    Push-Location $Dir
    try { (git rev-parse HEAD).Trim() }
    finally { Pop-Location }
}
function New-PlanText([string]$Step2, [string]$Reviewed = '', [string]$Issue = '#7') {
    $reviewedLine = if ($Reviewed) { "Reviewed: $Reviewed`n" } else { '' }
    $text = @'
# Plan: Demo plan

Issue: @@ISSUE@@
Release: v0.2.0
@@REVIEWED@@
## Steps

### [x] 1. Add a

- Done when: `exit 0`

### [@@STEP2@@] 2. Add b

- Done when: `exit 0`

## Review checklist

- Check the steps.
'@
    $text.Replace("@@REVIEWED@@`n", $reviewedLine).Replace('@@STEP2@@', $Step2).Replace('@@ISSUE@@', $Issue).Replace("`r`n", "`n") + "`n"
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null
$origin = Join-Path $Work 'origin.git'
$seed = Join-Path $Work 'seed'
$repo = Join-Path $Work 'repo'

Push-Location $Work
try {
    Invoke-Git init -q --bare -b main $origin
    Invoke-Git clone -q $origin $seed
}
finally { Pop-Location }
Add-Commit $seed 'README.md' 'Add README'
Push-Location $seed
try { Invoke-Git push -q origin HEAD:refs/heads/main }
finally { Pop-Location }
Push-Location $Work
try { Invoke-Git clone -q $origin $repo }
finally { Pop-Location }
[IO.File]::AppendAllText((Join-Path $repo '.git/info/exclude'), "PLAN.md`n.claude/worktrees/`n")

$planFile = Join-Path $repo 'PLAN.md'

# 1. On the default branch with no plan.
$r = Test-State (Get-State $repo) @{ plan = '-'; default = 'main'; branch = 'main'; host = 'other'; worktree = '-'; ahead = '0'; behind = '0'; landed = 'yes'; dirty = 'no'; plans = '-' }
Check 'local: a clean default branch with no plan' $r.Ok $r.Detail
$state = Get-State $repo
Check 'next: no plan means nothing to do' ($state['next'] -like 'none *') "next='$($state['next'])' expected 'none *'"

# 2. A plan branch with one finished step and one open step.
Push-Location $repo
try { Invoke-Git switch -q -c worktree-demo }
finally { Pop-Location }
Add-Commit $repo 'a.txt' 'Plan step 1: A'
Write-Text $planFile (New-PlanText ' ')
$r = Test-State (Get-State $repo) @{ plan = 'Demo plan'; issue = '#7'; release = 'v0.2.0'; steps = '1/2 open=1 escalated=- failed=-'; reviewed = '-'; ahead = '1'; landed = 'no'; dirty = 'no'; tag = 'absent' }
Check "local: reads the plan's header and steps" $r.Ok $r.Detail
$r = Test-State (Get-State $repo) @{ next = 'orchestrate-plan' }
Check 'next: an open step runs orchestrate-plan' $r.Ok $r.Detail

# 3. An escalated step.
Write-Text $planFile (New-PlanText '?')
$r = Test-State (Get-State $repo) @{ steps = '1/2 open=0 escalated=2 failed=-'; next = 'replan-step 2' }
Check 'next: an escalated step is re-planned first' $r.Ok $r.Detail

# 4. All steps finished, no review yet.
Write-Text $planFile (New-PlanText 'x')
$r = Test-State (Get-State $repo) @{ steps = '2/2 open=0 escalated=- failed=-'; reviewed = '-'; next = 'review-plan-diff' }
Check 'next: finished steps without a review run review-plan-diff' $r.Ok $r.Detail

# 5. Reviewed at the current HEAD, with no AGENTS.md.
Write-Text $planFile (New-PlanText 'x' (Get-Head $repo))
$r = Test-State (Get-State $repo) @{ landing = 'integrate=pull-request release=none changelog=CHANGELOG.md draft=no' }
Check 'local: the default landing policy applies without AGENTS.md' $r.Ok $r.Detail
$r = Test-State (Get-State $repo) @{ reviewed = 'current'; pr = '-'; merge = '-'; next = 'ship-plan' }
Check 'next: a reviewed plan is shipped' $r.Ok $r.Detail

# 6. A commit after the review.
Add-Commit $repo 'b.txt' 'Plan step 2: B'
$r = Test-State (Get-State $repo) @{ reviewed = 'stale'; next = 'review-plan-diff' }
Check 'next: a commit after the review needs a new review' $r.Ok $r.Detail

# 7. AGENTS.md with a Landing section, review at the new HEAD, then an empty commit.
Write-Text (Join-Path $repo 'AGENTS.md') @'
# Demo

## Landing

- integrate: direct
- release: tag+release
- changelog: docs/CHANGES.md
- draft: `yes`
'@
Push-Location $repo
try { Invoke-Git add AGENTS.md; Invoke-Git commit -q -m 'Add AGENTS.md' }
finally { Pop-Location }
Write-Text $planFile (New-PlanText 'x' (Get-Head $repo))
Push-Location $repo
try { Invoke-Git commit -q --allow-empty -m 'Re-plan step 2: B' }
finally { Pop-Location }
$r = Test-State (Get-State $repo) @{ landing = 'integrate=direct release=tag+release changelog=docs/CHANGES.md draft=yes' }
Check 'local: reads the Landing section of AGENTS.md' $r.Ok $r.Detail
$r = Test-State (Get-State $repo) @{ reviewed = 'current'; next = 'ship-plan' }
Check 'next: an empty commit after the review keeps it current' $r.Ok $r.Detail

# 8. Pushed to the default branch.
Push-Location $repo
try { Invoke-Git push -q origin HEAD:refs/heads/main }
finally { Pop-Location }
$r = Test-State (Get-State $repo) @{ landed = 'yes'; ahead = '0'; tag = 'absent' }
Check 'local: work pushed to the default branch is landed' $r.Ok $r.Detail
$r = Test-State (Get-State $repo) @{ next = 'ship-plan' }
Check 'next: a landed plan without its tag is shipped again' $r.Ok $r.Detail

# 9. Tagged and pushed.
Push-Location $repo
try { Invoke-Git tag -a v0.2.0 -m v0.2.0; Invoke-Git push -q origin v0.2.0 }
finally { Pop-Location }
$r = Test-State (Get-State $repo) @{ tag = 'present'; published = 'unknown'; 'issue-state' = 'unknown'; next = 'finish-plan' }
Check 'next: a landed, tagged plan is finished' $r.Ok $r.Detail

# 10. A commit upstream on the default branch.
Push-Location $seed
try { Invoke-Git pull -q }
finally { Pop-Location }
Add-Commit $seed 'c.txt' 'Add c'
Push-Location $seed
try { Invoke-Git push -q origin HEAD:refs/heads/main }
finally { Pop-Location }
$r = Test-State (Get-State $repo) @{ behind = '1'; landed = 'yes' }
Check 'local: commits on the default branch upstream count as behind' $r.Ok $r.Detail

# 10b. A commit upstream after the last fetch.
Add-Commit $seed 'd.txt' 'Add d'
Push-Location $seed
try { Invoke-Git push -q origin HEAD:refs/heads/main }
finally { Pop-Location }
$r = Test-State (Get-State $repo -NoFetch) @{ behind = '1' }
Check 'local: -NoFetch leaves out commits pushed after the last fetch' $r.Ok $r.Detail
$r = Test-State (Get-State $repo) @{ behind = '2'; landed = 'yes' }
Check 'local: without -NoFetch, the fetch counts them as behind' $r.Ok $r.Detail

# 11. Another plan worktree.
Push-Location $repo
try { Invoke-Git worktree add -q .claude/worktrees/other -b worktree-other }
finally { Pop-Location }
$other = Join-Path $repo '.claude/worktrees/other'
Write-Text (Join-Path $other 'PLAN.md') @'
# Plan: Other plan

## Steps

### [ ] 1. X

- Done when: `exit 0`
'@
$r = Test-State (Get-State $repo) @{ plans = 'other=Other plan' }
Check 'local: lists the other plan worktrees' $r.Ok $r.Detail
$r = Test-State (Get-State $other) @{ worktree = 'other'; branch = 'worktree-other'; plan = 'Other plan' }
Check 'local: names the worktree it runs in' $r.Ok $r.Detail

# 12. No plan on a landed branch.
Remove-Item -LiteralPath $planFile -Force
$r = Test-State (Get-State $repo) @{ plan = '-'; next = 'finish-plan' }
Check 'next: a landed branch without a plan is finished' $r.Ok $r.Detail

# 13. Uncommitted changes.
Write-Text (Join-Path $repo 'scratch.txt') "scratch`n"
$state = Get-State $repo
Check 'next: uncommitted changes stop everything' (($state['dirty'] -eq 'yes') -and ($state['next'] -like 'none *')) "dirty='$($state['dirty'])' next='$($state['next'])' expected dirty 'yes' and next 'none *'"

# Stand-ins for gh and glab: both print the contents of pr.json for a 'pr list' or 'mr list' call and fail otherwise.
$bin = Join-Path $Work 'bin'
New-Item -ItemType Directory -Force $bin | Out-Null
foreach ($cli in 'gh', 'glab') {
    Write-Text (Join-Path $bin "$cli.ps1") @'
if ($args[1] -eq 'list' -and $args[0] -in 'pr', 'mr') { [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'pr.json')); exit 0 }
if ($args[0] -eq 'issue' -and $args[1] -eq 'view') {
    $file = Join-Path $PSScriptRoot 'issues.json'
    if (-not (Test-Path $file)) { exit 1 }
    $issues = [IO.File]::ReadAllText($file) | ConvertFrom-Json
    $property = $issues.PSObject.Properties["$($args[2])"]
    if (-not $property) { exit 1 }
    if ((Split-Path -Leaf $PSCommandPath) -eq 'glab.ps1') {
        ConvertTo-Json @{ state = $(if ($property.Value -eq 'OPEN') { 'opened' } else { 'closed' }) }
    }
    else { $property.Value }
    exit 0
}
exit 1
'@
}
function Set-MergedRequest([string]$Merge, [string]$Head, [switch]$GitHub, [string]$Newer = '', [string]$Base = 'main') {
    $item = if ($GitHub) {
        @{ number = 6; state = 'MERGED'; mergeCommit = @{ oid = $Merge }; headRefOid = $Head; baseRefName = $Base }
    }
    else {
        @{ iid = 5; state = 'merged'; merge_commit_sha = $null; squash_commit_sha = $Merge; sha = $Head; target_branch = $Base }
    }
    $items = @($item)
    if ($Newer) {
        $newerItem = if ($GitHub) {
            @{ number = 8; state = $Newer; mergeCommit = $null; headRefOid = $Head }
        }
        else {
            @{ iid = 8; state = $Newer; merge_commit_sha = $null; squash_commit_sha = $null; sha = $Head }
        }
        $items = @($newerItem, $item)
    }
    Write-Text (Join-Path $bin 'pr.json') (ConvertTo-Json -InputObject $items -Depth 3)
}
function Set-IssueStates([hashtable]$States) { Write-Text (Join-Path $bin 'issues.json') (ConvertTo-Json -InputObject $States) }
function New-MergedClone([string]$Dir) {
    New-Item -ItemType Directory -Force $Dir | Out-Null
    $repoDir = Join-Path $Dir 'repo'
    Push-Location $Dir
    try {
        Invoke-Git init -q --bare -b main (Join-Path $Dir 'origin.git')
        Invoke-Git clone -q (Join-Path $Dir 'origin.git') $repoDir
    }
    finally { Pop-Location }
    [IO.File]::AppendAllText((Join-Path $repoDir '.git/info/exclude'), "PLAN.md`n")
    Add-Commit $repoDir 'README.md' 'Add README'
    Push-Location $repoDir
    try {
        Invoke-Git push -q origin HEAD:refs/heads/main
        Invoke-Git switch -q -c worktree-merged
    }
    finally { Pop-Location }
    Add-Commit $repoDir 'e.txt' 'Plan step 1: E'
    $head = Get-Head $repoDir
    Push-Location $repoDir
    try {
        $squash = (Invoke-Git commit-tree 'HEAD^{tree}' -p origin/main -m 'E (squashed)' | Out-String).Trim()
        Invoke-Git push -q origin "${squash}:refs/heads/main"
        $twin = (Invoke-Git commit-tree 'HEAD^{tree}' -m 'E (rebased)' | Out-String).Trim()
    }
    finally { Pop-Location }
    [pscustomobject]@{ Repo = $repoDir; Head = $head; Squash = $squash; Twin = $twin }
}

$savedPath = $env:PATH
$env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
try {
    # 14. A merged merge request on a GitLab origin.
    $gl = New-MergedClone (Join-Path $Work 'gitlab')

    Set-MergedRequest $gl.Squash $gl.Head
    $r = Test-State (Get-State $gl.Repo) @{ host = 'gitlab'; pr = '5 MERGED'; merge = $gl.Squash; ahead = '1'; landed = 'yes'; next = 'finish-plan' }
    Check 'local: a squash-merged merge request that holds HEAD is landed' $r.Ok $r.Detail

    Set-MergedRequest $gl.Squash $gl.Twin
    $r = Test-State (Get-State $gl.Repo) @{ landed = 'yes' }
    Check 'local: a merged head with the same tree as HEAD is landed' $r.Ok $r.Detail

    Set-MergedRequest $gl.Twin $gl.Head
    $r = Test-State (Get-State $gl.Repo) @{ landed = 'no' }
    Check 'local: a merge commit missing from the default branch is not landed' $r.Ok $r.Detail

    Set-MergedRequest $gl.Squash $gl.Head -Newer 'opened'
    $r = Test-State (Get-State $gl.Repo) @{ pr = '5 MERGED'; merge = $gl.Squash; landed = 'yes' }
    Check 'local: an older merged merge request that holds HEAD is landed under a newer open one' $r.Ok $r.Detail

    Set-MergedRequest $gl.Squash $gl.Head
    Add-Commit $gl.Repo 'f.txt' 'Plan step 2: F'
    Write-Text (Join-Path $gl.Repo 'PLAN.md') (New-PlanText 'x' (Get-Head $gl.Repo))
    $state = Get-State $gl.Repo
    Check 'next: commits after a merged merge request need a new branch' (($state['landed'] -eq 'no') -and ($state['next'] -like 'none pull request #5 merged*')) "landed='$($state['landed'])' next='$($state['next'])' expected landed 'no' and next 'none pull request #5 merged*'"

    Set-MergedRequest $gl.Squash $gl.Head -Newer 'opened'
    $r = Test-State (Get-State $gl.Repo) @{ pr = '8 OPEN'; landed = 'no'; next = 'wait pull request #8 is open: run ship-plan again once it merges' }
    Check 'next: a newer open merge request is waited for when no merged one holds HEAD' $r.Ok $r.Detail

    Set-MergedRequest $gl.Squash $gl.Head -Base 'release'
    $r = Test-State (Get-State $gl.Repo) @{ landed = 'no'; next = 'none pull request #5 merged into release, not main: this branch lands once release reaches main; run ship-plan again then' }
    Check 'next: a merge request merged into another branch waits for that branch' $r.Ok $r.Detail

    Write-Text (Join-Path $gl.Repo 'AGENTS.md') "# Demo`n`n## Landing`n`n- integrate: direct`n"
    Push-Location $gl.Repo
    try { Invoke-Git add AGENTS.md; Invoke-Git commit -q -m 'Add AGENTS.md' }
    finally { Pop-Location }
    Write-Text (Join-Path $gl.Repo 'PLAN.md') (New-PlanText 'x' (Get-Head $gl.Repo))
    Set-MergedRequest $gl.Squash $gl.Head
    $r = Test-State (Get-State $gl.Repo) @{ landed = 'no'; next = 'ship-plan' }
    Check 'next: with integrate direct, a merged merge request without HEAD leaves the branch to ship-plan' $r.Ok $r.Detail

    # 15. A merged pull request on a GitHub origin.
    $gh = New-MergedClone (Join-Path $Work 'github.com')

    Set-MergedRequest $gh.Squash $gh.Head -GitHub
    $r = Test-State (Get-State $gh.Repo) @{ host = 'github'; pr = '6 MERGED'; merge = $gh.Squash; landed = 'yes' }
    Check 'local: a merged GitHub pull request that holds HEAD is landed' $r.Ok $r.Detail

    Set-MergedRequest $gh.Twin $gh.Head -GitHub
    $r = Test-State (Get-State $gh.Repo) @{ landed = 'no' }
    Check 'local: a GitHub merge commit missing from the default branch is not landed' $r.Ok $r.Detail

    Set-MergedRequest $gh.Squash $gh.Head -GitHub -Newer 'CLOSED'
    $r = Test-State (Get-State $gh.Repo) @{ pr = '6 MERGED'; merge = $gh.Squash; landed = 'yes' }
    Check 'local: an older merged GitHub pull request that holds HEAD is landed under a newer closed one' $r.Ok $r.Detail

    $ff = New-MergedClone (Join-Path (Join-Path $Work 'ff') 'github.com')
    Push-Location $ff.Repo
    try { Invoke-Git push -q --force origin "$($ff.Head):refs/heads/main" }
    finally { Pop-Location }
    Set-MergedRequest $ff.Head $ff.Head -GitHub -Newer 'CLOSED'
    $r = Test-State (Get-State $ff.Repo) @{ pr = '6 MERGED'; merge = $ff.Head; landed = 'yes' }
    Check 'local: a merged pull request is named when HEAD is already on the default branch, under a newer closed one' $r.Ok $r.Detail

    # 16. The issues of a one-issue plan and a group plan.
    Set-MergedRequest $gh.Squash $gh.Head -GitHub
    Write-Text (Join-Path $gh.Repo 'PLAN.md') (New-PlanText 'x' (Get-Head $gh.Repo) '#7')
    Set-IssueStates @{ '7' = 'OPEN' }
    $r = Test-State (Get-State $gh.Repo) @{ issue = '#7'; 'issue-state' = 'OPEN'; 'issue-states' = '#7=OPEN'; next = 'ship-plan' }
    Check 'issues: a one-issue plan on GitHub reads its issue' $r.Ok $r.Detail

    Write-Text (Join-Path $gh.Repo 'PLAN.md') (New-PlanText 'x' (Get-Head $gh.Repo) '#7 #8 owner/other#9')
    Set-IssueStates @{ '7' = 'CLOSED'; '8' = 'OPEN'; '9' = 'CLOSED' }
    $r = Test-State (Get-State $gh.Repo) @{ issue = '#7 #8 owner/other#9'; 'issue-state' = 'OPEN'; 'issue-states' = '#7=CLOSED #8=OPEN owner/other#9=CLOSED'; next = 'ship-plan' }
    Check 'issues: a group plan on GitHub is open while one issue is open' $r.Ok $r.Detail

    Set-IssueStates @{ '7' = 'CLOSED'; '8' = 'CLOSED'; '9' = 'CLOSED' }
    $r = Test-State (Get-State $gh.Repo) @{ 'issue-state' = 'CLOSED'; next = 'finish-plan' }
    Check 'issues: a group plan on GitHub with every issue closed is finished' $r.Ok $r.Detail

    Write-Text (Join-Path $gl.Repo 'PLAN.md') (New-PlanText 'x' (Get-Head $gl.Repo) '#7 #8')
    Set-IssueStates @{ '7' = 'CLOSED'; '8' = 'OPEN' }
    $r = Test-State (Get-State $gl.Repo) @{ host = 'gitlab'; 'issue-state' = 'OPEN'; 'issue-states' = '#7=CLOSED #8=OPEN' }
    Check 'issues: a group plan on GitLab reads each issue through glab' $r.Ok $r.Detail

    Write-Text (Join-Path $gl.Repo 'PLAN.md') (New-PlanText 'x' (Get-Head $gl.Repo) '#7')
    Set-IssueStates @{ '7' = 'CLOSED' }
    $r = Test-State (Get-State $gl.Repo) @{ 'issue-state' = 'CLOSED'; 'issue-states' = '#7=CLOSED' }
    Check 'issues: a one-issue plan on GitLab reads its issue' $r.Ok $r.Detail
}
finally { $env:PATH = $savedPath }

''
if ($failures.Count) { "Plan state tests: FAILED ($($failures.Count))"; exit 1 }
'Plan state tests: PASSED'
exit 0
