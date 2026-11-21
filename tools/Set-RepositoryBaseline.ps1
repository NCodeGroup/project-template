<#
.SYNOPSIS
    Gives an NCodeGroup repository the baseline protection: nothing reaches the default branch except through a pull
    request, no release tag is moved or deleted, and the security settings a public project should have are on.

.DESCRIPTION
    For each repository it:
      - adds a "Protect main" ruleset on the default branch, the same shape as project-template's: no deletion, no force
        push, a pull request required (no approvals, since the organization has one maintainer, except where
        code-review.yml passes approve: true and a second person has write access, or NCode Review's approver is set up,
        as below) with every conversation
        resolved, with stale reviews dismissed on push, so a review finding from the bot, CodeQL or a person can't be
        merged past, merge-commit or rebase merges only, never squash, so each commit of a plan stays on the branch,
        when CodeQL's default setup is configured for the repository and analyzes at least one language a code-scanning
        rule that blocks a pull request whose CodeQL results add an alert at warning level or above or a security alert
        of any severity, and, when -RequireChecks names them, those CI jobs as required status checks, which must pass
        on a branch that is up to date with the default branch. A setup that GitHub reports as configured with no
        language, as an organization's security configuration can leave a new repository, runs CodeQL on no pull
        request, so the rule would block every merge: it counts as not configured, and the script says why and that a
        later run with -RequireChecks adds the rule once the repository's settings give CodeQL a language (the
        template's ADR-0030);
      - switches CodeQL's default setup, when it read it as configured with a language to analyze, to the extended query
        suite, before it writes the ruleset, so a switch that fails leaves the repository for the next run to retry. The
        switch sends the query suite alone and names no language, so it never runs on a setup that analyzes none;
      - turns on "delete branch on merge";
      - adds a "Protect release tags" ruleset on the tags matching v* (refs/tags/v*): no deletion and no update, so a
        tag is never moved, with no bypass. A release tag names one published package set, so it never changes;
      - turns on the security settings a public project should have, each where it is off: the workflow token
        (GITHUB_TOKEN) read-only by default, with GitHub Actions not allowed to create and approve pull requests, except
        where the default branch has .github/workflows/raise-baseline.yml, which opens a pull request; secret scanning
        and its push protection; Dependabot alerts and Dependabot security updates, which need the alerts; private
        vulnerability reporting; and immutable releases, except where a .yml or .yaml file in the default branch's
        .github/workflows runs on a release event or uploads release assets (gh release upload,
        actions/upload-release-asset, softprops/action-gh-release or uploadReleaseAsset), such as
        release-provenance.yml, since an immutable release refuses a file attached after it is published, or where a
        workflow can't be read; the line names the files;
      - turns on "Allow auto-merge" where it is off, so the template's code-review-auto-merge.yml workflow can turn on
        auto-merge for a Dependabot pull request that only moves the NCode Review pin. Allowing it merges nothing by
        itself: a pull request merges itself only once someone, or that workflow, turns it on, and still waits for what
        the ruleset requires and merges only as it allows;
      - for a public repository that has .github/workflows/code-review.yml or code-review-auto-merge.yml on its default
        branch, creates the Actions event policy "Allow pull_request_target for code review", which allows
        pull_request_target, issue_comment and every other event the two files' top-level on: keys name, for those two
        files alone, unless an active policy, of the repository or of its organization when this account may read those,
        already allows each of those events for them. A policy of that name is updated in place, keeping the other events it
        allows, when it isn't active, misses one of those events or doesn't cover both files, and left alone otherwise.
        An organization read that fails other than with HTTP 403 or 404 is named in the policy's line. GitHub's
        default policy blocks pull_request_target on a public repository without one from December 2, 2026.

    Where the default branch's .github/workflows/code-review.yml passes approve: true (NCode Review approves a clean
    review, ADR-0022), the "Protect main" ruleset it makes, and one an earlier run made, requires at least one
    approval, with approval of the last push. It never requires approval of the last push without an approval: GitHub
    then waits for an approval from someone other than the pusher, and it never lets an author approve their own pull
    request, so every merge stays blocked where one maintainer authors every pull request (the template's ADR-0031). A
    "Protect main" ruleset that has it on with no approval required, as one made by hand or by an older version of this
    script can, gets it turned off, and the run says so. A file it can't read is named, and the ruleset then requires no
    approval.

    Where NCode Review's approver is set up, meaning code-review.yml passes approve: true and a non-empty
    approver-private-key and the repository's code-review environment holds the secret
    NCODE_REVIEW_APPROVER_PRIVATE_KEY, the NCode Review Approver, an app that can write, submits the approval, so the
    ruleset requires one approval, of the last push, with one writer too (the template's ADR-0036). With the input but
    no secret the run says so and names the fix, and the ruleset gets no approval for it.

    Where one person has write access and the approver isn't set up, counted as the users the collaborators list
    (repos/<owner>/<name>/collaborators?affiliation=all&permission=push) gives, it requires no approval and no approval
    of the last push, also where code-review.yml passes approve: true, and a "Protect main" ruleset that requires an
    approval gets both turned off, and the run says so, also with -WhatIf: GitHub counts toward a required approval only
    a review from someone with write access, never the author's, and NCode Review's app has none, so either setting
    blocks every merge (the template's ADR-0034). Stale reviews are still dismissed on push. A collaborators list it
    can't read is named; the ruleset then gets no approval it doesn't have, and keeps the ones it has. A ruleset of the
    owner's that requires an approval there keeps its shape, and the run prints a notice with the command that requires
    no approval and no approval of the last push in it; where GitHub refuses the change to "Protect main", the notice
    says so and gives the same command. For a public repository with one writer, the run ends with a notice naming
    tools/Dismiss-ScorecardAlerts.ps1, which dismisses the Scorecard alerts one person can't clear (the template's
    ADR-0035).

    A repository that already has an active ruleset requiring pull requests on its default branch keeps it, because its
    owner shaped that ruleset. It still turns on "require conversation resolution" in each such ruleset, and in a "Protect
    main" ruleset an older version of this script made, when it is off, sending only the ruleset's rules with those
    parameters changed, so no pull request merges past an unresolved discussion (in the "Protect main" ruleset it also
    turns on dismissing stale reviews on push and, where code-review.yml passes approve: true, requires at least one
    approval, of the last push, and turns off approval of the last push where no approval is required); -WhatIf shows
    it, and a refusal is reported without failing the run. A ruleset of the owner's that requires approval of the last
    push but no approving review blocks every merge where only the author can approve: the script changes no ruleset
    but its own, so it prints a notice with the command that turns that off, which -All -WhatIf lists for every
    repository. A ruleset it made earlier is kept too; pass -RequireChecks to update that one's required checks
    in place. Either way the repository still gets the tag ruleset and the security settings, so a second run
    brings a repository protected by an older version of this script up to date. A ruleset named "Protect release tags",
    whatever its state, is left alone, and so is an active tag ruleset on v* tags that already refuses both deletion and
    update. An archived repository and a fork are skipped, and so is a repository whose default branch it skips with a
    reason (CodeQL's default setup can't be read, or -RequireChecks auto finds nothing to require): it changes nothing
    there. A "Protect main" ruleset that already has a code-scanning rule, such as one an older version of this script
    made, keeps that rule and its alert thresholds, and its repository's CodeQL suite is never switched: the script
    reads the default setup and, when it runs a suite other than extended, prints a notice with the command that
    switches it by hand, which can start blocking merges on new alerts. When the setup is configured but analyzes no
    language and the rule requires CodeQL, it warns instead that every pull request stays blocked, since the rule waits
    for CodeQL results that never come, and names the fix: set up CodeQL's languages in the repository's settings, or
    remove the rule, which the script never removes. It does both also when the ruleset sits beside one of the owner's.
    A setup it can't read is reported, and the run goes on.

    Each security setting, and auto-merge, is read first and printed as set, already set, would set (-WhatIf) or not
    available, with the reason, and none costs money. Secret scanning and its push protection are left out of a
    repository that isn't public, where they need the paid GitHub Secret Protection. A setting the API won't read or
    refuses to change, such as private vulnerability reporting on a private repository or a token setting the
    organization decides, is reported, and the run goes on with the next one. Requiring actions pinned to a full-length
    commit SHA is left out: it fails every workflow that names an action by tag, and an adopted repository's workflows
    may.

    Name only jobs that run on pull requests. A job that runs on a release or a schedule never reports on a pull
    request, so requiring it would block every merge.

    -RequireChecks auto names them for you, for each repository: it reads the check runs on the head commit of the latest
    pull request merged into the default branch and requires the GitHub Actions jobs that a pull_request event ran there
    and that passed (a job that ran more than once counts by its latest run). It leaves out, and lists with the reason,
    the review bot's advisory "Code review" and its pull_request_target job (the template's ADR-0019), CodeQL (the code-scanning rule covers it)
    and its Analyze jobs, a check another app reports, and any job that was skipped, neutral, failed or didn't finish,
    since a skipped required check counts as passing. A repository with no merged pull request, or none of whose checks
    qualify, is skipped with the reason and nothing changed. With -WhatIf it lists the checks and prints the command
    that names them, to edit and run; a job whose name has a comma is listed apart, since -RequireChecks would split it.
    The list comes from one pull request: a job whose workflow has paths or branches filters reports nothing on a pull
    request the filters skip, and that pull request can't merge, so run -WhatIf first and leave such jobs out.

    GitHub Free doesn't offer organization rulesets, so this applies them to each repository. New-Project.ps1 runs it
    for a repository it creates; Adopt-Project.ps1 prints the command to run.

    -SkipImmutableReleases leaves immutable releases off in every repository it runs on, and says so; one already on
    stays on, since the script never loosens a setting. Where they are already on and a workflow runs on a release
    event or uploads release assets, it prints a notice with the command that turns them off.

    -OrganizationPolicy, with -Owner alone, creates the same policy once for the organization, on every repository
    (~ALL), and touches no repository: run it as an organization owner, with a token that has the admin:org scope (gh
    auth refresh -h github.com -s admin:org). It reads the organization's policies first and updates one of that
    name in place, keeping the other events it allows, when it isn't active, misses one of those events or doesn't cover both files on every repository, and leaves alone one that does, or an active one that already allows pull_request_target and issue_comment for both files on every repository; -WhatIf prints the body it
    would post. It exits 1 when it can't read the policies or the API refuses the policy.
    It needs GitHub Team or above, the plans GitHub offers organization event policies on: when GitHub refuses them for
    the organization's plan, with an answer that asks to upgrade, such as "Upgrade to GitHub Team to enable this
    feature.", it says so and to run it for each repository instead, with -Repo <name> or -All.

    For a repository an organization owns, it also reports the organization's two-factor requirement, as
    "organization two-factor requirement: required", "not required" or "not available" with the reason (GitHub shows
    the field to an owner only). It reports and never sets it, -WhatIf prints the same, and a failed read never fails
    the run. require_2FA and secure_2FA in docs/best-practices-criteria.md stay Unmet until an owner confirms it.

.EXAMPLE
    .\tools\Set-RepositoryBaseline.ps1 -Repo Buffers -WhatIf     # shows what it would do, and each setting's state
    .\tools\Set-RepositoryBaseline.ps1 -Repo Buffers -RequireChecks 'build-and-test'
    .\tools\Set-RepositoryBaseline.ps1 -Repo Buffers -RequireChecks auto -WhatIf   # lists the checks it would require
    .\tools\Set-RepositoryBaseline.ps1 -All -Owner NCodeGroup
    .\tools\Set-RepositoryBaseline.ps1 -Repo brand -SkipImmutableReleases   # leaves releases mutable
    .\tools\Set-RepositoryBaseline.ps1 -OrganizationPolicy -Owner NCodeGroup -WhatIf   # prints the organization's policy it would create
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
    # Creates the organization's Actions event policy for the code-review workflows of every repository, instead of each
    # repository's own. Only with -Owner; an organization owner runs it, with the admin:org scope, on GitHub Team or above.
    [switch]$OrganizationPolicy,
    # Leaves immutable releases off in each repository, for one whose releases get files after they are published.
    [switch]$SkipImmutableReleases,
    # The owner of the repositories: an organization or a user.
    [Alias('Org')][string]$Owner = 'NCodeGroup'
)
$ErrorActionPreference = 'Stop'
if ($OrganizationPolicy -and ($Repo -or $All -or $RequireChecks.Count -or $SkipImmutableReleases)) { throw '-OrganizationPolicy sets the organization''s policy alone: pass it with -Owner only.' }
if (-not $Repo -and -not $All -and -not $OrganizationPolicy) { throw 'Pass -Repo <name> or -All, or -OrganizationPolicy.' }
if ($Repo -and $All) { throw 'Pass -Repo or -All, not both.' }
$RequireChecks = @($RequireChecks | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$autoChecks = $RequireChecks -contains 'auto'
if ($autoChecks -and $RequireChecks.Count -gt 1) { throw "-RequireChecks auto reads the checks itself: pass auto alone, or name the jobs." }
if ($All -and $RequireChecks.Count -and -not $autoChecks) { throw '-RequireChecks needs -Repo: each repository names its own jobs (or pass -RequireChecks auto).' }

$rulesetName = 'Protect main'
$tagRulesetName = 'Protect release tags'
# Why the script turns off approval of the last push where no approval is required (ADR-0031).
$lastPushWhy = 'which blocks every merge while no approval is required'
# Why the script requires no approval where one person can write (ADR-0034).
$soleWhy = 'which block every merge while one person has write access'
# GitHub Actions' app id: required checks are matched to the app that reports them.
$actionsAppId = 15368
# -RequireChecks auto never requires these checks, whatever app reported them or event ran them: each name pattern
# (matched with -like) maps to the reason it lists. CodeQL's Analyze jobs go by name too: a repository's own CodeQL
# workflow runs them on pull_request.
$excludedChecks = [ordered]@{
    'Code review' = "advice the person who merges waits for, as the template's ADR-0019 records"
    'CodeQL' = 'the code-scanning rule covers it'
    'Analyze (*)' = 'the code-scanning rule covers it'
}
# The Actions event policy that lets the template's code-review workflows start on pull_request_target (Set-EventPolicy).
# An event rule allows only the events it lists, for the workflows it targets: these two files and the events they use.
$eventPolicyName = 'Allow pull_request_target for code review'
$eventPolicyLabel = 'allow pull_request_target for the code-review workflows'
$codeReviewWorkflows = @('.github/workflows/code-review.yml', '.github/workflows/code-review-auto-merge.yml')
$codeReviewEvents = @('pull_request_target', 'issue_comment')

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

# Changes something through gh's API and returns the HTTP status and the body, read as Invoke-HostApi reads them, so a
# refusal says why. $Body, when there is one, goes in as JSON from a file: piping JSON into a function loses stdin.
function Invoke-HostWrite([string]$Method, [string]$Path, [hashtable]$Body) {
    $file = $null
    $inputArgs = @()
    if ($Body) {
        $file = New-TemporaryFile
        Set-Content -LiteralPath $file -Value ($Body | ConvertTo-Json -Depth 10) -Encoding utf8
        $inputArgs = @('--input', $file.FullName)
    }
    try { $lines = @(& gh api -X $Method --include $Path @inputArgs 2>$null) }
    finally { if ($file) { Remove-Item -LiteralPath $file -Force } }
    $status = $null
    if ($lines.Count -and $lines[0] -match '^HTTP/\S+\s+(\d{3})\b') { $status = [int]$Matches[1] }
    $blank = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if (-not $lines[$i].Trim()) { $blank = $i; break } }
    $text = if ($blank -ge 0 -and $blank -lt $lines.Count - 1) { $lines[($blank + 1)..($lines.Count - 1)] -join "`n" } else { '' }
    [pscustomobject]@{ Status = $status; Body = $text }
}

