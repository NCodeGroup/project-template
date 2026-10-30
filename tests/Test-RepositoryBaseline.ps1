<#
.SYNOPSIS
    Test that tools\Set-RepositoryBaseline.ps1 gives a repository the baseline ruleset and leaves protected ones alone.

.DESCRIPTION
    Runs the script against a stand-in for gh that serves canned repositories and rulesets and records what it is asked
    to change. Checks that -WhatIf changes nothing; that a repository with no ruleset gets "Protect main" on its default
    branch, with no deletion, no force push, a pull request with no approvals, merge-commit and rebase merges only and
    no bypass, and delete-branch-on-merge; that -RequireChecks adds required status checks; that a repository whose
    default branch already requires pull requests, or already has this ruleset, is left alone, and that -RequireChecks
    updates the ruleset the script made; that -All skips archived repositories and forks; and that bad parameters
    stop it. Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-baseline-test in the temp folder.

.EXAMPLE
    .\tests\Test-RepositoryBaseline.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) 'project-template-baseline-test'))
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Write-Text([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n")) }

if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$bin = Join-Path $Work 'bin'
New-Item -ItemType Directory -Force $bin | Out-Null

# The stand-in for gh. It serves repos.json (repository name -> repository, rulesets and their full forms), records every
# call in calls.log, and keeps the body of the last create or update in posted.json.
Write-Text (Join-Path $bin 'gh.ps1') @'
$log = Join-Path $PSScriptRoot 'calls.log'
Add-Content -LiteralPath $log -Value ($args -join ' ')
$data = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'repos.json') | ConvertFrom-Json -AsHashtable
if ($args[0] -eq 'repo' -and $args[1] -eq 'list') { ConvertTo-Json -InputObject @($data.list) -Depth 5; exit 0 }
if ($args[0] -ne 'api') { exit 1 }
$method = 'GET'
$rest = @($args[1..($args.Count - 1)])
if ($rest[0] -eq '-X') { $method = $rest[1]; $rest = @($rest[2..($rest.Count - 1)]) }
$path = $rest[0]
if ($rest -contains '--input') {
    $file = $rest[[array]::IndexOf($rest, '--input') + 1]
    Copy-Item -LiteralPath $file -Destination (Join-Path $PSScriptRoot 'posted.json') -Force
    Add-Content -LiteralPath $log -Value "BODY $method $path"
    '{}'; exit 0
}
if ($method -eq 'PATCH') { exit 0 }
if ($path -match '^repos/[^/]+/([^/]+)/rulesets/(\d+)$') { ConvertTo-Json -InputObject $data.repos[$Matches[1]].full["$($Matches[2])"] -Depth 10; exit 0 }
if ($path -match '^repos/[^/]+/([^/]+)/rulesets$') { ConvertTo-Json -InputObject @($data.repos[$Matches[1]].rulesets) -Depth 5; exit 0 }
if ($path -match '^repos/[^/]+/([^/]+)$') { ConvertTo-Json -InputObject $data.repos[$Matches[1]].info -Depth 5; exit 0 }
exit 1
'@

function New-Ruleset([string]$Name, [string[]]$Types = @('deletion', 'non_fast_forward', 'pull_request'), [string]$Include = '~DEFAULT_BRANCH') {
    @{ name = $Name; target = 'branch'; enforcement = 'active'
        conditions = @{ ref_name = @{ include = @($Include); exclude = @() } }
        rules = @($Types | ForEach-Object { @{ type = $_ } }) }
}
function New-Repo([string]$Branch = 'main', [bool]$Archived = $false, [bool]$Fork = $false, $Rulesets = @()) {
    $full = @{}
    $summaries = @()
    $id = 100
    foreach ($ruleset in $Rulesets) { $id++; $ruleset.id = $id; $full["$id"] = $ruleset; $summaries += @{ id = $id; name = $ruleset.name } }
    @{ info = @{ default_branch = $Branch; archived = $Archived; fork = $Fork }; rulesets = $summaries; full = $full }
}
$repos = @{
    fresh = New-Repo
    legacy = New-Repo -Branch master
    owned = New-Repo -Rulesets @((New-Ruleset 'main'))
    ours = New-Repo -Rulesets @((New-Ruleset 'Protect main'))
    tags = New-Repo -Rulesets @((@{ name = 'release-tags'; target = 'tag'; enforcement = 'active'; conditions = @{ ref_name = @{ include = @('refs/tags/v*'); exclude = @() } }; rules = @(@{ type = 'deletion' }) }))
    noPullRequest = New-Repo -Rulesets @((New-Ruleset 'no force push' @('non_fast_forward')))
    old = New-Repo -Archived $true
    forked = New-Repo -Fork $true
}
Write-Text (Join-Path $bin 'repos.json') (ConvertTo-Json -Depth 12 -InputObject @{
    repos = $repos
    list = @(
        foreach ($name in 'fresh', 'old', 'forked', 'owned') {
            @{ name = $name; isArchived = $repos[$name].info.archived; isFork = $repos[$name].info.fork }
        })
})

$script = Join-Path $repoRoot 'tools/Set-RepositoryBaseline.ps1'
$calls = Join-Path $bin 'calls.log'
$posted = Join-Path $bin 'posted.json'
function Invoke-Baseline([string[]]$Arguments) {
    foreach ($file in $calls, $posted) { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force } }
    $output = & pwsh -NoProfile -File $script @Arguments 2>&1 | Out-String
    $log = if (Test-Path -LiteralPath $calls) { Get-Content -LiteralPath $calls } else { @() }
    [pscustomobject]@{
        Output = $output
        ExitCode = $LASTEXITCODE
        Changes = @($log | Where-Object { $_ -like 'BODY *' -or $_ -like '*-X PATCH*' })
        Body = if (Test-Path -LiteralPath $posted) { Get-Content -Raw -LiteralPath $posted | ConvertFrom-Json } else { $null }
    }
}

