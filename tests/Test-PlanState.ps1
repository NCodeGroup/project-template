<#
.SYNOPSIS
    Test that workflow\Get-PlanState.ps1 reads where a plan stands and names the next command.

.DESCRIPTION
    Builds a bare origin and a clone in a scratch folder, then walks a plan through its life: no plan, open steps, an
    escalated step, finished steps, a review, a stale review, the Landing section of AGENTS.md, a push to the default
    branch, a tag, an upstream commit, an upstream commit read with and without -NoFetch, a second plan worktree, no plan, and uncommitted changes, then merged GitHub pull requests and GitLab merge requests, then the issues of a one-issue plan and a group plan, and an open issue on the Refs: line, and whether the default branch takes changes only through pull requests, read through stand-ins for gh and glab, then a plan whose release another plan took, before and while its pull request is open, then Keep a Changelog headings and the changelog lines, then the version tags merged into HEAD that the changelog has no section for, then the files that conflict with the default branch, before and while a pull request is open. After each move it runs
    Get-PlanState.ps1 and compares the key: value lines it prints with what the state should be. Prints PASS or FAIL
    per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-plan-state-test in the temp folder.

.EXAMPLE
    .\tests\Test-PlanState.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) 'project-template-plan-state-test'))
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
$r = Test-State (Get-State $repo) @{ plan = '-'; refs = '-'; default = 'main'; branch = 'main'; host = 'other'; worktree = '-';ahead = '0'; behind = '0'; landed = 'yes'; dirty = 'no'; plans = '-'; conflicts = '-'; protected = 'unknown' }
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
Write-Text $planFile ((New-PlanText ' ').Replace("Release: v0.2.0`n", "Release: v0.2.0`nRefs: #3 owner/other#90`n"))
$r = Test-State (Get-State $repo) @{ issue = '#7'; refs = '#3 owner/other#90'; release = 'v0.2.0'; next = 'orchestrate-plan' }
Check 'local: reads the plan''s Refs: line apart from its Issue: line' $r.Ok $r.Detail

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
$r = Test-State (Get-State $repo) @{ landing = 'integrate=pull-request release=none changelog=CHANGELOG.md draft=no follow-ups=issues follow-up-label=follow-up gate=none protect=none pr-format=none' }
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
- follow-ups: owner/backlog
- follow-up-label: tech debt
- gate: `./build/dod.ps1 -Fast -Affected`
- protect: hook
- pr-format: `AGENTS.md#Pull requests`
'@
Push-Location $repo
try { Invoke-Git add AGENTS.md; Invoke-Git commit -q -m 'Add AGENTS.md' }
finally { Pop-Location }
Write-Text $planFile (New-PlanText 'x' (Get-Head $repo))
Push-Location $repo
try { Invoke-Git commit -q --allow-empty -m 'Re-plan step 2: B' }
finally { Pop-Location }
$r = Test-State (Get-State $repo) @{ landing = 'integrate=direct release=tag+release changelog=docs/CHANGES.md draft=yes follow-ups=owner/backlog follow-up-label="tech debt" gate="./build/dod.ps1 -Fast -Affected" protect=hook pr-format="AGENTS.md#Pull requests"' }
Check 'local: reads the Landing section of AGENTS.md' $r.Ok $r.Detail
$r = Test-State (Get-State $repo) @{ protected = 'unknown' }
Check 'protected: protect hook without the hook enabled, on another host, is unknown' $r.Ok $r.Detail
$r = Test-State (Get-State $repo) @{ reviewed = 'current'; next = 'ship-plan' }
Check 'next: an empty commit after the review keeps it current' $r.Ok $r.Detail