# Why a call failed, for the line that reports it: the status and, when the answer has one, the API's message.
function Get-FailureReason($Response) {
    if ($null -eq $Response.Status) { return 'no response' }
    $message = try { "$(($Response.Body | ConvertFrom-Json -ErrorAction Stop).message)" } catch { '' }
    "HTTP $($Response.Status)$(if ($message) { ": $message" })"
}

# What a read of a security setting says: $true when it is on, $false when it is off, or, as a string, why it can't be
# told. $IsOn reads a 200 answer; $On and $Off list the other statuses that answer, such as Dependabot's 204 and 404.
function Get-SettingState($Response, [scriptblock]$IsOn, [int[]]$On = @(), [int[]]$Off = @()) {
    if ($null -ne $Response.Status -and $Response.Status -in $On) { return $true }
    if ($null -ne $Response.Status -and $Response.Status -in $Off) { return $false }
    if ($Response.Status -eq 200) {
        try { return [bool](& $IsOn ($Response.Body | ConvertFrom-Json -ErrorAction Stop)) }
        catch { return "couldn't read it: an answer that is not JSON" }
    }
    "couldn't read it: $(Get-FailureReason $Response)"
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

# Reads the default branch's .github/workflows/code-review.yml to see whether NCode Review approves: its job passes
# approve: true (ADR-0022). Approver is $true then; Why says why the file couldn't be read, and is $null when it was
# read or isn't there (404), so a repository without the workflow just gets no approval requirement. ApproverApp is
# $true when the file also passes approver-private-key and the repository's code-review environment holds the
# NCODE_REVIEW_APPROVER_PRIVATE_KEY secret, so the NCode Review Approver, which can write, submits the approval and
# GitHub counts it (ADR-0036); ApproverWhy says why it isn't, and is $null otherwise.
function Read-ReviewApproval([string]$Name, [string]$Branch) {
    $read = Invoke-HostApi gh "repos/$Owner/$Name/contents/.github/workflows/code-review.yml?ref=$Branch"
    if ($read.Status -eq 404) { return [pscustomobject]@{ Approver = $false; Why = $null; ApproverApp = $false; ApproverWhy = $null } }
    if ($read.Status -ne 200) { return [pscustomobject]@{ Approver = $false; Why = Get-FailureReason $read; ApproverApp = $false; ApproverWhy = $null } }
    $text = Get-ContentText $read.Body
    if ($null -eq $text) { return [pscustomobject]@{ Approver = $false; Why = 'the contents API sent no base64 UTF-8 text'; ApproverApp = $false; ApproverWhy = $null } }
    $approver = $text -match '(?m)^\s+approve:\s*["'']?true["'']?\s*(#.*)?$'
    $app = $false
    $appWhy = $null
    if ($approver -and $text -match '(?m)^\s+approver-private-key:\s*\S') {
        $secret = Invoke-HostApi gh "repos/$Owner/$Name/environments/code-review/secrets/NCODE_REVIEW_APPROVER_PRIVATE_KEY"
        if ($secret.Status -eq 200) { $app = $true }
        elseif ($secret.Status -eq 404) { $appWhy = 'its code-review environment has no NCODE_REVIEW_APPROVER_PRIVATE_KEY: run tools/Enable-CodeReview.ps1 -ApproverPrivateKeyPath from NCodeGroup/code-review' }
        else { $appWhy = Get-FailureReason $secret }
    }
    [pscustomobject]@{ Approver = $approver; Why = $null; ApproverApp = $app; ApproverWhy = $appWhy }
}

# Counts the users the collaborators list gives with push access or more. GitHub counts toward a required approval only
# a review from someone with write access, never the author's (ADR-0034). Count is $null and Why the reason when the
# list can't be read.
function Read-Writers([string]$Name) {
    $read = Invoke-HostApi gh "repos/$Owner/$Name/collaborators?affiliation=all&permission=push&per_page=100"
    $answer = $null
    if ($read.Status -eq 200) {
        try { $answer = @($read.Body | ConvertFrom-Json -ErrorAction Stop) } catch { $answer = $null }
    }
    if ($null -eq $answer) {
        [pscustomobject]@{ Count = $null; Why = if ($read.Status -eq 200) { 'an answer that is not JSON' } else { Get-FailureReason $read } }
    }
    else { [pscustomobject]@{ Count = @($answer | Where-Object { $_.type -eq 'User' }).Count; Why = $null } }
}

function Set-Baseline([string]$Name) {
    $info = Invoke-GhJson @('api', "repos/$Owner/$Name")
    if ($info.archived -or $info.fork) { Write-Host "${Name}: skipped (archived or fork)"; return }
    $rulesets = @(foreach ($summary in @(Invoke-GhJson @('api', "repos/$Owner/$Name/rulesets"))) {
        Invoke-GhJson @('api', "repos/$Owner/$Name/rulesets/$($summary.id)")
    })
    $review = Read-ReviewApproval $Name $info.default_branch
    if ($review.Why) { Write-Host "${Name}: couldn't read .github/workflows/code-review.yml to see whether NCode Review approves ($($review.Why)); the ruleset requires no approval" }
    $writers = Read-Writers $Name
    if ($writers.Why) { Write-Host "${Name}: couldn't read who has write access ($($writers.Why)); the ruleset gets no approval it doesn't have, and keeps the approvals it has" }
    $soleWriter = $null -ne $writers.Count -and $writers.Count -le 1
    $approver = [bool]($review.Approver -and ($review.ApproverApp -or ($null -ne $writers.Count -and $writers.Count -ge 2)))
    if ($review.ApproverWhy) {
        Write-Host "${Name}: code-review.yml passes approver-private-key, but $($review.ApproverWhy); the approver can't approve, so the ruleset gets no approval for it"
    }
    if ($review.ApproverApp) {
        Write-Host "${Name}: NCode Review approves as the NCode Review Approver, which can write, so the ruleset requires one approval, of the last push (the template's ADR-0036)"
    }
    if ($review.Approver -and $soleWriter -and -not $review.ApproverApp) {
        Write-Host "${Name}: code-review.yml passes approve: true, but one person has write access, and GitHub counts toward a required approval neither the author's approval nor NCode Review's, whose app has no write access: the ruleset requires no approval and no approval of the last push (the template's ADR-0034 and ADR-0036)"
    }
    # A repository skipped for its default branch gets nothing else either: the reason printed says what to fix first.
    if (-not (Set-BranchRuleset $Name $info.default_branch $rulesets -Approver $approver -SoleWriter ($soleWriter -and -not $review.ApproverApp))) { return }
    Set-TagRuleset $Name $rulesets
    Set-SecuritySettings $Name $info
    Set-AutoMerge $Name $info
    Set-EventPolicy $Name $info
    Write-OrganizationTwoFactor $Name $info
    if ($soleWriter) { Write-ScorecardNotice $Name $info }
}

# Reports whether the organization that owns the repository requires two-factor authentication of its members. It only
# reads: the setting is the organization's, an owner changes it, and -WhatIf prints the same. GitHub shows the field to
# an owner only, so an answer without it, or a refused read, is reported as not available and never fails the run. A
# repository a user owns has no organization, and gets no line.
function Write-OrganizationTwoFactor([string]$Name, $Info) {
    if ("$($Info.owner.type)" -ne 'Organization') { return }
    $read = Invoke-HostApi gh "orgs/$Owner"
    $label = 'organization two-factor requirement'
    if ($read.Status -ne 200) { Write-Host "${Name}: ${label}: not available ($(Get-FailureReason $read))"; return }
    $answer = try { $read.Body | ConvertFrom-Json -ErrorAction Stop } catch { $null }
    if ($null -eq $answer) { Write-Host "${Name}: ${label}: not available (an answer that is not JSON)"; return }
    if ($null -eq $answer.two_factor_requirement_enabled) { Write-Host "${Name}: ${label}: not available (the answer doesn't include it; GitHub shows it to an owner only)"; return }
    Write-Host "${Name}: ${label}: $(if ($answer.two_factor_requirement_enabled) { 'required' } else { 'not required' })"
}

# With one writer, Scorecard's Branch-Protection, CII-Best-Practices and Contributors checks stay below 10 and their
# code scanning alerts stay open (ADR-0035). A private repository publishes no Scorecard result, so it gets no notice.
function Write-ScorecardNotice([string]$Name, $Info) {
    if ($Info.private) { return }
    $helper = Join-Path $PSScriptRoot 'Dismiss-ScorecardAlerts.ps1'
    Write-Host "${Name}: notice: one person has write access, so Scorecard's Branch-Protection, CII-Best-Practices and Contributors checks stay below 10 and their code scanning alerts stay open (the template's ADR-0035). To dismiss them as won't fix with the standard reason, run: & '$helper' -Repo '$Owner/$Name' -WhatIf, then again without -WhatIf"
}

# Reads CodeQL's default setup. Status is the HTTP status, or $null for no response; Answer the parsed answer, or $null;
# Why the reason it couldn't be read, or $null when it was read or not found (404).
function Read-DefaultSetup([string]$Name) {
    $setup = Invoke-HostApi gh "repos/$Owner/$Name/code-scanning/default-setup"
    $answer = $null
    if ($setup.Status -eq 200) { try { $answer = $setup.Body | ConvertFrom-Json -ErrorAction Stop } catch { $answer = $null } }
    $why = if ($answer -or $setup.Status -eq 404) { $null } elseif ($null -eq $setup.Status) { 'no response' } elseif ($setup.Status -eq 200) { 'an answer that is not JSON' } else { "HTTP $($setup.Status)" }
    [pscustomobject]@{ Status = $setup.Status; Answer = $answer; Why = $why }
}

# The query suite a configured default setup runs, worded for the notice and the summary, or $null when it runs the
# extended one or isn't configured.
function Get-SuiteText($Answer) {
    if ($Answer.state -ne 'configured' -or $Answer.query_suite -eq 'extended') { return $null }
    if ("$($Answer.query_suite)") { "the $($Answer.query_suite) query suite" } else { 'a query suite it did not report' }
}

# The languages a default setup analyzes, as its answer's languages lists them: none when that list is empty or missing.
# GitHub can report a setup as configured with none: NCodeGroup/docs and NCodeGroup/brand answered state configured,
# languages [], no schedule and no updated_at on 2026-11-16, their organization's enforced security configuration having
# turned default setup on, and no CodeQL setup having run on either since its creation. CodeQL then runs on no pull
# request, so a code-scanning rule waits for results that never come and blocks every merge (ADR-0030).
function Get-SetupLanguages($Answer) {
    @($Answer.languages | ForEach-Object { "$_" } | Where-Object { $_ })
}

# A "Protect main" ruleset that already has a code-scanning rule keeps it and its thresholds. Its repository's default
# setup is never switched (the extended suite can raise new alerts the rule would block merges on), so this only reads
# the setup and prints a notice; it changes nothing. A setup that is configured but analyzes no language gets a warning
# instead, where the rule requires CodeQL, since the rule then blocks every merge: an update never removes the rule, so
# the warning names the fixes. A rule that names only other tools waits for none of CodeQL's results, and a suite
# switch would set up no language, so such a setup gets neither. A setup that isn't configured gets neither too: CodeQL
# can run through the repository's own workflow (advanced setup), and default setup then reads as not configured.
function Write-CodeScanningNotice([string]$Name, $Ruleset) {
    $setup = Read-DefaultSetup $Name
    if ($setup.Status -eq 404) { return }
    if ($setup.Why) {
        Write-Host "${Name}: couldn't read CodeQL's default setup to check its languages and query suite ($($setup.Why)); its ruleset's code-scanning rule is kept as it is"
        return
    }
    if ($setup.Answer.state -eq 'configured' -and -not @(Get-SetupLanguages $setup.Answer).Count) {
        $tools = @($Ruleset.rules | Where-Object type -eq 'code_scanning' | ForEach-Object { $_.parameters.code_scanning_tools } | ForEach-Object { "$($_.tool)" })
        if ($tools -contains 'CodeQL') {
            Write-Host "${Name}: warning: CodeQL's default setup is configured but analyzes no language, so CodeQL runs on no pull request and the code-scanning rule in '$rulesetName' waits for its results forever: every pull request stays blocked. Set up CodeQL's languages in the repository's settings (Settings > Advanced Security > CodeQL analysis), or remove the code-scanning rule from '$rulesetName'; this script never removes it."
        }
        return
    }
    $suite = Get-SuiteText $setup.Answer
    if (-not $suite) { return }
    Write-Host "${Name}: notice: CodeQL's default setup runs $suite, not the extended one the baseline uses, and this script doesn't switch a repository whose ruleset already has a code-scanning rule. To switch it by hand: gh api -X PATCH repos/$Owner/$Name/code-scanning/default-setup -f query_suite=extended. The extended suite can raise new alerts, and the ruleset's code-scanning rule may then block merges on them."
}

# The default branch's ruleset, the suite switch and delete-branch-on-merge. Returns $false when it skips the
# repository, which then changes nothing, and $true otherwise: done, shown by -WhatIf, or left alone.
function Set-BranchRuleset {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Name, [string]$Branch, [object[]]$Rulesets, [bool]$Approver = $false, [bool]$SoleWriter = $false)
    $own = $null
    $others = @()
    foreach ($full in $Rulesets) {
        if ($full.target -ne 'branch' -or $full.enforcement -ne 'active') { continue }
        $onDefault = $full.conditions.ref_name.include -contains '~DEFAULT_BRANCH' -or $full.conditions.ref_name.include -contains "refs/heads/$Branch"
        if (-not $onDefault) { continue }
        if ($full.name -eq $rulesetName) { $own = $full; continue }
        if ($full.rules.type -contains 'pull_request') { $others += $full }
    }
    if ($others.Count) {
        foreach ($full in $others) { Write-Host "${Name}: left alone ('$($full.name)' already requires pull requests)"; Enable-ThreadResolution $Name $full; if ($SoleWriter) { Write-SoleWriterNotice $Name $full } }
        if ($own) {
            Enable-ThreadResolution $Name $own -Strict -Approver:$Approver -SoleWriter:$SoleWriter
            if ($own.rules.type -contains 'code_scanning') { Write-CodeScanningNotice $Name $own }
        }
        return $true
    }

    # A ruleset of this name that exists already is changed only when -RequireChecks asks for new checks.
    if ($own -and -not $RequireChecks.Count) {
        Write-Host "${Name}: left alone (already has '$rulesetName')"
        Enable-ThreadResolution $Name $own -Strict -Approver:$Approver -SoleWriter:$SoleWriter
        if ($own.rules.type -contains 'code_scanning') { Write-CodeScanningNotice $Name $own }
        return $true
    }
    $checks = @($RequireChecks)
    if ($autoChecks) {
        $found = Get-PassingChecks $Name $Branch
        if (-not $found) { Write-Host "${Name}: skipped (-RequireChecks auto found no pull request merged into $Branch to read checks from; name the jobs with -RequireChecks)"; return $false }
        Write-Host "${Name}: pull request #$($found.Number) passed: $(if ($found.Checks.Count) { $found.Checks -join ', ' } else { 'nothing a ruleset can require' }); left out: $(if ($found.LeftOut.Count) { $found.LeftOut -join ', ' } else { 'nothing' })"
        if (-not $found.Checks.Count) { Write-Host "${Name}: skipped (no check that passed on pull request #$($found.Number) can be required; name the jobs with -RequireChecks)"; return $false }
        Write-Host "${Name}: these checks come from one pull request. A job whose workflow has paths or branches filters reports nothing on a pull request the filters skip, which then can't merge; leave such a job out by naming the rest with -RequireChecks"
        $checks = @($found.Checks)
    }

    # The code-scanning rule. A ruleset that has one keeps it as it is, whatever runs CodeQL (default setup or a
    # repository's own workflow): an update never removes it, and Write-CodeScanningNotice warns when the rule requires
    # CodeQL and the default setup is configured but analyzes no language. Otherwise CodeQL's default setup decides:
    # configured with a language to analyze adds the rule; an answer that says it isn't configured, one configured with
    # no language, or "not found" (HTTP 404), leaves it out, since every pull request would wait for CodeQL results that
    # never come. A lookup that fails for any other reason, such as a missing token scope or a 5xx, or an answer that
    # can't be read, says nothing, so the repository is skipped with the reason.
    $kept = if ($own) { @($own.rules | Where-Object type -eq 'code_scanning') } else { @() }
    $codeql = [bool]$kept.Count
    # The query suite a configured default setup is switched from, when it isn't the extended one already. An answer
    # that names no suite is switched too, and the summary says the suite wasn't reported. A setup with no language to
    # analyze is never switched: the switch names no language, so it would set none up.
    $suite = $null
    $languages = @()
    $languageless = $false
    if (-not $kept.Count) {
        $setup = Read-DefaultSetup $Name
        if ($setup.Why) { Write-Host "${Name}: skipped (couldn't read CodeQL's default setup: $($setup.Why))"; return $false }
        $configured = $setup.Status -ne 404 -and $setup.Answer.state -eq 'configured'
        $languages = @(Get-SetupLanguages $setup.Answer)
        $languageless = $configured -and -not $languages.Count
        $codeql = $configured -and [bool]$languages.Count
        if ($codeql) { $suite = Get-SuiteText $setup.Answer }
        if ($languageless) {
            Write-Host "${Name}: notice: CodeQL's default setup is configured but analyzes no language, so CodeQL would run on no pull request and a code-scanning rule would block every merge: the ruleset gets none, and the setup's query suite is left as it is, since switching it would set up no language. Set up CodeQL's languages in the repository's settings (Settings > Advanced Security > CodeQL analysis); a later run with -RequireChecks then adds the rule."
        }
    }
    else { Write-CodeScanningNotice $Name $own }

    # Approval of the last push is off while no approval is required, also in a ruleset an update finds with it on: GitHub
    # then wants an approval from someone other than the pusher, and never lets an author approve their own pull request,
    # so every merge is blocked where one maintainer authors every pull request (#385; ADR-0031, which amends ADR-0022).
    # An update keeps the approval count and code-owner review of the ruleset it made, and the last-push approval of one
    # that requires approvals. Where code-review.yml passes approve: true, one approval is required, and then approval of
    # the last push too (ADR-0022). With one writer no approval is required (ADR-0034).
    $ownPull = if ($own) { @($own.rules | Where-Object type -eq 'pull_request')[0].parameters } else { $null }
    $approvals = if ($ownPull) { [int]$ownPull.required_approving_review_count } else { 0 }
    $approvals = [Math]::Max($approvals, [int]$Approver)
    $lowered = $SoleWriter -and $null -ne $ownPull -and [int]$ownPull.required_approving_review_count -ge 1
    if ($SoleWriter) { $approvals = 0 }
    $lastPush = $approvals -ge 1 -and ($ownPull.require_last_push_approval -eq $true -or $Approver)
    $lastPushOff = $ownPull.require_last_push_approval -eq $true -and -not $lastPush
    $rules = @(
        @{ type = 'deletion' },
        @{ type = 'non_fast_forward' },
        @{ type = 'pull_request'; parameters = @{
            allowed_merge_methods = @('merge', 'rebase')
            dismiss_stale_reviews_on_push = $true
            require_code_owner_review = $ownPull.require_code_owner_review -eq $true
            require_last_push_approval = $lastPush
            required_approving_review_count = $approvals
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
    $scanning = if ($kept.Count) { ', and keeps its code-scanning rule' }
    elseif ($codeql) { ", and a code-scanning rule (CodeQL's default setup analyzes $($languages -join ', '))" }
    elseif ($languageless) { ", and no code-scanning rule (CodeQL's default setup analyzes no language)" }
    else { ", and no code-scanning rule (CodeQL's default setup is not configured)" }
    $summary = "$Name ($Branch): $verb '$rulesetName' with $($checks.Count) required check(s)$(if ($checks.Count) { ': ' + ($checks -join ', ') })$scanning$(if ($Approver) { ', at least one required approval, as NCode Review approves' })$(if ($lowered) { ", and requires no approval and no approval of the last push, $soleWhy" } elseif ($lastPushOff) { ", and turns off approval of the last push, $lastPushWhy" })$(if ($suite) { "; switch CodeQL from $suite to extended" })"
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
        return $true
    }

    # The suite switch comes first: once the ruleset has its code-scanning rule, a later run reads the default setup only
    # for its notice and never switches it, so a switch that failed after it could never be retried. It sends query_suite
    # alone. GitHub's REST reference, "Update a code scanning default setup configuration" (read 2026-11-16), makes every
    # field optional and describes languages only as "CodeQL languages to be analyzed", without saying what an update
    # does to the languages it leaves out; the switch names none, so it sets none up. NCodeGroup/docs and
    # NCodeGroup/brand were configured with no language on the extended suite on 2026-11-16, which most likely came from
    # this switch, since their organization's security configuration sets no query suite. So it runs only where the
    # setup already analyzes a language ($suite is set only with $codeql).
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
    $true
}

# Prints the command that turns off approval of the last push in a ruleset of the owner's that has it on with no approving
# review required: GitHub then wants someone other than the pusher to approve the newest push, which blocks every merge
# where only the author can approve (#385). This script changes no ruleset but its own "Protect main", which it turns
# the setting off in (ADR-0031), so the maintainer runs the printed command. -Refused is for the script's own ruleset
# when GitHub refused the write that turns it off: the setting is still on, so the notice says so and prints the command.
function Write-LastPushNotice([string]$Name, $Ruleset, [switch]$Refused) {
    $rule = @($Ruleset.rules | Where-Object type -eq 'pull_request')[0]
    if (-not $Refused -and (-not $rule -or $rule.parameters.require_last_push_approval -ne $true -or [int]$rule.parameters.required_approving_review_count -ge 1)) { return }
    $path = "repos/$Owner/$Name/rulesets/$($Ruleset.id)"
    $command = "`$rs = gh api $path | ConvertFrom-Json; (`$rs.rules | Where-Object type -eq 'pull_request').parameters.require_last_push_approval = `$false; @{ rules = `$rs.rules } | ConvertTo-Json -Depth 20 | gh api -X PUT $path --input -"
    $why = if ($Refused) { "GitHub refused the change, so it is still on; untick it in the ruleset's settings, or run" }
    else { "This script changes no ruleset but its own '$rulesetName'; to turn it off, run" }
    Write-Host "${Name}: notice: '$($Ruleset.name)' requires approval of the last push but no approving review, which blocks every merge where nobody but the author can approve. ${why}: $command"
}

# Prints the command that sets no approval and no approval of the last push in a ruleset of the owner's that requires
# an approval where one person has write access: GitHub counts no approval from the author or from NCode Review, so it
# blocks every merge (ADR-0034). This script changes no ruleset but its own "Protect main". -Refused is for the script's
# own ruleset when GitHub refused the write that sets both: it still requires an approval, so the notice says so.
function Write-SoleWriterNotice([string]$Name, $Ruleset, [switch]$Refused) {
    $rule = @($Ruleset.rules | Where-Object type -eq 'pull_request')[0]
    if (-not $Refused -and (-not $rule -or [int]$rule.parameters.required_approving_review_count -lt 1)) { return }
    $path = "repos/$Owner/$Name/rulesets/$($Ruleset.id)"
    $command = "`$rs = gh api $path | ConvertFrom-Json; `$p = (`$rs.rules | Where-Object type -eq 'pull_request').parameters; `$p.required_approving_review_count = 0; `$p.require_last_push_approval = `$false; @{ rules = `$rs.rules } | ConvertTo-Json -Depth 20 | gh api -X PUT $path --input -"
    $why = if ($Refused) { "GitHub refused the change, so it still requires one; set both in the ruleset's settings, or run" }
    else { "This script changes no ruleset but its own '$rulesetName'; to require no approval and no approval of the last push in it, run" }
    Write-Host "${Name}: notice: '$($Ruleset.name)' requires an approval while one person has write access, and GitHub counts no approval from the author or from NCode Review, so it blocks every merge (the template's ADR-0034). ${why}: $command"
}

# Turns on "require conversations resolved" in a ruleset that already requires pull requests, and changes nothing else in
# it: its other rules and their parameters are sent back as they were read. A ruleset without a pull request rule, or
# with the setting on already, is left as it is. A refusal is reported, not thrown, like a security setting's. A pull
# request rule that came without parameters is reported and left as it is: writing it would mean inventing its other
# parameters. For the script's own ruleset (-Strict) it also turns on dismissing stale reviews on push, and turns off
# approval of the last push where no approval is required, which blocks every merge (#385, ADR-0031). With -Approver
# too (the project's review passes approve: true) it requires at least one approval, of the last push, as a new ruleset
# does, keeping a larger count; it never turns on approval of the last push without an approval. With -SoleWriter too
# (one person can write) it requires no approval and no approval of the last push, which block every merge (ADR-0034).
function Enable-ThreadResolution {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Name, $Ruleset, [switch]$Strict, [switch]$Approver, [switch]$SoleWriter)
    $rule = @($Ruleset.rules | Where-Object type -eq 'pull_request')[0]
    if (-not $rule) { return }
    $raise = $Strict -and $Approver
    $needThreads = $rule.parameters.required_review_thread_resolution -ne $true
    $needStale = $Strict -and $rule.parameters.dismiss_stale_reviews_on_push -ne $true
    $needApproval = $raise -and ([int]$rule.parameters.required_approving_review_count -lt 1 -or $rule.parameters.require_last_push_approval -ne $true)
    $needLastPushOff = $Strict -and -not $Approver -and $rule.parameters.require_last_push_approval -eq $true -and [int]$rule.parameters.required_approving_review_count -lt 1
    $needLower = $Strict -and $SoleWriter -and [int]$rule.parameters.required_approving_review_count -ge 1
    if (-not $needThreads -and -not $needStale -and -not $needApproval -and -not $needLastPushOff -and -not $needLower) { Write-LastPushNotice $Name $Ruleset; return }
    $label = "'$($Ruleset.name)': " + (@(if ($needThreads) { 'require every conversation resolved' }; if ($needStale) { 'dismiss stale reviews on push' }; if ($needApproval) { 'require at least one approval, of the last push' }; if ($needLastPushOff) { "turn off approval of the last push, $lastPushWhy" }; if ($needLower) { "require no approval and no approval of the last push, $soleWhy" }) -join ', and ')
    if ($null -eq $rule.parameters) { Write-Host "${Name}: ${label}: not set (its pull request rule came without parameters; turn it on in the ruleset's settings on GitHub)"; return }
    if ($needThreads) { $rule.parameters | Add-Member -NotePropertyName required_review_thread_resolution -NotePropertyValue $true -Force }
    if ($Strict) { $rule.parameters | Add-Member -NotePropertyName dismiss_stale_reviews_on_push -NotePropertyValue $true -Force }
    if ($needLastPushOff) { $rule.parameters | Add-Member -NotePropertyName require_last_push_approval -NotePropertyValue $false -Force }
    if ($needLower) {
        $rule.parameters | Add-Member -NotePropertyName required_approving_review_count -NotePropertyValue 0 -Force
        $rule.parameters | Add-Member -NotePropertyName require_last_push_approval -NotePropertyValue $false -Force
    }
    if ($raise) {
        $rule.parameters | Add-Member -NotePropertyName required_approving_review_count -NotePropertyValue ([Math]::Max([int]$rule.parameters.required_approving_review_count, 1)) -Force
        $rule.parameters | Add-Member -NotePropertyName require_last_push_approval -NotePropertyValue $true -Force
    }
    Write-LastPushNotice $Name $Ruleset
    if (-not $PSCmdlet.ShouldProcess($Name, "update $label")) { Write-Host "${Name}: ${label}: would set"; return }
    $result = Invoke-HostWrite PUT "repos/$Owner/$Name/rulesets/$($Ruleset.id)" @{ rules = @($Ruleset.rules) }
    if ($result.Status -ge 200 -and $result.Status -lt 300) { Write-Host "${Name}: ${label}: set" }
    else {
        Write-Host "${Name}: ${label}: not available ($(Get-FailureReason $result))"
        if ($needLastPushOff) { Write-LastPushNotice $Name $Ruleset -Refused }
        if ($needLower) { Write-SoleWriterNotice $Name $Ruleset -Refused }
    }
}

# The release tags' ruleset: no v* tag is deleted or updated (moved), by anyone, since a release tag names one published
# package set. Creating a tag stays open, so a release can still be tagged. A ruleset of this name is left alone whatever
# its state, since its owner may have shaped or turned it off, and so is an active tag ruleset on v* tags (or on every
# tag) that refuses both already.
function Set-TagRuleset {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Name, [object[]]$Rulesets)
    foreach ($full in $Rulesets) {
        if ($full.name -eq $tagRulesetName) { Write-Host "${Name}: left alone (already has '$tagRulesetName')"; return }
    }
    foreach ($full in $Rulesets) {
        if ($full.target -ne 'tag' -or $full.enforcement -ne 'active') { continue }
        $include = @($full.conditions.ref_name.include)
        if ($include -notcontains 'refs/tags/v*' -and $include -notcontains '~ALL') { continue }
        $types = @($full.rules.type)
        if ($types -contains 'deletion' -and $types -contains 'update') { Write-Host "${Name}: left alone ('$($full.name)' already refuses deleting and moving v* tags)"; return }
    }

    $body = @{
        name = $tagRulesetName
        target = 'tag'
        enforcement = 'active'
        conditions = @{ ref_name = @{ include = @('refs/tags/v*'); exclude = @() } }
        bypass_actors = @()
        rules = @(@{ type = 'deletion' }, @{ type = 'update' })
    }
    $summary = "${Name}: create '$tagRulesetName' on v* tags: no deletion, no update (a tag is never moved), no bypass"
    if (-not $PSCmdlet.ShouldProcess($Name, "create ruleset '$tagRulesetName'")) { Write-Host "would: $summary"; return }
    $result = Invoke-HostWrite POST "repos/$Owner/$Name/rulesets" $body
    if ($result.Status -lt 200 -or $result.Status -ge 300) { throw "Couldn't create the '$tagRulesetName' ruleset on ${Name}: $(Get-FailureReason $result)." }
    Write-Host "done: $summary"
}

