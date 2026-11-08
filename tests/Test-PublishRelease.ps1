<#
.SYNOPSIS
    Test template\.template\Publish-Release.ps1, which .github\workflows\release.yml runs to tag and publish a release when it merges.

.DESCRIPTION
    Runs the script in a clone of a temporary bare repository, with a stand-in for gh that keeps each release it publishes
    as a file. Checks that it tags the commit with the changelog's newest version and publishes that version's section as
    the release notes; that a second run changes nothing; that a run after a tag without a release publishes only the
    release; that it tags nothing when the remote has a newer version tag, publishes no release with release: tag, and
    does nothing with release: none; that it drops the v when the remote's version tags have
    none; that a release lookup failing other than with a 404 stops it with gh's message; and that -WhatIf pushes and
    publishes nothing. Also checks that the version comes from the merged pull request's Release: line: with pre-release:
    untracked and no release heading it tags the merged commit with that version and publishes the [Unreleased] section,
    it does nothing for another commit's pull request or a description without the line, it accepts a line that agrees
    with the changelog and fails on one that disagrees, and it stops with gh's message when the pull request lookup
    fails. The stand-in also accepts the call that starts publish.yml. Also checks that release.yml runs the script on a push to main
    that changes CHANGELOG.md, with contents: write and the merged commit. Prints PASS or FAIL per check and exits 1 on
    any failure.

.EXAMPLE
    .\tests\Test-PublishRelease.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repoRoot 'template/.template/Publish-Release.ps1'
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}

$workflow = Get-Content -Raw -LiteralPath (Join-Path $repoRoot '.github/workflows/release.yml')
Check 'release.yml runs on a push to main that changes CHANGELOG.md' ($workflow -match '(?m)^  push:\r?\n    branches: \[main\]\r?\n    paths: \[CHANGELOG\.md\]')
Check 'release.yml gives its job contents: write and pull-requests: read' ($workflow -match '(?m)^    permissions:\r?\n      contents: write\r?\n(?:      #.*\r?\n)?      pull-requests: read')
Check 'release.yml runs the script on the merged commit' ($workflow -match [regex]::Escape('run: ./template/.template/Publish-Release.ps1 -Commit $env:GITHUB_SHA'))

$temp = Join-Path ([IO.Path]::GetTempPath()) "publish-release-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temp | Out-Null
$releases = Join-Path $temp 'releases'
New-Item -ItemType Directory -Path $releases | Out-Null
$standIn = Join-Path $temp 'gh.ps1'
# A stand-in for gh: `api repos/{owner}/{repo}/releases/tags/<tag>` succeeds when the release's file exists and else fails
# printing gh's 404 message, or a 401 one when PUBLISH_RELEASE_TEST_LOOKUP_ERROR is set; `api
# repos/{owner}/{repo}/releases -f tag_name=<tag> ... -F body=@<file>` copies the notes to it, `api
# repos/{owner}/{repo}/commits/<sha>/pulls` prints pulls.json (or [], or a 500 when PUBLISH_RELEASE_TEST_PULLS_ERROR is set),
# the publish.yml dispatch succeeds, and every call is logged.
Set-Content -LiteralPath $standIn -Encoding utf8NoBOM -Value @'
$releases = $env:PUBLISH_RELEASE_TEST_RELEASES
Add-Content -LiteralPath (Join-Path $releases 'calls.log') -Value ($args -join ' ')
if ($args[0] -eq 'api' -and $args[1] -match '^repos/\{owner\}/\{repo\}/releases/tags/(?<tag>.+)$') {
    if (Test-Path -LiteralPath (Join-Path $releases $Matches.tag)) { exit 0 }
    if ($env:PUBLISH_RELEASE_TEST_LOOKUP_ERROR) { 'gh: Bad credentials (HTTP 401)'; exit 1 }
    'gh: Not Found (HTTP 404)'; exit 1
}
if ($args[0] -eq 'api' -and $args[1] -eq 'repos/{owner}/{repo}/releases') {
    $tag = ($args -match '^tag_name=')[0] -replace '^tag_name='
    $notes = ($args -match '^body=@')[0] -replace '^body=@'
    Copy-Item -LiteralPath $notes -Destination (Join-Path $releases $tag)
    exit 0
}
if ($args[0] -eq 'api' -and $args[1] -match '^repos/\{owner\}/\{repo\}/commits/[0-9a-f]+/pulls$') {
    if ($env:PUBLISH_RELEASE_TEST_PULLS_ERROR) { 'gh: Server Error (HTTP 500)'; exit 1 }
    $pulls = Join-Path $releases 'pulls.json'
    if (Test-Path -LiteralPath $pulls) { Get-Content -Raw -LiteralPath $pulls } else { '[]' }
    exit 0
}
if ($args[0] -eq 'api' -and $args[1] -eq 'repos/{owner}/{repo}/actions/workflows/publish.yml/dispatches') { exit 0 }
exit 2
'@
$env:PUBLISH_RELEASE_TEST_RELEASES = $releases