$savedPath = $env:PATH
$env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
try {
    # 1. -WhatIf.
    $r = Invoke-Baseline @('-Repo', 'fresh', '-WhatIf')
    Check 'whatif: changes nothing' ($r.Changes.Count -eq 0 -and $r.Output -match "would: fresh \(main\): create 'Protect main'") "changes=$($r.Changes -join '|') output=$($r.Output)"

    # 2. A repository with no ruleset.
    $r = Invoke-Baseline @('-Repo', 'fresh')
    $types = @($r.Body.rules.type)
    Check 'create: posts one ruleset and turns on delete-branch-on-merge' (($r.Changes -join '|') -eq 'BODY POST repos/NCodeGroup/fresh/rulesets|api -X PATCH repos/NCodeGroup/fresh -F delete_branch_on_merge=true') ($r.Changes -join '|')
    Check 'create: protects the default branch and cannot be bypassed' (($r.Body.name -eq 'Protect main') -and ($r.Body.target -eq 'branch') -and ($r.Body.enforcement -eq 'active') -and ($r.Body.conditions.ref_name.include -contains '~DEFAULT_BRANCH') -and ($r.Body.bypass_actors.Count -eq 0))
    Check 'create: no deletion, no force push, a pull request, and nothing more' (($types -join ',') -eq 'deletion,non_fast_forward,pull_request') ($types -join ',')
    $pr = $r.Body.rules | Where-Object type -eq 'pull_request'
    Check 'create: no approvals, and merge-commit or rebase merges only, never squash' (($pr.parameters.required_approving_review_count -eq 0) -and ((@($pr.parameters.allowed_merge_methods) -join ',') -eq 'merge,rebase')) ($pr.parameters | ConvertTo-Json -Compress)

    # 3. Required checks, as one comma-separated string, which is how pwsh -File passes a list.
    $r = Invoke-Baseline @('-Repo', 'fresh', '-RequireChecks', 'build-and-test,Commit attribution')
    $checks = $r.Body.rules | Where-Object type -eq 'required_status_checks'
    Check 'checks: names the jobs, reported by GitHub Actions' ((@($checks.parameters.required_status_checks.context) -join ',') -eq 'build-and-test,Commit attribution' -and (@($checks.parameters.required_status_checks.integration_id | Select-Object -Unique) -join ',') -eq '15368') ($checks | ConvertTo-Json -Depth 6 -Compress)

    # 4. A branch other than main.
    $r = Invoke-Baseline @('-Repo', 'legacy')
    Check 'create: works for a default branch that is not main' (($r.Changes -join '|') -like 'BODY POST repos/NCodeGroup/legacy/rulesets*') ($r.Changes -join '|')

    # 5. Repositories left alone.
    $r = Invoke-Baseline @('-Repo', 'owned')
    Check 'alone: a default branch that already requires pull requests' ($r.Changes.Count -eq 0 -and $r.Output -match "owned: left alone \('main' already requires pull requests\)") $r.Output
    $r = Invoke-Baseline @('-Repo', 'ours')
    Check 'alone: a repository that already has Protect main' ($r.Changes.Count -eq 0 -and $r.Output -match "ours: left alone \(already has 'Protect main'\)") $r.Output
    $r = Invoke-Baseline @('-Repo', 'tags')
    Check 'create: a tag ruleset does not count as protecting the default branch' (($r.Changes -join '|') -like 'BODY POST repos/NCodeGroup/tags/rulesets*') ($r.Changes -join '|')
    $r = Invoke-Baseline @('-Repo', 'noPullRequest')
    Check 'create: a ruleset without a pull request rule does not count' (($r.Changes -join '|') -like 'BODY POST repos/NCodeGroup/noPullRequest/rulesets*') ($r.Changes -join '|')

    # 6. -RequireChecks updates the ruleset the script made.
    $r = Invoke-Baseline @('-Repo', 'ours', '-RequireChecks', 'test')
    Check 'update: -RequireChecks changes the ruleset it made, in place' (($r.Changes -join '|') -like 'BODY PUT repos/NCodeGroup/ours/rulesets/101*') ($r.Changes -join '|')

    # 7. -All.
    $r = Invoke-Baseline @('-All')
    Check 'all: skips archived repositories and forks' (($r.Output -notmatch 'old') -and ($r.Output -notmatch 'forked') -and ($r.Output -match 'done: fresh') -and ($r.Output -match 'owned: left alone')) $r.Output

    # 8. Bad parameters.
    $r = Invoke-Baseline @()
    Check 'params: needs -Repo or -All' ($r.ExitCode -ne 0 -and $r.Output -match 'Pass -Repo <name> or -All') $r.Output
    $r = Invoke-Baseline @('-All', '-RequireChecks', 'test')
    Check 'params: -RequireChecks needs -Repo' ($r.ExitCode -ne 0 -and $r.Changes.Count -eq 0 -and $r.Output -match '-RequireChecks needs -Repo') $r.Output
    $r = Invoke-Baseline @('-Repo', 'fresh', '-Owner', 'someone')
    Check 'params: -Owner picks the owner of the repository' (($r.Changes -join '|') -like 'BODY POST repos/someone/fresh/rulesets*') ($r.Changes -join '|')
}
finally { $env:PATH = $savedPath }

''
if ($failures.Count) { "Repository baseline tests: FAILED ($($failures.Count))"; exit 1 }
'Repository baseline tests: PASSED'
exit 0