# The text of a file as the contents API answers it: base64, with line breaks. $null when the answer isn't JSON, holds no
# base64 content, such as for a file over 1 MB, or isn't UTF-8 text.
function Get-ContentText([string]$Body) {
    try {
        $answer = $Body | ConvertFrom-Json -ErrorAction Stop
        if ($answer.encoding -ne 'base64' -or $null -eq $answer.content) { return $null }
        [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String(($answer.content -replace '\s', '')))
    }
    catch { $null }
}

# The events a workflow's top-level on: key names, in order: one event (on: push), a list in brackets, the keys or items
# indented below it, or - items at its own indent, with quotes, comments and blank lines allowed. A mapping in braces, or
# no on: key, gives none.
function Get-WorkflowEvents([string]$Text) {
    $lines = @($Text -split '\r?\n')
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^(on|"on"|''on''):(.*)$') { continue }
        $rest = ($Matches[2] -replace '(^|\s)#.*$', '').Trim()
        $names = if ($rest.StartsWith('[')) { $rest.Trim('[', ']') -split ',' }
        elseif ($rest.StartsWith('{')) { @() }
        elseif ($rest) { @($rest) }
        else {
            $indent = -1
            @(for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                $line = $lines[$j]
                if ($line -match '^\s*(#.*)?$') { continue }
                $null = $line -match '^(\s*)(.*)$'
                $lead = $Matches[1].Length
                $item = $Matches[2]
                # A line at column 0 ends the block, unless it is a - item of a sequence at the key's own indent.
                if (-not $lead -and -not ($indent -le 0 -and $item -match '^-(\s|$)')) { break }
                if ($indent -lt 0) { $indent = $lead }
                if ($lead -ne $indent) { continue }
                if ($item -match '^-\s*([^\s#]+)') { $Matches[1] }
                elseif ($item -match '^([^\s:#]+)\s*:') { $Matches[1] }
            })
        }
        return @($names | ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ -match '^[A-Za-z_]+$' })
    }
    @()
}