$changelog = @'
# Changelog

## [Unreleased]

## [0.2.0] - 2026-11-08

### Added

- The second thing.

## [0.1.0] - 2026-11-01

### Added

- The first thing.

[0.2.0]: https://example.com/compare/v0.1.0...v0.2.0
'@

function New-Clone([string]$Name, [string]$Landing, [string]$Changelog = $changelog, [hashtable]$Files = @{}) {
    $origin = Join-Path $temp "$Name.git"
    $work = Join-Path $temp $Name
    & git -c init.defaultBranch=main init -q --bare $origin
    & git -c init.defaultBranch=main init -q $work
    & git -C $work config user.name 'Test'
    & git -C $work config user.email 'test@example.com'
    & git -C $work config core.hooksPath ''
    & git -C $work remote add origin $origin
    Set-Content -LiteralPath (Join-Path $work 'AGENTS.md') -Encoding utf8NoBOM -Value "# Test`n`n## Landing`n`n$Landing`n`n## Other`n`n- release: tag+release"
    Set-Content -LiteralPath (Join-Path $work 'CHANGELOG.md') -Encoding utf8NoBOM -Value $Changelog
    foreach ($path in $Files.Keys) {
        $target = Join-Path $work $path
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Set-Content -LiteralPath $target -Encoding utf8NoBOM -Value $Files[$path]
    }
    & git -C $work add .
    & git -C $work commit -q -m 'Start'
    & git -C $work push -q origin HEAD:refs/heads/main 2>$null
    $work
}

function Invoke-Publish([string]$Work, [string[]]$Extra = @()) {
    Remove-Item -LiteralPath (Join-Path $releases 'calls.log') -ErrorAction SilentlyContinue
    Push-Location -LiteralPath $Work
    try {
        $output = & pwsh -NoProfile -File $script -Gh $standIn @Extra 2>&1
        [pscustomobject]@{ Code = $LASTEXITCODE; Output = (($output | ForEach-Object { "$_" }) -join "`n") }
    } finally { Pop-Location }
}

function Set-Pulls([string]$Sha, [string]$Body) {
    Set-Content -LiteralPath (Join-Path $releases 'pulls.json') -Encoding utf8NoBOM -Value (ConvertTo-Json -InputObject @(@{ number = 7; merge_commit_sha = $Sha; body = $Body }) -Compress)
}

function Get-OriginTag([string]$Work) { @(& git -C $Work ls-remote --tags --refs origin | ForEach-Object { ($_ -split "`t")[1] -replace '^refs/tags/' }) }
function Get-Calls { $log = Join-Path $releases 'calls.log'; if (Test-Path -LiteralPath $log) { @(Get-Content -LiteralPath $log) } else { @() } }

