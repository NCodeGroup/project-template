<#
.SYNOPSIS
    Runs every row of docs/adopt.md's Checklist for one adopted repository and prints each as done, not done,
    unreadable or does not apply, changing nothing.

.DESCRIPTION
    The script audits a clone of an adopted repository, on its default branch, against section 8 of docs/adopt.md. It
    reads the clone's files, commits and tags, and the repository on GitHub through gh; the owner and name come from
    the clone's origin remote. A clone without .copier-answers.yml isn't adopted, and
    the script throws.

    Each row prints as one line, `<step> <title>: <status>` or `<step> <title>: <status> (<detail>)`, in the table's
    order, then a summary line of the counts. The statuses are:
      done            the row's check shows it is done.
      not done        the row's check shows it isn't done.
      unreadable      the script can't tell: a read failed or ran past -TimeoutSeconds, a sibling script exited
                      non-zero, or only a web page shows the row (4.1, 6.2, 7.2 once .github/dependabot.yml exists,
                      and 7.3). The detail says why.
      does not apply  the row's Applies to column doesn't hold for this repository. The detail says why.

    Where a row's check names something a script can't run as written, the script runs an equivalent read: the
    latest run or merged pull request, the release's assets, or the baseline script's -WhatIf output. Reads are cached,
    so each command runs once even when several rows use it. The script never writes: it runs the baseline and
    Scorecard scripts only with -WhatIf, and calls gh and git only to read.

    The exit code is 1 when any row is not done, and 0 otherwise: an unreadable row doesn't fail the run. Run the
    script from a project-template clone, where the three scripts it runs with -WhatIf are.

.PARAMETER Path
    A clone of the adopted repository, on its default branch.

.PARAMETER TimeoutSeconds
    How long each command the script runs (gh, git, gitsign, copier, node, or a sibling script) may take, in
    seconds; 300 by default. A command still running then is stopped, with every process it started, and its row is
    unreadable, "timed out after <n> s".

.EXAMPLE
    .\tools\Get-AdoptionChecklist.ps1 -Path C:\src\Buffers
#>
[CmdletBinding()]
param(
    # A clone of the adopted repository, on its default branch.
    [Parameter(Mandatory)][string]$Path,
    # How long each command may run, in seconds, before it is stopped and its row is unreadable: far longer than
    # any read takes, short enough that a command stalled on the network or a prompt doesn't hang the audit.
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 300
)
$ErrorActionPreference = 'Stop'

# The newest merged pull requests rows 1.4, 5.3 and 5.4 read: 1.4 takes the newest, and 5.3 the newest a person wrote,
# which is among them unless bots merged all 20 since.
$mergedPullLimit = 20
# gh label list's limit, far above the labels a repository has; 6.5 looks for one of them.
$labelLimit = 500
# GitHub's largest REST page: the collaborators 2.2 counts and the reviews 5.3 reads come in one read.
$pageSize = 100
# The oldest PowerShell docs/adopt.md 0.1 accepts.
$minimumPowerShell = [version]'7.4'

$Path = (Resolve-Path -LiteralPath $Path).ProviderPath
$answersFile = Join-Path $Path '.copier-answers.yml'
if (-not (Test-Path -LiteralPath $answersFile -PathType Leaf)) {
    throw "$Path has no .copier-answers.yml, so it isn't adopted: see docs/adopt.md 1.2."
}
$pwsh = (Get-Process -Id $PID).Path
$script:cache = @{}
$timeoutMilliseconds = $TimeoutSeconds * 1000

