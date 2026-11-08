<#
.SYNOPSIS
    Tag and publish the release the changelog's newest section names, once the remote has no tag for it.

.DESCRIPTION
    .github/workflows/release.yml runs this on each push to main that changes the changelog, so a plan's release is tagged
    and published as soon as its pull request merges, with nothing left for a person or an agent to run. That includes a
    plan landed from a Claude Code cloud session, whose GitHub proxy refuses a tag push and GitHub's GraphQL API, which
    `gh release create` uses. It reads and publishes the release through GitHub's REST API, so it runs in such a session too.

    It reads the release, changelog and pre-release lines of the ## Landing section of AGENTS.md, as Get-PlanState.ps1
    does. release: none publishes nothing, tag pushes the tag alone, and tag+release also publishes the GitHub release.
    The version is the changelog's newest release heading, `## [<number>] - <date>`, with a v before the number, as
    /ship-plan names it, unless the remote's version tags have no v. Its section, without the heading, is the release's
    notes: up to the next `## ` heading or the link reference definitions that end a Keep a Changelog file. With
    pre-release: untracked, the version is in the plan rather than the changelog, so it publishes nothing and leaves the
    release to /ship-plan.

    It tags -Commit, the commit the pull request merged as, with an annotated tag, and only when the version is newer
    than every version tag the remote has, so an edit to an older section tags nothing. It's safe to run again: a tag the
    remote has is never moved and a release GitHub has is never changed, so /ship-plan run after the merge finds both
    done, and a run that stopped after the tag publishes the release the next time. -WhatIf says what it would do and
    pushes and publishes nothing.

.PARAMETER Commit
    The commit to tag: in the workflow, the commit the push made main point to.

.PARAMETER Remote
    The remote whose tags count and that gets the tag.

.PARAMETER Gh
    The gh command that reads and publishes the release; the tests pass a stand-in.

.EXAMPLE
    ./tools/Publish-Release.ps1 -Commit $env:GITHUB_SHA

.EXAMPLE
    ./tools/Publish-Release.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Commit = 'HEAD',
    [string]$Remote = 'origin',
    [string]$Gh = 'gh'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# The value of each `- <key>: <value>` line in the ## Landing section of AGENTS.md, without the quotes around a value.
function Get-LandingPolicy([string[]]$Lines) {
    $policy = @{}
    $inLanding = $false
    foreach ($line in $Lines) {
        if ($line -match '^## Landing\s*$') { $inLanding = $true; continue }
        if ($inLanding -and $line -match '^## ') { break }
        if ($inLanding -and $line -match '^- (?<key>[a-z-]+):\s*(?<value>.*?)\s*$') {
            $policy[$Matches.key] = $Matches.value -replace '^"(.*)"$', '$1'
        }
    }
    $policy
}

# The changelog's newest release section: its number and its notes, without the heading and the blank lines around them.
function Get-NewestRelease([string[]]$Lines) {
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -notmatch '^## \[(?<number>[^\]]+)\]' -or $Matches.number -eq 'Unreleased') { continue }
        $number = $Matches.number
        $notes = [Collections.Generic.List[string]]::new()
        for ($j = $i + 1; $j -lt $Lines.Count -and $Lines[$j] -notmatch '^## ' -and $Lines[$j] -notmatch '^\[[^\]]+\]:\s'; $j++) {
            $notes.Add($Lines[$j])
        }
        return [pscustomobject]@{ Number = $number; Notes = (($notes -join "`n").Trim()) }
    }
    $null
}

# The tag names the remote has, or an error when it can't be read.
function Get-RemoteTag([string]$Name) {
    $refs = @(& git ls-remote --tags --refs $Name)
    if ($LASTEXITCODE) { throw "Can't read the tags of $Name (git ls-remote exited $LASTEXITCODE)." }
    @($refs | ForEach-Object { if ($_ -match '\trefs/tags/(?<tag>.+)$') { $Matches.tag } })
}

