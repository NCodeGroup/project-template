<#
.SYNOPSIS
    Runs every row of docs/adopt.md's Checklist for one adopted repository and prints each as done, not done,
    unreadable or does not apply, changing nothing.

.DESCRIPTION
    The script audits a clone of an adopted repository, on its default branch, against section 8 of docs/adopt.md. It
    reads the clone's files, commits and tags, and the repository's host (GitHub through gh, GitLab through glab); the
    host, owner and name come from the clone's origin remote. A clone without .copier-answers.yml isn't adopted, and
    the script throws.

    Each row prints as one line, `<step> <title>: <status>` or `<step> <title>: <status> (<detail>)`, in the table's
    order, then a summary line of the counts. The statuses are:
      done            the row's check shows it is done.
      not done        the row's check shows it isn't done.
      unreadable      the script can't tell: a read failed, a sibling script exited non-zero, or only a web page shows
                      the row (4.1, 6.2, 7.2 once .github/dependabot.yml exists, and 7.3). The detail says why.
      does not apply  the row's Applies to column doesn't hold for this repository. The detail says why.

    Where a row's check names something a script can't run as written, the script runs an equivalent read: the
    latest run or merged pull request, the release's assets, or the baseline script's -WhatIf output. Reads are cached,
    so each command runs once even when several rows use it. The script never writes: it runs the baseline and
    Scorecard scripts only with -WhatIf, and calls gh, glab and git only to read.

    The exit code is 1 when any row is not done, and 0 otherwise: an unreadable row doesn't fail the run. Run the
    script from a project-template clone, where the three scripts it runs with -WhatIf are.

.PARAMETER Path
    A clone of the adopted repository, on its default branch.

.EXAMPLE
    .\tools\Get-AdoptionChecklist.ps1 -Path C:\src\Buffers
#>
[CmdletBinding()]
param(
    # A clone of the adopted repository, on its default branch.
    [Parameter(Mandatory)][string]$Path
)
$ErrorActionPreference = 'Stop'

$Path = (Resolve-Path -LiteralPath $Path).ProviderPath
$answersFile = Join-Path $Path '.copier-answers.yml'
if (-not (Test-Path -LiteralPath $answersFile -PathType Leaf)) {
    throw "$Path has no .copier-answers.yml, so it isn't adopted: see docs/adopt.md 1.2."
}
$pwsh = (Get-Process -Id $PID).Path
$script:cache = @{}

# Reads one answer from .copier-answers.yml; nothing when the file doesn't set it.
function Get-Answer([string]$Key) {
    $match = Select-String -LiteralPath $answersFile -Pattern "^${Key}:\s*(.+?)\s*$" | Select-Object -First 1
    if ($match) { $match.Matches[0].Groups[1].Value.Trim("'", '"') }
}

# Reads a file of the clone as one string; $null when it doesn't exist.
function Get-FileText([string]$Relative) {
    $file = Join-Path $Path $Relative
    if (Test-Path -LiteralPath $file -PathType Leaf) { Get-Content -LiteralPath $file -Raw }
    else { $null }
}

# Whether any workflow file, .yml or .yaml, contains the text.
function Test-WorkflowText([string]$Text) {
    $folder = Join-Path $Path '.github/workflows'
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { return $false }
    foreach ($file in Get-ChildItem -LiteralPath $folder -File | Where-Object { $_.Extension -in '.yml', '.yaml' }) {
        if ("$(Get-Content -LiteralPath $file.FullName -Raw)".Contains($Text)) { return $true }
    }
    $false
}

# The highest stable tag, v<major>.<minor>.<patch> with a major of 1 or more; $null when there is none.
function Get-StableTag {
    $best = $null
    foreach ($tag in @(git -C $Path tag --list)) {
        if ("$tag" -notmatch '^v?(\d+)\.\d+\.\d+$' -or [int]$Matches[1] -lt 1) { continue }
        $version = [version]("$tag" -replace '^v')
        if (-not $best -or $version -gt $best.Version) { $best = [pscustomobject]@{ Tag = "$tag"; Version = $version } }
    }
    if ($best) { $best.Tag } else { $null }
}

# Runs a read once per run, and gives the same value, or throws the same error, to every row that asks.
function Get-Cached([string]$Key, [scriptblock]$Read) {
    if (-not $script:cache.ContainsKey($Key)) {
        try { $script:cache[$Key] = [pscustomobject]@{ Value = (& $Read); Error = $null } }
        catch { $script:cache[$Key] = [pscustomobject]@{ Value = $null; Error = $_ } }
    }
    $entry = $script:cache[$Key]
    if ($entry.Error) { throw $entry.Error }
    $entry.Value
}

function New-Result([string]$Status, [string]$Detail = '') {
    [pscustomobject]@{ Status = $Status; Detail = $Detail }
}