# Reads one answer from .copier-answers.yml; nothing when the file doesn't set it.
function Get-Answer([string]$Key) {
    $match = Select-String -LiteralPath $answersFile -Pattern "^${Key}:\s*(.+?)\s*\z" | Select-Object -First 1
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
    foreach ($tag in Get-GitLines @('tag', '--list')) {
        if ("$tag" -notmatch '^v?([0-9]+)\.[0-9]+\.[0-9]+\z' -or [int]$Matches[1] -lt 1) { continue }
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

# Runs a program in a process of its own, its input closed so a program that would ask gets no answer instead of
# waiting, and gives { ExitCode; Out; Err }, its output and error lines. When it runs past -TimeoutSeconds, stops it
# and every process it started, and throws.
function Invoke-Process([string]$FileName, [string[]]$Arguments, [string]$WorkingDirectory, [string]$Label) {
    $start = [Diagnostics.ProcessStartInfo]::new($FileName)
    foreach ($a in $Arguments) { $start.ArgumentList.Add($a) }
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $process = [Diagnostics.Process]::Start($start)
    try {
        $process.StandardInput.Close()
        $out = $process.StandardOutput.ReadToEndAsync()
        $err = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($timeoutMilliseconds)) {
            # It may have exited just before the kill, which leaves nothing to stop.
            try { $process.Kill($true) }
            catch [InvalidOperationException] { Write-Verbose "$Label exited before it could be stopped." }
            $process.WaitForExit()
            throw "$Label timed out after $TimeoutSeconds s"
        }
        $process.WaitForExit()
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Out = @(($out.Result -replace '\r?\n\z') -split '\r?\n')
            Err = @($err.Result -split '\r?\n' | Where-Object { $_ })
        }
    }
    finally { $process.Dispose() }
}

# Runs a .ps1 command, such as the suite's stand-ins, in a runspace of its own in this process, as & did: a pwsh
# process for each would add a third of a second to every read. Gives { ExitCode; Out; Err } as Invoke-Process
# does; when it runs past -TimeoutSeconds, stops it and throws.
function Invoke-Script([string]$File, [string[]]$Arguments, [string]$WorkingDirectory, [string]$Label) {
    $body = {
        param([string]$File, [string[]]$Arguments, [string]$Folder)
        Set-Location -LiteralPath $Folder
        $global:LASTEXITCODE = 0
        $errors = [Collections.Generic.List[string]]::new()
        $out = @(& $File @Arguments 2>&1 | ForEach-Object {
                if ($_ -is [Management.Automation.ErrorRecord]) { $errors.Add("$_") } else { "$_" }
            })
        [pscustomobject]@{ ExitCode = $global:LASTEXITCODE; Out = $out; Err = $errors.ToArray() }
    }
    $shell = [powershell]::Create()
    try {
        $null = $shell.AddScript($body.ToString()).AddArgument($File).AddArgument($Arguments)
        $null = $shell.AddArgument($WorkingDirectory)
        $async = $shell.BeginInvoke()
        if (-not $async.AsyncWaitHandle.WaitOne($timeoutMilliseconds)) {
            $shell.Stop()
            throw "$Label timed out after $TimeoutSeconds s"
        }
        @($shell.EndInvoke($async))[0]
    }
    finally { $shell.Dispose() }
}

