<#
.SYNOPSIS
    Test that tools\Set-RepositoryBaseline.ps1 gives a repository the baseline ruleset and leaves protected ones alone.

.DESCRIPTION
    Runs the script against a stand-in for gh that serves canned repositories and rulesets and records what it is asked
    to change. Checks that -WhatIf changes nothing; that a repository with no ruleset gets "Protect main" on its default
    branch, with no deletion, no force push, a pull request with no approvals, merge-commit and rebase merges only and
    no bypass, and delete-branch-on-merge; that -RequireChecks adds required status checks; that a repository whose
    default branch already requires pull requests, or already has this ruleset, is left alone, and that -RequireChecks
    updates the ruleset the script made; that a ruleset that already has a code-scanning rule keeps it and its
    thresholds, its repository's suite is never switched, and a notice, with -WhatIf too, says when the default setup
    runs a suite other than extended and how to switch it by hand, while a setup it can't read is reported without
    failing the run; that -RequireChecks auto requires the GitHub Actions checks that passed on the
    latest merged pull request, found on any page of closed pull requests, reading every page of its check runs and
    workflow runs, Commit attribution among them, leaves out the review bot's Code review and its job, CodeQL and its
    Analyze jobs, push-only jobs, jobs no workflow run accounts for, other apps' checks and skipped, neutral, failed or
    unfinished ones, lists them with -WhatIf with a command that names them, quoted so it parses, gives each repository
    its own checks with -All, and skips a repository with no merged pull request or no check to require; that every
    repository it doesn't skip, one whose default branch it leaves alone too, gets a "Protect release tags" ruleset on
    v* tags with no deletion, no update and no bypass, which -WhatIf shows, unless it has one of that name, whatever its
    state, or an active tag ruleset that refuses both already; that it turns on, in order, the read-only workflow token
    with Actions not approving pull requests, secret scanning, its push protection, Dependabot alerts, Dependabot
    security updates and private vulnerability reporting, each with the call and body the API takes, and only where it
    is off, reports each as set, already set, would set or not available, leaves secret scanning out of a repository
    that isn't public, and reports a setting the API won't read or refuses without failing the run; that it allows
    auto-merge, with a PATCH that changes nothing else, where it is off, on a repository whose default branch it leaves
    alone too, and reports an answer without it or a refusal; that -All skips archived repositories and forks; and that
    bad parameters stop it. Prints PASS or FAIL per check and exits 1 on any failure.

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
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Write-Text([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n")) }

if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$bin = Join-Path $Work 'bin'
New-Item -ItemType Directory -Force $bin | Out-Null

# The stand-in for gh. It serves repos.json (repository name -> repository, rulesets and their full forms, and its
# security settings), records every call in calls.log, and keeps the body of every change in bodies.log.
Write-Text (Join-Path $bin 'gh.ps1') @'
# The script runs this in its own session, so a -WhatIf run would reach it as $WhatIfPreference, and its log would stay
# empty: it has to record the calls of a -WhatIf run too, to show that they change nothing.
$WhatIfPreference = $false
$log = Join-Path $PSScriptRoot 'calls.log'
Add-Content -LiteralPath $log -Value ($args -join ' ')
$data = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'repos.json') | ConvertFrom-Json -AsHashtable
if ($args[0] -eq 'repo' -and $args[1] -eq 'list') { ConvertTo-Json -InputObject @($data.list) -Depth 5; exit 0 }
if ($args[0] -ne 'api') { exit 1 }
$method = 'GET'
$rest = @($args[1..($args.Count - 1)] | Where-Object { $_ -notin '--include', '--paginate', '--slurp' })
$include = $args -contains '--include'
# Lists come in pages of 5 here, so a few check runs already span pages. --paginate --slurp answers every page, as an
# array; without it only the first page comes back. Without $Key a page is a bare array, as GitHub pages pull requests.
$paginate = $args -contains '--paginate' -and $args -contains '--slurp'
function Out-Pages([string]$Key, $Items) {
    $pages = @(for ($i = 0; $i -lt [Math]::Max(1, $Items.Count); $i += 5) {
        $page = @($Items | Select-Object -Skip $i -First 5)
        if ($Key) { @{ total_count = $Items.Count; $Key = $page } } else { , $page }
    })
    if ($paginate) { ConvertTo-Json -InputObject $pages -Depth 8 } else { ConvertTo-Json -InputObject $pages[0] -Depth 8 }
}
# Answers with a status and a body; with --include the status line and a header come first, as gh prints them. A status
# of 300 or more exits 1, as gh does.
function Out-Answer([int]$Status, [string]$Body) {
    if ($include) { "HTTP/2.0 $Status Status"; 'Content-Type: application/json'; '' }
    if ($Body) { $Body }
    if ($Status -ge 300) { exit 1 }
    exit 0
}
if ($rest[0] -eq '-X') { $method = $rest[1]; $rest = @($rest[2..($rest.Count - 1)]) }
$path = $rest[0]
if ($method -ne 'GET') {
    # A change. A body sent with --input is logged as BODY <method> <path> and kept in bodies.log, one JSON line each.
    # writeFails (what is changed -> status) refuses it: the key is the path after the repository's, for a
    # security_and_analysis change the feature's name, or allow_auto_merge.
    $repo = $null; $key = ''
    if ($path -match '^repos/[^/]+/([^/]+)/?(.*)$') { $repo = $data.repos[$Matches[1]]; $key = $Matches[2] }
    if ($rest -contains '--input') {
        $file = $rest[[array]::IndexOf($rest, '--input') + 1]
        $sent = Get-Content -Raw -LiteralPath $file | ConvertFrom-Json -AsHashtable
        Add-Content -LiteralPath (Join-Path $PSScriptRoot 'bodies.log') -Value (ConvertTo-Json -Compress -Depth 20 -InputObject @{ method = $method; path = $path; body = $sent })
        Add-Content -LiteralPath $log -Value "BODY $method $path"
        if ($sent.security_and_analysis) { $key = @($sent.security_and_analysis.Keys)[0] }
        elseif ($sent.ContainsKey('allow_auto_merge')) { $key = 'allow_auto_merge' }
    }
    if ($key -eq 'code-scanning/default-setup' -and $repo.switchFails) { exit 1 }
    $refused = if ($repo -and $repo.writeFails) { $repo.writeFails[$key] }
    if ($refused) { Out-Answer ([int]$refused) "{""message"":""Stand-in refused $key""}" }
    if ($rest -contains '--input') { Out-Answer 200 '{}' } else { Out-Answer 204 '' }
}
# The security settings' reads: on, off, readApproves (the workflow token read-only, but Actions may approve pull
# requests) or fail:<code>, as GitHub answers each.
if ($path -match '^repos/[^/]+/([^/]+)/(actions/permissions/workflow|vulnerability-alerts|automated-security-fixes|private-vulnerability-reporting)$') {
    $key = $Matches[2]
    $state = "$($data.repos[$Matches[1]].security[$key])"
    if ($state.StartsWith('fail:')) { Out-Answer ([int]$state.Substring(5)) '{"message":"Stand-in refused to read it"}' }
    $on = $state -eq 'on'
    switch ($key) {
        'actions/permissions/workflow' { Out-Answer 200 (ConvertTo-Json -Compress -InputObject @{ default_workflow_permissions = if ($on -or $state -eq 'readApproves') { 'read' } else { 'write' }; can_approve_pull_request_reviews = -not $on }) }
        'vulnerability-alerts' { if ($on) { Out-Answer 204 '' } else { Out-Answer 404 '{"message":"Vulnerability alerts are disabled."}' } }
        'automated-security-fixes' { if ($on) { Out-Answer 200 '{"enabled":true,"paused":false}' } else { Out-Answer 404 '{"message":"Not Found"}' } }
        default { Out-Answer 200 (ConvertTo-Json -Compress -InputObject @{ enabled = $on }) }
    }
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
if ($path -match '^repos/[^/]+/([^/]+)/pulls\?') { Out-Pages '' @($data.repos[$Matches[1]].pulls | Where-Object { $_ }); exit 0 }
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
function New-TagRuleset([string]$Name, [string[]]$Types = @('deletion', 'update'), [string]$Include = 'refs/tags/v*', [string]$Enforcement = 'active') {
    @{ name = $Name; target = 'tag'; enforcement = $Enforcement
        conditions = @{ ref_name = @{ include = @($Include); exclude = @() } }
        rules = @($Types | ForEach-Object { @{ type = $_ } }) }
}
# $Security sets the state the stand-in reads for a setting, by its path after the repository's (on, off, readApproves
# or fail:<code>): every one is off unless it says otherwise. $WriteFails refuses a change with a status (see the
# stand-in). Secret scanning and its push protection are read from the repository itself, as GitHub reports them, and
# so is auto-merge: $AutoMerge $null leaves it out of the answer, as GitHub does for someone who can't change it.
function New-Repo([string]$Branch = 'main', [bool]$Archived = $false, [bool]$Fork = $false, $Rulesets = @(), [string]$CodeQL = 'configured', [string]$Suite = 'default', [bool]$SwitchFails = $false, $Pulls = @(), [hashtable]$CheckRuns = @{}, [hashtable]$WorkflowRuns = @{},
    [string]$Visibility = 'public', [string]$SecretScanning = 'disabled', [string]$PushProtection = 'disabled', [hashtable]$Security = @{}, [hashtable]$WriteFails = @{}, $AutoMerge = $false) {
    $full = @{}
    $summaries = @()
    $id = 100
    foreach ($ruleset in $Rulesets) { $id++; $ruleset.id = $id; $full["$id"] = $ruleset; $summaries += @{ id = $id; name = $ruleset.name } }
    $settings = @{ 'actions/permissions/workflow' = 'off'; 'vulnerability-alerts' = 'off'; 'automated-security-fixes' = 'off'; 'private-vulnerability-reporting' = 'off' }
    foreach ($key in $Security.Keys) { $settings[$key] = $Security[$key] }
    $analysis = @{ secret_scanning = @{ status = $SecretScanning }; secret_scanning_push_protection = @{ status = $PushProtection } }
    $info = @{ default_branch = $Branch; archived = $Archived; fork = $Fork; private = $Visibility -ne 'public'; visibility = $Visibility; security_and_analysis = $analysis }
    if ($null -ne $AutoMerge) { $info.allow_auto_merge = $AutoMerge }
    @{ info = $info
        rulesets = $summaries; full = $full; codeql = $CodeQL; suite = $Suite; switchFails = $SwitchFails
        pulls = @($Pulls); checkRuns = $CheckRuns; workflowRuns = $WorkflowRuns; security = $settings; writeFails = $WriteFails }
}
$allSecurityOn = @{ 'actions/permissions/workflow' = 'on'; 'vulnerability-alerts' = 'on'; 'automated-security-fixes' = 'on'; 'private-vulnerability-reporting' = 'on' }
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
$scanTypes = @('deletion', 'non_fast_forward', 'pull_request', 'code_scanning')
$looseRuleset = New-Ruleset 'Protect main' @('deletion', 'non_fast_forward', 'pull_request')
$looseRuleset.rules += @{ type = 'code_scanning'; parameters = @{ code_scanning_tools = @(@{ tool = 'CodeQL'; alerts_threshold = 'errors'; security_alerts_threshold = 'high_or_higher' }) } }
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
    oursScanDefault = New-Repo -Rulesets @((New-Ruleset 'Protect main' $scanTypes))
    oursScanExtended = New-Repo -Suite 'extended' -Rulesets @((New-Ruleset 'Protect main' $scanTypes))
    oursScanUnreported = New-Repo -Suite '' -Rulesets @((New-Ruleset 'Protect main' $scanTypes))
    oursScanUnreadable = New-Repo -CodeQL 'fail:403' -Rulesets @((New-Ruleset 'Protect main' $scanTypes))
    oursScanLoose = New-Repo -Rulesets @($looseRuleset)
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
    # A curly apostrophe, which PowerShell also reads as a single quote.
    curlyName = New-Repo -Pulls @((New-Pull 6 'sha6' '2026-10-03T10:00:00Z')) -CheckRuns @{ sha6 = @((New-CheckRun 1 "it$([char]0x2019)s curly"), (New-CheckRun 2 'plain')) } -WorkflowRuns @{ sha6 = $prWorkflowRuns }
    # A second repository with checks of its own, for -All -RequireChecks auto.
    autoOther = New-Repo -Pulls @((New-Pull 3 'sha3' '2026-10-04T10:00:00Z')) -CheckRuns @{ sha3 = @((New-CheckRun 1 'other-build')) } -WorkflowRuns @{ sha3 = $prWorkflowRuns }
    # Seven closed pull requests, five to a page: the latest merged one (#30) is on the second page.
    # Release tags: a ruleset of this name, turned off, is still left alone; so is another active one on v* tags, or on
    # every tag, that refuses both deletion and update.
    tagsOurs = New-Repo -Rulesets @((New-TagRuleset 'Protect release tags' -Enforcement 'disabled'))
    tagsOwned = New-Repo -Rulesets @((New-TagRuleset 'release-tags'))
    tagsAll = New-Repo -Rulesets @((New-TagRuleset 'every tag' -Include '~ALL'))
    tagsInactive = New-Repo -Rulesets @((New-TagRuleset 'release-tags' -Enforcement 'evaluate'))
    # Security settings: every one on already; a private repository, where private vulnerability reporting can't be
    # read; settings the API refuses to change; a workflow token setting it won't read; and some on, some off.
    complete = New-Repo -Rulesets @((New-Ruleset 'Protect main'), (New-TagRuleset 'Protect release tags')) -SecretScanning 'enabled' -PushProtection 'enabled' -Security $allSecurityOn -AutoMerge $true
    private = New-Repo -Visibility 'private' -Security @{ 'private-vulnerability-reporting' = 'fail:422' }
    refused = New-Repo -WriteFails @{ 'actions/permissions/workflow' = 409; 'secret_scanning_push_protection' = 422; 'automated-security-fixes' = 422; 'allow_auto_merge' = 403 }
    workflowUnreadable = New-Repo -Security @{ 'actions/permissions/workflow' = 'fail:403' }
    partial = New-Repo -SecretScanning 'enabled' -Security @{ 'actions/permissions/workflow' = 'readApproves'; 'vulnerability-alerts' = 'on'; 'private-vulnerability-reporting' = 'on' } -AutoMerge $true
    # Auto-merge: an answer that leaves allow_auto_merge out, as GitHub's does for someone who can't change it.
    autoMergeUnread = New-Repo -AutoMerge $null
    autoPaged = New-Repo -Pulls @((New-Pull 21 'sha21' '2026-10-01T10:00:00Z'), (New-Pull 22 'sha22' '2026-10-02T10:00:00Z'), (New-Pull 23 'sha23' ''), (New-Pull 24 'sha24' '2026-10-03T10:00:00Z'), (New-Pull 25 'sha25' '2026-10-04T10:00:00Z'), (New-Pull 26 'sha26' ''), (New-Pull 30 'sha30' '2026-10-25T10:00:00Z')) -CheckRuns @{ sha25 = @((New-CheckRun 1 'first-page-job')); sha30 = @((New-CheckRun 1 'paged-build')) } -WorkflowRuns @{ sha25 = $prWorkflowRuns; sha30 = $prWorkflowRuns }
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
$bodyLog = Join-Path $bin 'bodies.log'
# A run: its output and exit code, its changes in order (a call with a body as its BODY line, without --include), every
# body it sent with its method and path, and the bodies of the last "Protect main" and "Protect release tags" it sent.
function Invoke-Baseline([string[]]$Arguments) {
    foreach ($file in $calls, $bodyLog) { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force } }
    $output = & pwsh -NoProfile -File $script @Arguments 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $log = if (Test-Path -LiteralPath $calls) { Get-Content -LiteralPath $calls } else { @() }
    $sent = @(if (Test-Path -LiteralPath $bodyLog) { Get-Content -LiteralPath $bodyLog | ForEach-Object { $_ | ConvertFrom-Json } })
    [pscustomobject]@{
        Output = $output
        ExitCode = $exitCode
        Changes = @($log | Where-Object { $_ -like 'BODY *' -or ($_ -like '*-X *' -and $_ -notlike '*--input*') } | ForEach-Object { $_ -replace ' --include', '' })
        Bodies = $sent
        Body = ($sent | Where-Object { $_.body.name -eq 'Protect main' } | Select-Object -Last 1).body
        TagBody = ($sent | Where-Object { $_.body.name -eq 'Protect release tags' } | Select-Object -Last 1).body
    }
}
# The command a -RequireChecks auto -WhatIf run prints, parsed: the line, the parse errors, the command, the names it
# passes to -RequireChecks and the script path.
function Read-PrintedCommand([string]$Output) {
    $line = ($Output -split "`r?`n" | Where-Object { $_ -like '*to require them by name: *' } | Select-Object -First 1) -replace '^.*to require them by name: ', ''
    $errors = $null
    $command = [Management.Automation.Language.Parser]::ParseInput("$line", [ref]$null, [ref]$errors).Find({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true)
    $elements = if ($command) { @($command.CommandElements) } else { @() }
    $at = [array]::FindIndex([object[]]$elements, [Predicate[object]] { param($e) $e -is [Management.Automation.Language.CommandParameterAst] -and $e.ParameterName -eq 'RequireChecks' })
    $named = if ($at -ge 0 -and $at + 1 -lt $elements.Count) { $elements[$at + 1].SafeGetValue() } else { $null }
    $path = if ($elements.Count) { $elements[0].SafeGetValue() } else { $null }
    [pscustomobject]@{ Line = $line; Errors = $errors; Command = $command; Named = $named; Path = $path }
}

$savedPath = $env:PATH
$env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
try {
    # 1. -WhatIf.
    $r = Invoke-Baseline @('-Repo', 'fresh', '-WhatIf')
    Check 'whatif: changes nothing' ($r.Changes.Count -eq 0 -and $r.Bodies.Count -eq 0 -and $r.Output -match "would: fresh \(main\): create 'Protect main'") "changes=$($r.Changes -join '|') output=$($r.Output)"
    Check 'whatif: shows the release tags ruleset it would create' ($r.Output -match [regex]::Escape("would: fresh: create 'Protect release tags' on v* tags: no deletion, no update")) $r.Output
    foreach ($label in 'read-only workflow token, and Actions not approving pull requests', 'secret scanning', 'secret scanning push protection', 'Dependabot alerts', 'Dependabot security updates', 'private vulnerability reporting') {
        Check "whatif: shows the security setting it would turn on ($label)" ($r.Output -match [regex]::Escape("fresh: ${label}: would set")) $r.Output
    }
    Check 'whatif: shows that it would allow auto-merge' ($r.Output -match [regex]::Escape('fresh: allow auto-merge: would set')) $r.Output

    # 2. A repository with no ruleset.
    $r = Invoke-Baseline @('-Repo', 'fresh')
    $types = @($r.Body.rules.type)
    Check 'create: switches CodeQL to the extended suite first, then posts one ruleset and turns on delete-branch-on-merge' (($r.Changes[0..2] -join '|') -eq 'api -X PATCH repos/NCodeGroup/fresh/code-scanning/default-setup -f query_suite=extended|BODY POST repos/NCodeGroup/fresh/rulesets|api -X PATCH repos/NCodeGroup/fresh -F delete_branch_on_merge=true' -and $r.Bodies[0].body.name -eq 'Protect main') ($r.Changes -join '|')
    Check 'create: then the release tags ruleset, then each security setting, Dependabot alerts before its security updates, then auto-merge' (($r.Changes[3..($r.Changes.Count - 1)] -join '|') -eq 'BODY POST repos/NCodeGroup/fresh/rulesets|BODY PUT repos/NCodeGroup/fresh/actions/permissions/workflow|BODY PATCH repos/NCodeGroup/fresh|BODY PATCH repos/NCodeGroup/fresh|api -X PUT repos/NCodeGroup/fresh/vulnerability-alerts|api -X PUT repos/NCodeGroup/fresh/automated-security-fixes|api -X PUT repos/NCodeGroup/fresh/private-vulnerability-reporting|BODY PATCH repos/NCodeGroup/fresh') ($r.Changes -join '|')
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
    # The default branch's ruleset and delete-branch-on-merge are left alone; the release tags ruleset and the security
    # settings still come, so a run brings a repository an older baseline protected up to date.
    $r = Invoke-Baseline @('-Repo', 'owned')
    Check 'alone: a default branch that already requires pull requests' (-not $r.Body -and ($r.Changes -join '|') -notmatch 'delete_branch_on_merge' -and $r.Output -match "owned: left alone \('main' already requires pull requests\)") "$($r.Changes -join '|') $($r.Output)"
    Check 'alone: a default branch that already requires pull requests still gets the release tags ruleset and the security settings' ($r.TagBody -and $r.Output -match "done: owned: create 'Protect release tags'" -and $r.Output -match 'owned: private vulnerability reporting: set') $r.Output
    $r = Invoke-Baseline @('-Repo', 'ours')
    Check 'alone: a repository that already has Protect main' (-not $r.Body -and ($r.Changes -join '|') -notmatch 'delete_branch_on_merge|rulesets/101' -and $r.Output -match "ours: left alone \(already has 'Protect main'\)") "$($r.Changes -join '|') $($r.Output)"
    Check 'alone: a repository that already has Protect main still gets the release tags ruleset and the security settings' ($r.TagBody -and $r.Output -match "done: ours: create 'Protect release tags'" -and $r.Output -match 'ours: secret scanning: set') $r.Output
    $r = Invoke-Baseline @('-Repo', 'tags')
    Check 'create: a tag ruleset does not count as protecting the default branch' (($r.Changes -join '|') -like '*BODY POST repos/NCodeGroup/tags/rulesets*' -and $r.Body) ($r.Changes -join '|')
    Check 'tags: a tag ruleset that refuses deletion but not update gets Protect release tags beside it' ($r.TagBody -and $r.Output -match "done: tags: create 'Protect release tags'") $r.Output
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

    # 6a. A ruleset that already has a code-scanning rule: its repository's suite is reported, never switched.
    $r = Invoke-Baseline @('-Repo', 'oursScanDefault')
    Check 'suite: a Protect main with a code-scanning rule is left alone, and its suite is not switched' ($r.Output -match "oursScanDefault: left alone \(already has 'Protect main'\)" -and ($r.Changes -join '|') -notmatch 'default-setup|rulesets/101') "$($r.Changes -join '|') $($r.Output)"
    Check 'suite: the notice says which suite the setup runs and how to switch it by hand' ($r.Output.Contains("oursScanDefault: notice: CodeQL's default setup runs the default query suite, not the extended one") -and $r.Output.Contains('gh api -X PATCH repos/NCodeGroup/oursScanDefault/code-scanning/default-setup -f query_suite=extended') -and $r.Output.Contains('may then block merges on them')) $r.Output
    Check 'suite: the notice doesn''t stop the release tags ruleset or the security settings' ($r.TagBody -and $r.Output -match 'oursScanDefault: secret scanning: set') $r.Output
    $r = Invoke-Baseline @('-Repo', 'oursScanDefault', '-WhatIf')
    Check 'suite: -WhatIf prints the notice too, and changes nothing' ($r.Changes.Count -eq 0 -and $r.Output.Contains('oursScanDefault: notice:')) "$($r.Changes -join '|') $($r.Output)"
    $r = Invoke-Baseline @('-Repo', 'oursScanExtended')
    Check 'suite: no notice when the setup already runs the extended suite' ($r.Output -notmatch 'notice:' -and ($r.Changes -join '|') -notmatch 'default-setup') "$($r.Changes -join '|') $($r.Output)"
    $r = Invoke-Baseline @('-Repo', 'oursScanUnreported')
    Check 'suite: a setup that names no suite gets the notice' ($r.Output.Contains('oursScanUnreported: notice: CodeQL''s default setup runs a query suite it did not report') -and ($r.Changes -join '|') -notmatch 'default-setup') "$($r.Changes -join '|') $($r.Output)"
    $r = Invoke-Baseline @('-Repo', 'oursScanUnreadable')
    Check 'suite: a setup it can''t read is reported, and the run goes on' ($r.ExitCode -eq 0 -and $r.Output.Contains("oursScanUnreadable: couldn't read CodeQL's default setup to check its query suite (HTTP 403)") -and $r.Output -notmatch 'FAILED' -and $r.TagBody) "$($r.ExitCode) $($r.Output)"
    $r = Invoke-Baseline @('-Repo', 'oursScanLoose', '-RequireChecks', 'test')
    $scan = @(($r.Body.rules | Where-Object type -eq 'code_scanning').parameters.code_scanning_tools)
    Check 'suite: -RequireChecks keeps the ruleset''s own code-scanning thresholds and doesn''t switch the suite' ((($r.Changes -join '|') -like '*BODY PUT repos/NCodeGroup/oursScanLoose/rulesets/101*') -and ($r.Changes -join '|') -notmatch 'default-setup' -and ($scan.Count -eq 1) -and ($scan[0].alerts_threshold -eq 'errors') -and ($scan[0].security_alerts_threshold -eq 'high_or_higher') -and $r.Output.Contains('oursScanLoose: notice:')) "$($r.Changes -join '|') $($r.Output)"
    $r = Invoke-Baseline @('-Repo', 'oursWithoutCodeQL', '-RequireChecks', 'test')
    $r2 = Invoke-Baseline @('-Repo', 'oursCodeQL404', '-RequireChecks', 'test')
    Check 'suite: no notice where the default setup is not configured or not found' ($r.Output -notmatch "notice:|couldn't read CodeQL" -and $r2.Output -notmatch "notice:|couldn't read CodeQL") "$($r.Output) $($r2.Output)"

    # 6b. -RequireChecks auto requires the checks that passed on the latest merged pull request.
    $r = Invoke-Baseline @('-Repo', 'autoChecks', '-RequireChecks', 'auto', '-WhatIf')
    Check 'auto: -WhatIf changes nothing' ($r.Changes.Count -eq 0) ($r.Changes -join '|')
    Check 'auto: -WhatIf lists the checks that passed on the latest merged pull request, Commit attribution among them' ($r.Output -match [regex]::Escape('autoChecks: pull request #9 passed: build-and-test, Commit attribution, flaky;') -and $r.Output -match [regex]::Escape("would: autoChecks (main): create 'Protect main' with 3 required check(s): build-and-test, Commit attribution, flaky")) $r.Output
    Check 'auto: -WhatIf prints the command that names them' ($r.Output -match [regex]::Escape("-Repo 'autoChecks' -Owner 'NCodeGroup' -RequireChecks 'build-and-test,Commit attribution,flaky'")) $r.Output
    Check 'auto: -WhatIf says the checks come from one pull request and a path-filtered job would block others' ($r.Output -match [regex]::Escape('autoChecks: these checks come from one pull request. A job whose workflow has paths or branches filters')) $r.Output
    foreach ($leftOut in "Code review (the review bot's advice)", 'CodeQL (the code-scanning rule covers it)', 'Analyze (csharp) (the code-scanning rule covers it)', 'Analyze (python) (the code-scanning rule covers it)', 'review (ran on pull_request_target, not pull_request)', 'deploy (ran on push, not pull_request)', 'orphan (no workflow run on the commit says what ran it)', 'external (reported by other-ci, not GitHub Actions)', 'lint (skipped)', 'docs (neutral)', 'broken (failure)', 'slow (in_progress)') {
        Check "auto: leaves out $leftOut" ($r.Output -match ('left out: .*' + [regex]::Escape($leftOut))) $r.Output
    }
    Check 'auto: reads the latest merged pull request, not an older one' ($r.Output -notmatch 'old-job') $r.Output
    $r = Invoke-Baseline @('-Repo', 'autoPaged', '-RequireChecks', 'auto', '-WhatIf')
    Check 'auto: reads every page of closed pull requests to find the latest merged one' ($r.Output -match [regex]::Escape('autoPaged: pull request #30 passed: paged-build;')) $r.Output

    # The printed command has to run as it is: parse it, and read back the script path and the names it passes.
    $r = Invoke-Baseline @('-Repo', 'oddNames', '-RequireChecks', 'auto', '-WhatIf')
    $p = Read-PrintedCommand $r.Output
    Check 'auto: the printed command parses, with the script path quoted' (-not $p.Errors.Count -and $p.Command.InvocationOperator -eq 'Ampersand' -and $p.Path -and [IO.Path]::GetFullPath($p.Path) -eq [IO.Path]::GetFullPath($script)) $p.Line
    Check 'auto: the printed command passes a name with a quote as it is' ($p.Named -eq "it's fine,plain") "$($p.Named) | $($p.Line)"
    Check 'auto: a name with a comma is left out of the command, and listed' ($r.Output -match [regex]::Escape('left out of that command, since -RequireChecks splits a name at its comma: a, b')) $r.Output
    $r = Invoke-Baseline @('-Repo', 'oddNames', '-RequireChecks', 'auto')
    $checks = $r.Body.rules | Where-Object type -eq 'required_status_checks'
    Check 'auto: applied, a name with a quote or a comma is required as one check, as it is' ((@($checks.parameters.required_status_checks.context) -join '|') -eq "a, b|it's fine|plain") ($checks | ConvertTo-Json -Depth 6 -Compress)

    # The run prints a curly quote, so its output is read as UTF-8, also from a Windows console.
    $encoding = [Console]::OutputEncoding
    try {
        try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { Write-Verbose "Couldn't set the console's output encoding: $_" }
        $r = Invoke-Baseline @('-Repo', 'curlyName', '-RequireChecks', 'auto', '-WhatIf')
    }
    finally { try { [Console]::OutputEncoding = $encoding } catch { Write-Verbose "Couldn't restore the console's output encoding: $_" } }
    $p = Read-PrintedCommand $r.Output
    $curly = "it$([char]0x2019)s curly"
    Check 'auto: the printed command doubles a curly quote and passes the name as it is' ((-not $p.Errors.Count) -and $p.Line.Contains("it$([char]0x2019)$([char]0x2019)s curly") -and ($p.Named -eq "$curly,plain")) "$($p.Named) | $($p.Line)"

    $r = Invoke-Baseline @('-Repo', 'autoChecks', '-RequireChecks', 'auto')
    $checks = $r.Body.rules | Where-Object type -eq 'required_status_checks'
    Check 'auto: requires exactly the checks that passed, reported by GitHub Actions' ((@($checks.parameters.required_status_checks.context) -join ',') -eq 'build-and-test,Commit attribution,flaky' -and (@($checks.parameters.required_status_checks.integration_id | Select-Object -Unique) -join ',') -eq '15368') ($checks | ConvertTo-Json -Depth 6 -Compress)
    Check 'auto: creates the ruleset and says so' (($r.Changes -join '|') -like '*BODY POST repos/NCodeGroup/autoChecks/rulesets*' -and $r.Output -match 'done: autoChecks') $r.Output
    Check 'auto: an applied run says the checks come from one pull request too' ($r.Output -match [regex]::Escape('autoChecks: these checks come from one pull request.')) $r.Output

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
        $body = ($r.Bodies | Where-Object { $_.path -eq "repos/NCodeGroup/$name/rulesets" -and $_.body.name -eq 'Protect main' } | Select-Object -Last 1).body
        "${name}=$(@(($body.rules | Where-Object type -eq 'required_status_checks').parameters.required_status_checks.context) -join ',')"
    }
    Check 'auto: -All gives each repository the checks of its own pull request' (($each -join '|') -eq 'autoChecks=build-and-test,Commit attribution,flaky|autoOther=other-build' -and $r.Output -match 'fresh: skipped \(-RequireChecks auto found no pull request') "$($each -join '|') $($r.Output)"

    # 7. -All.
    $r = Invoke-Baseline @('-All')
    Check 'all: skips archived repositories and forks' (($r.Output -notmatch 'old') -and ($r.Output -notmatch 'forked') -and ($r.Output -match 'done: fresh') -and ($r.Output -match 'owned: left alone')) $r.Output

    # 7b. The release tags ruleset.
    $r = Invoke-Baseline @('-Repo', 'fresh')
    $tag = $r.TagBody
    Check 'tags: Protect release tags is on v* tags only, active, and cannot be bypassed' ($tag -and $tag.target -eq 'tag' -and $tag.enforcement -eq 'active' -and (@($tag.conditions.ref_name.include) -join ',') -eq 'refs/tags/v*' -and @($tag.conditions.ref_name.exclude).Count -eq 0 -and @($tag.bypass_actors).Count -eq 0) ($tag | ConvertTo-Json -Depth 6 -Compress)
    Check 'tags: refuses deleting and updating (moving) a tag, and nothing more, so a release can still be tagged' ((@($tag.rules.type) -join ',') -eq 'deletion,update') ($tag | ConvertTo-Json -Depth 6 -Compress)
    Check 'tags: posted to the repository''s rulesets, and the run says so' (@($r.Bodies | Where-Object { $_.body.name -eq 'Protect release tags' -and $_.method -eq 'POST' -and $_.path -eq 'repos/NCodeGroup/fresh/rulesets' }).Count -eq 1 -and $r.Output -match [regex]::Escape("done: fresh: create 'Protect release tags' on v* tags: no deletion, no update (a tag is never moved), no bypass")) $r.Output
    foreach ($case in @(
            @{ Repo = 'tagsOurs'; Says = "tagsOurs: left alone (already has 'Protect release tags')"; What = 'a ruleset of that name, even one turned off' },
            @{ Repo = 'tagsOwned'; Says = "tagsOwned: left alone ('release-tags' already refuses deleting and moving v* tags)"; What = 'an active tag ruleset on v* that refuses deletion and update' },
            @{ Repo = 'tagsAll'; Says = "tagsAll: left alone ('every tag' already refuses deleting and moving v* tags)"; What = 'an active ruleset on every tag that refuses deletion and update' })) {
        $r = Invoke-Baseline @('-Repo', $case.Repo)
        Check "tags: leaves alone $($case.What)" (-not $r.TagBody -and $r.Output.Contains($case.Says) -and $r.Body -and $r.Output -match "done: $($case.Repo) \(main\)") $r.Output
    }
    $r = Invoke-Baseline @('-Repo', 'tagsInactive')
    Check 'tags: a tag ruleset that is not active does not count' ($r.TagBody -and $r.Output -match "done: tagsInactive: create 'Protect release tags'") $r.Output
    $r = Invoke-Baseline @('-Repo', 'tagsOurs', '-WhatIf')
    Check 'tags: -WhatIf says it leaves an existing one alone, and changes nothing' ($r.Changes.Count -eq 0 -and $r.Output -match [regex]::Escape("tagsOurs: left alone (already has 'Protect release tags')") -and $r.Output -notmatch "would: tagsOurs: create 'Protect release tags'") $r.Output

    # 7c. The security settings.
    $r = Invoke-Baseline @('-Repo', 'fresh')
    $settings = @($r.Bodies | Where-Object { $_.path -ne 'repos/NCodeGroup/fresh/rulesets' })
    $workflow = $settings | Where-Object { $_.path -eq 'repos/NCodeGroup/fresh/actions/permissions/workflow' }
    Check 'security: the workflow token is read-only by default and Actions may not approve pull requests' ($workflow.method -eq 'PUT' -and $workflow.body.default_workflow_permissions -eq 'read' -and $workflow.body.can_approve_pull_request_reviews -eq $false -and @($workflow.body.PSObject.Properties).Count -eq 2) ($workflow | ConvertTo-Json -Depth 6 -Compress)
    $analysis = @($settings | Where-Object { $_.path -eq 'repos/NCodeGroup/fresh' -and $_.method -eq 'PATCH' -and $_.body.security_and_analysis } | ForEach-Object { $_.body.security_and_analysis | ConvertTo-Json -Depth 6 -Compress })
    Check 'security: secret scanning, then its push protection, each turned on in its own PATCH of the repository' (($analysis -join '|') -eq '{"secret_scanning":{"status":"enabled"}}|{"secret_scanning_push_protection":{"status":"enabled"}}') ($analysis -join '|')
    Check 'security: Dependabot alerts, Dependabot security updates and private vulnerability reporting are turned on with a PUT and no body' (@($settings | Where-Object { $_.path -match 'vulnerability-alerts|automated-security-fixes|private-vulnerability-reporting' }).Count -eq 0 -and (@($r.Changes | Where-Object { $_ -like 'api -X PUT *' }) -join '|') -eq 'api -X PUT repos/NCodeGroup/fresh/vulnerability-alerts|api -X PUT repos/NCodeGroup/fresh/automated-security-fixes|api -X PUT repos/NCodeGroup/fresh/private-vulnerability-reporting') ($r.Changes -join '|')
    foreach ($label in 'read-only workflow token, and Actions not approving pull requests', 'secret scanning', 'secret scanning push protection', 'Dependabot alerts', 'Dependabot security updates', 'private vulnerability reporting') {
        Check "security: reports the setting as set ($label)" ($r.Output -match [regex]::Escape("fresh: ${label}: set")) $r.Output
    }

    $r = Invoke-Baseline @('-Repo', 'complete')
    Check 'security: a repository with everything on already changes nothing' ($r.Changes.Count -eq 0) ($r.Changes -join '|')
    foreach ($label in 'read-only workflow token, and Actions not approving pull requests', 'secret scanning', 'secret scanning push protection', 'Dependabot alerts', 'Dependabot security updates', 'private vulnerability reporting') {
        Check "security: reports a setting that is on as already set ($label)" ($r.Output -match [regex]::Escape("complete: ${label}: already set")) $r.Output
    }

    $r = Invoke-Baseline @('-Repo', 'partial')
    Check 'security: only the settings that are off are changed' ((@($r.Changes | Where-Object { $_ -notlike '*rulesets*' -and $_ -notlike '*default-setup*' -and $_ -notlike '*delete_branch_on_merge*' }) -join '|') -eq 'BODY PUT repos/NCodeGroup/partial/actions/permissions/workflow|BODY PATCH repos/NCodeGroup/partial|api -X PUT repos/NCodeGroup/partial/automated-security-fixes') ($r.Changes -join '|')
    Check 'security: a read-only token that may still approve pull requests counts as off' ($r.Output -match [regex]::Escape('partial: read-only workflow token, and Actions not approving pull requests: set')) $r.Output
    Check 'security: with secret scanning on, only its push protection is turned on' ((@($r.Bodies | Where-Object { $_.path -eq 'repos/NCodeGroup/partial' } | ForEach-Object { $_.body.security_and_analysis | ConvertTo-Json -Depth 6 -Compress }) -join '|') -eq '{"secret_scanning_push_protection":{"status":"enabled"}}' -and $r.Output -match 'partial: secret scanning: already set') $r.Output

    $r = Invoke-Baseline @('-Repo', 'private')
    Check 'security: secret scanning is left out of a repository that is not public, with the reason, since it would be paid there' (@($r.Bodies | Where-Object { $_.body.security_and_analysis }).Count -eq 0 -and $r.Output -match [regex]::Escape("private: secret scanning: not available (the repository isn't public") -and $r.Output -match [regex]::Escape("private: secret scanning push protection: not available (the repository isn't public")) $r.Output
    Check 'security: a setting the API will not read is reported, with its answer, and not written' (($r.Changes -join '|') -notmatch 'private-vulnerability-reporting' -and $r.Output -match [regex]::Escape("private: private vulnerability reporting: not available (couldn't read it: HTTP 422: Stand-in refused to read it)")) "$($r.Changes -join '|') $($r.Output)"
    Check 'security: an unavailable setting does not fail the run' ($r.ExitCode -eq 0 -and $r.Output -notmatch 'FAILED' -and $r.Output -match "done: private \(main\)" -and $r.Output -match 'private: Dependabot security updates: set') $r.Output

    $r = Invoke-Baseline @('-Repo', 'refused')
    foreach ($case in @(
            @{ Label = 'read-only workflow token, and Actions not approving pull requests'; Why = 'HTTP 409: Stand-in refused actions/permissions/workflow' },
            @{ Label = 'secret scanning push protection'; Why = 'HTTP 422: Stand-in refused secret_scanning_push_protection' },
            @{ Label = 'Dependabot security updates'; Why = 'HTTP 422: Stand-in refused automated-security-fixes' })) {
        Check "security: a change the API refuses is reported as not available, with its answer ($($case.Label))" ($r.Output -match [regex]::Escape("refused: $($case.Label): not available ($($case.Why))")) $r.Output
    }
    Check 'security: after a refusal the next settings are still turned on, and the run does not fail' ($r.ExitCode -eq 0 -and $r.Output -notmatch 'FAILED' -and ($r.Changes -join '|') -match 'api -X PUT repos/NCodeGroup/refused/private-vulnerability-reporting' -and $r.Output -match 'refused: secret scanning: set' -and $r.Output -match 'refused: private vulnerability reporting: set') $r.Output

    $r = Invoke-Baseline @('-Repo', 'workflowUnreadable')
    Check 'security: a workflow token setting that cannot be read is reported and left as it is' (($r.Changes -join '|') -notmatch 'actions/permissions/workflow' -and $r.Output -match [regex]::Escape("workflowUnreadable: read-only workflow token, and Actions not approving pull requests: not available (couldn't read it: HTTP 403: Stand-in refused to read it)") -and $r.Output -match 'workflowUnreadable: secret scanning: set') "$($r.Changes -join '|') $($r.Output)"

    $r = Invoke-Baseline @('-Repo', 'private', '-WhatIf')
    Check 'security: -WhatIf reads the settings, reports them, and writes nothing' ($r.Changes.Count -eq 0 -and $r.Output -match 'private: Dependabot alerts: would set' -and $r.Output -match [regex]::Escape("private: secret scanning: not available (the repository isn't public")) $r.Output
    $r = Invoke-Baseline @('-Repo', 'setupFailed')
    Check 'security: a repository skipped for its default branch gets no tag ruleset and no setting' ($r.Changes.Count -eq 0 -and $r.Output -notmatch 'Protect release tags|secret scanning|auto-merge') $r.Output

    # 7d. Auto-merge, which the template's code-review-auto-merge.yml needs.
    $r = Invoke-Baseline @('-Repo', 'fresh')
    $autoMerge = @($r.Bodies | Where-Object { $_.path -eq 'repos/NCodeGroup/fresh' -and $null -ne $_.body.allow_auto_merge })
    Check 'auto-merge: allowed with a PATCH of the repository that changes nothing else, and the run says so' ($autoMerge.Count -eq 1 -and $autoMerge[0].method -eq 'PATCH' -and $autoMerge[0].body.allow_auto_merge -eq $true -and @($autoMerge[0].body.PSObject.Properties).Count -eq 1 -and $r.Output -match [regex]::Escape('fresh: allow auto-merge: set')) "$($autoMerge | ConvertTo-Json -Depth 6 -Compress) $($r.Output)"
    $r = Invoke-Baseline @('-Repo', 'complete')
    Check 'auto-merge: a repository that allows it already is reported and not written' ($r.Output -match [regex]::Escape('complete: allow auto-merge: already set') -and -not @($r.Bodies | Where-Object { $null -ne $_.body.allow_auto_merge }).Count) $r.Output
    $r = Invoke-Baseline @('-Repo', 'owned')
    Check 'auto-merge: a repository whose default branch is left alone still gets it' ($r.Output -match "owned: left alone \('main' already requires pull requests\)" -and $r.Output -match [regex]::Escape('owned: allow auto-merge: set')) $r.Output
    $r = Invoke-Baseline @('-Repo', 'autoMergeUnread')
    Check 'auto-merge: an answer that leaves it out is reported and not written' ($r.Output -match [regex]::Escape("autoMergeUnread: allow auto-merge: not available (couldn't read it: the repository's answer doesn't include it)") -and -not @($r.Bodies | Where-Object { $null -ne $_.body.allow_auto_merge }).Count) $r.Output
    $r = Invoke-Baseline @('-Repo', 'refused')
    Check 'auto-merge: a change the API refuses is reported as not available, with its answer, and does not fail the run' ($r.ExitCode -eq 0 -and $r.Output -notmatch 'FAILED' -and $r.Output -match [regex]::Escape('refused: allow auto-merge: not available (HTTP 403: Stand-in refused allow_auto_merge)')) $r.Output

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
