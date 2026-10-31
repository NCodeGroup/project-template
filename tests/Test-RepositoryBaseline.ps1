<#
.SYNOPSIS
    Test that tools\Set-RepositoryBaseline.ps1 gives a repository the baseline ruleset and leaves protected ones alone.

.DESCRIPTION
    Runs the script against a stand-in for gh that serves canned repositories and rulesets and records what it is asked
    to change. Checks that -WhatIf changes nothing; that a repository with no ruleset gets "Protect main" on its default
    branch, with no deletion, no force push, a pull request with no approvals, merge-commit and rebase merges only and
    no bypass, and delete-branch-on-merge; that -RequireChecks adds required status checks; that a repository whose
    default branch already requires pull requests, or already has this ruleset, is left alone, and that -RequireChecks
    updates the ruleset the script made; that -RequireChecks auto requires the GitHub Actions checks that passed on the
    latest merged pull request, reading every page of its check runs and workflow runs, Commit attribution among them,
    leaves out the review bot's Code review and its job, CodeQL and its Analyze jobs, push-only jobs, jobs no workflow
    run accounts for, other apps' checks and skipped, neutral, failed or unfinished ones, lists them with -WhatIf with a
    command that names them, quoted so it parses, gives each repository its own checks with -All, and skips a repository
    with no merged pull request or no check to require; that -All skips archived repositories and forks; and that bad
    parameters stop it. Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-baseline-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-RepositoryBaseline.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-baseline-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
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
$rest = @($args[1..($args.Count - 1)] | Where-Object { $_ -notin '--include', '--paginate', '--slurp' })
$include = $args -contains '--include'
# Lists come in pages of 5 here, so a few check runs already span pages. --paginate --slurp answers every page, as an
# array; without it only the first page comes back.
$paginate = $args -contains '--paginate' -and $args -contains '--slurp'
function Out-Pages([string]$Key, $Items) {
    $pages = @(for ($i = 0; $i -lt [Math]::Max(1, $Items.Count); $i += 5) { @{ total_count = $Items.Count; $Key = @($Items | Select-Object -Skip $i -First 5) } })
    if ($paginate) { ConvertTo-Json -InputObject $pages -Depth 8 } else { ConvertTo-Json -InputObject $pages[0] -Depth 8 }
}
if ($rest[0] -eq '-X') { $method = $rest[1]; $rest = @($rest[2..($rest.Count - 1)]) }
$path = $rest[0]
if ($rest -contains '--input') {
    $file = $rest[[array]::IndexOf($rest, '--input') + 1]
    Copy-Item -LiteralPath $file -Destination (Join-Path $PSScriptRoot 'posted.json') -Force
    if ($path -match '^repos/[^/]+/([^/]+)/rulesets') { Copy-Item -LiteralPath $file -Destination (Join-Path $PSScriptRoot "posted-$($Matches[1]).json") -Force }
    Add-Content -LiteralPath $log -Value "BODY $method $path"
    '{}'; exit 0
}
if ($method -eq 'PATCH') {
    if ($path -match '^repos/[^/]+/([^/]+)/code-scanning/default-setup$' -and $data.repos[$Matches[1]].switchFails) { exit 1 }
    exit 0
}
if ($path -match '^repos/[^/]+/([^/]+)/code-scanning/default-setup$') {
    # codeql is a state, 404 for not found, fail:<code> for another status, fail:none for no response at all, or
    # raw:<text> for a body that isn't JSON. An empty suite leaves query_suite out of the answer. With --include, the
    # answer starts with the status line and a header.
    $codeql = "$($data.repos[$Matches[1]].codeql)"
    $answer = @{ state = $codeql }
    if ("$($data.repos[$Matches[1]].suite)") { $answer.query_suite = "$($data.repos[$Matches[1]].suite)" }
    $status = 200; $body = ConvertTo-Json -InputObject $answer
    if ($codeql -eq 'fail:none') { exit 1 }
    if ($codeql -eq '404') { $status = 404; $body = '{"message":"Not Found"}' }
    elseif ($codeql.StartsWith('fail:')) { $status = [int]$codeql.Substring(5); $body = '{"message":"Error"}' }
    elseif ($codeql.StartsWith('raw:')) { $body = $codeql.Substring(4) }
    if ($include) { "HTTP/2.0 $status Status"; 'Content-Type: application/json'; '' }
    $body
    if ($status -ne 200) { exit 1 }
    exit 0
}
if ($path -match '^repos/[^/]+/([^/]+)/rulesets/(\d+)$') { ConvertTo-Json -InputObject $data.repos[$Matches[1]].full["$($Matches[2])"] -Depth 10; exit 0 }
if ($path -match '^repos/[^/]+/([^/]+)/rulesets$') { ConvertTo-Json -InputObject @($data.repos[$Matches[1]].rulesets) -Depth 5; exit 0 }
# Pull requests, and the check runs and workflow runs of a commit, for -RequireChecks auto.
if ($path -match '^repos/[^/]+/([^/]+)/pulls\?') { ConvertTo-Json -InputObject @($data.repos[$Matches[1]].pulls | Where-Object { $_ }) -Depth 5; exit 0 }
if ($path -match '^repos/[^/]+/([^/]+)/commits/([^/]+)/check-runs\?') {
    Out-Pages 'check_runs' @($data.repos[$Matches[1]].checkRuns[$Matches[2]] | Where-Object { $_ }); exit 0
}
if ($path -match '^repos/[^/]+/([^/]+)/actions/runs\?head_sha=([^&]+)') {
    Out-Pages 'workflow_runs' @($data.repos[$Matches[1]].workflowRuns[$Matches[2]] | Where-Object { $_ }); exit 0
}
if ($path -match '^repos/[^/]+/([^/]+)$') { ConvertTo-Json -InputObject $data.repos[$Matches[1]].info -Depth 5; exit 0 }
exit 1
'@