# Whether a workflow's text runs on a release event, or uploads release assets with gh, an upload action or the API
# on a line that isn't a comment.
function Test-ReleaseAssetWorkflow([string]$Text) {
    $code = $Text -replace '(?m)^\s*#.*$', ''
    [bool](((Get-WorkflowEvents $Text) -contains 'release') -or ($code -match 'gh\s+release\s+upload|upload-release-asset|uploadReleaseAsset|action-gh-release'))
}

# The workflow files of a repository's default branch that run on a release event or upload release assets, which an
# immutable release refuses once it is published. Why is the reason a folder or file couldn't be read, or $null.
function Find-ReleaseAssetWorkflows([string]$Name, [string]$Branch) {
    $list = Invoke-HostApi gh "repos/$Owner/$Name/contents/.github/workflows?ref=$Branch"
    if ($list.Status -eq 404) { return [pscustomobject]@{ Files = @(); Why = $null } }
    $items = $null
    if ($list.Status -eq 200) { try { $items = @($list.Body | ConvertFrom-Json -ErrorAction Stop) } catch { $items = $null } }
    if ($list.Status -ne 200 -or $null -eq $items) {
        $reason = if ($list.Status -eq 200) { 'an answer that is not JSON' } else { Get-FailureReason $list }
        return [pscustomobject]@{ Files = @(); Why = "couldn't read .github/workflows: $reason" }
    }
    $files = [Collections.Generic.List[string]]::new()
    foreach ($item in $items) {
        if ($item.type -ne 'file' -or $item.name -notmatch '\.ya?ml$') { continue }
        $read = Invoke-HostApi gh "repos/$Owner/$Name/contents/$($item.path)?ref=$Branch"
        if ($read.Status -ne 200) { return [pscustomobject]@{ Files = @(); Why = "couldn't read $($item.path): $(Get-FailureReason $read)" } }
        $text = Get-ContentText $read.Body
        if ($null -eq $text) { return [pscustomobject]@{ Files = @(); Why = "couldn't read $($item.path): the contents API sent no base64 UTF-8 text, such as for a file over 1 MB" } }
        if (Test-ReleaseAssetWorkflow $text) { $files.Add($item.path) }
    }
    [pscustomobject]@{ Files = @($files); Why = $null }
}

