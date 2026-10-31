<#
.SYNOPSIS
    Gives an NCodeGroup repository the baseline branch protection, so nothing reaches the default branch except through a
    pull request.

.DESCRIPTION
    For each repository it:
      - adds a "Protect main" ruleset on the default branch, the same shape as project-template's: no deletion, no force
        push, a pull request required (no approvals, since the organization has one maintainer), merge-commit or rebase
        merges only, never squash, so each commit of a plan stays on the branch, a code-scanning rule that blocks a
        pull request whose CodeQL results add an alert at error level or a security alert of medium severity or higher,
        and, when -RequireChecks names them, those CI jobs as required status checks;
      - turns on "delete branch on merge".

    A repository that already has an active ruleset requiring pull requests on its default branch is left alone, because
    its owner shaped that ruleset. An archived repository and a fork are skipped. A ruleset it made earlier is left
    alone too; pass -RequireChecks to update that one's required checks in place.

    Name only jobs that run on pull requests. A job that runs on a release or a schedule never reports on a pull
    request, so requiring it would block every merge.

    GitHub Free doesn't offer organization rulesets, so this applies one to each repository. New-Project.ps1 runs it for a
    repository it creates; Adopt-Project.ps1 prints the command to run.

.EXAMPLE
    .\tools\Set-RepositoryBaseline.ps1 -Repo Buffers -WhatIf     # shows what it would do
    .\tools\Set-RepositoryBaseline.ps1 -Repo Buffers -RequireChecks 'build-and-test,Commit attribution'
    .\tools\Set-RepositoryBaseline.ps1 -All -Owner NCodeGroup
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Owner', Justification = 'Get-Targets and Set-Baseline, nested functions, use it.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Repo,
    [switch]$All,
    # Names of the jobs a pull request must pass, as the checks list shows them, separated by commas (pwsh -File passes
    # one value for a parameter, so a list has to arrive as one string). Only with -Repo.
    [string[]]$RequireChecks = @(),
    # The owner of the repositories: an organization or a user.
    [Alias('Org')][string]$Owner = 'NCodeGroup'
)
$ErrorActionPreference = 'Stop'
if (-not $Repo -and -not $All) { throw 'Pass -Repo <name> or -All.' }
if ($Repo -and $All) { throw 'Pass -Repo or -All, not both.' }
$RequireChecks = @($RequireChecks | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($All -and $RequireChecks.Count) { throw '-RequireChecks needs -Repo: each repository names its own jobs.' }

$rulesetName = 'Protect main'
# GitHub Actions' app id: required checks are matched to the app that reports them.
$actionsAppId = 15368

function Invoke-GhJson([string[]]$GhArgs) {
    $out = & gh @GhArgs
    if ($LASTEXITCODE) { throw "gh $($GhArgs -join ' ') failed." }
    if ($out) { $out | ConvertFrom-Json } else { $null }
}

function Get-Targets {
    if ($Repo) { return @($Repo) }
    (Invoke-GhJson @('repo', 'list', $Owner, '--limit', '200', '--json', 'name,isArchived,isFork')) |
        Where-Object { -not $_.isArchived -and -not $_.isFork } | Sort-Object name | ForEach-Object { $_.name }
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

    $rules = @(
        @{ type = 'deletion' },
        @{ type = 'non_fast_forward' },
        @{ type = 'pull_request'; parameters = @{
            allowed_merge_methods = @('merge', 'rebase')
            dismiss_stale_reviews_on_push = $false
            require_code_owner_review = $false
            require_last_push_approval = $false
            required_approving_review_count = 0
            required_review_thread_resolution = $false
        } },
        # The organization's security configuration turns CodeQL on in every repository, so this rule always has results.
        @{ type = 'code_scanning'; parameters = @{
            code_scanning_tools = @(@{ tool = 'CodeQL'; alerts_threshold = 'errors'; security_alerts_threshold = 'medium_or_higher' })
        } }
    )
    if ($checks.Count) {
        $rules += @{ type = 'required_status_checks'; parameters = @{
            strict_required_status_checks_policy = $false
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
    $summary = "$Name ($branch): $verb '$rulesetName' with $($checks.Count) required check(s)$(if ($checks.Count) { ': ' + ($checks -join ', ') })"
    if (-not $PSCmdlet.ShouldProcess($Name, "$verb ruleset and delete-branch-on-merge")) { Write-Host "would: $summary"; return }

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
