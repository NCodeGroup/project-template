<#
.SYNOPSIS
    Bring an existing repository under the project template: work out the template's answers from the repository,
    apply the template, and commit the result.

.DESCRIPTION
    Works out the template's answers from what the repository already has (stack, project name, git host, workflow tools, authors,
    build and test commands), applies -Data over them, and runs `copier copy --overwrite --defaults` into the
    repository (Copier from PATH, or through uvx). The answers are recorded in .copier-answers.yml, so the project
    can update itself with .\.template\Update-Project.ps1 afterwards. A merged file that -Data's project_owned_files names is kept exactly as the repository has it, and later updates show the template's changes to it instead of merging them.

    The repository must be the root of a Git repository with no uncommitted changes and no .copier-answers.yml.
    The result is one commit, "Adopt project-template <version>"; -NoCommit stages it instead. Before committing, the
    build and test commands from the answers run in the repository; if one fails, the adoption stays staged and
    nothing is committed. -NoVerify skips that check. If anything else fails after the template is applied, the
    repository is reset to where it was.

    It enables the template's Git hooks (core.hooksPath .githooks), so .githooks/commit-msg strips AI agent
    attribution from commit messages, unless the repository already has a hooks path, hooks in .git/hooks, or uses
    pre-commit; then it leaves them as they are and warns, naming the command that runs the template's hooks.

.EXAMPLE
    .\Adopt-Project.ps1 -Path C:\src\buffers
    .\Adopt-Project.ps1 -Path C:\src\buffers -Data @{ workflow_tools = 'claude', 'copilot' }
    .\Adopt-Project.ps1 -Path C:\src\buffers -Data @{ project_owned_files = '.github/workflows/ci.yml' }
    .\Adopt-Project.ps1 -Path C:\src\buffers -NoCommit
    .\Adopt-Project.ps1 -Path C:\src\buffers -NoVerify
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [string]$Template = 'https://github.com/NCodeGroup/project-template.git',
    [string]$Ref,
    [hashtable]$Data = @{},
    [switch]$NoCommit,
    [switch]$NoVerify
)
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'tools\adopt\Adoption.psm1') -Force

function Invoke-Copier {
    if (Get-Command copier -ErrorAction SilentlyContinue) { & copier @args }
    elseif (Get-Command uvx -ErrorAction SilentlyContinue) { & uvx --from copier copier @args }
    else { throw 'Copier not found. Install it with: uv tool install copier' }
    if ($LASTEXITCODE) { throw "copier exited with code $LASTEXITCODE." }
}

# Copier reads --data values as YAML, so a list answer goes as a flow sequence: [claude, copilot].
function ConvertTo-CopierValue($Value) {
    if ($Value -is [Collections.IList]) { '[' + ($Value -join ', ') + ']' } else { "$Value" }
}

function Get-Answer([string]$Key) {
    $match = Select-String -LiteralPath .copier-answers.yml -Pattern "^${Key}:\s*(.+?)\s*$" | Select-Object -First 1
    if ($match) { $match.Matches[0].Groups[1].Value.Trim("'", '"') }
}