# Folds the results of a row's parts into one: not done if any is, else unreadable if any is, else done.
function Join-Result([object[]]$Parts) {
    $notDone = @($Parts | Where-Object { $_.Status -eq 'not done' })
    if ($notDone.Count) { return New-Result 'not done' (@($notDone.Detail | Where-Object { $_ }) -join '; ') }
    $unreadable = @($Parts | Where-Object { $_.Status -eq 'unreadable' })
    if ($unreadable.Count) { return New-Result 'unreadable' (@($unreadable.Detail | Where-Object { $_ }) -join '; ') }
    New-Result 'done' (@($Parts.Detail | Where-Object { $_ }) -join '; ')
}

# Runs a command and keeps what it printed: Out is the output lines joined by newlines, Error the error text, and
# Status the HTTP status that gh names in it, or 0. ExitCode is -1 when the command isn't installed.
function Invoke-Tool([string]$Name, [string[]]$Arguments, [string]$WorkingDirectory) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ ExitCode = -1; Out = ''; Error = "$Name isn't installed"; Status = 0 }
    }
    $ErrorActionPreference = 'Continue'
    $errors = [Collections.Generic.List[string]]::new()
    if ($WorkingDirectory) { Push-Location -LiteralPath $WorkingDirectory }
    try {
        $out = @(& $Name @Arguments 2>&1 | ForEach-Object {
                if ($_ -is [Management.Automation.ErrorRecord]) { $errors.Add("$_".Trim()) } else { "$_" }
            })
        $code = $LASTEXITCODE
    }
    finally {
        if ($WorkingDirectory) { Pop-Location }
    }
    $said = @($errors | Where-Object { $_ }) -join ' '
    $status = if ($said -match 'HTTP (\d{3})') { [int]$Matches[1] } else { 0 }
    [pscustomobject]@{ ExitCode = $code; Out = ($out -join "`n"); Error = $said; Status = $status }
}

# Runs gh and gives its JSON output as objects; $null for a 404 when -Missing is set, else a failure throws.
function Read-Gh([string[]]$Arguments, [switch]$Missing) {
    $r = Invoke-Tool 'gh' $Arguments
    if ($r.ExitCode) {
        if ($Missing -and $r.Status -eq 404) { return $null }
        $why = if ($r.Error) { $r.Error } else { "gh exited $($r.ExitCode)" }
        throw "gh $($Arguments -join ' ') failed: $why"
    }
    $r.Out | ConvertFrom-Json
}

# Runs one of the sibling scripts in tools/, which the baseline and Scorecard rows read with -WhatIf.
function Invoke-Sibling([string]$Script, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    $lines = @(& $pwsh -NoProfile -File (Join-Path $PSScriptRoot $Script) @Arguments 2>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = $lines }
}

# The GitHub repository, from gh api.
function Get-Repo { Get-Cached 'repo' { Read-Gh @('api', "repos/$slug") } }

# Facts about the repository, read once. The row checks read $hostName and $encoded, so they are script-scoped.
$origin = "$(git -C $Path remote get-url origin 2>$null)"
if ($origin -notmatch '^(?:(?:https?|ssh)://)?(?:[^@/]+@)?(?<host>[\w.-]+\.[\w-]+)(?::\d+)?[:/](?<path>[\w.-]+(?:/[\w.-]+?)+?)(?:\.git)?/?$') {
    throw "Couldn't tell the repository from the origin remote of ${Path}: '$origin'."
}
$script:hostName = $Matches['host']
$originPath = $Matches['path']
$gitHost = if ((Get-Answer 'git_host') -eq 'gitlab') { 'gitlab' } else { 'github' }
if ($gitHost -eq 'github') {
    $owner, $name = $originPath -split '/'
    $slug = "$owner/$name"
}
else {
    $project = $originPath
    $script:encoded = [uri]::EscapeDataString($project)
}
$release = if ((Get-FileText 'AGENTS.md') -match '(?m)^- release:[ \t]*(\S+)') { $Matches[1] } else { 'none' }
$rootSubject = @(git -C $Path log --max-parents=0 --format=%s)[-1]

# The rows of docs/adopt.md's section 8 Checklist, titled as its headings are.
$rows = @(
    @('0.1', 'Accounts and Tools'), @('0.2', "The Organization's Actions Policy"), @('0.3', "NCode Review's Organization Setup"),
    @('1.1', 'A New Project'), @('1.2', 'An Existing Repository'), @('1.3', 'Node.js: nvs and the Prelude'),
    @('1.4', 'First Push and First Pull Request'),
    @('2.1', 'Run the Baseline'), @('2.2', 'When an Approval Is Required'), @('2.3', "CodeQL's Languages"),
    @('2.4', 'Scorecard'), @('2.5', 'On GitLab'),
    @('3.1', 'How a Release Happens'), @('3.2', 'Signed Tags'), @('3.3', 'Immutable Releases'),
    @('4.1', 'Trusted Publishing on nuget.org'), @('4.2', 'The nuget Environment and NUGET_USER'),
    @('4.3', 'The First Package Validation Baseline'), @('4.4', 'Publish a Release'),
    @('4.5', 'Re-publish a Release That Failed'), @('4.6', 'Raise the Baseline After a Stable Release'),
    @('4.7', 'Check the Package'),
    @('5.1', 'Set Up the Repository'), @('5.2', 'Require the Approval'), @('5.3', 'Check the Approval'),
    @('5.4', 'Day to Day'),
    @('6.1', 'The OpenSSF Best Practices Badge'), @('6.2', 'Codecov'),
    @('6.3', 'The Documentation Site and GitHub Pages'), @('6.4', "The Copilot Cloud Agent's Environment"),
    @('6.5', 'Labels'),
    @('7.1', 'Template Updates'), @('7.2', 'Dependabot'), @('7.3', 'Rotate a Key')
) | ForEach-Object { [pscustomobject]@{ Step = $_[0]; Title = $_[1] } }