# Immutable releases already on refuse the files a workflow attaches after a release is published. This script never
# loosens a setting, so this only reads the workflows and prints a notice with the command that turns them off.
function Write-ImmutableReleaseNotice([string]$Name, [string]$Branch) {
    $found = Find-ReleaseAssetWorkflows $Name $Branch
    if ($found.Why) { Write-Host "${Name}: couldn't read the workflows to check them against its immutable releases ($($found.Why))"; return }
    if (-not $found.Files.Count) { return }
    Write-Host "${Name}: notice: immutable releases are on, but these workflows run on a release event or upload release assets, which an immutable release refuses once it is published: $($found.Files -join ', '). This script never loosens a setting; to turn them off, run: gh api -X DELETE repos/$Owner/$Name/immutable-releases"
}

# Reads the Actions policies at $Path (a repository's or an organization's). A repository's list is an object,
# { total_count, policies }, whose items leave out their conditions and rules, which a read by its id gives; a bare array
# is read too. Why is the reason a policy couldn't be read, or $null. Status is the HTTP status of the read that failed, or of the list when none did, and $null when a call got no response.
function Read-EventPolicies([string]$Path) {
    $list = Invoke-HostApi gh "${Path}?per_page=100"
    $answer = $null
    if ($list.Status -eq 200) { try { $answer = $list.Body | ConvertFrom-Json -NoEnumerate -ErrorAction Stop } catch { $answer = $null } }
    if ($list.Status -ne 200 -or $null -eq $answer) {
        $reason = if ($list.Status -eq 200) { 'an answer that is not JSON' } else { Get-FailureReason $list }
        return [pscustomobject]@{ Policies = @(); Why = "couldn't read its Actions policies: $reason"; Status = $list.Status }
    }
    $policies = [Collections.Generic.List[object]]::new()
    foreach ($item in @(if ($answer -is [array]) { $answer } else { $answer.policies })) {
        if ($null -eq $item) { continue }
        if ($null -eq $item.rules) {
            $one = Invoke-HostApi gh "$Path/$($item.id)"
            $full = $null
            if ($one.Status -eq 200) { try { $full = $one.Body | ConvertFrom-Json -ErrorAction Stop } catch { $full = $null } }
            if ($null -eq $full) {
                $reason = if ($one.Status -eq 200) { 'an answer that is not JSON' } else { Get-FailureReason $one }
                return [pscustomobject]@{ Policies = @(); Why = "couldn't read Actions policy $($item.id): $reason"; Status = $one.Status }
            }
            $item = $full
        }
        $policies.Add($item)
    }
    [pscustomobject]@{ Policies = @($policies); Why = $null; Status = $list.Status }
}

