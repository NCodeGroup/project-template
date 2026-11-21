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
        if ((Get-Content -LiteralPath $file.FullName -Raw).Contains($Text)) { return $true }
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
$release = if ((Get-FileText 'AGENTS.md') -match '(?m)^- release:\s*(\S+)') { $Matches[1] } else { 'none' }
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
    $major = (("$text".Trim() -split '\r?\n')[0] -replace '^v') -replace '\..*$'
    $r = Invoke-Tool $pwsh @('-NoProfile', '-Command', '. ./.template/Use-Node.ps1; node --version') -WorkingDirectory $Path
    $node = if ($r.Out) { @($r.Out -split "`n")[-1].Trim() } else { '' }
    if (-not $r.ExitCode -and $node -and (($node -replace '^v') -replace '\..*$') -eq $major) {
        return New-Result 'done' "node $node"
    }
    $seen = if ($r.ExitCode -or -not $node) { "$($r.Error)".Trim() } else { $node }
    if (-not $seen) { $seen = "exit $($r.ExitCode)" }
    New-Result 'not done' "node $seen doesn't match .node-version $major"
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