# The reason a row's Applies to doesn't hold for this repository; $null when it holds.
function Get-NotApplying([string]$Step) {
    $section = $Step.Split('.')[0]
    if ($gitHost -eq 'gitlab') {
        if ($Step -notin '0.1', '1.1', '1.2', '1.3', '1.4', '2.5', '4.3', '7.1') { return 'GitHub only' }
    }
    elseif ($Step -eq '2.5') { return 'GitLab only' }
    if (($Step -in '0.2', '0.3') -and (Get-Repo).owner.type -ne 'Organization') {
        return 'the owner is not an organization'
    }
    if (($Step -in '0.3', '5.1', '5.2', '5.3', '5.4', '7.3') -and (Get-Answer 'code_review') -ne 'true') {
        return 'without NCode Review'
    }
    $created = "$rootSubject".StartsWith('Create project from project-template ')
    if ($Step -eq '1.1' -and -not $created) { return 'adopted, as 1.2' }
    if ($Step -eq '1.2' -and $created) { return 'created from the template, as 1.1' }
    if ($Step -eq '1.3' -and (Get-Answer 'uses_node') -ne 'true') { return 'not a Node.js project' }
    if (($Step -in '2.4', '3.2') -and (Get-Repo).visibility -ne 'public') { return 'not a public repository' }
    if ($section -eq '3' -and $release -ne 'tag+release') { return "AGENTS.md's Landing says release: $release" }
    if ($section -eq '4') {
        if ((Get-Answer 'nuget_package') -ne 'true') { return 'not a .NET library' }
        if ($Step -ne '4.3' -and (Get-Answer 'nuget_publisher')) {
            return 'its own workflow publishes the packages (nuget_publisher)'
        }
    }
    if ($Step -eq '6.2' -and -not (Test-WorkflowText 'codecov/codecov-action')) { return 'no Codecov upload' }
    if ($Step -eq '6.3' -and -not (Test-WorkflowText 'actions/deploy-pages')) { return 'no documentation site' }
    if ($Step -eq '6.4' -and -not (Test-Path -LiteralPath (Join-Path $Path '.github/workflows/copilot-setup-steps.yml'))) {
        return 'without Copilot'
    }
    $null
}

# Reads a template version, v<major>.<minor>.<patch> or shorter, as Get-TemplateUpdate.ps1 does; $null when it isn't one.
function ConvertTo-TemplateVersion([string]$Text) {
    if ($Text -notmatch '^v?(\d+(?:\.\d+){0,3})$') { return $null }
    $parts = @($Matches[1] -split '\.')
    while ($parts.Count -lt 3) { $parts += '0' }
    [version]($parts -join '.')
}

# The baseline script's -WhatIf run, which several rows read.
function Get-Baseline {
    Get-Cached 'baseline' { Invoke-Sibling 'Set-RepositoryBaseline.ps1' @('-Repo', $name, '-Owner', $owner, '-WhatIf') }
}

# The last non-empty line of a sibling run, for the reason a run that exited non-zero gives.
function Get-LastLine([object]$Run) {
    $last = @($Run.Lines | Where-Object { "$_".Trim() }) | Select-Object -Last 1
    if ($last) { "$last".Trim() } else { 'no output' }
}

# The baseline's output lines; throws, so the row is unreadable, when its -WhatIf run exited non-zero.
function Get-BaselineLines {
    $run = Get-Baseline
    if ($run.ExitCode) { throw "the baseline's -WhatIf run exited $($run.ExitCode): $(Get-LastLine $run)" }
    @($run.Lines)
}

# The names of the secrets of the code-review environment; none when the environment doesn't exist (a 404).
function Get-EnvSecretNames {
    Get-Cached 'envSecrets' {
        $list = Read-Gh @('secret', 'list', '--env', 'code-review', '--repo', $slug, '--json', 'name') -Missing
        @($list | ForEach-Object { $_.name })
    }
}

# The workflow that runs NCode Review, and whether it passes approve: true and the approver's private key.
$reviewFile = Get-FileText '.github/workflows/code-review.yml'
$approve = "$reviewFile" -match 'approve:[ \t]*true'
$approverKey = "$reviewFile" -match 'approver-private-key:[ \t]*\S'

# The approvals the default branch's pull request rule requires; $null when no rule requires a pull request.
function Get-RequiredApprovals {
    Get-Cached 'requiredApprovals' {
        $rules = Read-Gh @('api', "repos/$slug/rules/branches/$((Get-Repo).default_branch)")
        $rule = @($rules) | Where-Object { $_.type -eq 'pull_request' } | Select-Object -First 1
        if ($rule) { [int]$rule.parameters.required_approving_review_count }
    }
}