# Whether a policy's condition (repository_name or workflow_path) covers $Value: a missing condition covers everything,
# and ~ALL every repository.
function Test-ConditionCovers($Condition, [string]$Value) {
    if ($null -eq $Condition) { return $true }
    $include = @($Condition.include | Where-Object { $_ })
    $exclude = @($Condition.exclude | Where-Object { $_ })
    if ($Value -eq '~ALL') { return ($include -contains '~ALL' -and -not $exclude.Count) }
    [bool](@($include | Where-Object { $_ -eq '~ALL' -or $Value -like $_ }).Count -and -not @($exclude | Where-Object { $Value -like $_ }).Count)
}

# Whether an Actions policy is active and allows every event of $Events for each workflow file in $Paths and, when $Repo
# is set, for that repository. See Test-ConditionCovers for the conditions.
function Test-AllowsEvents($Policy, [string[]]$Paths, [string[]]$Events, [string]$Repo = '') {
    if ($Policy.enforcement -ne 'active') { return $false }
    $allowed = @($Policy.rules | Where-Object { $_.type -eq 'restrict_action_events' } | ForEach-Object { @($_.parameters.allowed_events) })
    if (-not $Events.Count -or @($Events | Where-Object { $allowed -notcontains $_ }).Count) { return $false }
    if ($Repo -and -not (Test-ConditionCovers $Policy.conditions.repository_name $Repo)) { return $false }
    foreach ($path in $Paths) {
        if (-not (Test-ConditionCovers $Policy.conditions.workflow_path $path)) { return $false }
    }
    $true
}

