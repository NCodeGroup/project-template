<#
.SYNOPSIS
    Gives an NCodeGroup repository the baseline branch protection, so nothing reaches the default branch except through a
    pull request.

.DESCRIPTION
    For each repository it:
      - adds a "Protect main" ruleset on the default branch, the same shape as project-template's: no deletion, no force
        push, a pull request required (no approvals, since the organization has one maintainer) with every conversation
        resolved, so a review finding from the bot, CodeQL or a person can't be merged past, merge-commit or rebase
        merges only, never squash, so each commit of a plan stays on the branch, when CodeQL's default setup is
        configured for the repository a code-scanning rule that blocks a pull request whose CodeQL results add an alert
        at warning level or above or a security alert of any severity, and, when -RequireChecks names them, those CI
        jobs as required status checks, which must pass on a branch that is up to date with the default branch;
      - switches CodeQL's default setup, when it read it as configured, to the extended query suite, before it writes the
        ruleset, so a switch that fails leaves the repository for the next run to retry;
      - turns on "delete branch on merge".

    A repository that already has an active ruleset requiring pull requests on its default branch is left alone, because
    its owner shaped that ruleset. An archived repository and a fork are skipped. A ruleset it made earlier is left
    alone too; pass -RequireChecks to update that one's required checks in place.

    Name only jobs that run on pull requests. A job that runs on a release or a schedule never reports on a pull
    request, so requiring it would block every merge.

    -RequireChecks auto names them for you, for each repository: it reads the check runs on the head commit of the latest
    pull request merged into the default branch and requires the GitHub Actions jobs that a pull_request event ran there
    and that passed (a job that ran more than once counts by its latest run). It leaves out, and lists with the reason,
    the review bot's advisory "Code review" and its pull_request_target job, CodeQL (the code-scanning rule covers it)
    and its Analyze jobs, a check another app reports, and any job that was skipped, neutral, failed or didn't finish,
    since a skipped required check counts as passing. The template's "Commit attribution" job is required this way
    wherever it ran on that pull request and passed, so a commit with an AI co-author trailer can't merge. A repository
    with no merged pull request, or none of whose checks qualify, is skipped with the reason and nothing changed. With
    -WhatIf it lists the checks and prints the command that names them, to edit and run; a job whose name has a comma is
    listed apart, since -RequireChecks would split it. The list comes from one pull request: a job whose workflow has
    paths or branches filters reports nothing on a pull request the filters skip, and that pull request can't merge, so
    run -WhatIf first and leave such jobs out.

    GitHub Free doesn't offer organization rulesets, so this applies one to each repository. New-Project.ps1 runs it for a
    repository it creates; Adopt-Project.ps1 prints the command to run.

