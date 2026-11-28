<#
.SYNOPSIS
    Bring an existing repository under the project template: work out the template's answers from the repository,
    apply the template, and commit the result.

.DESCRIPTION
    Works out the template's answers from what the repository already has (stack, project name, workflow tools, authors,
    build and test commands), applies -Data over them, and runs `copier copy --overwrite --defaults` into the
    repository (Copier from PATH, or through uvx). The answers are recorded in .copier-answers.yml, so the project
    can update itself with .\.template\Update-Project.ps1 afterwards. When -Template is a local clone of the template, such as ., the answers name the clone's origin remote as the template's address instead of its folder, so the project updates from any PC; a clone without an origin address keeps the folder, with a warning. The answers include pre_release = tracked, so an AGENTS.md the template writes, for a repository that has none, says pre-release: tracked, since the repository has a history (ADR-0015); Copier records that answer nowhere. A repository whose own AGENTS.md the adoption keeps gets the release_policy answer from that file's Landing section, none without a release line, so SECURITY.md describes signed release tags only when something makes them; Copier records that answer nowhere either. A repository that uses Node.js without being a Node.js project answers uses_node, and a .nvmrc without a .node-version gives .node-version its version (ADR-0200). A merged or template-owned file that -Data's project_owned_files names is kept exactly as the repository has it, and later updates show the template's changes to it instead of merging or replacing it; the answer can't name .copier-answers.yml, .template-version or a file in .template/.

    The repository must be the root of a Git repository with no uncommitted changes and no .copier-answers.yml. Its origin remote, when it has one, must be on GitHub, and -Data can't answer git_host other than github: the template is for NCodeGroup's GitHub repositories only (ADR-0040).
    The result is one commit, "Adopt project-template <version>"; -NoCommit stages it instead. Before committing, the
    build and test commands from the answers run in the repository; if one fails, the adoption stays staged and
    nothing is committed. -NoVerify skips that check. If anything else fails after the template is applied, the
    repository is reset to where it was.

    It enables the template's Git hooks (core.hooksPath .githooks), so .githooks/pre-push runs, unless the
    repository already has a hooks path, hooks in .git/hooks, or uses pre-commit; then it leaves them as they are and warns, naming the command that runs the template's hooks.

    When its origin remote names a GitHub repository whose name doesn't fit NCodeGroup's rule for the stack answer
    (NCodeGroup/.github ADR-1001, the template's ADR-0045): for stack dotnet, the root namespace's PascalCase segments
    joined by '.', without a leading NCode., and for every other stack, lowercase kebab case, it prints a note with the
    name that fits and what a rename touches. It renames nothing.

    A repository whose own workflow already runs CodeQL, a line that isn't a comment using
    github/codeql-action/analyze@, keeps it and gets no .github/workflows/codeql.yml, and the report says so (the
    template's ADR-0044).

    When the repository keeps its own .github/workflows/publish.yml without a workflow_dispatch trigger and gets
    .github/workflows/tag-release.yml, it prints the warning .\.template\Update-Project.ps1 prints: the Tag and publish
    release workflow starts publish.yml through that trigger, so until it has one, a release ships no packages.

    When the nuget_publisher answer names a library's own publishing workflows, the AGENTS.md the adoption leaves says
    release: tag+release and the repository gets .github/workflows/tag-release.yml, it prints the note
    .\.template\Update-Project.ps1 prints for each of those workflows without a workflow_dispatch trigger, or that
    doesn't exist: tag-release.yml starts them through that trigger, so until each has it, a release ships no packages.

    When the repository is a .NET library on GitHub with .github/workflows/tag-release.yml and the AGENTS.md the
    adoption leaves says release: none or tag, or has no release line, it prints the note
    .\.template\Update-Project.ps1 prints with the one-line change to - release: tag+release, unless a workflow the
    nuget_publisher answer names has no workflow_dispatch trigger or doesn't exist.

    When that publish.yml doesn't call .github/workflows/release-provenance.yml or
    .github/workflows/raise-baseline.yml, or both, which the adoption added and which no longer start on workflow_run,
    it prints the warning .\.template\Update-Project.ps1 prints (ADR-0151): until publish.yml calls each, no release
    gets the provenance or the baseline pull request the missing one makes.

    When tag-release.yml calls a ci.yml the repository kept, it prints the notes .\.template\Update-Project.ps1 prints when that ci.yml has no workflow_call trigger, or when its top-level permissions or a job's ask for more than contents: read, which tag-release.yml grants it: until then, no release is tagged (ADR-0026).

    When the repository has version.json, it prints the note .\.template\Update-Project.ps1 prints for each job of the repository's own workflows, other than publish.yml, that builds in the folder of an actions/checkout step without fetch-depth: 0, or with a -p:Version argument, which Nerdbank.GitVersioning fails on or ignores (ADR-0138).

    When the SECURITY.md the adoption leaves says releases are immutable and a workflow in .github/workflows runs on a
    release event or uploads release assets, it prints the note .\.template\Update-Project.ps1 prints: delete that
    paragraph, since the template's tools/Set-RepositoryBaseline.ps1 leaves such a repository's releases mutable
    (ADR-0028).

    It answers license blank, never copier.yml's Apache-2.0 default, when it works out no license and -Data gives none, so it never chooses a license for existing code (ADR-0024). With no LICENSE or COPYING file at the root, it prints the warning .\.template\Update-Project.ps1 prints: for a blank answer with the command that adds Apache-2.0, for any other answer saying to add that license's text.

    For a library it lists the stale NuGet logistics it finds as follow-ups (Get-NuGetLogistics): a .props file no project imports, GeneratePackageOnBuild, settings the template already makes, a .sln, a UTF-8 BOM and projects at the repository root, and the package Description and PackageTags that differ from the newest published package (Get-PackageMetadataDrift).

    For a .NET repository whose .config/dotnet-tools.json names CSharpier, it lists each of the repository's own build/*.ps1 scripts that runs dotnet csharpier check as a follow-up (Get-CSharpierWrapper), because the adopted build/dod.ps1 runs that check in its Format stage.

    When the repository references Nerdbank.GitVersioning itself and build/ProjectTemplate.props references it too, as a library's does once version.json exists, it drops the repository's own PackageReference (and a second PackageVersion in Directory.Packages.props) and reports it, because two references fail the build with NU1504 or NU1506 (ADR-0138). A repository that isn't a library keeps its own reference, its only one.

.EXAMPLE
    .\Adopt-Project.ps1 -Path C:\src\Buffers
    .\Adopt-Project.ps1 -Path C:\src\Buffers -Data @{ workflow_tools = 'claude', 'copilot' }
    .\Adopt-Project.ps1 -Path C:\src\Buffers -Data @{ project_owned_files = '.github/workflows/ci.yml' }
    .\Adopt-Project.ps1 -Path C:\src\Buffers -NoCommit
    .\Adopt-Project.ps1 -Path C:\src\Buffers -NoVerify
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

# The events a workflow's top-level on: key names, in order: one event (on: push), a list in brackets, the keys or items
# indented below it, or - items at its own indent, with quotes, comments and blank lines allowed. A mapping in braces, or
# no on: key, gives none.
# A copy of .template/Update-Project.ps1's; tests/Test-UpdateNotes.ps1 keeps the copies equal.
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
# A copy of .template/Update-Project.ps1's; tests/Test-UpdateNotes.ps1 keeps the copies equal.
function Test-ReleaseAssetWorkflow([string]$Text) {
    $code = $Text -replace '(?m)^\s*#.*$', ''
    [bool](((Get-WorkflowEvents $Text) -contains 'release') -or ($code -match 'gh\s+release\s+upload|upload-release-asset|uploadReleaseAsset|action-gh-release'))
}

# SECURITY.md's Verify a Release section says releases are immutable, which the template's
# tools/Set-RepositoryBaseline.ps1 leaves off where a workflow runs on a release event or uploads release assets
# (ADR-0028).
# A copy of .template/Update-Project.ps1's; tests/Test-UpdateNotes.ps1 keeps the copies equal.
function Get-ImmutableReleaseNote([bool]$Offered) {
    $says = (Test-Path -LiteralPath SECURITY.md) -and (Get-Content -LiteralPath SECURITY.md -Raw) -match '(?m)^Releases are immutable'
    if (-not ($says -or $Offered) -or -not (Test-Path -LiteralPath .github/workflows)) { return }
    $files = @(Get-ChildItem -LiteralPath .github/workflows -File | Where-Object { $_.Name -match '\.ya?ml$' -and (Test-ReleaseAssetWorkflow (Get-Content -LiteralPath $_.FullName -Raw)) } | ForEach-Object { ".github/workflows/$($_.Name)" })
    if (-not $files) { return }
    ''
    "$(if ($says) { 'SECURITY.md says' } else { 'The template''s change to SECURITY.md above says' }) releases are immutable, but $($files -join ', ') run on a release event or upload release assets, which an immutable release refuses once it is published, so the template's tools/Set-RepositoryBaseline.ps1 leaves this repository's releases mutable (the template's ADR-0028, in docs/decisions/project-template/). $(if ($says) { 'Delete' } else { 'Leave out' }) the paragraph of its Verify a Release section that starts `"Releases are immutable`"."
}

# A library whose own workflows publish its packages (the nuget_publisher answer), with release: tag+release: tag-release.yml starts each through workflow_dispatch once it publishes a release, so one without that trigger ships no packages (the template's ADR-0137).
# A copy of .template/Update-Project.ps1's; tests/Test-UpdateNotes.ps1 keeps the copies equal. Get-ReleasePolicyAnswer comes from tools/adopt/Adoption.psm1.
function Get-PublisherDispatchNote {
    if ((Get-ReleasePolicyAnswer) -ne 'tag+release' -or -not (Test-Path -LiteralPath .github/workflows/tag-release.yml)) { return }
    foreach ($workflow in @("$(Get-Answer 'nuget_publisher')" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        if (-not (Test-Path -LiteralPath $workflow -PathType Leaf)) {
            ''
            "$workflow, which the nuget_publisher answer names as this library's publishing workflow, doesn't exist. AGENTS.md says release: tag+release, so .github/workflows/tag-release.yml starts each workflow that answer names once it publishes a release, and that run fails for $workflow. Name the workflows that publish this library's packages in the nuget_publisher answer, or restore $workflow (the template's ADR-0137)."
            continue
        }
        if (@(Get-WorkflowEvents (Get-Content -LiteralPath $workflow -Raw)) -contains 'workflow_dispatch') { continue }
        ''
        "$workflow publishes this library's NuGet packages (the nuget_publisher answer) and has no workflow_dispatch trigger. AGENTS.md says release: tag+release, so .github/workflows/tag-release.yml publishes each release with the workflow's token, which starts no other workflow, and then starts $workflow through workflow_dispatch on the release's tag; until $workflow has that trigger, that run fails and a release ships no packages. Add workflow_dispatch to its on: section, and read the tag from inputs.tag, when it declares a tag input, or else github.ref_name, when the run has no release (the template's ADR-0137)."
    }
}

# A .NET library on GitHub whose AGENTS.md says release: none or tag, or has no release line, publishes nothing as a release's pull request merges, though the template gives it tag+release (the template's ADR-0016 and ADR-0137).
# A copy of .template/Update-Project.ps1's; tests/Test-UpdateNotes.ps1 keeps the copies equal. Get-ReleasePolicyAnswer comes from tools/adopt/Adoption.psm1.
function Get-ReleasePolicyNote {
    if ((Get-Answer 'nuget_package') -ne 'true' -or (Get-Answer 'git_host') -ne 'github' -or -not (Test-Path -LiteralPath .github/workflows/tag-release.yml)) { return }
    $policy = Get-ReleasePolicyAnswer
    if ($policy -notin 'none', 'tag') { return }
    $publishers = @("$(Get-Answer 'nuget_publisher')" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($workflow in $publishers) {
        if (-not (Test-Path -LiteralPath $workflow -PathType Leaf) -or @(Get-WorkflowEvents (Get-Content -LiteralPath $workflow -Raw)) -notcontains 'workflow_dispatch') { return }
    }
    $merge = if ($policy -eq 'none') { 'tags nothing, publishes no GitHub release' } else { 'tags the release but publishes no GitHub release' }
    $starts = if ($publishers.Count) { "$($publishers -join ', '), this library's own publishing workflow$(if ($publishers.Count -gt 1) { 's' })" } else { '.github/workflows/publish.yml, which publishes the packages to nuget.org once a maintainer approves the nuget environment' }
    ''
    "AGENTS.md's Landing section says release: $policy, so merging a release's pull request $merge and starts no publishing workflow. The template gives a .NET library on GitHub release: tag+release, under which .github/workflows/tag-release.yml tags each release and publishes its GitHub release from the changelog as its pull request merges, then starts $starts (the template's ADR-0016 and ADR-0137, in docs/decisions/project-template/). To publish on merge, change the release line of AGENTS.md's Landing section to:"
    '  - release: tag+release'
    "The first run after that change publishes nothing while the changelog's newest release section is already tagged and has its GitHub release; when that tag has no GitHub release yet, the run publishes it and starts the publishing workflow for it. SECURITY.md can then say how to verify a release tag's gitsign signature, as the SECURITY.md the template gives a library with release: tag+release does (the template's ADR-0028)."
    "./.template/Publish-Release.ps1 -Policy then prints tag+release, the policy tag-release.yml reads. The change ships nothing, so it gets no Release: line: record it under the changelog's ## [Unreleased] heading as a ### Changed entry, as the template's ADR-0032 item 2 says, such as the one below. Work already under ## [Unreleased] waits until a plan with a Release: line gives it a version section."
    '  - Merging a release''s pull request now tags the release, publishes its GitHub release and starts the package publishing (release: tag+release in AGENTS.md).'
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
    $originUrl = "$(git remote get-url origin 2>$null)"
    if ($originUrl -and -not (Test-GitHubRemote $originUrl)) {
        throw (Get-GitHubOnlyMessage "$project's origin remote, $($originUrl -replace '^(https?://)[^/@]*@', '$1'), isn't on GitHub.")
    }
    if ($Data.ContainsKey('git_host') -and "$($Data['git_host'])" -ne 'github') {
        throw (Get-GitHubOnlyMessage "-Data answers git_host '$($Data['git_host'])'.")
    }

    $merged = @(Get-CopierList (Join-Path $PSScriptRoot 'copier.yml') '_merged_files')
    $ownable = @(Get-OwnableFile (Join-Path $PSScriptRoot 'template'))
    $answers = Get-AdoptionAnswers $project
    # Read before Copier writes the template's .node-version.
    $nodeVersion = Get-NodeVersionFile $project
    $nvmrcText = $null
    $adapters = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'tools\adopt\legacy') -Filter '*.ps1' -File | Sort-Object Name | Where-Object { & $_.FullName -Path $project -Phase Detect })
    foreach ($adapter in $adapters) {
        "Found $($adapter.BaseName)"
        $adapterAnswers = & $adapter.FullName -Path $project -Phase Answers
        foreach ($k in $adapterAnswers.Keys) { $answers[$k] = $adapterAnswers[$k] }
    }
    foreach ($k in $Data.Keys) { $answers[$k] = $Data[$k] }
    # Never copier.yml's Apache-2.0 default for existing code (ADR-0024): without a license worked out or given, the answer is blank, and the warning below says how to add one.
    if (-not $answers.Contains('license')) { $answers['license'] = '' }
    # The nuget_publisher answer keeps the template's publish.yml, release-provenance.yml and raise-baseline.yml out of a library whose own workflow pushes its packages, and has the documents name that workflow.
    if ("$($answers['nuget_package'])" -eq 'true' -and -not $answers.Contains('nuget_publisher')) {
        $publisherAnswer = Get-NuGetPublisherAnswer
        if ($publisherAnswer) { $answers['nuget_publisher'] = $publisherAnswer }
    }
    # The release_policy answer follows the release line of the AGENTS.md the adoption keeps, none without one, as the release workflow reads it, so SECURITY.md describes signed release tags only when something makes them.
    if (-not $answers.Contains('release_policy')) {
        $releasePolicy = Get-ReleasePolicyAnswer
        if ($releasePolicy) { $answers['release_policy'] = $releasePolicy }
    }
    # Files the repository owns, merged or template-owned (its project_owned_files answer): Copier leaves them as they are, and updates show the template's changes to them.
    $ownedFiles = @()
    if ($answers.Contains('project_owned_files')) { $ownedFiles = Get-OwnedFile $answers['project_owned_files'] $ownable; $answers['project_owned_files'] = $ownedFiles }
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

    $headerless = @()
    try {
        $copierArgs = @('copy', '--overwrite', '--defaults', '--quiet')
        if ($Ref) { $copierArgs += '--vcs-ref', $Ref }
        foreach ($k in $answers.Keys) {
            if ($null -ne $answers[$k]) { $copierArgs += '--data', "$k=$(ConvertTo-CopierValue $answers[$k])" }
        }
        # Files the repository owns, merged or template-owned, stay exactly as they are.
        foreach ($file in $ownedFiles) { $copierArgs += '--exclude', "/$file" }
        # A repository whose own workflow already runs CodeQL keeps it alone, without the template's codeql.yml beside it, which would analyze each commit a second time under the same categories (the template's ADR-0044).
        $codeqlWorkflows = @(Get-CodeQLWorkflow)
        $codeqlLeftOut = $codeqlWorkflows.Count -gt 0 -and -not (Test-Path -LiteralPath .github/workflows/codeql.yml)
        if ($codeqlLeftOut) { $copierArgs += '--exclude', '/.github/workflows/codeql.yml' }
        $copierArgs += $Template, $project
        $versionFileNew = -not (Test-Path -LiteralPath version.json)
        Invoke-Copier @copierArgs
        Set-TemplateSource $project $Template

        $utf8 = [Text.UTF8Encoding]::new($false)
        $report = [Collections.Generic.List[string]]::new()
        foreach ($p in $merged) {
            if (-not $originals.ContainsKey($p)) { continue }
            if ($p -in $ownedFiles) { $report.Add("  Owned $p $([char]0x2014) kept as the repository had it (project_owned_files)"); continue }
            $full = Join-Path $project $p
            $result = Merge-AdoptedFile $p $originals[$p] ([IO.File]::ReadAllText($full))
            [IO.File]::WriteAllText($full, $result.Text, $utf8)
            $report.Add("  $($result.Strategy) $p" + $(if ($result.Note) { " $([char]0x2014) $($result.Note)" } else { '' }))
        }
        foreach ($p in $ownedFiles | Where-Object { $_ -notin $merged -and (Test-Path -LiteralPath $_ -PathType Leaf) }) { $report.Add("  Owned $p $([char]0x2014) kept as the repository had it (project_owned_files)") }
        if ($originals.ContainsKey('AGENTS.md')) {
            [IO.File]::WriteAllText((Join-Path $project 'AGENTS.md'), (Add-TemplateIndexEntry $originals['AGENTS.md']), $utf8)
        }
        if ($originals.ContainsKey('Directory.Build.props') -and (Test-Path -LiteralPath build\ProjectTemplate.props)) {
            [IO.File]::WriteAllText((Join-Path $project 'Directory.Build.props'), (Add-ProjectTemplateImport $originals['Directory.Build.props']), $utf8)
        }
        foreach ($adapter in $adapters) {
            foreach ($line in @(& $adapter.FullName -Path $project -Phase Apply)) { $report.Add("  $line") }
        }
        if ($nodeVersion -and $nodeVersion.File -eq '.nvmrc' -and (Test-Path -LiteralPath .node-version)) {
            if ($nodeVersion.Version) {
                [IO.File]::WriteAllText((Join-Path $project '.node-version'), "$($nodeVersion.Version)`n", $utf8)
                $report.Add("  Carried .node-version $([char]0x2014) Node.js $($nodeVersion.Version), from .nvmrc")
            }
            else { $nvmrcText = $nodeVersion.Text }
        }
        if ((Test-Path -LiteralPath Directory.Packages.props) -and -not $originals.ContainsKey('Directory.Packages.props')) {
            foreach ($line in @(Move-PackageVersionsToCentral $project)) { $report.Add("  $line") }
        }
        # A repository that already has a license under another name keeps it alone, without the template's LICENSE.txt beside it.
        $rootFiles = @(git ls-tree --name-only $head)
        $ownLicense = @($rootFiles | Where-Object { $_ -match '^(LICEN[CS]E|COPYING)(\.\w+)?$' -and $_ -ne 'LICENSE.txt' })
        if ($ownLicense) {
            foreach ($p in 'LICENSE.txt', 'COPYRIGHT.txt') {
                if ((Test-Path -LiteralPath $p) -and $p -notin $rootFiles) {
                    Remove-Item -LiteralPath $p
                    $report.Add("  Skipped $p $([char]0x2014) the repository has its own license, $($ownLicense -join ', ')")
                }
            }
        }
        # A repository whose own workflow already pushes NuGet packages keeps it alone: its nuget_publisher answer kept the template's publish.yml and the release follow-ups it calls out.
        if ($answers.Contains('nuget_publisher') -and $answers['nuget_publisher']) {
            $report.Add("  Skipped .github/workflows/publish.yml, release-provenance.yml and raise-baseline.yml $([char]0x2014) $($answers['nuget_publisher']) already push NuGet packages")
        }
        if ($codeqlLeftOut) { $report.Add("  Skipped .github/workflows/codeql.yml $([char]0x2014) $($codeqlWorkflows -join ', ') already run CodeQL") }
        # A version.json this adoption brought in starts at the patch after the newest release tag, with the AssemblyVersion its current major shipped.
        if ($versionFileNew -and (Test-Path -LiteralPath version.json -PathType Leaf)) {
            $versionFile = Update-VersionFile
            if ($versionFile -and ($versionFile.Version -or $versionFile.AssemblyVersion)) {
                $line = "  Set version.json $([char]0x2014) "
                if ($versionFile.Version) { $line += "version $($versionFile.Version), the patch after $($versionFile.Tag)" }
                if ($versionFile.AssemblyVersion) {
                    if ($versionFile.Version) { $line += '; ' }
                    $line += "assemblyVersion $($versionFile.AssemblyVersion) ($($versionFile.Precision))"
                }
                $report.Add($line)
            }
        }
        if ((Test-Path -LiteralPath version.json -PathType Leaf) -and (Test-Path -LiteralPath build/ProjectTemplate.props -PathType Leaf)) {
            foreach ($dropped in @(Remove-GitVersioningReference $project)) {
                $message = "  Dropped $($dropped.File) $([char]0x2014) the template references Nerdbank.GitVersioning itself (ADR-0138)"
                if ($dropped.Version) {
                    $message += "; it pinned version $($dropped.Version), so raise the template's PackageVersion in Directory.Packages.props if the project needs it"
                }
                $report.Add($message)
            }
        }

        $followUps = [Collections.Generic.List[string]]::new()
        if ($nvmrcText) { $followUps.Add("set .node-version to the Node.js version .nvmrc names ($nvmrcText); it holds the template's version until then") }
        if (Test-Path -LiteralPath .github/copilot-instructions.md) { $followUps.Add('fold .github/copilot-instructions.md into AGENTS.md or a file it lists') }
        # A ci.yml the repository already had was kept, so its other workflows are not in conflict with the template's.
        if ((Test-Path -LiteralPath .github/workflows/ci.yml) -and -not $originals.ContainsKey('.github/workflows/ci.yml')) {
            # code-review.yml, code-review-auto-merge.yml, publish.yml and tag-release.yml are the template's own workflows for the review bot, for merging its Dependabot bumps, for publishing packages and for tagging and publishing releases, separate from CI by design: nothing to reconcile. So are scorecard.yml, which scores the repository's supply chain, codeql.yml, which runs CodeQL, and release-provenance.yml, which attests the packages publish.yml publishes, and raise-baseline.yml, which raises the package validation baseline after each release. A workflow of the repository's own that runs CodeQL takes codeql.yml's place, so it isn't reconciled either.
            foreach ($f in Get-ChildItem -LiteralPath .github/workflows -File | Where-Object { $_.Extension -in '.yml', '.yaml' -and $_.Name -notin 'ci.yml', 'code-review.yml', 'code-review-auto-merge.yml', 'publish.yml', 'tag-release.yml', 'scorecard.yml', 'codeql.yml', 'release-provenance.yml', 'raise-baseline.yml' -and ".github/workflows/$($_.Name)" -notin $codeqlWorkflows } | Sort-Object Name) {
                $followUps.Add("reconcile .github/workflows/$($f.Name) with ci.yml")
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
            $otherInstructions = @(Get-ChildItem -LiteralPath .github/instructions -Filter '*.instructions.md' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin 'csharp.instructions.md', 'csharp-tests.instructions.md', 'project-template.instructions.md' } | Sort-Object Name | ForEach-Object Name)
            if ($otherInstructions.Count) { $followUps.Add("reconcile .github/instructions/csharp.instructions.md with $($otherInstructions -join ', ')") }
            foreach ($wrapper in @(Get-CSharpierWrapper $ownable)) { $followUps.Add("drop dotnet csharpier check from $wrapper, which build/dod.ps1 already runs in its Format stage now that .config/dotnet-tools.json names CSharpier (ADR-0148), and update any comment or decision record of the repository's that says build/dod.ps1 doesn't check the formatting") }
            # The template's build settings are a new import, so each list of the build's files must admit them.
            if (Test-Path -LiteralPath build/ProjectTemplate.props) {
                $buildLists = @(Get-BuildFileList $project)
                if ($buildLists.Count) { $followUps.Add("re-admit Directory.Build.props and build/ProjectTemplate.props, which it imports, in each list of the build's files: $($buildLists -join ', ')") }
            }
            $floor = if (-not (Test-Path -LiteralPath version.json)) { Get-AssemblyVersionFloor }
            if ($floor) { $followUps.Add("set <AssemblyVersion>$($floor.AssemblyVersion)</AssemblyVersion> in Directory.Build.props until the next major version, because $($floor.Tag) was released with that assembly version (ADR-0136)") }
            if ((Test-Path -LiteralPath version.json) -and (Test-Path -LiteralPath .github/workflows/publish.yml) -and (Get-Content -Raw -LiteralPath .github/workflows/publish.yml) -notmatch 'PublicRelease=true') {
                $followUps.Add('add -p:PublicRelease=true to the dotnet test and dotnet pack commands of .github/workflows/publish.yml, which packs the version version.json holds only with it (ADR-0138)')
            }
            # A library without a package validation baseline: name the published version to set.
            if ((Get-Answer 'nuget_package') -eq 'true') {
                if (-not (Test-PackageValidationBaseline)) {
                    foreach ($published in @(Get-PublishedPackageVersion)) {
                        $followUps.Add("set <PackageValidationBaselineVersion>$($published.Version)</PackageValidationBaselineVersion> in Directory.Build.props, after the import: $($published.Id) is published on nuget.org at $($published.Version), and the build now validates every pack against it (ADR-0147)")
                    }
                }
                foreach ($finding in @(Get-NuGetLogistics)) { $followUps.Add($finding.Message) }
                foreach ($drift in @(Get-PackageMetadataDrift)) { $followUps.Add($drift.Message) }
            }
            # A library's build fails on a public symbol its PublicAPI.*.txt files don't list; the verification below records the API as it is.
            if ($NoVerify -and (Test-Path -LiteralPath build/Update-PublicApi.ps1)) { $followUps.Add('record each packable project''s public API with ./build/Update-PublicApi.ps1, which the build now checks') }
        }
        $headerless = if ((Get-Answer 'stack') -eq 'dotnet') { @(Get-CSharpFileWithoutHeader) } else { @() }

        git add -A
        # Executable on Linux and macOS; Windows doesn't record the bit on its own.
        if (Test-Path -LiteralPath .githooks/pre-push) { git update-index --chmod=+x .githooks/pre-push }
        # The template's versioned hooks, unless the repository already has a hooks path or runs hooks another way
        # (Get-GitHooksSetup): then a warning that says how to run them.
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
    if ($headerless.Count -gt 0) {
        ''
        "$($headerless.Count) C# file$(if ($headerless.Count -ne 1) { 's' }) don't start with the header .editorconfig sets (file_header_template). csharp_format is off, so they build. Rewrite each before you turn it on with .\.template\Update-Project.ps1 -Data @{ csharp_format = `$true }, because IDE0073 then fails the build for each (the template's ADR-0148): replace the old header, such as a #region Copyright Preamble block, with the header's lines as // comments, and drop a UTF-8 byte order mark. $(($headerless | Select-Object -First 5) -join ', ')$(if ($headerless.Count -gt 5) { ', ...' })"
    }
    # A publish.yml the repository kept, without the trigger tag-release.yml starts it with: a release that workflow
    # publishes would ship no packages. The warning is .template/Update-Project.ps1's, word for word;
    # tests/Test-AdoptEdgeCases.ps1 keeps the two equal.
    if ((Test-Path -LiteralPath .github/workflows/tag-release.yml) -and (Test-Path -LiteralPath .github/workflows/publish.yml) -and @(Get-WorkflowEvents (Get-Content -LiteralPath .github/workflows/publish.yml -Raw)) -notcontains 'workflow_dispatch') {
        ''
        '.github/workflows/publish.yml has no workflow_dispatch trigger. .github/workflows/tag-release.yml publishes each release with the workflow''s token, which starts no other workflow, so it starts publish.yml through workflow_dispatch, and until publish.yml has that trigger, a release ships no packages. Add the trigger with a required tag input to its on: section, read the tag from inputs.tag when the run has no release, and check out refs/tags/<tag>, as the publish.yml the project template gives a .NET library on GitHub does (the template''s ADR-0137, which such a library has in docs/decisions/project-template/).'
    }
    # A .NET library on GitHub whose AGENTS.md says release: none or tag publishes nothing on merge. The note is
    # .template/Update-Project.ps1's, word for word; tests/Test-UpdateNotes.ps1 keeps the two functions equal.
    Get-ReleasePolicyNote
    # A library whose own workflows publish its packages, without the trigger tag-release.yml starts them with. The note is
    # .template/Update-Project.ps1's, word for word; tests/Test-UpdateNotes.ps1 keeps the two functions equal.
    Get-PublisherDispatchNote
    # A publish.yml that doesn't call one of the release follow-ups, or either (ADR-0151): they no longer start on
    # workflow_run, so a release misses what each one it doesn't call makes. The warning is
    # .template/Update-Project.ps1's, word for word; tests/Test-AdoptEdgeCases.ps1 keeps the two equal.
    $publishText = if (Test-Path -LiteralPath .github/workflows/publish.yml) { Get-Content -LiteralPath .github/workflows/publish.yml -Raw } else { '' }
    if ($publishText -and (((Test-Path -LiteralPath .github/workflows/release-provenance.yml) -and $publishText -notmatch '(?m)^\s+uses:\s*\./\.github/workflows/release-provenance\.yml\s*(#.*)?$') -or ((Test-Path -LiteralPath .github/workflows/raise-baseline.yml) -and $publishText -notmatch '(?m)^\s+uses:\s*\./\.github/workflows/raise-baseline\.yml\s*(#.*)?$'))) {
        ''
        '.github/workflows/publish.yml doesn''t call .github/workflows/release-provenance.yml or .github/workflows/raise-baseline.yml, or both, which no longer start on workflow_run, since GitHub starts none for the run tag-release.yml starts: until it calls each, no release gets the provenance or the baseline pull request the missing one makes. Add the provenance and baseline jobs of the template''s publish.yml (the template''s ADR-0151). To attest an earlier release while its Publish packages run''s artifact is kept (14 days): gh workflow run release-provenance.yml -f tag=<tag> -f run-id=<run id>'
    }
    # A ci.yml the repository kept, which tag-release.yml calls with only contents: read (ADR-0026): without the
    # workflow_call trigger, or with a job that asks for more, no release is tagged. The notes are
    # .template/Update-Project.ps1's, word for word; tests/Test-UpdateNotes.ps1 runs both copies through the same cases.
    Get-CiCallNote
    Get-CiPermissionNote
    # Nerdbank.GitVersioning, once version.json exists (ADR-0138): the note is .template/Update-Project.ps1's, word for word;
    # tests/Test-UpdateNotes.ps1 runs both copies through the same cases.
    Get-GitVersioningWorkflowNote
    # SECURITY.md's "Releases are immutable" paragraph, where a workflow needs mutable releases (ADR-0028). The note is
    # .template/Update-Project.ps1's, word for word.
    Get-ImmutableReleaseNote $false
    # No license (ADR-0024): the warnings are .template/Update-Project.ps1's, word for word; tests/Test-LicenseWarning.ps1 keeps them equal.
    if (-not (Get-ChildItem -LiteralPath $project -File | Where-Object Name -Match '^(LICEN[CS]E|COPYING)(\.\w+)?$')) {
        $licenseAnswer = "$(Get-Answer 'license')".Trim()
        ''
        if (-not $licenseAnswer) {
            'No license: the license answer is blank and the repository has no LICENSE or COPYING file, so no one else may use, copy or change its code, and the OpenSSF Best Practices criteria for a license can''t be met. To license it under Apache-2.0, NCode Group''s license, which adds LICENSE.txt and COPYRIGHT.txt, run the command below in the repository; for another SPDX license expression, such as MIT, put it in place of Apache-2.0:'
            "  .\.template\Update-Project.ps1 -Data @{ license = 'Apache-2.0' }"
        }
        else {
            "No license file: the license answer is $licenseAnswer, but the repository has no LICENSE or COPYING file, so no one else may use, copy or change its code, and the OpenSSF Best Practices criteria for a license can't be met. Add the text of the $licenseAnswer license as LICENSE.txt at the repository's root."
        }
    }

    # A GitHub repository's default branch should take changes only through pull requests. The baseline script changes the
    # repository's settings on GitHub, which an adoption that only commits locally shouldn't do on its own, so print it.
    if ($originUrl -match '^(?:https://(?:[^@/]+@)?github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+)/([^/]+?)(?:\.git)?/?$') {
        # The next -match overwrites $Matches.
        $owner, $repo = $Matches[1], $Matches[2]
        # NCodeGroup's rule for repository names (the template's ADR-0045): an adoption refuses nothing, so it names a repository whose name doesn't fit and what its rename touches.
        $nameWarning = Get-RepositoryNameWarning $repo (Get-Answer 'stack')
        if ($nameWarning) { ''; $nameWarning }
        $ci = if (Test-Path -LiteralPath .github/workflows/ci.yml) { Get-Content -Raw -LiteralPath .github/workflows/ci.yml } else { '' }
        $checks = if ($ci -match '(?m)^  build-and-test:' -and $ci.Contains('./.template/Test-AdrIndex.ps1')) { " -RequireChecks 'build-and-test'" } else { '' }
        ''
        "Protect the default branch, so changes reach it only through a pull request. From the template's clone, run:"
        "  $(Join-Path $PSScriptRoot 'tools/Set-RepositoryBaseline.ps1') -Repo $repo -Owner $owner$checks"
        if (-not $checks) { "  (this repository keeps its own CI: add -RequireChecks auto to require the checks that passed on its latest merged pull request, with -WhatIf first to list them, or -RequireChecks '<the jobs that run on pull requests>', comma-separated)" }
    }

    if ($followUps.Count) {
        ''
        "Still to do $([char]0x2014) in the repository, run:"
        "  /plan-migration Finish adopting the project template: $($followUps -join '; ')"
    }

    ''
    if (-not $NoVerify) {
        # A library's build fails on a public symbol its PublicAPI.*.txt files don't list: record the API as it is now, the baseline the next changes are reviewed against.
        if (Test-Path -LiteralPath build/Update-PublicApi.ps1) {
            'Running ./build/Update-PublicApi.ps1'
            $apiOutput = pwsh -NoProfile -File build/Update-PublicApi.ps1 2>&1 | Out-String
            if ($LASTEXITCODE) {
                $apiOutput.TrimEnd()
                'Recording the public API failed after adopting. The adoption is staged, not committed: fix it and commit, or abandon it with: git reset --hard; git clean -fd'
                exit 1
            }
            @($apiOutput -split '\r?\n' | Where-Object { $_ -ne '' }) | ForEach-Object { "  $_" }
            git add -A
        }
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