function New-Ruleset([string]$Name, [string[]]$Types = @('deletion', 'non_fast_forward', 'pull_request'), [string]$Include = '~DEFAULT_BRANCH') {
    @{ name = $Name; target = 'branch'; enforcement = 'active'
        conditions = @{ ref_name = @{ include = @($Include); exclude = @() } }
        rules = @($Types | ForEach-Object { @{ type = $_ } }) }
}
function New-Repo([string]$Branch = 'main', [bool]$Archived = $false, [bool]$Fork = $false, $Rulesets = @(), [string]$CodeQL = 'configured', [string]$Suite = 'default', [bool]$SwitchFails = $false, $Pulls = @(), [hashtable]$CheckRuns = @{}, [hashtable]$WorkflowRuns = @{}) {
    $full = @{}
    $summaries = @()
    $id = 100
    foreach ($ruleset in $Rulesets) { $id++; $ruleset.id = $id; $full["$id"] = $ruleset; $summaries += @{ id = $id; name = $ruleset.name } }
    @{ info = @{ default_branch = $Branch; archived = $Archived; fork = $Fork }; rulesets = $summaries; full = $full; codeql = $CodeQL; suite = $Suite; switchFails = $SwitchFails
        pulls = @($Pulls); checkRuns = $CheckRuns; workflowRuns = $WorkflowRuns }
}
function New-Pull([int]$Number, [string]$Sha, [string]$MergedAt) { @{ number = $Number; head = @{ sha = $Sha }; merged_at = if ($MergedAt) { $MergedAt } else { $null } } }
function New-CheckRun([long]$Id, [string]$Name, [string]$Conclusion = 'success', [long]$Suite = 1, [long]$App = 15368, [string]$Slug = 'github-actions', [string]$Status = 'completed') {
    @{ id = $Id; name = $Name; status = $Status; conclusion = if ($Status -eq 'completed') { $Conclusion } else { $null }; app = @{ id = $App; slug = $Slug }; check_suite = @{ id = $Suite } }
}
# The workflow runs on a pull request's head commit: its CI (suite 1), the review bot's job (suite 2), CodeQL's default
# setup (suite 3), a push-only workflow (suite 4) and scheduled runs, as GitHub reports them. CI comes last, on the
# second page.
$prWorkflowRuns = @(
    @{ check_suite_id = 2; name = 'Code review'; event = 'pull_request_target' },
    @{ check_suite_id = 3; name = 'PR #9'; event = 'dynamic' },
    @{ check_suite_id = 4; name = 'Deploy'; event = 'push' },
    @{ check_suite_id = 5; name = 'Nightly'; event = 'schedule' },
    @{ check_suite_id = 6; name = 'Nightly'; event = 'schedule' },
    @{ check_suite_id = 1; name = 'CI'; event = 'pull_request' })