# The approvals the baseline requires (ADR-0034, ADR-0036): 1 when NCode Review approves with the approver's key, or
# when approve: true and a second person can push; else 0.
function Get-ExpectedApprovals {
    if ($approve -and $approverKey -and ('NCODE_REVIEW_APPROVER_PRIVATE_KEY' -in @(Get-EnvSecretNames))) { return 1 }
    if ($approve) {
        $people = @(Read-Gh @('api', "repos/$slug/collaborators?affiliation=all&permission=push&per_page=100") |
                Where-Object { $_.type -eq 'User' })
        if ($people.Count -ge 2) { return 1 }
    }
    0
}

# The latest merged pull requests, newest first.
function Get-MergedPulls {
    Get-Cached 'mergedPulls' {
        @(Read-Gh @('pr', 'list', '--repo', $slug, '--state', 'merged', '--limit', '20', '--json', 'number,author'))
    }
}

# A result for a workflow's latest run: done when it succeeded, else not done with how it stands.
function Get-LatestRun([string]$Workflow) {
    $runs = @(Read-Gh @('run', 'list', '--repo', $slug, '--workflow', $Workflow, '--limit', '1', '--json', 'conclusion,status'))
    if (-not $runs.Count) { return New-Result 'not done' "no $Workflow run yet" }
    $run = $runs[0]
    if ($run.conclusion -eq 'success') { return New-Result 'done' }
    if (-not $run.conclusion) { return New-Result 'not done' "the latest $Workflow run is $($run.status)" }
    New-Result 'not done' "the latest $Workflow run ended $($run.conclusion)"
}

# gh's view of the latest release, kept with its exit code and error.
function Get-ReleaseView {
    Get-Cached 'releaseView' { Invoke-Tool 'gh' @('release', 'view', '--repo', $slug, '--json', 'tagName,assets') }
}

# The reviews of the latest merged pull request a person wrote, as a result; rows 5.3 and 5.4 share it.
function Get-ApprovalResult {
    Get-Cached 'approvalResult' {
        $pull = Get-MergedPulls | Where-Object { $_.author.is_bot -ne $true } | Select-Object -First 1
        if (-not $pull) { return New-Result 'not done' 'no merged pull request by a person yet' }
        $number = $pull.number
        $reviews = @(Read-Gh @('api', "repos/$slug/pulls/$number/reviews?per_page=100"))
        $approved = @($reviews | Where-Object { $_.user.login -eq 'ncode-review-approver[bot]' -and $_.state -eq 'APPROVED' })
        if ($approved.Count) { New-Result 'done' "#$number approved by ncode-review-approver[bot]" }
        else { New-Result 'not done' "#$number has no approval from ncode-review-approver[bot]" }
    }
}

# Row checks
$checks = @{}

$checks['0.1'] = {
    $parts = @()
    $auth = if ($gitHost -eq 'gitlab') { Invoke-Tool 'glab' @('auth', 'status', '--hostname', $hostName) }
    else { Invoke-Tool 'gh' @('auth', 'status') }
    if ($auth.ExitCode) {
        $tool = if ($gitHost -eq 'gitlab') { 'glab' } else { 'gh' }
        $why = if ($auth.ExitCode -eq -1) { $auth.Error } else { "$tool isn't signed in" }
        $parts += New-Result 'not done' $why
    }
    $copier = Invoke-Tool 'copier' @('--version')
    if ($copier.ExitCode) { $parts += New-Result 'not done' "copier: $($copier.Error)" }
    if (-not ($PSVersionTable.PSVersion -ge [version]'7.4')) {
        $parts += New-Result 'not done' "PowerShell $($PSVersionTable.PSVersion) is older than 7.4"
    }
    $email = Invoke-Tool 'git' @('-C', $Path, 'config', 'user.email')
    if (-not $email.Out.Trim()) { $parts += New-Result 'not done' 'git has no user.email' }
    Join-Result (@($parts) + (New-Result 'done'))
}

$checks['1.1'] = {
    $version = "$(Get-FileText '.template-version')".Trim()
    if (-not $version) { return New-Result 'not done' 'no .template-version' }
    if ($gitHost -eq 'gitlab') {
        $r = Invoke-Tool 'glab' @('api', '--hostname', $hostName, "projects/$encoded")
        if ($r.ExitCode) { throw "couldn't read ${project}: $($r.Error)" }
    }
    else { $null = Get-Repo }
    New-Result 'done' "template $version"
}

$checks['1.2'] = {
    $subject = @(git -C $Path log --format=%s) | Where-Object { "$_".StartsWith('Adopt project-template ') } |
        Select-Object -First 1
    if ($subject) { New-Result 'done' "$subject" }
    else { New-Result 'not done' "no 'Adopt project-template' commit" }
}