.EXAMPLE
    .\tools\Set-RepositoryBaseline.ps1 -Repo Buffers -WhatIf     # shows what it would do
    .\tools\Set-RepositoryBaseline.ps1 -Repo Buffers -RequireChecks 'build-and-test,Commit attribution'
    .\tools\Set-RepositoryBaseline.ps1 -Repo Buffers -RequireChecks auto -WhatIf   # lists the checks it would require
    .\tools\Set-RepositoryBaseline.ps1 -All -Owner NCodeGroup
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Owner', Justification = 'Get-Targets and Set-Baseline, nested functions, use it.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Repo,
    [switch]$All,
    # Names of the jobs a pull request must pass, as the checks list shows them, separated by commas (pwsh -File passes
    # one value for a parameter, so a list has to arrive as one string). Only with -Repo. Or auto, alone, which reads them
    # from each repository's latest merged pull request, and works with -All too.
    [string[]]$RequireChecks = @(),
    # The owner of the repositories: an organization or a user.
    [Alias('Org')][string]$Owner = 'NCodeGroup'
)
$ErrorActionPreference = 'Stop'
if (-not $Repo -and -not $All) { throw 'Pass -Repo <name> or -All.' }
if ($Repo -and $All) { throw 'Pass -Repo or -All, not both.' }
$RequireChecks = @($RequireChecks | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$autoChecks = $RequireChecks -contains 'auto'
if ($autoChecks -and $RequireChecks.Count -gt 1) { throw "-RequireChecks auto reads the checks itself: pass auto alone, or name the jobs." }
if ($All -and $RequireChecks.Count -and -not $autoChecks) { throw '-RequireChecks needs -Repo: each repository names its own jobs (or pass -RequireChecks auto).' }

$rulesetName = 'Protect main'
# GitHub Actions' app id: required checks are matched to the app that reports them.
$actionsAppId = 15368
# -RequireChecks auto never requires these checks, whatever app reported them or event ran them: each name pattern
# (matched with -like) maps to the reason it lists. CodeQL's Analyze jobs go by name too: a repository's own CodeQL
# workflow runs them on pull_request.
$excludedChecks = [ordered]@{
    'Code review' = "the review bot's advice"
    'CodeQL' = 'the code-scanning rule covers it'
    'Analyze (*)' = 'the code-scanning rule covers it'
}

function Invoke-GhJson([string[]]$GhArgs) {
    $out = & gh @GhArgs
    if ($LASTEXITCODE) { throw "gh $($GhArgs -join ' ') failed." }
    if ($out) { $out | ConvertFrom-Json } else { $null }
}

# Reads every page of a list the API pages, and returns the items under $Key from all of them: one page holds at most
# 100, and a list cut short would quietly leave checks out. Without $Key, each page is the list itself, as the pull
# requests list is.
function Get-GhPagedItems([string]$Path, [string]$Key = '') {
    @(Invoke-GhJson @('api', '--paginate', '--slurp', $Path) | ForEach-Object { if ($Key) { $_.$Key } else { $_ } } | Where-Object { $_ })
}

# Calls the host's API and returns the HTTP status and the body. The status comes from the response's own status line
# (--include), never from the CLI's wording, and stderr stays out of the body, so a warning can't spoil the JSON. A call
# that got no response at all (no network, no login) has no status.
# workflow/Get-PlanState.ps1 has the same function; a change to one belongs in both.
function Invoke-HostApi([string]$Cli, [string]$Path) {
    $lines = @(& $Cli api --include $Path 2>$null)
    $status = $null
    if ($lines.Count -and $lines[0] -match '^HTTP/\S+\s+(\d{3})\b') { $status = [int]$Matches[1] }
    $blank = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if (-not $lines[$i].Trim()) { $blank = $i; break } }
    $body = if ($blank -ge 0 -and $blank -lt $lines.Count - 1) { $lines[($blank + 1)..($lines.Count - 1)] -join "`n" } else { '' }
    [pscustomobject]@{ Status = $status; Body = $body }
}

function Get-Targets {
    if ($Repo) { return @($Repo) }
    (Invoke-GhJson @('repo', 'list', $Owner, '--limit', '200', '--json', 'name,isArchived,isFork')) |
        Where-Object { -not $_.isArchived -and -not $_.isFork } | Sort-Object name | ForEach-Object { $_.name }
}

# -RequireChecks auto: reads the check runs on the head commit of the latest pull request merged into $Branch and returns
# its number, the checks a ruleset can require, and the others with the reason each is left out; $null when no pull
# request was merged into it. A required check is matched to GitHub Actions, so only the Actions jobs a pull_request
# event ran qualify: pull_request_target (the review bot's job), CodeQL's dynamic Analyze jobs and push-only jobs don't
# run on every pull request. It reads every page of the closed pull requests, since the latest merged one can be past
# the 100 updated last, and of the check runs and workflow runs.
function Get-PassingChecks([string]$Name, [string]$Branch) {
    $pulls = Get-GhPagedItems "repos/$Owner/$Name/pulls?state=closed&base=$Branch&sort=updated&direction=desc&per_page=100"
    $latest = $pulls | Where-Object { $_.merged_at } | Sort-Object { [datetime]$_.merged_at } -Descending | Select-Object -First 1
    if (-not $latest) { return $null }
    $sha = $latest.head.sha
    $runs = Get-GhPagedItems "repos/$Owner/$Name/commits/$sha/check-runs?per_page=100" 'check_runs'
    $events = @{}
    foreach ($run in Get-GhPagedItems "repos/$Owner/$Name/actions/runs?head_sha=$sha&per_page=100" 'workflow_runs') {
        $events["$($run.check_suite_id)"] = "$($run.event)"
    }
    $passed = [Collections.Generic.List[string]]::new()
    $leftOut = [Collections.Generic.List[string]]::new()
    foreach ($group in $runs | Group-Object name | Sort-Object Name) {
        $checkName = $group.Name
        $why = $null
        foreach ($pattern in $excludedChecks.Keys) { if ($checkName -like $pattern) { $why = $excludedChecks[$pattern]; break } }
        if (-not $why) {
            $ours = @($group.Group | Where-Object { $_.app.id -eq $actionsAppId -and $events["$($_.check_suite.id)"] -eq 'pull_request' })
            if (-not $ours.Count) {
                $other = $group.Group | Sort-Object { [long]$_.id } -Descending | Select-Object -First 1
                $ranOn = $events["$($other.check_suite.id)"]
                $why = if ($other.app.id -ne $actionsAppId) { "reported by $($other.app.slug), not GitHub Actions" } elseif ($ranOn) { "ran on $ranOn, not pull_request" } else { 'no workflow run on the commit says what ran it' }
            }
            else {
                # A job that ran more than once, such as a re-run, counts by its latest run.
                $check = $ours | Sort-Object { [long]$_.id } -Descending | Select-Object -First 1
                if ($check.status -ne 'completed') { $why = "$($check.status)" }
                elseif ($check.conclusion -ne 'success') { $why = "$($check.conclusion)" }
            }
        }
        if ($why) { $leftOut.Add("$checkName ($why)") } else { $passed.Add($checkName) }
    }
    [pscustomobject]@{ Number = $latest.number; Checks = @($passed); LeftOut = @($leftOut) }
}