# The latest merged pull request (#9) is neither the first one listed nor the latest one closed (#10, not merged).
$autoPulls = @((New-Pull 7 'sha7' '2026-10-01T10:00:00Z'), (New-Pull 10 'sha10' ''), (New-Pull 9 'sha9' '2026-10-20T10:00:00Z'))
$autoRuns = @{
    sha7 = @((New-CheckRun 70 'old-job'))
    sha9 = @(
        (New-CheckRun 1 'build-and-test'),
        (New-CheckRun 2 'Commit attribution'),
        (New-CheckRun 3 'lint' 'skipped'),
        (New-CheckRun 4 'docs' 'neutral'),
        (New-CheckRun 5 'broken' 'failure'),
        (New-CheckRun 6 'flaky' 'failure'),
        (New-CheckRun 16 'flaky'),
        (New-CheckRun 7 'slow' -Status 'in_progress'),
        (New-CheckRun 8 'Code review' 'neutral' -Suite 50 -App 5534990 -Slug 'ncode-review'),
        (New-CheckRun 9 'review' -Suite 2),
        (New-CheckRun 10 'CodeQL' -Suite 60 -App 57789 -Slug 'github-advanced-security'),
        (New-CheckRun 11 'Analyze (csharp)' -Suite 3),
        (New-CheckRun 12 'external' -Suite 70 -App 999 -Slug 'other-ci'),
        (New-CheckRun 13 'Analyze (python)'),
        (New-CheckRun 14 'deploy' -Suite 4),
        (New-CheckRun 15 'orphan' -Suite 80))
}
$autoWorkflowRuns = @{ sha7 = $prWorkflowRuns; sha9 = $prWorkflowRuns }
$repos = @{
    fresh = New-Repo
    extendedAlready = New-Repo -Suite 'extended'
    suiteUnreported = New-Repo -Suite ''
    switchRefused = New-Repo -SwitchFails $true
    noCodeQL = New-Repo -CodeQL 'not-configured'
    setupNotFound = New-Repo -CodeQL '404'
    setupFailed = New-Repo -CodeQL 'fail:403'
    setupNoResponse = New-Repo -CodeQL 'fail:none'
    setupUnreadable = New-Repo -CodeQL 'raw:<html>Bad Gateway</html>'
    oursCodeQL404 = New-Repo -CodeQL '404' -Rulesets @((New-Ruleset 'Protect main' @('deletion', 'non_fast_forward', 'pull_request', 'code_scanning')))
    oursWithoutCodeQL = New-Repo -CodeQL 'not-configured' -Rulesets @((New-Ruleset 'Protect main' @('deletion', 'non_fast_forward', 'pull_request', 'code_scanning')))
    legacy = New-Repo -Branch master
    owned = New-Repo -Rulesets @((New-Ruleset 'main'))
    ours = New-Repo -Rulesets @((New-Ruleset 'Protect main'))
    tags = New-Repo -Rulesets @((@{ name = 'release-tags'; target = 'tag'; enforcement = 'active'; conditions = @{ ref_name = @{ include = @('refs/tags/v*'); exclude = @() } }; rules = @(@{ type = 'deletion' }) }))
    noPullRequest = New-Repo -Rulesets @((New-Ruleset 'no force push' @('non_fast_forward')))
    old = New-Repo -Archived $true
    forked = New-Repo -Fork $true
    autoChecks = New-Repo -Pulls $autoPulls -CheckRuns $autoRuns -WorkflowRuns $autoWorkflowRuns
    oursAuto = New-Repo -Rulesets @((New-Ruleset 'Protect main')) -Pulls $autoPulls -CheckRuns $autoRuns -WorkflowRuns $autoWorkflowRuns
    noMergedPull = New-Repo -Pulls @((New-Pull 4 'sha4' ''))
    nothingPassed = New-Repo -Pulls @((New-Pull 5 'sha5' '2026-10-02T10:00:00Z')) -CheckRuns @{ sha5 = @((New-CheckRun 1 'lint' 'skipped'), (New-CheckRun 2 'Code review' 'neutral' -Suite 50 -App 5534990 -Slug 'ncode-review'), (New-CheckRun 3 'CodeQL' -Suite 60 -App 57789 -Slug 'github-advanced-security')) } -WorkflowRuns @{ sha5 = $prWorkflowRuns }
    noCheckRuns = New-Repo -Pulls @((New-Pull 8 'sha8' '2026-10-05T10:00:00Z')) -CheckRuns @{ sha8 = @() } -WorkflowRuns @{ sha8 = @() }
    # Job names the printed command has to quote, or can't name at all.
    oddNames = New-Repo -Pulls @((New-Pull 6 'sha6' '2026-10-03T10:00:00Z')) -CheckRuns @{ sha6 = @((New-CheckRun 1 "it's fine"), (New-CheckRun 2 'a, b'), (New-CheckRun 3 'plain')) } -WorkflowRuns @{ sha6 = $prWorkflowRuns }
    # A second repository with checks of its own, for -All -RequireChecks auto.
    autoOther = New-Repo -Pulls @((New-Pull 3 'sha3' '2026-10-04T10:00:00Z')) -CheckRuns @{ sha3 = @((New-CheckRun 1 'other-build')) } -WorkflowRuns @{ sha3 = $prWorkflowRuns }
}
Write-Text (Join-Path $bin 'repos.json') (ConvertTo-Json -Depth 12 -InputObject @{
    repos = $repos
    list = @(
        foreach ($name in 'fresh', 'old', 'forked', 'owned', 'autoChecks', 'autoOther') {
            @{ name = $name; isArchived = $repos[$name].info.archived; isFork = $repos[$name].info.fork }
        })
})