$root = (& git rev-parse --show-toplevel)
if ($LASTEXITCODE) { throw 'Run this in a clone of the repository.' }
$agents = Join-Path $root 'AGENTS.md'
if (-not (Test-Path -LiteralPath $agents)) { 'AGENTS.md is missing, so there is no release policy: nothing to publish.'; exit 0 }
$policy = Get-LandingPolicy @(Get-Content -LiteralPath $agents)
$release = if ($policy.ContainsKey('release')) { $policy['release'] } else { 'none' }
if ($release -notin 'none', 'tag', 'tag+release') { throw "AGENTS.md's Landing section says release: $release; use none, tag or tag+release." }
if ($release -eq 'none') { "AGENTS.md's Landing section says release: none: nothing to publish."; exit 0 }
if ($policy.ContainsKey('pre-release') -and $policy['pre-release'] -eq 'untracked') {
    "AGENTS.md's Landing section says pre-release: untracked, so the version is in the plan, not the changelog: /ship-plan tags and publishes it."
    exit 0
}

$changelogName = if ($policy.ContainsKey('changelog') -and $policy['changelog']) { $policy['changelog'] } else { 'CHANGELOG.md' }
$changelog = Join-Path $root $changelogName
if (-not (Test-Path -LiteralPath $changelog)) { "$changelogName is missing: nothing to publish."; exit 0 }
$newest = Get-NewestRelease @(Get-Content -LiteralPath $changelog)
if (-not $newest) { "$changelogName has no release section yet: nothing to publish."; exit 0 }
if ($newest.Number -notmatch '^\d+\.\d+\.\d+$') { "$changelogName's newest release, $($newest.Number), isn't shaped like 1.2.3: tag it with /ship-plan."; exit 0 }

$tags = Get-RemoteTag $Remote
$versionTags = @($tags | Where-Object { $_ -match '^v?\d+\.\d+\.\d+$' })
$prefix = if ($versionTags.Count -and -not @($versionTags | Where-Object { $_ -like 'v*' }).Count) { '' } else { 'v' }
$version = "$prefix$($newest.Number)"

if ($tags -ccontains $version) {
    "$Remote has the tag $version already."
} else {
    $newer = @($versionTags | Where-Object { [version]($_ -replace '^v') -ge [version]$newest.Number })
    if ($newer.Count) {
        "$changelogName's newest release is $version, but $Remote has $(($newer | Sort-Object { [version]($_ -replace '^v') } | Select-Object -Last 1)) already: nothing to tag."
        exit 0
    }
    $sha = (& git rev-parse --verify --quiet "$Commit^{commit}")
    if ($LASTEXITCODE -or -not $sha) { throw "$Commit isn't a commit in this clone." }
    if ($PSCmdlet.ShouldProcess("$sha on $Remote", "Tag $version")) {
        & git tag -a $version -m $version $sha
        if ($LASTEXITCODE) { throw "git tag -a $version exited $LASTEXITCODE." }
        & git push $Remote "refs/tags/$version"
        if ($LASTEXITCODE) {
            & git tag -d $version | Out-Null
            # Another run, or /ship-plan, may have pushed the same tag a moment ago; the release below still needs it.
            if (-not ((Get-RemoteTag $Remote) -ccontains $version)) { throw "Pushing the tag $version to $Remote failed." }
            "$Remote got the tag $version from another run meanwhile."
        } else {
            "Tagged $sha as $version and pushed it to $Remote."
        }
    }
}

if ($release -eq 'tag+release') {
    # REST, not `gh release view` and `gh release create`, which use GraphQL: a Claude Code cloud session can run this too.
    & $Gh api "repos/{owner}/{repo}/releases/tags/$version" --silent *> $null
    if (-not $LASTEXITCODE) {
        "GitHub has the release $version already."
    } elseif ($PSCmdlet.ShouldProcess($version, 'Publish the GitHub release')) {
        $notesFile = New-TemporaryFile
        try {
            Set-Content -LiteralPath $notesFile -Value $newest.Notes -Encoding utf8NoBOM
            & $Gh api 'repos/{owner}/{repo}/releases' -f "tag_name=$version" -f "name=$version" -F "body=@$notesFile" --silent
            if ($LASTEXITCODE) { throw "Publishing the GitHub release $version failed (gh api exited $LASTEXITCODE)." }
            "Published the GitHub release $version from its $changelogName section."
        } finally {
            Remove-Item -LiteralPath $notesFile -ErrorAction SilentlyContinue
        }
    }
}