try {
    $work = New-Clone 'full' '- release: tag+release'
    $head = (& git -C $work rev-parse HEAD)
    $run = Invoke-Publish $work
    Check 'a new version: the script exits 0' ($run.Code -eq 0) $run.Output
    Check 'a new version: origin gets the tag v0.2.0' ((Get-OriginTag $work) -ccontains 'v0.2.0') ((Get-OriginTag $work) -join ', ')
    Check 'a new version: the tag is annotated and names the commit' ((& git -C $work cat-file -t 'refs/tags/v0.2.0') -eq 'tag' -and (& git -C $work rev-parse 'v0.2.0^{commit}') -eq $head)
    $notesPath = Join-Path $releases 'v0.2.0'
    $notes = if (Test-Path -LiteralPath $notesPath) { (Get-Content -Raw -LiteralPath $notesPath).Trim() } else { '' }
    Check 'a new version: the release has the section without its heading or the link references' ($notes -eq "### Added`n`n- The second thing.") $notes
    Check 'a new version: the release is named with the version and created once' ((@(Get-Calls) -match '^api repos/\{owner\}/\{repo\}/releases -f tag_name=v0\.2\.0 -f name=v0\.2\.0 -F body=@').Count -eq 1) ((Get-Calls) -join ' | ')

    $run = Invoke-Publish $work
    Check 'a second run: it exits 0 and publishes nothing' ($run.Code -eq 0 -and -not (@(Get-Calls) -match '^api repos/\{owner\}/\{repo\}/releases -f')) ((Get-Calls) -join ' | ')
    Check 'a second run: it says both are there' ($run.Output -match 'has the tag v0\.2\.0 already' -and $run.Output -match 'has the release v0\.2\.0 already') $run.Output

    Remove-Item -LiteralPath $notesPath
    $run = Invoke-Publish $work
    Check 'a tag without its release: it publishes only the release' ($run.Code -eq 0 -and (Test-Path -LiteralPath $notesPath) -and $run.Output -match 'has the tag v0\.2\.0 already') $run.Output

    $work = New-Clone 'newer' '- release: tag+release'
    & git -C $work tag v0.3.0
    & git -C $work push -q origin refs/tags/v0.3.0 2>$null
    $run = Invoke-Publish $work
    Check 'a newer version tag on origin: it tags and publishes nothing' ($run.Code -eq 0 -and -not ((Get-OriginTag $work) -ccontains 'v0.2.0') -and -not (@(Get-Calls) -match '^api repos/\{owner\}/\{repo\}/releases')) $run.Output

    $work = New-Clone 'tag-only' '- release: tag'
    $run = Invoke-Publish $work
    Check 'release: tag: it pushes the tag and publishes no release' ($run.Code -eq 0 -and (Get-OriginTag $work) -ccontains 'v0.2.0' -and -not (@(Get-Calls) -match '^api repos/\{owner\}/\{repo\}/releases')) $run.Output

    foreach ($case in @(
            @{ Name = 'release: none'; Landing = '- release: none' },
            @{ Name = 'no release line'; Landing = '- integrate: pull-request' })) {
        $work = New-Clone ($case.Name -replace '[^a-z]', '') $case.Landing
        $run = Invoke-Publish $work
        Check "$($case.Name): it tags and publishes nothing" ($run.Code -eq 0 -and -not (Get-OriginTag $work).Count -and -not (Get-Calls).Count) $run.Output
    }

    $work = New-Clone 'no-prefix' '- release: tag+release' ($changelog -replace '0\.2\.0', '1.1.0')
    & git -C $work tag 1.0.0
    & git -C $work push -q origin refs/tags/1.0.0 2>$null
    $run = Invoke-Publish $work
    Check 'version tags without a v: it tags 1.1.0' ($run.Code -eq 0 -and (Get-OriginTag $work) -ccontains '1.1.0') ((Get-OriginTag $work) -join ', ')

    $work = New-Clone 'what-if' '- release: tag+release'
    $run = Invoke-Publish $work @('-WhatIf')
    Check '-WhatIf: it pushes and publishes nothing' ($run.Code -eq 0 -and -not (Get-OriginTag $work).Count -and -not (@(Get-Calls) -match '^api repos/\{owner\}/\{repo\}/releases -f') -and -not (& git -C $work tag --list)) $run.Output

    $work = New-Clone 'lookup-error' '- release: tag+release'
    Remove-Item -LiteralPath (Join-Path $releases 'v0.2.0') -ErrorAction SilentlyContinue
    $env:PUBLISH_RELEASE_TEST_LOOKUP_ERROR = '1'
    try { $run = Invoke-Publish $work } finally { Remove-Item Env:PUBLISH_RELEASE_TEST_LOOKUP_ERROR }
    Check 'a release lookup that fails other than 404: it fails with gh''s message and publishes nothing' ($run.Code -ne 0 -and $run.Output -match 'HTTP 401' -and -not (@(Get-Calls) -match '^api repos/\{owner\}/\{repo\}/releases -f')) $run.Output

    $work = New-Clone 'bad-policy' '- release: always'
    $run = Invoke-Publish $work
    Check 'an unknown release value: it fails and names it' ($run.Code -ne 0 -and $run.Output -match 'release: always') $run.Output

    $untrackedLanding = "- release: tag+release`n- pre-release: untracked"
    $untrackedChangelog = "# Changelog`n`n## [Unreleased]`n`n### Added`n`n- The product does a thing.`n"
    $body030 = "Summary.`n`nRelease: v0.3.0`nCloses #5"

    $work = New-Clone 'untracked-release' $untrackedLanding $untrackedChangelog
    $head = (& git -C $work rev-parse HEAD)
    Remove-Item -LiteralPath (Join-Path $releases 'pulls.json'), (Join-Path $releases 'v0.3.0') -ErrorAction SilentlyContinue
    Set-Pulls $head $body030
    $run = Invoke-Publish $work
    Check 'pre-release: untracked with a Release: line: it tags the merged commit with v0.3.0' ($run.Code -eq 0 -and (Get-OriginTag $work) -ccontains 'v0.3.0' -and (& git -C $work cat-file -t 'refs/tags/v0.3.0') -eq 'tag' -and (& git -C $work rev-parse 'v0.3.0^{commit}') -eq $head) $run.Output
    $notesPath = Join-Path $releases 'v0.3.0'
    $notes = if (Test-Path -LiteralPath $notesPath) { (Get-Content -Raw -LiteralPath $notesPath).Trim() } else { '' }
    Check 'pre-release: untracked with a Release: line: the release notes are the [Unreleased] section' ($notes -eq "### Added`n`n- The product does a thing.") $notes

    $work = New-Clone 'untracked-other-pull' $untrackedLanding $untrackedChangelog
    Remove-Item -LiteralPath (Join-Path $releases 'pulls.json'), (Join-Path $releases 'v0.3.0') -ErrorAction SilentlyContinue
    Set-Pulls ('0' * 40) $body030
    $run = Invoke-Publish $work
    Check 'pre-release: untracked, another commit''s pull request: it tags and publishes nothing' ($run.Code -eq 0 -and -not (Get-OriginTag $work).Count -and -not (@(Get-Calls) -match '^api repos/\{owner\}/\{repo\}/releases -f')) $run.Output

    $work = New-Clone 'untracked-no-line' $untrackedLanding $untrackedChangelog
    $head = (& git -C $work rev-parse HEAD)
    Remove-Item -LiteralPath (Join-Path $releases 'pulls.json'), (Join-Path $releases 'v0.3.0') -ErrorAction SilentlyContinue
    Set-Pulls $head "Summary.`n`nCloses #5"
    $run = Invoke-Publish $work
    Check 'pre-release: untracked, no Release: line: it tags and publishes nothing' ($run.Code -eq 0 -and -not (Get-OriginTag $work).Count -and -not (@(Get-Calls) -match '^api repos/\{owner\}/\{repo\}/releases -f')) $run.Output

    $work = New-Clone 'line-agrees' '- release: tag+release'
    $head = (& git -C $work rev-parse HEAD)
    Remove-Item -LiteralPath (Join-Path $releases 'pulls.json'), (Join-Path $releases 'v0.2.0') -ErrorAction SilentlyContinue
    Set-Pulls $head "Summary.`n`nRelease: v0.2.0`nCloses #5"
    $run = Invoke-Publish $work
    Check 'a Release: line that agrees with the changelog: it tags v0.2.0' ($run.Code -eq 0 -and (Get-OriginTag $work) -ccontains 'v0.2.0') $run.Output

    $work = New-Clone 'line-disagrees' '- release: tag+release'
    $head = (& git -C $work rev-parse HEAD)
    Remove-Item -LiteralPath (Join-Path $releases 'pulls.json'), (Join-Path $releases 'v0.2.0') -ErrorAction SilentlyContinue
    Set-Pulls $head $body030
    $run = Invoke-Publish $work
    Check 'a Release: line that disagrees with the changelog: it fails, names both versions and tags nothing' ($run.Code -ne 0 -and $run.Output -match 'v0\.3\.0' -and $run.Output -match '0\.2\.0' -and -not (Get-OriginTag $work).Count) $run.Output

    $work = New-Clone 'pulls-error' '- release: tag+release'
    Remove-Item -LiteralPath (Join-Path $releases 'pulls.json'), (Join-Path $releases 'v0.2.0') -ErrorAction SilentlyContinue
    $env:PUBLISH_RELEASE_TEST_PULLS_ERROR = '1'
    try { $run = Invoke-Publish $work } finally { Remove-Item Env:PUBLISH_RELEASE_TEST_PULLS_ERROR }
    Check 'a pull request lookup that fails: it fails with gh''s message and tags nothing' ($run.Code -ne 0 -and $run.Output -match 'HTTP 500' -and -not (Get-OriginTag $work).Count) $run.Output
} finally {
    Remove-Item Env:PUBLISH_RELEASE_TEST_RELEASES -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { "Tests: FAILED ($($failures.Count))"; exit 1 }
'Tests: PASSED'
# The last git or pwsh call above may have failed on purpose; a caller that reads $LASTEXITCODE, as CI's pwsh shell does, sees 0.
exit 0