# The body of the event policy to create or update: the two code-review workflows, $Events, and with -Organization every
# repository.
function New-EventPolicyBody([string[]]$Events = $codeReviewEvents, [switch]$Organization) {
    $conditions = [ordered]@{ workflow_path = @{ include = $codeReviewWorkflows; exclude = @() } }
    if ($Organization) { $conditions.repository_name = @{ include = @('~ALL'); exclude = @() } }
    @{ name = $eventPolicyName; enforcement = 'active'; conditions = $conditions; rules = @(@{ type = 'restrict_action_events'; parameters = @{ allowed_events = $Events } }) }
}

# What keeps the baseline's own event policy from doing its job, one phrase per gap: not active, an event of $Events
# it doesn't allow, or a code-review workflow it doesn't cover. None when it does its job.
function Get-EventPolicyGaps($Policy, [string[]]$Events) {
    if ($Policy.enforcement -ne 'active') { "its enforcement is $($Policy.enforcement)" }
    $allowed = @($Policy.rules | Where-Object { $_.type -eq 'restrict_action_events' } | ForEach-Object { @($_.parameters.allowed_events) })
    $missing = @($Events | Where-Object { $allowed -notcontains $_ })
    if ($missing.Count) { "it doesn't allow $($missing -join ', ')" }
    $uncovered = @($codeReviewWorkflows | Where-Object { -not (Test-ConditionCovers $Policy.conditions.workflow_path $_) })
    if ($uncovered.Count) { "it doesn't cover $($uncovered -join ', ')" }
}

# Sets one security setting where Get-SettingState read it as off, and prints the outcome on one line. A refusal is
# reported, not thrown: each setting stands on its own, so the next one is still tried.
function Set-SecuritySetting {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Name, [string]$Label, $State, [string]$Method, [string]$Path, [hashtable]$Body)
    if ($State -is [string]) { Write-Host "${Name}: ${Label}: not available ($State)"; return }
    if ($State) { Write-Host "${Name}: ${Label}: already set"; return }
    if (-not $PSCmdlet.ShouldProcess($Name, "turn on $Label")) { Write-Host "${Name}: ${Label}: would set"; return }
    $result = Invoke-HostWrite $Method $Path $Body
    if ($result.Status -ge 200 -and $result.Status -lt 300) { Write-Host "${Name}: ${Label}: set" }
    else { Write-Host "${Name}: ${Label}: not available ($(Get-FailureReason $result))" }
}

# The security settings a public project should have, in an order where each one's prerequisite comes first: Dependabot
# security updates need Dependabot alerts. None costs money. Secret scanning and its push protection are free on a
# public repository only, so one that isn't public is left out with the reason, rather than spending a GitHub Secret
# Protection seat. The rest the API decides: a setting it won't read, or refuses to change, is reported as not
# available with its answer, such as private vulnerability reporting on a private repository, or a token setting its
# organization fixes (HTTP 409).
function Set-SecuritySettings([string]$Name, $Info) {
    $base = "repos/$Owner/$Name"
    # GitHub's "Allow GitHub Actions to create and approve pull requests" is one setting: it is on only where
    # raise-baseline.yml must open its pull request (the template's ADR-0150), and a read that fails leaves it off.
    $raiser = (Invoke-HostApi gh "$base/contents/.github/workflows/raise-baseline.yml?ref=$($Info.default_branch)").Status -eq 200
    $label = if ($raiser) { 'read-only workflow token, and Actions opening the baseline pull request' } else { 'read-only workflow token, and Actions not approving pull requests' }
    $state = Get-SettingState (Invoke-HostApi gh "$base/actions/permissions/workflow") { param($answer) $answer.default_workflow_permissions -eq 'read' -and [bool]$answer.can_approve_pull_request_reviews -eq $raiser }
    Set-SecuritySetting $Name $label $state PUT "$base/actions/permissions/workflow" @{ default_workflow_permissions = 'read'; can_approve_pull_request_reviews = $raiser }

    $features = [ordered]@{ secret_scanning = 'secret scanning'; secret_scanning_push_protection = 'secret scanning push protection' }
    foreach ($feature in $features.Keys) {
        $state = if ($Info.private) { "the repository isn't public, and one that isn't needs the paid GitHub Secret Protection for it" }
        else { "$($Info.security_and_analysis.$feature.status)" -eq 'enabled' }
        Set-SecuritySetting $Name $features[$feature] $state PATCH $base @{ security_and_analysis = @{ $feature = @{ status = 'enabled' } } }
    }

    $state = Get-SettingState (Invoke-HostApi gh "$base/vulnerability-alerts") { $true } -On 204 -Off 404
    Set-SecuritySetting $Name 'Dependabot alerts' $state PUT "$base/vulnerability-alerts"
    $state = Get-SettingState (Invoke-HostApi gh "$base/automated-security-fixes") { param($answer) $answer.enabled } -Off 404
    Set-SecuritySetting $Name 'Dependabot security updates' $state PUT "$base/automated-security-fixes"
    $state = Get-SettingState (Invoke-HostApi gh "$base/private-vulnerability-reporting") { param($answer) $answer.enabled }
    Set-SecuritySetting $Name 'private vulnerability reporting' $state PUT "$base/private-vulnerability-reporting"
    # Immutable releases: GitHub then signs an attestation of each release it publishes, which gh release verify checks
    # (the template's ADR-0028). release-provenance.yml attaches a library's packages to its release after it is
    # published, which an immutable release refuses, so such a repository is left as it is. So is one with a workflow
    # that runs on a release event or uploads release assets, or one the script can't read.
    $state = Get-SettingState (Invoke-HostApi gh "$base/immutable-releases") { param($answer) $answer.enabled }
    if ($SkipImmutableReleases -and $state -is [bool] -and -not $state) { $state = '-SkipImmutableReleases leaves them off' }
    if ($state -is [bool] -and -not $state) {
        # Only a 404 says the file is absent: any other answer leaves the setting as it is, and says why.
        $provenance = (Invoke-HostApi gh "$base/contents/.github/workflows/release-provenance.yml?ref=$($Info.default_branch)").Status
        if ($provenance -eq 200) { $state = 'release-provenance.yml attaches packages to a release after it is published, which an immutable release refuses' }
        elseif ($provenance -ne 404) { $state = "couldn't read .github/workflows/release-provenance.yml: $(if ($provenance) { "HTTP $provenance" } else { 'no response' })" }
    }
    if ($state -is [bool] -and -not $state) {
        $found = Find-ReleaseAssetWorkflows $Name $Info.default_branch
        if ($found.Why) { $state = $found.Why }
        elseif ($found.Files.Count) { $state = "these workflows run on a release event or upload release assets, which an immutable release refuses once it is published: $($found.Files -join ', ')" }
    }
    Set-SecuritySetting $Name 'immutable releases' $state PUT "$base/immutable-releases"
    if ($state -is [bool] -and $state) { Write-ImmutableReleaseNotice $Name $Info.default_branch }
}

# "Allow auto-merge", which the template's code-review-auto-merge.yml needs to have a Dependabot bump of NCode Review
# merge itself once the required checks pass. GitHub reports it with the repository only to someone who may change it,
# so an answer without it is reported, not written.
function Set-AutoMerge([string]$Name, $Info) {
    $state = if ($null -eq $Info.allow_auto_merge) { "couldn't read it: the repository's answer doesn't include it" } else { [bool]$Info.allow_auto_merge }
    Set-SecuritySetting $Name 'allow auto-merge' $state PATCH "repos/$Owner/$Name" @{ allow_auto_merge = $true }
}