$script = Join-Path $repoRoot 'tools/Set-RepositoryBaseline.ps1'
$calls = Join-Path $bin 'calls.log'
$posted = Join-Path $bin 'posted.json'
function Invoke-Baseline([string[]]$Arguments) {
    foreach ($file in @($calls, $posted) + @(Get-ChildItem -LiteralPath $bin -Filter 'posted-*.json' | ForEach-Object FullName)) { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force } }
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
    Check 'create: switches CodeQL to the extended suite first, then posts one ruleset and turns on delete-branch-on-merge' (($r.Changes -join '|') -eq 'api -X PATCH repos/NCodeGroup/fresh/code-scanning/default-setup -f query_suite=extended|BODY POST repos/NCodeGroup/fresh/rulesets|api -X PATCH repos/NCodeGroup/fresh -F delete_branch_on_merge=true') ($r.Changes -join '|')
    Check 'create: the summary says CodeQL moves to the extended suite' ($r.Output -match 'switch CodeQL from the default query suite to extended') $r.Output
    Check 'create: protects the default branch and cannot be bypassed' (($r.Body.name -eq 'Protect main') -and ($r.Body.target -eq 'branch') -and ($r.Body.enforcement -eq 'active') -and ($r.Body.conditions.ref_name.include -contains '~DEFAULT_BRANCH') -and ($r.Body.bypass_actors.Count -eq 0))
    Check 'create: no deletion, no force push, a pull request, a code-scanning rule, and nothing more' (($types -join ',') -eq 'deletion,non_fast_forward,pull_request,code_scanning') ($types -join ',')
    $scan = @(($r.Body.rules | Where-Object type -eq 'code_scanning').parameters.code_scanning_tools)
    Check 'create: the code-scanning rule blocks CodeQL alerts at warning level or above and security alerts of any severity' (($scan.Count -eq 1) -and ($scan[0].tool -eq 'CodeQL') -and ($scan[0].alerts_threshold -eq 'errors_and_warnings') -and ($scan[0].security_alerts_threshold -eq 'all')) ($scan | ConvertTo-Json -Compress)
    $pr = $r.Body.rules | Where-Object type -eq 'pull_request'
    Check 'create: no approvals, and merge-commit or rebase merges only, never squash' (($pr.parameters.required_approving_review_count -eq 0) -and ((@($pr.parameters.allowed_merge_methods) -join ',') -eq 'merge,rebase')) ($pr.parameters | ConvertTo-Json -Compress)
    Check 'create: every conversation must be resolved before a merge' ($pr.parameters.required_review_thread_resolution -eq $true) ($pr.parameters | ConvertTo-Json -Compress)

    $r = Invoke-Baseline @('-Repo', 'extendedAlready')
    Check 'create: a setup already on the extended suite is not changed' (($r.Changes -join '|') -notmatch 'default-setup' -and $r.Output -notmatch 'query suite') "$($r.Changes -join '|') $($r.Output)"

    $r = Invoke-Baseline @('-Repo', 'suiteUnreported')
    Check 'create: a configured setup that names no query suite is switched to extended, and the summary says so' ((($r.Changes -join '|') -match [regex]::Escape('api -X PATCH repos/NCodeGroup/suiteUnreported/code-scanning/default-setup -f query_suite=extended')) -and $r.Output -match 'switch CodeQL from a query suite it did not report to extended') "$($r.Changes -join '|') $($r.Output)"

    $r = Invoke-Baseline @('-Repo', 'switchRefused')
    Check 'create: a refused switch to the extended suite reports the repository as failed, and says nothing else changed' ($r.Output -match [regex]::Escape("switchRefused: FAILED: Couldn't switch CodeQL's default setup to the extended query suite for switchRefused; its ruleset and delete-branch-on-merge were left as they were, so run it again.") -and $r.Output -notmatch 'done: switchRefused') $r.Output
    Check 'create: a refused switch writes no ruleset and leaves delete-branch-on-merge alone, so the next run retries it' (($r.Changes -join '|') -eq 'api -X PATCH repos/NCodeGroup/switchRefused/code-scanning/default-setup -f query_suite=extended') ($r.Changes -join '|')

    # 3. Required checks, as one comma-separated string, which is how pwsh -File passes a list.
    $r = Invoke-Baseline @('-Repo', 'fresh', '-RequireChecks', 'build-and-test,Commit attribution')
    $checks = $r.Body.rules | Where-Object type -eq 'required_status_checks'
    Check 'checks: names the jobs, reported by GitHub Actions' ((@($checks.parameters.required_status_checks.context) -join ',') -eq 'build-and-test,Commit attribution' -and (@($checks.parameters.required_status_checks.integration_id | Select-Object -Unique) -join ',') -eq '15368') ($checks | ConvertTo-Json -Depth 6 -Compress)
    Check 'checks: must pass on a branch that is up to date with the default branch' ($checks.parameters.strict_required_status_checks_policy -eq $true) ($checks | ConvertTo-Json -Depth 6 -Compress)

    # 3b. A repository where CodeQL's default setup isn't configured gets no code-scanning rule, which would wait forever.
    $r = Invoke-Baseline @('-Repo', 'noCodeQL')
    Check 'create: no code-scanning rule where CodeQL is not configured, and says so' (((@($r.Body.rules.type)) -join ',') -eq 'deletion,non_fast_forward,pull_request' -and $r.Output -match [regex]::Escape("no code-scanning rule (CodeQL's default setup is not configured)")) "$(@($r.Body.rules.type) -join ',') $($r.Output)"
    Check 'create: CodeQL that is not configured is not switched to a suite' (($r.Changes -join '|') -notmatch 'default-setup') ($r.Changes -join '|')

    $r = Invoke-Baseline @('-Repo', 'setupNotFound')
    Check 'create: CodeQL setup not found (404) gets no code-scanning rule' (((@($r.Body.rules.type)) -join ',') -eq 'deletion,non_fast_forward,pull_request') "$(@($r.Body.rules.type) -join ',') $($r.Output)"
    foreach ($name in 'setupFailed', 'setupNoResponse', 'setupUnreadable') {
        $r = Invoke-Baseline @('-Repo', $name)
        Check "skip: a CodeQL setup lookup that fails or can't be read changes nothing ($name)" ($r.Changes.Count -eq 0 -and $r.Output -match "${name}: skipped \(couldn't read CodeQL's default setup") "$($r.Changes -join '|') $($r.Output)"
    }

    # 3c. Invoke-HostApi is copied from workflow/Get-PlanState.ps1, which projects get on its own; the copies must match.
    $bodies = foreach ($file in (Join-Path $repoRoot 'tools/Set-RepositoryBaseline.ps1'), (Join-Path $repoRoot 'workflow/Get-PlanState.ps1')) {
        $ast = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
        $fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-HostApi' }, $true)
        if ($fn) { $fn.Extent.Text -replace '\r\n', "`n" } else { '' }
    }
    Check 'copies: Invoke-HostApi is the same in Set-RepositoryBaseline.ps1 and Get-PlanState.ps1' ($bodies[0] -and $bodies[0] -eq $bodies[1]) 'the two functions differ, or one is missing'

    # 4. A branch other than main.
    $r = Invoke-Baseline @('-Repo', 'legacy')
    Check 'create: works for a default branch that is not main' (($r.Changes -join '|') -like '*BODY POST repos/NCodeGroup/legacy/rulesets*') ($r.Changes -join '|')

    # 5. Repositories left alone.
    $r = Invoke-Baseline @('-Repo', 'owned')
    Check 'alone: a default branch that already requires pull requests' ($r.Changes.Count -eq 0 -and $r.Output -match "owned: left alone \('main' already requires pull requests\)") $r.Output
    $r = Invoke-Baseline @('-Repo', 'ours')
    Check 'alone: a repository that already has Protect main' ($r.Changes.Count -eq 0 -and $r.Output -match "ours: left alone \(already has 'Protect main'\)") $r.Output
    $r = Invoke-Baseline @('-Repo', 'tags')
    Check 'create: a tag ruleset does not count as protecting the default branch' (($r.Changes -join '|') -like '*BODY POST repos/NCodeGroup/tags/rulesets*') ($r.Changes -join '|')
    $r = Invoke-Baseline @('-Repo', 'noPullRequest')
    Check 'create: a ruleset without a pull request rule does not count' (($r.Changes -join '|') -like '*BODY POST repos/NCodeGroup/noPullRequest/rulesets*') ($r.Changes -join '|')

    # 6. -RequireChecks updates the ruleset the script made.
    $r = Invoke-Baseline @('-Repo', 'ours', '-RequireChecks', 'test')
    Check 'update: -RequireChecks changes the ruleset it made, in place' (($r.Changes -join '|') -like '*BODY PUT repos/NCodeGroup/ours/rulesets/101*') ($r.Changes -join '|')
    $scan = @(($r.Body.rules | Where-Object type -eq 'code_scanning').parameters.code_scanning_tools)
    $r2 = Invoke-Baseline @('-Repo', 'oursWithoutCodeQL', '-RequireChecks', 'test')
    Check 'update: a ruleset with a code-scanning rule keeps it, whatever the default setup says (advanced setup runs CodeQL too)' ((@($r2.Body.rules.type) -contains 'code_scanning') -and $r2.Output -match 'keeps its code-scanning rule') "$(@($r2.Body.rules.type) -join ',') $($r2.Output)"
    $r3 = Invoke-Baseline @('-Repo', 'oursCodeQL404', '-RequireChecks', 'test')
    Check 'update: a 404 from the CodeQL setup doesn''t touch the rule a ruleset has' ((@($r3.Body.rules.type) -contains 'code_scanning') -and $r3.Output -match 'keeps its code-scanning rule') "$(@($r3.Body.rules.type) -join ',') $($r3.Output)"
    Check 'update: a ruleset without a code-scanning rule gets one, with the baseline thresholds' (($scan.Count -eq 1) -and ($scan[0].alerts_threshold -eq 'errors_and_warnings') -and ($scan[0].security_alerts_threshold -eq 'all')) (@($r.Body.rules.type) -join ',')

    # 6b. -RequireChecks auto requires the checks that passed on the latest merged pull request.
    $r = Invoke-Baseline @('-Repo', 'autoChecks', '-RequireChecks', 'auto', '-WhatIf')
    Check 'auto: -WhatIf changes nothing' ($r.Changes.Count -eq 0) ($r.Changes -join '|')
    Check 'auto: -WhatIf lists the checks that passed on the latest merged pull request, Commit attribution among them' ($r.Output -match [regex]::Escape('autoChecks: pull request #9 passed: build-and-test, Commit attribution, flaky;') -and $r.Output -match [regex]::Escape("would: autoChecks (main): create 'Protect main' with 3 required check(s): build-and-test, Commit attribution, flaky")) $r.Output
    Check 'auto: -WhatIf prints the command that names them' ($r.Output -match [regex]::Escape("-Repo 'autoChecks' -Owner 'NCodeGroup' -RequireChecks 'build-and-test,Commit attribution,flaky'")) $r.Output
    foreach ($leftOut in "Code review (the review bot's advice)", 'CodeQL (the code-scanning rule covers it)', 'Analyze (csharp) (the code-scanning rule covers it)', 'Analyze (python) (the code-scanning rule covers it)', 'review (ran on pull_request_target, not pull_request)', 'deploy (ran on push, not pull_request)', 'orphan (no workflow run on the commit says what ran it)', 'external (reported by other-ci, not GitHub Actions)', 'lint (skipped)', 'docs (neutral)', 'broken (failure)', 'slow (in_progress)') {
        Check "auto: leaves out $leftOut" ($r.Output -match ('left out: .*' + [regex]::Escape($leftOut))) $r.Output
    }
    Check 'auto: reads the latest merged pull request, not an older one' ($r.Output -notmatch 'old-job') $r.Output

    # The printed command has to run as it is: parse it, and read back the script path and the names it passes.
    $r = Invoke-Baseline @('-Repo', 'oddNames', '-RequireChecks', 'auto', '-WhatIf')
    $line = ($r.Output -split "`r?`n" | Where-Object { $_ -like '*to require them by name: *' } | Select-Object -First 1) -replace '^.*to require them by name: ', ''
    $errors = $null
    $command = [Management.Automation.Language.Parser]::ParseInput("$line", [ref]$null, [ref]$errors).Find({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true)
    $elements = if ($command) { @($command.CommandElements) } else { @() }
    $at = [array]::FindIndex([object[]]$elements, [Predicate[object]] { param($e) $e -is [Management.Automation.Language.CommandParameterAst] -and $e.ParameterName -eq 'RequireChecks' })
    $named = if ($at -ge 0 -and $at + 1 -lt $elements.Count) { $elements[$at + 1].SafeGetValue() } else { $null }
    $path = if ($elements.Count) { $elements[0].SafeGetValue() } else { $null }
    Check 'auto: the printed command parses, with the script path quoted' (-not $errors.Count -and $command.InvocationOperator -eq 'Ampersand' -and $path -and [IO.Path]::GetFullPath($path) -eq [IO.Path]::GetFullPath($script)) $line
    Check 'auto: the printed command passes a name with a quote as it is' ($named -eq "it's fine,plain") "$named | $line"
    Check 'auto: a name with a comma is left out of the command, and listed' ($r.Output -match [regex]::Escape('left out of that command, since -RequireChecks splits a name at its comma: a, b')) $r.Output
    $r = Invoke-Baseline @('-Repo', 'oddNames', '-RequireChecks', 'auto')
    $checks = $r.Body.rules | Where-Object type -eq 'required_status_checks'
    Check 'auto: applied, a name with a quote or a comma is required as one check, as it is' ((@($checks.parameters.required_status_checks.context) -join '|') -eq "a, b|it's fine|plain") ($checks | ConvertTo-Json -Depth 6 -Compress)

    $r = Invoke-Baseline @('-Repo', 'autoChecks', '-RequireChecks', 'auto')
    $checks = $r.Body.rules | Where-Object type -eq 'required_status_checks'
    Check 'auto: requires exactly the checks that passed, reported by GitHub Actions' ((@($checks.parameters.required_status_checks.context) -join ',') -eq 'build-and-test,Commit attribution,flaky' -and (@($checks.parameters.required_status_checks.integration_id | Select-Object -Unique) -join ',') -eq '15368') ($checks | ConvertTo-Json -Depth 6 -Compress)
    Check 'auto: creates the ruleset and says so' (($r.Changes -join '|') -like '*BODY POST repos/NCodeGroup/autoChecks/rulesets*' -and $r.Output -match 'done: autoChecks') $r.Output

    $r = Invoke-Baseline @('-Repo', 'oursAuto', '-RequireChecks', 'auto')
    $checks = $r.Body.rules | Where-Object type -eq 'required_status_checks'
    Check 'auto: updates the ruleset it made, in place' (($r.Changes -join '|') -like '*BODY PUT repos/NCodeGroup/oursAuto/rulesets/101*' -and (@($checks.parameters.required_status_checks.context) -join ',') -eq 'build-and-test,Commit attribution,flaky') "$($r.Changes -join '|') $($r.Output)"

    $r = Invoke-Baseline @('-Repo', 'noMergedPull', '-RequireChecks', 'auto')
    Check 'auto: a repository with no merged pull request is skipped, with a clear message' ($r.Changes.Count -eq 0 -and $r.Output -match [regex]::Escape('noMergedPull: skipped (-RequireChecks auto found no pull request merged into main to read checks from; name the jobs with -RequireChecks)')) "$($r.Changes -join '|') $($r.Output)"
    $r = Invoke-Baseline @('-Repo', 'ours', '-RequireChecks', 'auto')
    Check 'auto: a ruleset it made is left as it was when there is no merged pull request' ($r.Changes.Count -eq 0 -and $r.Output -match 'ours: skipped \(-RequireChecks auto found no pull request') "$($r.Changes -join '|') $($r.Output)"
    $r = Invoke-Baseline @('-Repo', 'nothingPassed', '-RequireChecks', 'auto')
    Check 'auto: a pull request with no check a ruleset can require is skipped, with a clear message' ($r.Changes.Count -eq 0 -and $r.Output -match [regex]::Escape('nothingPassed: skipped (no check that passed on pull request #5 can be required; name the jobs with -RequireChecks)')) "$($r.Changes -join '|') $($r.Output)"
    $r = Invoke-Baseline @('-Repo', 'noCheckRuns', '-RequireChecks', 'auto')
    Check 'auto: a pull request with no check runs at all is skipped, with a clear message' ($r.ExitCode -eq 0 -and $r.Changes.Count -eq 0 -and $r.Output -match [regex]::Escape('noCheckRuns: skipped (no check that passed on pull request #8 can be required; name the jobs with -RequireChecks)') -and $r.Output -notmatch 'FAILED') "$($r.Changes -join '|') $($r.Output)"

    $r = Invoke-Baseline @('-All', '-RequireChecks', 'auto', '-WhatIf')
    Check 'auto: works with -All, reading each repository''s own pull request' ($r.ExitCode -eq 0 -and $r.Changes.Count -eq 0 -and $r.Output -match 'fresh: skipped \(-RequireChecks auto found no pull request' -and $r.Output -match 'owned: left alone') $r.Output

    $r = Invoke-Baseline @('-All', '-RequireChecks', 'auto')
    $each = foreach ($name in 'autoChecks', 'autoOther') {
        $file = Join-Path $bin "posted-$name.json"
        $body = if (Test-Path -LiteralPath $file) { Get-Content -Raw -LiteralPath $file | ConvertFrom-Json } else { $null }
        "${name}=$(@(($body.rules | Where-Object type -eq 'required_status_checks').parameters.required_status_checks.context) -join ',')"
    }
    Check 'auto: -All gives each repository the checks of its own pull request' (($each -join '|') -eq 'autoChecks=build-and-test,Commit attribution,flaky|autoOther=other-build' -and $r.Output -match 'fresh: skipped \(-RequireChecks auto found no pull request') "$($each -join '|') $($r.Output)"

    # 7. -All.
    $r = Invoke-Baseline @('-All')
    Check 'all: skips archived repositories and forks' (($r.Output -notmatch 'old') -and ($r.Output -notmatch 'forked') -and ($r.Output -match 'done: fresh') -and ($r.Output -match 'owned: left alone')) $r.Output

    # 8. Bad parameters.
    $r = Invoke-Baseline @()
    Check 'params: needs -Repo or -All' ($r.ExitCode -ne 0 -and $r.Output -match 'Pass -Repo <name> or -All') $r.Output
    $r = Invoke-Baseline @('-All', '-RequireChecks', 'test')
    Check 'params: -RequireChecks needs -Repo' ($r.ExitCode -ne 0 -and $r.Changes.Count -eq 0 -and $r.Output -match '-RequireChecks needs -Repo') $r.Output
    $r = Invoke-Baseline @('-Repo', 'autoChecks', '-RequireChecks', 'auto,test')
    Check 'params: -RequireChecks auto takes no job names' ($r.ExitCode -ne 0 -and $r.Changes.Count -eq 0 -and $r.Output -match 'pass auto alone') $r.Output
    $r = Invoke-Baseline @('-Repo', 'fresh', '-Owner', 'someone')
    Check 'params: -Owner picks the owner of the repository' (($r.Changes -join '|') -like '*BODY POST repos/someone/fresh/rulesets*') ($r.Changes -join '|')
}
finally { $env:PATH = $savedPath }

''
if ($failures.Count) { "Kept the work folder: $Work"; "Repository baseline tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Repository baseline tests: PASSED'
exit 0