$checks['1.3'] = {
    $text = Get-FileText '.node-version'
    if (-not $text) { return New-Result 'not done' 'no .node-version' }
    # Reads what Use-Node.ps1 would select without running it: it installs a missing release with nvs add.
    $wanted = (("$text".Trim() -split '\r?\n')[0]).Trim() -creplace '^v', ''
    $fits = {
        param([string]$Version)
        $Version -and ($Version -ceq $wanted -or $Version.StartsWith("$wanted.", [StringComparison]::Ordinal))
    }
    $r = Invoke-Tool node @('--version')
    $onPath = if (-not $r.ExitCode -and $r.Out) { @($r.Out -split "`n")[-1].Trim() -creplace '^v', '' } else { '' }
    if (& $fits $onPath) { return New-Result 'done' "node v$onPath on PATH" }
    $nvsHome = if ($env:NVS_HOME) { $env:NVS_HOME }
    elseif ($IsWindows) { Join-Path $env:LOCALAPPDATA 'nvs' }
    else { Join-Path $HOME '.nvs' }
    $nodeFolder = Join-Path $nvsHome 'node'
    if ((Test-Path -LiteralPath (Join-Path $nvsHome 'nvs.ps1')) -and (Test-Path -LiteralPath $nodeFolder)) {
        $installed = @(Get-ChildItem -LiteralPath $nodeFolder -Directory | Where-Object { & $fits $_.Name } |
                ForEach-Object Name)
        if ($installed.Count) { return New-Result 'done' "nvs has node $($installed -join ', ')" }
    }
    $found = if ($onPath) { "node v$onPath" } else { 'no node' }
    New-Result 'not done' ("Node.js $wanted from .node-version is neither on PATH (found $found) " +
        "nor installed in nvs at ${nvsHome}: run ./.template/Initialize-Nvs.ps1")
}

$checks['2.1'] = {
    $set = @(Get-BaselineLines | Where-Object { $_ -match ': would set' -or $_.StartsWith('would: ') })
    if ($set.Count) { New-Result 'not done' "$($set.Count) to set: $($set -join '; ')" }
    else { New-Result 'done' }
}

$checks['3.3'] = {
    $line = Get-BaselineLines | Where-Object { $_ -match ': immutable releases: (.+)$' } | Select-Object -First 1
    if (-not $line) { return New-Result 'unreadable' 'the baseline printed no immutable releases line' }
    $null = "$line" -match ': immutable releases: (.+)$'
    $state = $Matches[1].Trim()
    if ($state -eq 'already set') { New-Result 'done' 'on' }
    elseif ($state -eq 'would set') { New-Result 'not done' 'immutable releases are off' }
    elseif ($state.StartsWith('not available')) { New-Result 'done' $state }
    else { New-Result 'unreadable' "unknown immutable releases state: $state" }
}

$checks['0.2'] = {
    $parts = @()
    $org = Invoke-Sibling 'Set-RepositoryBaseline.ps1' @('-OrganizationPolicy', '-Owner', $owner, '-WhatIf')
    if ($org.ExitCode) {
        $parts += New-Result 'unreadable' "the -OrganizationPolicy -WhatIf run exited $($org.ExitCode): $(Get-LastLine $org)"
    }
    else {
        $set = @($org.Lines | Where-Object { $_ -match 'would set' })
        $parts += if ($set.Count) { New-Result 'not done' "$($set.Count) organization setting(s) to set" }
        else { New-Result 'done' }
    }
    $baseline = Get-Baseline
    if ($baseline.ExitCode) {
        $parts += New-Result 'unreadable' "the baseline's -WhatIf run exited $($baseline.ExitCode): $(Get-LastLine $baseline)"
    }
    else {
        $line = $baseline.Lines | Where-Object { $_ -match 'organization two-factor requirement: (.+)$' } |
            Select-Object -First 1
        if (-not $line) { $parts += New-Result 'unreadable' 'no two-factor line' }
        else {
            $null = "$line" -match 'organization two-factor requirement: (.+)$'
            $state = $Matches[1].Trim()
            $parts += if ($state -eq 'required') { New-Result 'done' }
            elseif ($state -eq 'not required') {
                New-Result 'not done' "the organization doesn't require two-factor authentication"
            }
            else { New-Result 'unreadable' $state }
        }
    }
    Join-Result $parts
}

$checks['2.4'] = {
    $run = Invoke-Sibling 'Dismiss-ScorecardAlerts.ps1' @('-Repo', $slug, '-WhatIf')
    if ($run.ExitCode) { return New-Result 'unreadable' (Get-LastLine $run) }
    $would = @($run.Lines | Where-Object { $_ -like '*would dismiss*' })
    if ($would.Count) { New-Result 'not done' "would dismiss $($would.Count) alert(s)" }
    else { New-Result 'done' }
}

$checks['2.2'] = {
    $count = Get-RequiredApprovals
    if ($null -eq $count) { return New-Result 'not done' "no rule requires a pull request on $((Get-Repo).default_branch)" }
    $expected = Get-ExpectedApprovals
    if ($count -eq $expected) { New-Result 'done' "requires $count approval(s)" }
    else { New-Result 'not done' "requires $count approval(s), expected $expected" }
}

$checks['5.2'] = {
    $count = Get-RequiredApprovals
    if ($null -eq $count) { return New-Result 'not done' "no rule requires a pull request on $((Get-Repo).default_branch)" }
    if ($count -eq 1) { New-Result 'done' }
    else { New-Result 'not done' "requires $count approval(s), expected 1" }
}