# 8. Pushed to the default branch.
Push-Location $repo
try { Invoke-Git push -q origin HEAD:refs/heads/main }
finally { Pop-Location }
$r = Test-State (Get-State $repo) @{ landed = 'yes'; ahead = '0'; conflicts = '-'; tag = 'absent' }
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
if ($args[0] -eq 'api') {
    $file = Join-Path $PSScriptRoot 'api.json'
    if (-not (Test-Path $file)) { exit 1 }
    $responses = [IO.File]::ReadAllText($file) | ConvertFrom-Json
    $property = $responses.PSObject.Properties["$($args[1])"]
    if (-not $property) { exit 1 }
    ConvertTo-Json -InputObject $property.Value -Depth 5
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
function Set-HostApi([hashtable]$Responses) { Write-Text (Join-Path $bin 'api.json') (ConvertTo-Json -InputObject $Responses -Depth 5) }
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

    Set-HostApi @{ 'projects/:id/protected_branches/main' = @{ push_access_levels = @(@{ access_level = 0 }) } }
    $r = Test-State (Get-State $gl.Repo) @{ protected = 'host' }
    Check 'protected: a GitLab protected branch nobody can push to' $r.Ok $r.Detail

    Set-HostApi @{ 'projects/:id/protected_branches/main' = @{ push_access_levels = @(@{ access_level = 40 }) } }
    $r = Test-State (Get-State $gl.Repo) @{ protected = 'no' }
    Check 'protected: a GitLab protected branch maintainers can push to is not enough' $r.Ok $r.Detail

    Set-HostApi @{}
    $r = Test-State (Get-State $gl.Repo) @{ protected = 'no' }
    Check 'protected: a GitLab branch that is not protected' $r.Ok $r.Detail

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

    Set-HostApi @{ 'repos/{owner}/{repo}/rules/branches/main' = @(@{ type = 'pull_request' }) }
    $r = Test-State (Get-State $gh.Repo) @{ protected = 'host' }
    Check 'protected: a GitHub ruleset that requires a pull request' $r.Ok $r.Detail

    Set-HostApi @{ 'repos/{owner}/{repo}/rules/branches/main' = @(@{ type = 'deletion' }); 'repos/{owner}/{repo}/branches/main/protection/required_pull_request_reviews' = @{ required_approving_review_count = 1 } }
    $r = Test-State (Get-State $gh.Repo) @{ protected = 'host' }
    Check 'protected: a GitHub branch protection rule that requires reviews' $r.Ok $r.Detail

    Set-HostApi @{ 'repos/{owner}/{repo}/rules/branches/main' = @(@{ type = 'deletion' }) }
    $r = Test-State (Get-State $gh.Repo) @{ protected = 'no' }
    Check 'protected: a GitHub ruleset without a pull request rule' $r.Ok $r.Detail
    Set-HostApi @{}

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

    Write-Text (Join-Path $gh.Repo 'PLAN.md') ((New-PlanText 'x' (Get-Head $gh.Repo) '#7').Replace("Release: v0.2.0`n", "Release: v0.2.0`nRefs: #8`n"))
    Set-IssueStates @{ '7' = 'CLOSED'; '8' = 'OPEN' }
    $r = Test-State (Get-State $gh.Repo) @{ issue = '#7'; refs = '#8'; 'issue-state' = 'CLOSED'; 'issue-states' = '#7=CLOSED'; next = 'finish-plan' }
    Check 'issues: an open issue on the Refs: line keeps no plan open' $r.Ok $r.Detail

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

# 17. A plan whose release another plan took.
$lateOrigin = Join-Path $Work 'renumber.git'
$lateSeed = Join-Path $Work 'renumber-seed'
$lateRepo = Join-Path $Work 'renumber-repo'
Push-Location $Work
try {
    Invoke-Git init -q --bare -b main $lateOrigin
    Invoke-Git clone -q $lateOrigin $lateSeed
}
finally { Pop-Location }
Write-Text (Join-Path $lateSeed 'AGENTS.md') "# Demo`n`n## Landing`n`n- release: tag+release`n"
Write-Text (Join-Path $lateSeed 'CHANGELOG.md') "# Changelog`n`n## v0.1.0`n`n- First.`n"
Push-Location $lateSeed
try {
    Invoke-Git add AGENTS.md CHANGELOG.md
    Invoke-Git commit -q -m 'Add landing and changelog'
    Invoke-Git tag v0.1.0
    Invoke-Git push -q origin HEAD:refs/heads/main
    Invoke-Git push -q origin v0.1.0
}
finally { Pop-Location }
Push-Location $Work
try { Invoke-Git clone -q $lateOrigin $lateRepo }
finally { Pop-Location }
[IO.File]::AppendAllText((Join-Path $lateRepo '.git/info/exclude'), "PLAN.md`n")
Push-Location $lateRepo
try { Invoke-Git switch -q -c worktree-late }
finally { Pop-Location }
Add-Commit $lateRepo 'late.txt' 'Plan step 1: Late'
$latePlan = Join-Path $lateRepo 'PLAN.md'
Write-Text $latePlan (New-PlanText 'x' (Get-Head $lateRepo))
$r = Test-State (Get-State $lateRepo) @{ release = 'v0.2.0'; renumber = '-'; next = 'ship-plan' }
Check 'renumber: a version newer than every tag and changelog heading is free' $r.Ok $r.Detail

Write-Text (Join-Path $lateSeed 'CHANGELOG.md') "# Changelog`n`n## v0.2.0`n`n- Second.`n`n## v0.1.0`n`n- First.`n"
Push-Location $lateSeed
try {
    Invoke-Git add CHANGELOG.md
    Invoke-Git commit -q -m 'Release 0.2.0'
    Invoke-Git push -q origin HEAD:refs/heads/main
}
finally { Pop-Location }
$r = Test-State (Get-State $lateRepo) @{ renumber = 'v0.3.0'; next = 'ship-plan' }
Check 'renumber: a merged changelog heading at the plan''s version moves it a minor version on' $r.Ok $r.Detail

Push-Location $lateSeed
try {
    Invoke-Git tag v0.3.0
    Invoke-Git push -q origin v0.3.0
}
finally { Pop-Location }
$r = Test-State (Get-State $lateRepo) @{ renumber = 'v0.4.0' }
Check 'renumber: a newer tag moves it past the tag' $r.Ok $r.Detail

Write-Text $latePlan ((Get-Content -Raw $latePlan).Replace('Release: v0.2.0', 'Release: v0.2.1').Replace("`r`n", "`n"))
$r = Test-State (Get-State $lateRepo) @{ release = 'v0.2.1'; renumber = 'v0.3.1' }
Check 'renumber: a patch plan moves to the next patch' $r.Ok $r.Detail

# 18. An open pull request whose release another plan took.
$prOrigin = Join-Path $Work 'late-pr/github.com/origin.git'
Invoke-Git clone -q --bare $lateOrigin $prOrigin
Push-Location $lateRepo
try { Invoke-Git remote set-url origin $prOrigin }
finally { Pop-Location }
Write-Text (Join-Path $bin 'pr.json') (ConvertTo-Json -InputObject @(@{ number = 9; state = 'OPEN'; mergeCommit = $null; headRefOid = (Get-Head $lateRepo); baseRefName = 'main' }) -Depth 3)
$savedPath = $env:PATH
$env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
try {
    $r = Test-State (Get-State $lateRepo) @{ host = 'github'; pr = '9 OPEN'; renumber = 'v0.3.1'; next = 'ship-plan' }
    Check 'next: an open pull request whose release another plan took goes back to ship-plan' $r.Ok $r.Detail

    Write-Text $latePlan ((Get-Content -Raw $latePlan).Replace('Release: v0.2.1', 'Release: v0.3.1').Replace("`r`n", "`n"))
    $r = Test-State (Get-State $lateRepo) @{ pr = '9 OPEN'; renumber = '-'; next = 'wait pull request #9 is open: run ship-plan again once it merges' }
    Check 'next: an open pull request at a free version waits' $r.Ok $r.Detail
}
finally { $env:PATH = $savedPath }

# 19. Keep a Changelog headings.
Push-Location $lateRepo
try { Invoke-Git remote set-url origin $lateOrigin }
finally { Pop-Location }
$r = Test-State (Get-State $lateRepo) @{ 'changelog-format' = 'other'; 'changelog-version' = 'v0.1.0' }
Check 'changelog: a changelog without Keep a Changelog headings is other' $r.Ok $r.Detail

Write-Text (Join-Path $lateSeed 'CHANGELOG.md') "# Changelog`n`n## [Unreleased]`n`n## [0.4.0] - 2026-10-28`n`n### Added`n`n- Fourth.`n`n## v0.2.0`n`n- Second.`n`n[unreleased]: https://example.invalid/compare/v0.4.0...HEAD`n"
Push-Location $lateSeed
try {
    Invoke-Git add CHANGELOG.md
    Invoke-Git commit -q -m 'Release 0.4.0'
    Invoke-Git push -q origin HEAD:refs/heads/main
}
finally { Pop-Location }
$r = Test-State (Get-State $lateRepo) @{ release = 'v0.3.1'; renumber = 'v0.4.1' }
Check 'renumber: a Keep a Changelog heading on the default branch moves the plan past it' $r.Ok $r.Detail

$lateLog = Join-Path $lateRepo 'CHANGELOG.md'
Write-Text $lateLog "# Changelog`n`n## [Unreleased]`n`n## [0.3.1] - 2026-10-28`n`n### Fixed`n`n- Third.`n"
$r = Test-State (Get-State $lateRepo) @{ 'changelog-format' = 'keep-a-changelog'; 'changelog-version' = 'v0.3.1' }
Check 'changelog: reads the newest Keep a Changelog release with the plan''s prefix' $r.Ok $r.Detail

Write-Text $lateLog "# Changelog`n`n## [Unreleased]`n`n### Added`n`n- Coming.`n"
$r = Test-State (Get-State $lateRepo) @{ 'changelog-format' = 'keep-a-changelog'; 'changelog-version' = '-' }
Check 'changelog: an Unreleased section alone is no release' $r.Ok $r.Detail

Remove-Item -LiteralPath $lateLog
$r = Test-State (Get-State $lateRepo) @{ 'changelog-format' = 'missing'; 'changelog-version' = '-' }
Check 'changelog: a missing changelog' $r.Ok $r.Detail

# 20. Version tags without a changelog section.
$r = Test-State (Get-State $lateRepo -NoFetch) @{ 'changelog-backfill' = 'v0.1.0' }
Check 'backfill: a missing changelog names the tag merged into HEAD, not a later one' $r.Ok $r.Detail

Push-Location $lateRepo
try {
    Invoke-Git tag v0.1.1
    Invoke-Git tag 0.1.2
}
finally { Pop-Location }
$r = Test-State (Get-State $lateRepo -NoFetch) @{ 'changelog-backfill' = 'v0.1.0..0.1.2' }
Check 'backfill: names the oldest and the newest tag without a section' $r.Ok $r.Detail

Write-Text $lateLog "# Changelog`n`n## [Unreleased]`n`n## [0.1.2] - 2026-10-28`n`n- Third.`n"
$r = Test-State (Get-State $lateRepo -NoFetch) @{ 'changelog-backfill' = 'v0.1.0..v0.1.1' }
Check 'backfill: a changelog started mid-history names the older tags' $r.Ok $r.Detail

Write-Text $lateLog "# Changelog`n`n## [Unreleased]`n`n## [0.1.2] - 2026-10-28`n`n## v0.1.1`n`n## [0.1.0] - 2026-10-01 [YANKED]`n"
$r = Test-State (Get-State $lateRepo -NoFetch) @{ 'changelog-backfill' = '-' }
Check 'backfill: every tag merged into HEAD has a section' $r.Ok $r.Detail

# 21. Files that conflict with the default branch.
$cOrigin = Join-Path $Work 'conflict/github.com/origin.git'
$cSeed = Join-Path $Work 'conflict/seed'
$cRepo = Join-Path $Work 'conflict/repo'
Push-Location $Work
try {
    Invoke-Git init -q --bare -b main $cOrigin
    Invoke-Git clone -q $cOrigin $cSeed
}
finally { Pop-Location }
Add-Commit $cSeed 'shared.txt' 'Add shared'
Push-Location $cSeed
try { Invoke-Git push -q origin HEAD:refs/heads/main }
finally { Pop-Location }
Push-Location $Work
try { Invoke-Git clone -q $cOrigin $cRepo }
finally { Pop-Location }
[IO.File]::AppendAllText((Join-Path $cRepo '.git/info/exclude'), "PLAN.md`n")
Push-Location $cRepo
try { Invoke-Git switch -q -c worktree-conflict }
finally { Pop-Location }
Write-Text (Join-Path $cRepo 'shared.txt') "plan`n"
Push-Location $cRepo
try { Invoke-Git add shared.txt; Invoke-Git commit -q -m 'Plan step 1: Change shared' }
finally { Pop-Location }
$cPlan = Join-Path $cRepo 'PLAN.md'
Write-Text $cPlan (New-PlanText 'x' (Get-Head $cRepo))
Write-Text (Join-Path $bin 'pr.json') '[]'
$savedPath = $env:PATH
$env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
try {
    $r = Test-State (Get-State $cRepo) @{ host = 'github'; behind = '0'; conflicts = 'none'; next = 'ship-plan' }
    Check 'conflicts: a branch level with the default branch merges cleanly' $r.Ok $r.Detail

    Add-Commit $cSeed 'other.txt' 'Add other'
    Push-Location $cSeed
    try { Invoke-Git push -q origin HEAD:refs/heads/main }
    finally { Pop-Location }
    $r = Test-State (Get-State $cRepo) @{ behind = '1'; conflicts = 'none'; next = 'ship-plan' }
    Check 'conflicts: a default branch that changed other files merges cleanly' $r.Ok $r.Detail

    New-Item -ItemType Directory -Force (Join-Path $cSeed 'docs') | Out-Null
    Write-Text (Join-Path $cSeed 'shared.txt') "main`n"
    Write-Text (Join-Path $cSeed 'docs/new file.md') "main`n"
    Push-Location $cSeed
    try {
        Invoke-Git add shared.txt 'docs/new file.md'
        Invoke-Git commit -q -m 'Change shared and add new file'
        Invoke-Git push -q origin HEAD:refs/heads/main
    }
    finally { Pop-Location }
    New-Item -ItemType Directory -Force (Join-Path $cRepo 'docs') | Out-Null
    Write-Text (Join-Path $cRepo 'docs/new file.md') "plan`n"
    Push-Location $cRepo
    try { Invoke-Git add 'docs/new file.md'; Invoke-Git commit -q -m 'Plan step 2: Add new file' }
    finally { Pop-Location }
    Write-Text $cPlan (New-PlanText 'x' (Get-Head $cRepo))
    $r = Test-State (Get-State $cRepo) @{ conflicts = 'docs/new file.md, shared.txt'; next = 'ship-plan' }
    Check 'conflicts: names each file that conflicts, in path order' $r.Ok $r.Detail

    Write-Text (Join-Path $bin 'pr.json') (ConvertTo-Json -InputObject @(@{ number = 4; state = 'OPEN'; mergeCommit = $null; headRefOid = (Get-Head $cRepo); baseRefName = 'main' }) -Depth 3)
    $r = Test-State (Get-State $cRepo) @{ pr = '4 OPEN'; renumber = '-'; conflicts = 'docs/new file.md, shared.txt'; next = 'ship-plan' }
    Check 'next: an open pull request that conflicts with the default branch goes back to ship-plan' $r.Ok $r.Detail

    Push-Location $cRepo
    try {
        git merge --no-commit --no-ff origin/main 2>$null | Out-Null
        Write-Text (Join-Path $cRepo 'shared.txt') "both`n"
        Write-Text (Join-Path $cRepo 'docs/new file.md') "both`n"
        Invoke-Git add shared.txt 'docs/new file.md'
        Invoke-Git commit -q -m 'Plan step 3: Merge main in'
    }
    finally { Pop-Location }
    Write-Text $cPlan (New-PlanText 'x' (Get-Head $cRepo))
    $r = Test-State (Get-State $cRepo) @{ conflicts = 'none'; next = 'wait pull request #4 is open: run ship-plan again once it merges' }
    Check 'conflicts: none once the default branch is merged in' $r.Ok $r.Detail

    Push-Location $cSeed
    try {
        $lone = (Invoke-Git commit-tree 'HEAD^{tree}' -m 'Unrelated root' | Out-String).Trim()
        Invoke-Git push -q --force origin "${lone}:refs/heads/main"
    }
    finally { Pop-Location }
    $r = Test-State (Get-State $cRepo) @{ conflicts = 'unknown'; next = 'wait pull request #4 is open: run ship-plan again once it merges' }
    Check 'conflicts: unknown when git merge-tree cannot merge the default branch' $r.Ok $r.Detail
}
finally { $env:PATH = $savedPath }

''
if ($failures.Count) { "Plan state tests: FAILED ($($failures.Count))"; exit 1 }
'Plan state tests: PASSED'
exit 0