# GitHub's default Actions policy blocks pull_request_target from December 2, 2026 on a public repository without an event
# policy allowing it. The two code-review workflows run from the default branch and check out nothing, so they keep the
# event; every other workflow keeps the default. Its own policy, by name, is updated in place when it isn't active, misses
# an event or doesn't cover both files. It allows pull_request_target, issue_comment and every other event the two files'
# top-level on: keys name.
function Set-EventPolicy {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Name, $Info)
    $prefix = "${Name}: ${eventPolicyLabel}: "
    if ($Info.private) {
        Write-Host "${prefix}not needed (the repository isn't public, and GitHub's default policy blocks the event only on a public one)"
        return
    }
    $present = [Collections.Generic.List[string]]::new()
    $started = [Collections.Generic.List[string]]::new()
    $unread = [Collections.Generic.List[string]]::new()
    foreach ($file in $codeReviewWorkflows) {
        $read = Invoke-HostApi gh "repos/$Owner/$Name/contents/${file}?ref=$($Info.default_branch)"
        if ($read.Status -eq 404) { continue }
        if ($read.Status -ne 200) {
            Write-Host "${prefix}not available (couldn't read ${file}: $(Get-FailureReason $read))"
            return
        }
        $present.Add($file)
        $text = Get-ContentText $read.Body
        if ($null -eq $text) { $unread.Add($file) } else { foreach ($trigger in Get-WorkflowEvents $text) { $started.Add($trigger) } }
    }
    if (-not $present.Count) { Write-Host "${prefix}not needed (it has no code-review workflow)"; return }
    $events = @(@($codeReviewEvents) + @($started) | Select-Object -Unique)
    $triggerNote = if ($unread.Count) { " (the on: key of $($unread -join ' and ') wasn't read: the contents API sent no base64 UTF-8 text, such as for a file over 1 MB)" } else { '' }

    $own = Read-EventPolicies "repos/$Owner/$Name/actions/policies"
    if ($own.Why) { Write-Host "${prefix}not available ($($own.Why))$triggerNote"; return }
    $ours = @($own.Policies | Where-Object { $_.name -eq $eventPolicyName }) | Select-Object -First 1
    if ($ours) {
        $gaps = @(Get-EventPolicyGaps $ours $events)
        if (-not $gaps.Count) { Write-Host "${prefix}already set ('$eventPolicyName' allows it)$triggerNote"; return }
        $why = $gaps -join '; '
        $kept = @($ours.rules | Where-Object { $_.type -eq 'restrict_action_events' } | ForEach-Object { @($_.parameters.allowed_events) })
        $allowed = @(@($events) + $kept | Where-Object { $_ } | Select-Object -Unique)
        if (-not $PSCmdlet.ShouldProcess($Name, "update Actions policy '$eventPolicyName'")) {
            Write-Host "${prefix}would set (update '$eventPolicyName', as $why, for $($codeReviewWorkflows -join ' and '), allowing $($allowed -join ', '))$triggerNote"
            return
        }
        $result = Invoke-HostWrite PUT "repos/$Owner/$Name/actions/policies/$($ours.id)" (New-EventPolicyBody $allowed)
        if ($result.Status -ge 200 -and $result.Status -lt 300) { Write-Host "${prefix}set (updated '$eventPolicyName', as $why)$triggerNote" }
        else { Write-Host "${prefix}not available (couldn't update '$eventPolicyName', as ${why}: $(Get-FailureReason $result))$triggerNote" }
        return
    }
    $allowing = @($own.Policies | Where-Object { Test-AllowsEvents $_ $present $events })
    if ($allowing.Count) { Write-Host "${prefix}already set ('$($allowing[0].name)' allows it)$triggerNote"; return }

    $org = Read-EventPolicies "orgs/$Owner/actions/policies"
    # HTTP 403 or 404 is what an account that may not read them, or an owner that is a user, gets: nothing to report.
    $orgNote = if ($org.Why -and $org.Status -notin @(403, 404)) { " (the organization's policies weren't checked: $($org.Why))" } else { '' }
    $allowing = @($org.Policies | Where-Object { Test-AllowsEvents $_ $present $events $Name })
    if ($allowing.Count) { Write-Host "${prefix}already set (the organization's '$($allowing[0].name)' allows it)$triggerNote"; return }

    if (-not $PSCmdlet.ShouldProcess($Name, "create Actions policy '$eventPolicyName'")) {
        Write-Host "${prefix}would set (create '$eventPolicyName' for $($codeReviewWorkflows -join ' and '), allowing $($events -join ', '))$orgNote$triggerNote"
        return
    }
    $result = Invoke-HostWrite POST "repos/$Owner/$Name/actions/policies" (New-EventPolicyBody $events)
    if ($result.Status -ge 200 -and $result.Status -lt 300) { Write-Host "${prefix}set ('$eventPolicyName')$orgNote$triggerNote" }
    else { Write-Host "${prefix}not available ($(Get-FailureReason $result))$orgNote$triggerNote" }
}

# GitHub offers organization event policies only on GitHub Team and above, and refuses them on another plan with a
# message that asks to upgrade, such as "Upgrade to GitHub Team to enable this feature.". Returns what to do instead
# when $Reason holds such a message, or '' for any other refusal.
function Get-PlanRefusalHint([string]$Reason) {
    if ($Reason -notlike '*Upgrade to GitHub*') { return '' }
    'organization event policies need GitHub Team or above: run it for each repository instead, with -Repo <name>, or with -All once its -WhatIf looks right'
}

# The same policy once for the organization, on every repository (~ALL). Its own policy, by name, is updated in place
# when it isn't active, misses an event or doesn't cover both files on every repository. Returns $true unless it can't
# read the policies or the API refuses the policy. It writes only its report lines (and, with -WhatIf, the body) to the host.
function Set-OrganizationEventPolicy {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $prefix = "$Owner (organization): ${eventPolicyLabel}: "
    $read = Read-EventPolicies "orgs/$Owner/actions/policies"
    if ($read.Why) {
        $hint = Get-PlanRefusalHint $read.Why
        if (-not $hint) { $hint = 'run it as an owner of the organization, with a token that has the admin:org scope' }
        Write-Host "${prefix}not available ($($read.Why)); $hint"
        return $false
    }
    $ours = @($read.Policies | Where-Object { $_.name -eq $eventPolicyName }) | Select-Object -First 1
    if ($ours) {
        $gaps = @(Get-EventPolicyGaps $ours $codeReviewEvents)
        if (-not (Test-ConditionCovers $ours.conditions.repository_name '~ALL')) { $gaps += "it doesn't cover every repository" }
        if (-not $gaps.Count) { Write-Host "${prefix}already set ('$eventPolicyName' allows it)"; return $true }
        $why = $gaps -join '; '
        $kept = @($ours.rules | Where-Object { $_.type -eq 'restrict_action_events' } | ForEach-Object { @($_.parameters.allowed_events) })
        $allowed = @(@($codeReviewEvents) + $kept | Where-Object { $_ } | Select-Object -Unique)
        $body = New-EventPolicyBody $allowed -Organization
        if (-not $PSCmdlet.ShouldProcess($Owner, "update Actions policy '$eventPolicyName'")) {
            Write-Host "${prefix}would set (update '$eventPolicyName', as ${why}: PUT orgs/$Owner/actions/policies/$($ours.id) with this body)"
            Write-Host ($body | ConvertTo-Json -Depth 10)
            return $true
        }
        $result = Invoke-HostWrite PUT "orgs/$Owner/actions/policies/$($ours.id)" $body
        if ($result.Status -ge 200 -and $result.Status -lt 300) { Write-Host "${prefix}set (updated '$eventPolicyName', as $why)"; return $true }
        $reason = Get-FailureReason $result
        $hint = Get-PlanRefusalHint $reason
        Write-Host "${prefix}not available (couldn't update '$eventPolicyName', as ${why}: $reason)$(if ($hint) { "; $hint" })"
        return $false
    }
    $allowing = @($read.Policies | Where-Object { Test-AllowsEvents $_ $codeReviewWorkflows $codeReviewEvents '~ALL' })
    if ($allowing.Count) { Write-Host "${prefix}already set ('$($allowing[0].name)' allows it)"; return $true }

    $body = New-EventPolicyBody -Organization
    if (-not $PSCmdlet.ShouldProcess($Owner, "create Actions policy '$eventPolicyName'")) {
        Write-Host "${prefix}would set (POST orgs/$Owner/actions/policies with this body)"
        Write-Host ($body | ConvertTo-Json -Depth 10)
        return $true
    }
    $result = Invoke-HostWrite POST "orgs/$Owner/actions/policies" $body
    if ($result.Status -ge 200 -and $result.Status -lt 300) { Write-Host "${prefix}set ('$eventPolicyName')"; return $true }
    $reason = Get-FailureReason $result
    $hint = Get-PlanRefusalHint $reason
    Write-Host "${prefix}not available ($reason)$(if ($hint) { "; $hint" })"
    return $false
}

if ($OrganizationPolicy) { if (Set-OrganizationEventPolicy) { exit 0 } else { exit 1 } }
foreach ($name in Get-Targets) {
    try { Set-Baseline $name } catch { Write-Host "${name}: FAILED: $($_.Exception.Message)" -ForegroundColor Red }
}