$checks['2.3'] = {
    $setup = Read-Gh @('api', "repos/$slug/code-scanning/default-setup")
    $languages = @($setup.languages | Where-Object { $_ })
    if ($setup.state -eq 'configured' -and $languages.Count) { return New-Result 'done' "configured: $($languages -join ', ')" }
    $analyzing = if ($languages.Count) { $languages -join ', ' } else { 'no language' }
    New-Result 'not done' "$($setup.state), analyzing $analyzing"
}

$checks['5.1'] = {
    $parts = @()
    if ('NCODE_REVIEW_APPROVER_PRIVATE_KEY' -notin @(Get-EnvSecretNames)) {
        $parts += New-Result 'not done' 'the code-review environment has no NCODE_REVIEW_APPROVER_PRIVATE_KEY'
    }
    if (-not ($approve -and $approverKey)) {
        $parts += New-Result 'not done' ".github/workflows/code-review.yml doesn't pass approve: true and approver-private-key"
    }
    Join-Result (@($parts) + (New-Result 'done'))
}

$checks['0.3'] = {
    $list = Read-Gh @('secret', 'list', '--org', $owner, '--json', 'name')
    $names = @($list | ForEach-Object { $_.name })
    $missing = @('NCODE_REVIEW_APP_PRIVATE_KEY', 'AWS_BEARER_TOKEN_BEDROCK' | Where-Object { $_ -notin $names })
    if ($missing.Count) { New-Result 'not done' "missing $($missing -join ', ')" }
    else { New-Result 'done' }
}

$checks['4.3'] = {
    $tag = Get-StableTag
    if (-not $tag) { return New-Result 'done' 'no stable release yet, so no baseline is due' }
    $r = Invoke-Tool 'git' @('-C', $Path, 'grep', '-l', 'PackageValidationBaselineVersion')
    if ($r.ExitCode -gt 1 -or $r.ExitCode -lt 0) { throw "git grep failed: $($r.Error)" }
    $files = @($r.Out -split "`n" | Where-Object { $_.Trim() })
    if (-not $r.ExitCode -and $files) { return New-Result 'done' "set in $($files -join ', ')" }
    New-Result 'not done' "$tag is released and nothing sets PackageValidationBaselineVersion"
}

$checks['6.1'] = {
    $id = Get-Answer 'best_practices_project'
    if (-not $id) { return New-Result 'not done' 'not registered: no best_practices_project answer' }
    $badge = "https://www.bestpractices.dev/projects/$id/badge"
    if (-not "$(Get-FileText 'README.md')".Contains($badge)) {
        return New-Result 'not done' "README.md doesn't show the badge"
    }
    New-Result 'done' "project $id"
}

$checks['7.1'] = {
    $versionFile = Get-FileText '.template-version'
    $currentText = if ($null -ne $versionFile) { "$(@($versionFile -split '\r?\n')[0])".Trim() } else { Get-Answer '_commit' }
    # A version between tags, such as v0.12.0-3-gabc1234, is the tag before the first dash.
    $currentTag = "$currentText" -replace '-.*$'
    $current = ConvertTo-TemplateVersion $currentTag
    if (-not $current) { throw "can't read the project's template version from .template-version ('$currentText')" }
    $src = Get-Answer '_src_path'
    if (-not $src) { throw '.copier-answers.yml has no _src_path' }
    # Copier's shorthands, and the template's old address, which GitHub only redirects, as Get-TemplateUpdate.ps1 reads them.
    if ($src -match '^gh:(.+)$') { $src = "https://github.com/$($Matches[1])" }
    elseif ($src -match '^gl:(.+)$') { $src = "https://gitlab.com/$($Matches[1])" }
    if ($src -match '^https://github\.com/polewskm/project-template(?:\.git)?/?$') {
        $src = 'https://github.com/NCodeGroup/project-template.git'
    }
    $r = Invoke-Tool 'git' @('ls-remote', '--tags', '--refs', '--', $src)
    if ($r.ExitCode) { return New-Result 'unreadable' "couldn't read the template's tags at ${src}: $($r.Error)" }
    $newest = $null
    foreach ($ref in $r.Out -split "`n") {
        if ($ref -match 'refs/tags/(.+)$') {
            $version = ConvertTo-TemplateVersion $Matches[1]
            if ($version -and (-not $newest -or $version -gt $newest.Version)) {
                $newest = [pscustomobject]@{ Tag = $Matches[1]; Version = $version }
            }
        }
    }
    if (-not $newest) { return New-Result 'unreadable' "the template at $src has no version tags" }
    if ($newest.Version -le $current) { return New-Result 'done' "on $currentTag" }
    New-Result 'not done' "$($newest.Tag) is out; the project is on $currentTag"
}