function Get-NormalPath([string]$Value) {
    [IO.Path]::GetFullPath($Value).TrimEnd('\', '/')
}

if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "$Path isn't a folder." }
$project = (Resolve-Path -LiteralPath $Path).Path
if ($Template -eq '.') { $Template = $PSScriptRoot }
$outputEncoding = [Console]::OutputEncoding
Push-Location -LiteralPath $project
try {
    # Read Git's output as UTF-8, so file names keep their characters.
    try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { Write-Verbose "Couldn't set the console's output encoding: $_" }
    $top = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -or -not $top -or (Get-NormalPath $top) -ne (Get-NormalPath $project)) { throw "$project isn't the root of a Git repository." }
    if (Test-Path -LiteralPath .copier-answers.yml) { throw "$project already uses the project template; update it with .\.template\Update-Project.ps1." }
    if (git status --porcelain) { throw "$project has uncommitted changes. Commit or stash them first." }
    foreach ($key in 'user.name', 'user.email') {
        if (-not (git config $key)) { throw "Git has no $key. Set it with: git config --global $key ""<value>""" }
    }

    $merged = @(Get-CopierList (Join-Path $PSScriptRoot 'copier.yml') '_merged_files')
    $answers = Get-AdoptionAnswers $project
    $adapters = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'tools\adopt\legacy') -Filter '*.ps1' -File | Sort-Object Name | Where-Object { & $_.FullName -Path $project -Phase Detect })
    foreach ($adapter in $adapters) {
        "Found $($adapter.BaseName)"
        $adapterAnswers = & $adapter.FullName -Path $project -Phase Answers
        foreach ($k in $adapterAnswers.Keys) { $answers[$k] = $adapterAnswers[$k] }
    }
    foreach ($k in $Data.Keys) { $answers[$k] = $Data[$k] }
    # Merged files the repository owns (its project_owned_files answer): Copier leaves them as they are, and updates show the template's changes to them.
    $ownedMerged = @()
    if ($answers.Contains('project_owned_files')) { $ownedMerged = Get-OwnedMergedFile $answers['project_owned_files'] $merged; $answers['project_owned_files'] = $ownedMerged }
    'Answers:'
    foreach ($k in $answers.Keys) {
        if ($null -ne $answers[$k]) { "  ${k}: $(ConvertTo-CopierValue $answers[$k])" }
    }
    if (-not $answers.Contains('workflow_tools')) { "  workflow_tools: [claude, copilot], the template's default: the repository has no Copilot or Hybrid agent files. To add the Hybrid agents, which use the shack PC's private model, pass -Data @{ workflow_tools = 'claude', 'copilot', 'local' }" }

    # Copier overwrites the merged files, so keep the repository's versions to merge back afterwards.
    $originals = @{}
    foreach ($p in $merged + 'AGENTS.md' + 'Directory.Build.props') {
        if (Test-Path -LiteralPath $p -PathType Leaf) { $originals[$p] = [IO.File]::ReadAllText((Join-Path $project $p)) }
    }

    # Without a commit to go back to, a failed adoption couldn't be rolled back.
    $head = git rev-parse HEAD 2>$null
    if ($LASTEXITCODE -or -not $head) { throw "$project has no commits yet. Make the first commit, then adopt it." }

    try {
        $copierArgs = @('copy', '--overwrite', '--defaults', '--quiet')
        if ($Ref) { $copierArgs += '--vcs-ref', $Ref }
        foreach ($k in $answers.Keys) {
            if ($null -ne $answers[$k]) { $copierArgs += '--data', "$k=$(ConvertTo-CopierValue $answers[$k])" }
        }
        # A merged file the repository owns stays exactly as it is.
        foreach ($file in $ownedMerged) { $copierArgs += '--exclude', $file }
        $copierArgs += $Template, $project
        Invoke-Copier @copierArgs

        $utf8 = [Text.UTF8Encoding]::new($false)
        $report = [Collections.Generic.List[string]]::new()
        foreach ($p in $merged) {
            if (-not $originals.ContainsKey($p)) { continue }
            if ($p -in $ownedMerged) { $report.Add("  Owned $p $([char]0x2014) kept as the repository had it (project_owned_files)"); continue }
            $full = Join-Path $project $p
            $result = Merge-AdoptedFile $p $originals[$p] ([IO.File]::ReadAllText($full))
            [IO.File]::WriteAllText($full, $result.Text, $utf8)
            $report.Add("  $($result.Strategy) $p" + $(if ($result.Note) { " $([char]0x2014) $($result.Note)" } else { '' }))
        }
        if ($originals.ContainsKey('AGENTS.md')) {
            [IO.File]::WriteAllText((Join-Path $project 'AGENTS.md'), (Add-TemplateIndexEntry $originals['AGENTS.md']), $utf8)
        }
        if ($originals.ContainsKey('Directory.Build.props') -and (Test-Path -LiteralPath build\ProjectTemplate.props)) {
            [IO.File]::WriteAllText((Join-Path $project 'Directory.Build.props'), (Add-ProjectTemplateImport $originals['Directory.Build.props']), $utf8)
        }
        foreach ($adapter in $adapters) {
            foreach ($line in @(& $adapter.FullName -Path $project -Phase Apply)) { $report.Add("  $line") }
        }
        if ((Test-Path -LiteralPath Directory.Packages.props) -and -not $originals.ContainsKey('Directory.Packages.props')) {
            foreach ($line in @(Move-PackageVersionsToCentral $project)) { $report.Add("  $line") }
        }

        $followUps = [Collections.Generic.List[string]]::new()
        if (Test-Path -LiteralPath .github/copilot-instructions.md) { $followUps.Add('fold .github/copilot-instructions.md into AGENTS.md or a file it lists') }
        # A ci.yml the repository already had was kept, so its other workflows are not in conflict with the template's.
        if ((Test-Path -LiteralPath .github/workflows/ci.yml) -and -not $originals.ContainsKey('.github/workflows/ci.yml')) {
            # code-review.yml is the template's own workflow for the review bot, separate from CI by design: nothing to reconcile.
            foreach ($f in Get-ChildItem -LiteralPath .github/workflows -File | Where-Object { $_.Extension -in '.yml', '.yaml' -and $_.Name -notin 'ci.yml', 'code-review.yml' } | Sort-Object Name) {
                $followUps.Add("reconcile .github/workflows/$($f.Name) with ci.yml")
            }
        }
        # A CI file the repository already had was kept, so it lacks the template's commit-attribution job.
        foreach ($p in '.github/workflows/ci.yml', '.gitlab-ci.yml') {
            if ($originals.ContainsKey($p) -and -not [IO.File]::ReadAllText((Join-Path $project $p)).Contains('Test-CommitAttribution.ps1')) {
                $followUps.Add("add the template's commit-attribution job to $p, so CI rejects commits attributed to an AI agent")
            }
        }
        # The repository's own changelog stays as it is; plans keep its style until a plan converts it.
        if ((Test-Path -LiteralPath CHANGELOG.md -PathType Leaf) -and -not (Test-KeepAChangelog ([IO.File]::ReadAllText((Join-Path $project 'CHANGELOG.md'))))) {
            $followUps.Add('convert CHANGELOG.md to Keep a Changelog 1.1.0 (https://keepachangelog.com/en/1.1.0/), keeping every entry')
        }
        # Version tags the changelog has no section for, such as releases from before it started.
        $backfill = Get-ChangelogBackfill
        if ($backfill.Range -ne '-') { $followUps.Add("backfill $($backfill.File) from the releases $($backfill.Range)") }
        if ((Get-Answer 'stack') -eq 'dotnet') {
            $otherInstructions = @(Get-ChildItem -LiteralPath .github/instructions -Filter '*.instructions.md' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin 'csharp.instructions.md', 'project-template.instructions.md' } | Sort-Object Name | ForEach-Object Name)
            if ($otherInstructions.Count) { $followUps.Add("reconcile .github/instructions/csharp.instructions.md with $($otherInstructions -join ', ')") }
            # The template's build settings are a new import, so each list of the build's files must admit them.
            if (Test-Path -LiteralPath build/ProjectTemplate.props) {
                $buildLists = @(Get-BuildFileList $project)
                if ($buildLists.Count) { $followUps.Add("re-admit Directory.Build.props and build/ProjectTemplate.props, which it imports, in each list of the build's files: $($buildLists -join ', ')") }
            }
        }

        git add -A
        # Executable on Linux and macOS; Windows doesn't record the bit on its own.
        if (Test-Path -LiteralPath .githooks/commit-msg) { git update-index --chmod=+x .githooks/commit-msg }
        if (Test-Path -LiteralPath .githooks/pre-push) { git update-index --chmod=+x .githooks/pre-push }
        # The template's versioned hooks, unless the repository already has a hooks path or runs hooks another way
        # (Get-GitHooksSetup): then a warning, because without them nothing strips AI agent attribution before a push.
        $hooksNote = $null
        if (Test-Path -LiteralPath .githooks) {
            $hooksSetup = Get-GitHooksSetup
            if ($hooksSetup.HooksPath) { git config core.hooksPath .githooks }
            else { $hooksNote = $hooksSetup.Note }
        }
    }
    catch {
        git reset -q --hard $head
        git clean -fdq
        throw "Adopting $project failed and was rolled back: $($_.Exception.Message)"
    }

    $version = Get-Answer '_commit'
    ''
    "Adopted project-template $version in ${project}:"
    git status --porcelain | ForEach-Object { "  $_" }
    if ($report.Count) { ''; "Merged with the repository's own files:"; $report }
    if ($hooksNote) { ''; Write-Warning $hooksNote }

    # A GitHub repository's default branch should take changes only through pull requests. The baseline script changes the
    # repository's settings on GitHub, which an adoption that only commits locally shouldn't do on its own, so print it.
    $origin = "$(git remote get-url origin 2>$null)"
    if ($origin -match '^(?:https://github\.com/|git@github\.com:)([^/]+)/([^/]+?)(?:\.git)?/?$') {
        # The next -match overwrites $Matches.
        $owner, $repo = $Matches[1], $Matches[2]
        $ci = if (Test-Path -LiteralPath .github/workflows/ci.yml) { Get-Content -Raw -LiteralPath .github/workflows/ci.yml } else { '' }
        $checks = if ($ci -match '(?m)^  build-and-test:' -and $ci.Contains('name: Commit attribution')) { " -RequireChecks 'build-and-test,Commit attribution'" } else { '' }
        ''
        "Protect the default branch, so changes reach it only through a pull request. From the template's clone, run:"
        "  $(Join-Path $PSScriptRoot 'tools/Set-RepositoryBaseline.ps1') -Repo $repo -Owner $owner$checks"
        if (-not $checks) { "  (this repository keeps its own CI: add -RequireChecks '<the jobs that run on pull requests>', comma-separated)" }
    }

    if ($followUps.Count) {
        ''
        "Still to do $([char]0x2014) in the repository, run:"
        "  /plan-migration Finish adopting the project template: $($followUps -join '; ')"
    }

    ''
    if (-not $NoVerify) {
        foreach ($key in 'build_command', 'test_command') {
            $command = Get-Answer $key
            if ($null -eq $command -or $command -in '', "''", '""', 'null') { continue }
            "Running $command"
            $output = pwsh -NoProfile -Command $command 2>&1 | Out-String
            if ($LASTEXITCODE) {
                @($output -split '\r?\n' | Where-Object { $_ -ne '' }) | Select-Object -Last 30
                "`"$command`" fails after adopting. The adoption is staged, not committed: fix it and commit, or abandon it with: git reset --hard; git clean -fd"
                exit 1
            }
        }
        ''
    }
    $message = "Adopt project-template $version"
    if ($NoCommit) { 'Staged, not committed. Review it with: git diff --cached --stat'; return }
    $messageFile = [IO.Path]::GetTempFileName()
    try {
        $body = if ($report.Count) { "`n`n" + ($report -join "`n") } else { '' }
        [IO.File]::WriteAllText($messageFile, "$message$body`n", $utf8)
        git commit -q -F $messageFile
        if ($LASTEXITCODE) { throw 'The commit failed.' }
    }
    finally { Remove-Item -LiteralPath $messageFile -Force -ErrorAction SilentlyContinue }
    "Committed `"$message`". Review it with: git show --stat"
}
finally {
    Pop-Location
    try { [Console]::OutputEncoding = $outputEncoding } catch { Write-Verbose "Couldn't restore the console's output encoding: $_" }
}