function Set-Baseline {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Name)
    $info = Invoke-GhJson @('api', "repos/$Owner/$Name")
    if ($info.archived -or $info.fork) { Write-Host "${Name}: skipped (archived or fork)"; return }
    $branch = $info.default_branch

    $rulesets = @(Invoke-GhJson @('api', "repos/$Owner/$Name/rulesets"))
    $own = $null
    foreach ($summary in $rulesets) {
        $full = Invoke-GhJson @('api', "repos/$Owner/$Name/rulesets/$($summary.id)")
        if ($full.target -ne 'branch' -or $full.enforcement -ne 'active') { continue }
        $onDefault = $full.conditions.ref_name.include -contains '~DEFAULT_BRANCH' -or $full.conditions.ref_name.include -contains "refs/heads/$branch"
        if (-not $onDefault) { continue }
        if ($full.name -eq $rulesetName) { $own = $full; continue }
        if ($full.rules.type -contains 'pull_request') { Write-Host "${Name}: left alone ('$($full.name)' already requires pull requests)"; return }
    }

    # A ruleset of this name that exists already is changed only when -RequireChecks asks for new checks.
    if ($own -and -not $RequireChecks.Count) { Write-Host "${Name}: left alone (already has '$rulesetName')"; return }
    $checks = @($RequireChecks)
    if ($autoChecks) {
        $found = Get-PassingChecks $Name $branch
        if (-not $found) { Write-Host "${Name}: skipped (-RequireChecks auto found no pull request merged into $branch to read checks from; name the jobs with -RequireChecks)"; return }
        Write-Host "${Name}: pull request #$($found.Number) passed: $(if ($found.Checks.Count) { $found.Checks -join ', ' } else { 'nothing a ruleset can require' }); left out: $(if ($found.LeftOut.Count) { $found.LeftOut -join ', ' } else { 'nothing' })"
        if (-not $found.Checks.Count) { Write-Host "${Name}: skipped (no check that passed on pull request #$($found.Number) can be required; name the jobs with -RequireChecks)"; return }
        Write-Host "${Name}: these checks come from one pull request. A job whose workflow has paths or branches filters reports nothing on a pull request the filters skip, which then can't merge; leave such a job out by naming the rest with -RequireChecks"
        $checks = @($found.Checks)
    }

    # The code-scanning rule. A ruleset that has one keeps it as it is, whatever runs CodeQL (default setup or a
    # repository's own workflow): an update never removes it. Otherwise CodeQL's default setup decides: configured adds
    # the rule; an answer that says it isn't, or "not found" (HTTP 404), leaves it out, since every pull request would
    # wait for CodeQL results that never come. A lookup that fails for any other reason, such as a missing token scope or
    # a 5xx, or an answer that can't be read, says nothing, so the repository is skipped with the reason.
    $kept = if ($own) { @($own.rules | Where-Object type -eq 'code_scanning') } else { @() }
    $codeql = [bool]$kept.Count
    # The query suite a configured default setup is switched from, when it isn't the extended one already. An answer
    # that names no suite is switched too, and the summary says the suite wasn't reported.
    $suite = $null
    if (-not $kept.Count) {
        $setup = Invoke-HostApi gh "repos/$Owner/$Name/code-scanning/default-setup"
        $codeql = $null
        if ($setup.Status -eq 200) {
            try {
                $answer = $setup.Body | ConvertFrom-Json -ErrorAction Stop
                $codeql = $answer.state -eq 'configured'
                if ($codeql -and $answer.query_suite -ne 'extended') {
                    $suite = if ("$($answer.query_suite)") { "the $($answer.query_suite) query suite" } else { 'a query suite it did not report' }
                }
            }
            catch { $codeql = $null }
        }
        elseif ($setup.Status -eq 404) { $codeql = $false }
        if ($null -eq $codeql) {
            $why = if ($null -eq $setup.Status) { 'no response' } elseif ($setup.Status -eq 200) { 'an answer that is not JSON' } else { "HTTP $($setup.Status)" }
            Write-Host "${Name}: skipped (couldn't read CodeQL's default setup: $why)"
            return
        }
    }

    $rules = @(
        @{ type = 'deletion' },
        @{ type = 'non_fast_forward' },
        @{ type = 'pull_request'; parameters = @{
            allowed_merge_methods = @('merge', 'rebase')
            dismiss_stale_reviews_on_push = $false
            require_code_owner_review = $false
            require_last_push_approval = $false
            required_approving_review_count = 0
            required_review_thread_resolution = $true
        } }
    )
    if ($kept.Count) { $rules += $kept[0] }
    elseif ($codeql) {
        $rules += @{ type = 'code_scanning'; parameters = @{
            code_scanning_tools = @(@{ tool = 'CodeQL'; alerts_threshold = 'errors_and_warnings'; security_alerts_threshold = 'all' })
        } }
    }
    if ($checks.Count) {
        # Strict: the checks must have run on the branch as it would merge, so two pull requests that each pass can't
        # break the default branch together.
        $rules += @{ type = 'required_status_checks'; parameters = @{
            strict_required_status_checks_policy = $true
            do_not_enforce_on_create = $false
            required_status_checks = @($checks | ForEach-Object { @{ context = $_; integration_id = $actionsAppId } })
        } }
    }
    $body = @{
        name = $rulesetName
        target = 'branch'
        enforcement = 'active'
        conditions = @{ ref_name = @{ include = @('~DEFAULT_BRANCH'); exclude = @() } }
        bypass_actors = @()
        rules = $rules
    } | ConvertTo-Json -Depth 10

    $verb = if ($own) { 'update' } else { 'create' }
    $summary = "$Name ($branch): $verb '$rulesetName' with $($checks.Count) required check(s)$(if ($checks.Count) { ': ' + ($checks -join ', ') })$(if ($kept.Count) { ', and keeps its code-scanning rule' } elseif ($codeql) { ', and a code-scanning rule' } else { ', and no code-scanning rule (CodeQL''s default setup is not configured)' })$(if ($suite) { "; switch CodeQL from $suite to extended" })"
    if (-not $PSCmdlet.ShouldProcess($Name, "$verb ruleset and delete-branch-on-merge")) {
        Write-Host "would: $summary"
        if ($autoChecks) {
            # Quoted for PowerShell: inside a single-quoted string every single-quote character, the curly ones too, is
            # doubled. A name with a comma can't be named: -RequireChecks splits it in two.
            $quote = { param($text) "'$([Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($text))'" }
            $named = @($checks | Where-Object { $_ -notlike '*,*' })
            if ($named.Count) { Write-Host "  to require them by name: & $(& $quote $PSCommandPath) -Repo $(& $quote $Name) -Owner $(& $quote $Owner) -RequireChecks $(& $quote ($named -join ','))" }
            $unnamed = @($checks | Where-Object { $_ -like '*,*' })
            if ($unnamed.Count) { Write-Host "  left out of that command, since -RequireChecks splits a name at its comma: $($unnamed -join '; ')" }
        }
        return
    }

    # The suite switch comes first: once the ruleset has its code-scanning rule, a later run no longer reads the default
    # setup, so a switch that failed after it could never be retried.
    if ($suite) {
        & gh api -X PATCH "repos/$Owner/$Name/code-scanning/default-setup" -f query_suite=extended | Out-Null
        if ($LASTEXITCODE) { throw "Couldn't switch CodeQL's default setup to the extended query suite for $Name; its ruleset and delete-branch-on-merge were left as they were, so run it again." }
    }

    # gh reads the body from a file: piping JSON into a function loses stdin.
    $file = New-TemporaryFile
    try {
        Set-Content -LiteralPath $file -Value $body -Encoding utf8
        if ($own) { & gh api -X PUT "repos/$Owner/$Name/rulesets/$($own.id)" --input $file | Out-Null }
        else { & gh api -X POST "repos/$Owner/$Name/rulesets" --input $file | Out-Null }
        if ($LASTEXITCODE) { throw "Couldn't $verb the ruleset on $Name." }
    } finally { Remove-Item -LiteralPath $file -Force }
    & gh api -X PATCH "repos/$Owner/$Name" -F delete_branch_on_merge=true | Out-Null
    if ($LASTEXITCODE) { throw "Couldn't turn on delete-branch-on-merge for $Name." }
    Write-Host "done: $summary"
}

foreach ($name in Get-Targets) {
    try { Set-Baseline $name } catch { Write-Host "${name}: FAILED: $($_.Exception.Message)" -ForegroundColor Red }
}