$checks['1.4'] = {
    if ($gitHost -eq 'gitlab') {
        $list = Invoke-Tool 'glab' @('api', '--hostname', $hostName, "projects/$encoded/merge_requests?state=merged&order_by=updated_at&per_page=1")
        if ($list.ExitCode) { throw "glab api merge_requests failed: $($list.Error)" }
        $merged = if ($list.Out.Trim()) { @($list.Out | ConvertFrom-Json) } else { @() }
        if (-not $merged.Count) { return New-Result 'not done' 'no merged merge request yet' }
        $iid = $merged[0].iid
        $r = Invoke-Tool 'glab' @('api', '--hostname', $hostName, "projects/$encoded/merge_requests/$iid")
        if ($r.ExitCode) { throw "glab api merge_requests/$iid failed: $($r.Error)" }
        $status = ($r.Out | ConvertFrom-Json).head_pipeline.status
        if ($status -eq 'success') { return New-Result 'done' "!$iid's pipeline passed" }
        $shown = if ($status) { $status } else { 'none' }
        return New-Result 'not done' "!$iid's pipeline: $shown"
    }
    $pull = @(Get-MergedPulls) | Select-Object -First 1
    if (-not $pull) { return New-Result 'not done' 'no merged pull request yet' }
    $number = $pull.number
    # gh exits 8 while checks are pending, so the output is read whatever the exit code.
    $r = Invoke-Tool 'gh' @('pr', 'checks', "$number", '--repo', $slug, '--json', 'name,bucket')
    try {
        if (-not $r.Out.Trim()) { throw 'no output' }
        $reported = @($r.Out | ConvertFrom-Json -ErrorAction Stop)
    }
    catch { throw "couldn't read the checks of #${number}: $($r.Error)" }
    if (-not $reported.Count) { return New-Result 'not done' "#$number reported no checks" }
    $failing = @($reported | Where-Object { $_.bucket -notin 'pass', 'skipping' })
    if ($failing.Count) {
        return New-Result 'not done' "#${number}: $(@($failing | ForEach-Object { "$($_.name) ($($_.bucket))" }) -join ', ')"
    }
    New-Result 'done' "#${number}: $($reported.Count) checks passed"
}

$checks['3.1'] = {
    $parts = @(Get-LatestRun 'tag-release.yml')
    $view = Get-ReleaseView
    if (-not $view.ExitCode) { $parts += New-Result 'done' "$(($view.Out | ConvertFrom-Json).tagName)" }
    elseif ($view.Error -match 'not found') { $parts += New-Result 'not done' 'no release yet' }
    else {
        $why = if ($view.Error) { $view.Error } else { "gh exited $($view.ExitCode)" }
        $parts += New-Result 'unreadable' "gh release view failed: $why"
    }
    Join-Result $parts
}

$checks['3.2'] = {
    $tag = @(git -C $Path tag --list 'v*' --sort=-version:refname) | Select-Object -First 1
    if (-not $tag) { return New-Result 'not done' 'no release tag in the clone' }
    $identity = "https://github.com/$slug/.github/workflows/tag-release.yml@refs/heads/$((Get-Repo).default_branch)"
    $r = Invoke-Tool 'gitsign' @('verify-tag', '--certificate-identity', $identity,
        '--certificate-oidc-issuer', 'https://token.actions.githubusercontent.com', "$tag") -WorkingDirectory $Path
    if ($r.ExitCode -eq -1) { return New-Result 'unreadable' "gitsign isn't installed" }
    if ($r.ExitCode -eq 0) { return New-Result 'done' "$tag verified" }
    $why = if ($r.Error) { $r.Error } else { "exit $($r.ExitCode)" }
    New-Result 'not done' "gitsign refused ${tag}: $why"
}

$checks['5.3'] = { Get-ApprovalResult }

$checks['5.4'] = {
    $r = Get-ApprovalResult
    New-Result $r.Status "as 5.3: $($r.Detail)"
}

$checks['6.4'] = { Get-LatestRun 'copilot-setup-steps.yml' }

$checks['4.1'] = {
    New-Result 'unreadable' 'only https://www.nuget.org/account/trustedpublishing lists the policy'
}

$checks['4.2'] = {
    $parts = @()
    $policies = Read-Gh @('api', "repos/$slug/environments/nuget/deployment-branch-policies") -Missing
    if ($null -eq $policies) {
        $parts += New-Result 'not done' 'no nuget environment with selected branches and tags'
    }
    else {
        $entries = @(@($policies.branch_policies) | Where-Object { $_ } | ForEach-Object {
                $type = if ($_.type) { $_.type } else { 'branch' }
                "$type $($_.name)"
            })
        $wanted = @("branch $((Get-Repo).default_branch)", 'tag v*')
        $missing = @($wanted | Where-Object { $_ -notin $entries })
        if ($missing.Count) { $parts += New-Result 'not done' "missing $($missing -join ', ')" }
    }
    $variables = @(Read-Gh @('variable', 'list', '--repo', $slug, '--json', 'name') | ForEach-Object { $_.name })
    if ('NUGET_USER' -notin $variables) { $parts += New-Result 'not done' 'no NUGET_USER variable' }
    Join-Result (@($parts) + (New-Result 'done'))
}

$checks['4.4'] = { Get-LatestRun 'publish.yml' }

$checks['4.5'] = {
    $r = Get-LatestRun 'publish.yml'
    New-Result $r.Status "as 4.4: $($r.Detail)"
}