# Runs a command and keeps what it printed: Out is the output lines joined by newlines, Error the error text, and
# Status the HTTP status that gh names in it, or 0. ExitCode is -1 when the command isn't installed.
# FirstError is the first error line.
# Throws when the command runs past -TimeoutSeconds.
function Invoke-Tool([string]$Name, [string[]]$Arguments, [string]$WorkingDirectory) {
    $command = Get-Command $Name -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $command) {
        return [pscustomobject]@{
            ExitCode = -1; Out = ''; Error = "$Name isn't installed"; FirstError = "$Name isn't installed"; Status = 0
        }
    }
    $folder = if ($WorkingDirectory) { $WorkingDirectory } else { (Get-Location -PSProvider FileSystem).ProviderPath }
    $label = "$Name $($Arguments -join ' ')"
    $run = if ($command.CommandType -eq 'ExternalScript') { Invoke-Script $command.Source $Arguments $folder $label }
    else { Invoke-Process $command.Source $Arguments $folder $label }
    $errors = @($run.Err | ForEach-Object { "$_" -split '\r?\n' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $said = $errors -join ' '
    $status = if ($said -match 'HTTP ([0-9]{3})') { [int]$Matches[1] } else { 0 }
    [pscustomobject]@{
        ExitCode = $run.ExitCode
        Out = (@($run.Out) -join "`n")
        Error = $said
        FirstError = "$(@($errors)[0])"
        Status = $status
    }
}

# The output lines of a git command in the clone, whatever git's exit code, as the git calls it replaces read them.
function Get-GitLines([string[]]$Arguments) {
    @((Invoke-Tool 'git' (@('-C', $Path) + $Arguments)).Out -split "`n" | Where-Object { $_ })
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

# Runs one of the sibling scripts in tools/, which the baseline and Scorecard rows read with -WhatIf. Lines are its
# output lines, then its error lines; throws when it runs past -TimeoutSeconds.
function Invoke-Sibling([string]$Script, [string[]]$Arguments) {
    $folder = (Get-Location -PSProvider FileSystem).ProviderPath
    $file = Join-Path $PSScriptRoot $Script
    $run = Invoke-Process $pwsh (@('-NoProfile', '-File', $file) + $Arguments) $folder $Script
    [pscustomobject]@{ ExitCode = $run.ExitCode; Lines = @($run.Out) + @($run.Err) }
}

# The GitHub repository, from gh api.
function Get-Repo { Get-Cached 'repo' { Read-Gh @('api', "repos/$slug") } }

# Facts about the repository, read once.
$originRead = Invoke-Tool 'git' @('-C', $Path, 'remote', 'get-url', 'origin')
if ($originRead.ExitCode) { throw "Couldn't read the origin remote of ${Path}: $($originRead.Error)" }
$origin = $originRead.Out.Trim()
if ($origin -notmatch '^(?:(?:https?|ssh)://)?(?:[^@/]+@)?(?<host>[\w.-]+\.[\w-]+)(?::[0-9]+)?[:/](?<path>[\w.-]+(?:/[\w.-]+?)+?)(?:\.git)?/?\z') {
    throw "Couldn't tell the repository from the origin remote of ${Path}: '$origin'."
}
$originPath = $Matches['path']
$owner, $name = $originPath -split '/'
$slug = "$owner/$name"
$release = if ((Get-FileText 'AGENTS.md') -match '(?m)^- release:[ \t]*(\S+)') { $Matches[1] } else { 'none' }
$rootSubject = @(Get-GitLines @('log', '--max-parents=0', '--format=%s'))[-1]

# The rows of docs/adopt.md's section 8 Checklist, titled as its headings are.
$rows = @(
    @('0.1', 'Accounts and Tools'), @('0.2', "The Organization's Actions Policy"),
    @('0.3', "NCode Review's Organization Setup"),
    @('1.1', 'A New Project'), @('1.2', 'An Existing Repository'), @('1.3', 'Node.js: nvs and the Prelude'),
    @('1.4', 'First Push and First Pull Request'),
    @('2.1', 'Run the Baseline'), @('2.2', 'When an Approval Is Required'), @('2.3', "CodeQL's Languages"),
    @('2.4', 'Scorecard'),
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
    $noCopilot = -not (Test-Path -LiteralPath (Join-Path $Path '.github/workflows/copilot-setup-steps.yml'))
    if ($Step -eq '6.4' -and $noCopilot) {
        return 'without Copilot'
    }
    $null
}

# Reads a template version, v<major>.<minor>.<patch> or shorter, as Get-TemplateUpdate.ps1 does;
# $null when it isn't one.
# Its pattern and 7.1's address rewrites are Get-TemplateUpdate.ps1's:
# tests/Test-AdoptionChecklist.ps1 checks they match.
function ConvertTo-TemplateVersion([string]$Text) {
    if ($Text -notmatch '^v?([0-9]+(?:\.[0-9]+){0,3})\z') { return $null }
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

# The approvals the default branch's pull request rules require: the most any one requires, since GitHub enforces
# the strictest; $null when no rule requires a pull request.
function Get-RequiredApprovals {
    Get-Cached 'requiredApprovals' {
        $rules = Read-Gh @('api', "repos/$slug/rules/branches/$((Get-Repo).default_branch)")
        $counts = @(@($rules) | Where-Object { $_.type -eq 'pull_request' } |
                ForEach-Object { [int]$_.parameters.required_approving_review_count })
        if ($counts.Count) { [int]($counts | Measure-Object -Maximum).Maximum }
    }
}

# The approvals the baseline requires (ADR-0034, ADR-0036): 1 when NCode Review approves with the approver's key, or
# when approve: true and a second person can push; else 0.
function Get-ExpectedApprovals {
    if ($approve -and $approverKey -and ('NCODE_REVIEW_APPROVER_PRIVATE_KEY' -in @(Get-EnvSecretNames))) { return 1 }
    if ($approve) {
        $people = @(Read-Gh @('api', "repos/$slug/collaborators?affiliation=all&permission=push&per_page=$pageSize") |
                Where-Object { $_.type -eq 'User' })
        if ($people.Count -ge 2) { return 1 }
    }
    0
}

# The latest merged pull requests, newest first.
function Get-MergedPulls {
    Get-Cached 'mergedPulls' {
        @(Read-Gh @('pr', 'list', '--repo', $slug, '--state', 'merged', '--limit', "$mergedPullLimit",
                '--json', 'number,author'))
    }
}

# A result for a workflow's latest run: done when it succeeded, else not done with how it stands.
function Get-LatestRun([string]$Workflow) {
    $runs = @(Read-Gh @('run', 'list', '--repo', $slug, '--workflow', $Workflow, '--limit', '1',
            '--json', 'conclusion,status'))
    if (-not $runs.Count) { return New-Result 'not done' "no $Workflow run yet" }
    $run = $runs[0]
    if ($run.conclusion -eq 'success') { return New-Result 'done' }
    if (-not $run.conclusion) { return New-Result 'not done' "the latest $Workflow run is $($run.status)" }
    New-Result 'not done' "the latest $Workflow run ended $($run.conclusion)"
}

# The latest release; $null when there is none (a 404).
function Get-LatestRelease {
    Get-Cached 'latestRelease' { Read-Gh @('api', "repos/$slug/releases/latest") -Missing }
}

# The reviews of the latest merged pull request a person wrote, as a result; rows 5.3 and 5.4 share it.
function Get-ApprovalResult {
    Get-Cached 'approvalResult' {
        $pull = Get-MergedPulls | Where-Object { $_.author.is_bot -ne $true } | Select-Object -First 1
        if (-not $pull) { return New-Result 'not done' 'no merged pull request by a person yet' }
        $number = $pull.number
        $reviews = @(Read-Gh @('api', "repos/$slug/pulls/$number/reviews?per_page=$pageSize"))
        $approved = @($reviews |
                Where-Object { $_.user.login -eq 'ncode-review-approver[bot]' -and $_.state -eq 'APPROVED' })
        if ($approved.Count) { New-Result 'done' "#$number approved by ncode-review-approver[bot]" }
        else { New-Result 'not done' "#$number has no approval from ncode-review-approver[bot]" }
    }
}

# Row checks
$checks = @{}

$checks['0.1'] = {
    $parts = @()
    $auth = Invoke-Tool 'gh' @('auth', 'status')
    if ($auth.ExitCode) {
        $why = if ($auth.ExitCode -eq -1) { $auth.Error } else { "gh isn't signed in" }
        $parts += New-Result 'not done' $why
    }
    $copier = Invoke-Tool 'copier' @('--version')
    if ($copier.ExitCode) { $parts += New-Result 'not done' "copier: $($copier.Error)" }
    if (-not ($PSVersionTable.PSVersion -ge $minimumPowerShell)) {
        $parts += New-Result 'not done' "PowerShell $($PSVersionTable.PSVersion) is older than $minimumPowerShell"
    }
    $email = Invoke-Tool 'git' @('-C', $Path, 'config', 'user.email')
    if (-not $email.Out.Trim()) { $parts += New-Result 'not done' 'git has no user.email' }
    Join-Result (@($parts) + (New-Result 'done'))
}

$checks['1.1'] = {
    $version = "$(Get-FileText '.template-version')".Trim()
    if (-not $version) { return New-Result 'not done' 'no .template-version' }
    # Get-Repo throws when gh can't read the repository, which makes the row unreadable.
    $null = Get-Repo
    New-Result 'done' "template $version"
}

$checks['1.2'] = {
    $subject = Get-GitLines @('log', '--format=%s') | Where-Object { "$_".StartsWith('Adopt project-template ') } |
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
    $line = Get-BaselineLines | Where-Object { $_ -match ': immutable releases: (.+)\z' } | Select-Object -First 1
    if (-not $line) { return New-Result 'unreadable' 'the baseline printed no immutable releases line' }
    # Matches the line again to fill $Matches.
    $null = "$line" -match ': immutable releases: (.+)\z'
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
        $why = "the -OrganizationPolicy -WhatIf run exited $($org.ExitCode): $(Get-LastLine $org)"
        $parts += New-Result 'unreadable' $why
    }
    else {
        $set = @($org.Lines | Where-Object { $_ -match 'would set' })
        $parts += if ($set.Count) { New-Result 'not done' "$($set.Count) organization setting(s) to set" }
        else { New-Result 'done' }
    }
    $baseline = Get-Baseline
    if ($baseline.ExitCode) {
        $why = "the baseline's -WhatIf run exited $($baseline.ExitCode): $(Get-LastLine $baseline)"
        $parts += New-Result 'unreadable' $why
    }
    else {
        $line = $baseline.Lines | Where-Object { $_ -match 'organization two-factor requirement: (.+)\z' } |
            Select-Object -First 1
        if (-not $line) { $parts += New-Result 'unreadable' 'no two-factor line' }
        else {
            # Matches the line again to fill $Matches.
            $null = "$line" -match 'organization two-factor requirement: (.+)\z'
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
    if ($null -eq $count) {
        $why = "no rule requires a pull request on $((Get-Repo).default_branch)"
        return New-Result 'not done' $why
    }
    $expected = Get-ExpectedApprovals
    if ($count -eq $expected) { New-Result 'done' "requires $count approval(s)" }
    else { New-Result 'not done' "requires $count approval(s), expected $expected" }
}

$checks['5.2'] = {
    $count = Get-RequiredApprovals
    if ($null -eq $count) {
        $why = "no rule requires a pull request on $((Get-Repo).default_branch)"
        return New-Result 'not done' $why
    }
    if ($count -eq 1) { New-Result 'done' }
    else { New-Result 'not done' "requires $count approval(s), expected 1" }
}

# A workflow counts as CodeQL's setup when it runs on pull_request and a line that isn't a comment uses
# github/codeql-action/analyze@: the first such .yml or .yaml file in .github/workflows, by name, such as codeql.yml.
# tools/Set-RepositoryBaseline.ps1's Test-CodeQLWorkflow applies the same rules; a change to one belongs in both.
$checks['2.3'] = {
    $setup = Read-Gh @('api', "repos/$slug/code-scanning/default-setup")
    $codeqlWorkflow = $null
    $folder = Join-Path $Path '.github/workflows'
    if (Test-Path -LiteralPath $folder -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $folder -File | Where-Object { $_.Extension -in '.yml', '.yaml' } | Sort-Object Name) {
            $codeqlCode = [regex]::Replace("$(Get-Content -LiteralPath $file.FullName -Raw)", '(?m)^[ \t]*#.*$', '')
            $codeqlUses = $codeqlCode -match '(?m)^[ \t]*(-[ \t]+)?uses:[ \t]*[''"]?github/codeql-action/analyze@'
            $codeqlOnPullRequest = $codeqlCode -match '(?m)^[ \t]*pull_request[ \t]*:' -or
                $codeqlCode -match '(?m)^on:[ \t]*\[[^\]\r\n]*\bpull_request\b' -or
                $codeqlCode -match '(?m)^on:[ \t]*pull_request[ \t]*$'
            if ($codeqlUses -and $codeqlOnPullRequest) { $codeqlWorkflow = ".github/workflows/$($file.Name)"; break }
        }
    }
    if ($codeqlWorkflow) {
        if ($setup.state -eq 'configured') {
            $why = "CodeQL's default setup is on, which refuses ${codeqlWorkflow}'s results: run Set-RepositoryBaseline.ps1"
            return New-Result 'not done' $why
        }
        return New-Result 'done' "$codeqlWorkflow runs CodeQL; the default setup is off"
    }
    $languages = @($setup.languages | Where-Object { $_ })
    if ($setup.state -eq 'configured' -and $languages.Count) {
        $why = "configured: $($languages -join ', ')"
        return New-Result 'done' $why
    }
    $analyzing = if ($languages.Count) { $languages -join ', ' } else { 'no language' }
    New-Result 'not done' "$($setup.state), analyzing $analyzing"
}

$checks['5.1'] = {
    $parts = @()
    if ('NCODE_REVIEW_APPROVER_PRIVATE_KEY' -notin @(Get-EnvSecretNames)) {
        $parts += New-Result 'not done' 'the code-review environment has no NCODE_REVIEW_APPROVER_PRIVATE_KEY'
    }
    if (-not ($approve -and $approverKey)) {
        $why = ".github/workflows/code-review.yml doesn't pass approve: true and approver-private-key"
        $parts += New-Result 'not done' $why
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
    $currentText = if ($null -ne $versionFile) { "$(@($versionFile -split '\r?\n')[0])".Trim() }
    else { Get-Answer '_commit' }
    # A version between tags, such as v0.12.0-3-gabc1234, is the tag before the first dash.
    $currentTag = "$currentText" -replace '-.*$'
    $current = ConvertTo-TemplateVersion $currentTag
    if (-not $current) { throw "can't read the project's template version from .template-version ('$currentText')" }
    $src = Get-Answer '_src_path'
    if (-not $src) { throw '.copier-answers.yml has no _src_path' }
    # Copier's shorthands, and the template's old address, which GitHub only redirects,
    # as Get-TemplateUpdate.ps1 reads them.
    if ($src -match '^gh:(.+)\z') { $src = "https://github.com/$($Matches[1])" }
    elseif ($src -match '^gl:(.+)\z') { $src = "https://gitlab.com/$($Matches[1])" }
    if ($src -match '^https://github\.com/polewskm/project-template(?:\.git)?/?\z') {
        $src = 'https://github.com/NCodeGroup/project-template.git'
    }
    # A template folder that isn't here, such as the clone the project was created from on another PC.
    if ($src -notmatch '^(?:[A-Za-z][A-Za-z0-9+.-]+://|gh:|gl:|[^@/\\\s]+@[^:/\\\s]+:)' -and -not (Test-Path -LiteralPath $src -PathType Container)) {
        $src = 'https://github.com/NCodeGroup/project-template.git'
    }
    $r = Invoke-Tool 'git' @('ls-remote', '--tags', '--refs', '--', $src)
    if ($r.ExitCode) { return New-Result 'unreadable' "couldn't read the template's tags at ${src}: $($r.Error)" }
    $newest = $null
    foreach ($ref in $r.Out -split "`n") {
        if ($ref -match 'refs/tags/(.+)\z') {
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
        $why = "#${number}: $(@($failing | ForEach-Object { "$($_.name) ($($_.bucket))" }) -join ', ')"
        return New-Result 'not done' $why
    }
    New-Result 'done' "#${number}: $($reported.Count) checks passed"
}

$checks['3.1'] = {
    $parts = @(Get-LatestRun 'tag-release.yml')
    try {
        $latest = Get-LatestRelease
        if ($null -eq $latest) { $parts += New-Result 'not done' 'no release yet' }
        else { $parts += New-Result 'done' "$($latest.tag_name)" }
    }
    catch { $parts += New-Result 'unreadable' "$($_.Exception.Message)" }
    Join-Result $parts
}

# gitsign exits 1 for any failure, so only its message tells a tag it refuses from a check that couldn't run. These
# messages come from gitsign's verify-tag and verifier and cosign's certificate check; any other error, such as
# reading TUF, Fulcio or Rekor failing, leaves row 3.2 unreadable.
$gitsignRefusal = @(
    'none of the expected identities matched'             # another workflow, branch or issuer signed it
    'failed to verify (?:detached|attached) signature'    # the signature or its certificate chain doesn't verify
    'failed to parse signature'                           # the signature isn't one gitsign can read
    'error getting signature certs'                       # the signature's certificates can't be read
    'no certificates found in signature'                  # the signature carries no certificate
    'no verified certificate chains returned'             # its certificate doesn't chain to Fulcio's root
    'tag has no in-body signature'                        # the annotated tag isn't signed
    'unsupported signature type'                          # signed, but not by gitsign, such as with GPG or SSH
    'error reading tag object: object not found'          # a lightweight tag, which has no signature
) -join '|'

$checks['3.2'] = {
    $tag = Get-GitLines @('tag', '--list', 'v*', '--sort=-version:refname') | Select-Object -First 1
    if (-not $tag) { return New-Result 'not done' 'no release tag in the clone' }
    $identity = "https://github.com/$slug/.github/workflows/tag-release.yml@refs/heads/$((Get-Repo).default_branch)"
    $r = Invoke-Tool 'gitsign' @('verify-tag', '--certificate-identity', $identity,
        '--certificate-oidc-issuer', 'https://token.actions.githubusercontent.com', "$tag") -WorkingDirectory $Path
    if ($r.ExitCode -eq -1) { return New-Result 'unreadable' "gitsign isn't installed" }
    if ($r.ExitCode -eq 0) { return New-Result 'done' "$tag verified" }
    if ($r.Error -match $gitsignRefusal) { return New-Result 'not done' "gitsign refused ${tag}: $($r.Error)" }
    $first = if ($r.FirstError) { $r.FirstError -replace '^Error: ' } else { "exit $($r.ExitCode)" }
    New-Result 'unreadable' "gitsign couldn't check ${tag}: $first"
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
    $pulls = @(Read-Gh @('pr', 'list', '--repo', $slug, '--head', "baseline-$version", '--state', 'merged',
            '--json', 'number'))
    if ($pulls.Count) { New-Result 'done' "#$($pulls[0].number) merged" }
    else { New-Result 'not done' "no merged pull request from baseline-$version" }
}

$checks['4.7'] = {
    $latest = Get-LatestRelease
    if ($null -eq $latest) { return New-Result 'not done' 'no release yet' }
    $tag = "$($latest.tag_name)"
    $assets = @(@($latest.assets) | ForEach-Object { "$($_.name)" })
    $missing = @()
    if (-not @($assets | Where-Object { $_.EndsWith('.nupkg') })) { $missing += 'a .nupkg' }
    if (-not @($assets | Where-Object { $_.EndsWith('.snupkg') })) { $missing += 'a .snupkg' }
    foreach ($suffix in 'intoto.jsonl', 'spdx.json') {
        if ("$tag.$suffix" -notin $assets) { $missing += "$tag.$suffix" }
    }
    if ($missing.Count) { return New-Result 'not done' "$tag lacks $($missing -join ', ')" }
    New-Result 'done' "$tag has its packages, provenance and SBOM"
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
    $labels = @(Read-Gh @('label', 'list', '--repo', $slug, '--json', 'name', '--limit', "$labelLimit") |
            ForEach-Object { $_.name })
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
Write-Host ("${slug}: $($counts['done']) done, $($counts['not done']) not done, " +
    "$($counts['unreadable']) unreadable, $($counts['does not apply']) do not apply")
if ($counts['not done']) { exit 1 }
exit 0