$checks['4.6'] = {
    $tag = Get-StableTag
    if (-not $tag) { return New-Result 'done' 'no stable release yet' }
    $version = "$tag" -replace '^v'
    $pulls = @(Read-Gh @('pr', 'list', '--repo', $slug, '--head', "baseline-$version", '--state', 'merged', '--json', 'number'))
    if ($pulls.Count) { New-Result 'done' "#$($pulls[0].number) merged" }
    else { New-Result 'not done' "no merged pull request from baseline-$version" }
}

$checks['4.7'] = {
    $view = Get-ReleaseView
    if ($view.ExitCode) {
        if ($view.Error -match 'not found') { return New-Result 'not done' 'no release yet' }
        $why = if ($view.Error) { $view.Error } else { "gh exited $($view.ExitCode)" }
        return New-Result 'unreadable' "gh release view failed: $why"
    }
    $release = $view.Out | ConvertFrom-Json
    $tag = "$($release.tagName)"
    $assets = @(@($release.assets) | ForEach-Object { "$($_.name)" })
    $missing = @()
    if (-not @($assets | Where-Object { $_.EndsWith('.nupkg') })) { $missing += 'a .nupkg' }
    if (-not @($assets | Where-Object { $_.EndsWith('.snupkg') })) { $missing += 'a .snupkg' }
    foreach ($suffix in 'intoto.jsonl', 'spdx.json') {
        if ("$tag.$suffix" -notin $assets) { $missing += "$tag.$suffix" }
    }
    if ($missing.Count) { return New-Result 'not done' "$tag lacks $($missing -join ', ')" }
    New-Result 'done' "$tag has its packages, provenance and SBOM"
}

$checks['2.5'] = {
    $extra = @()
    if ((Get-Answer 'nuget_package') -eq 'true') { $extra += '-BaselineToken' }
    $run = Invoke-Sibling 'Set-GitLabBaseline.ps1' (@('-Path', $Path, '-WhatIf') + $extra)
    if ($run.ExitCode) {
        return New-Result 'unreadable' "the -WhatIf run exited $($run.ExitCode): $(Get-LastLine $run)"
    }
    $set = @($run.Lines | Where-Object { $_ -match 'would set' })
    if ($set.Count) { return New-Result 'not done' "$($set.Count) setting(s) to set: $($set -join '; ')" }
    $unavailable = @($run.Lines | Where-Object { $_ -match 'not available' })
    if ($unavailable.Count) { return New-Result 'unreadable' ($unavailable -join '; ') }
    New-Result 'done'
}

$checks['6.2'] = {
    New-Result 'unreadable' "only https://app.codecov.io/gh/$slug shows the latest commit"
}

$checks['6.3'] = {
    $pages = Read-Gh @('api', "repos/$slug/pages") -Missing
    if ($null -eq $pages) { return New-Result 'not done' "Pages isn't set up" }
    $cname = "$($pages.cname)"
    if ($pages.build_type -eq 'workflow' -and $cname -and $pages.https_enforced -eq $true) {
        return New-Result 'done' "workflow $cname true"
    }
    New-Result 'not done' "$($pages.build_type) $cname $($pages.https_enforced)"
}

$checks['6.5'] = {
    $labels = @(Read-Gh @('label', 'list', '--repo', $slug, '--json', 'name', '--limit', '500') | ForEach-Object { $_.name })
    if ('documentation' -in $labels) { New-Result 'done' }
    else { New-Result 'not done' 'no documentation label' }
}

$checks['7.2'] = {
    if (-not (Test-Path -LiteralPath (Join-Path $Path '.github/dependabot.yml')) -and
        -not (Test-Path -LiteralPath (Join-Path $Path '.github/dependabot.yaml'))) {
        return New-Result 'not done' 'no .github/dependabot.yml'
    }
    New-Result 'unreadable' 'only Insights > Dependency graph > Dependabot shows its recent checks'
}

$checks['7.3'] = {
    New-Result 'unreadable' "only the NCode Review apps' settings pages list their keys"
}

$counts = @{ 'done' = 0; 'not done' = 0; 'unreadable' = 0; 'does not apply' = 0 }
foreach ($row in $rows) {
    try {
        $reason = Get-NotApplying $row.Step
        $result = if ($reason) { New-Result 'does not apply' $reason }
        elseif ($checks.ContainsKey($row.Step)) { & $checks[$row.Step] }
        else { New-Result 'unreadable' 'no check for this row yet' }
    }
    catch {
        $result = New-Result 'unreadable' "$($_.Exception.Message)"
    }
    $counts[$result.Status]++
    $line = "$($row.Step) $($row.Title): $($result.Status)"
    if ($result.Detail) { $line += " ($($result.Detail))" }
    Write-Host $line
}
$label = if ($gitHost -eq 'gitlab') { $project } else { $slug }
Write-Host ("${label}: $($counts['done']) done, $($counts['not done']) not done, $($counts['unreadable']) unreadable, " +
    "$($counts['does not apply']) do not apply")
if ($counts['not done']) { exit 1 }
exit 0
