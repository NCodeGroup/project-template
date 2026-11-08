<#
.SYNOPSIS
    Test tools\Publish-Release.ps1, which .github\workflows\release.yml runs to tag and publish a release when it merges.

.DESCRIPTION
    Runs the script in a clone of a temporary bare repository, with a stand-in for gh that keeps each release it publishes
    as a file. Checks that it tags the commit with the changelog's newest version and publishes that version's section as
    the release notes; that a second run changes nothing; that a run after a tag without a release publishes only the
    release; that it tags nothing when the remote has a newer version tag, publishes no release with release: tag, and
    does nothing with release: none or pre-release: untracked; that it drops the v when the remote's version tags have
    none; and that -WhatIf pushes and publishes nothing. Also checks that release.yml runs the script on a push to main
    that changes CHANGELOG.md, with contents: write and the merged commit. Prints PASS or FAIL per check and exits 1 on
    any failure.

.EXAMPLE
    .\tests\Test-PublishRelease.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repoRoot 'tools/Publish-Release.ps1'
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}

$workflow = Get-Content -Raw -LiteralPath (Join-Path $repoRoot '.github/workflows/release.yml')
Check 'release.yml runs on a push to main that changes CHANGELOG.md' ($workflow -match '(?m)^  push:\r?\n    branches: \[main\]\r?\n    paths: \[CHANGELOG\.md\]')
Check 'release.yml gives its job contents: write' ($workflow -match '(?m)^    permissions:\r?\n      contents: write')
Check 'release.yml runs the script on the merged commit' ($workflow -match [regex]::Escape('run: ./tools/Publish-Release.ps1 -Commit $env:GITHUB_SHA'))

$temp = Join-Path ([IO.Path]::GetTempPath()) "publish-release-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temp | Out-Null
$releases = Join-Path $temp 'releases'
New-Item -ItemType Directory -Path $releases | Out-Null
$standIn = Join-Path $temp 'gh.ps1'
# A stand-in for gh: `api repos/{owner}/{repo}/releases/tags/<tag>` succeeds when the release's file exists, `api
# repos/{owner}/{repo}/releases -f tag_name=<tag> ... -F body=@<file>` copies the notes to it, and every call is logged.
Set-Content -LiteralPath $standIn -Encoding utf8NoBOM -Value @'
$releases = $env:PUBLISH_RELEASE_TEST_RELEASES
Add-Content -LiteralPath (Join-Path $releases 'calls.log') -Value ($args -join ' ')
if ($args[0] -eq 'api' -and $args[1] -match '^repos/\{owner\}/\{repo\}/releases/tags/(?<tag>.+)$') {
    if (Test-Path -LiteralPath (Join-Path $releases $Matches.tag)) { exit 0 } else { exit 1 }
}
if ($args[0] -eq 'api' -and $args[1] -eq 'repos/{owner}/{repo}/releases') {
    $tag = ($args -match '^tag_name=')[0] -replace '^tag_name='
    $notes = ($args -match '^body=@')[0] -replace '^body=@'
    Copy-Item -LiteralPath $notes -Destination (Join-Path $releases $tag)
    exit 0
}
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

function New-Clone([string]$Name, [string]$Landing, [string]$Changelog = $changelog) {
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
    & git -C $work add AGENTS.md CHANGELOG.md
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
    Check 'a newer version tag on origin: it tags and publishes nothing' ($run.Code -eq 0 -and -not ((Get-OriginTag $work) -ccontains 'v0.2.0') -and -not (Get-Calls).Count) $run.Output

    $work = New-Clone 'tag-only' '- release: tag'
    $run = Invoke-Publish $work
    Check 'release: tag: it pushes the tag and publishes no release' ($run.Code -eq 0 -and (Get-OriginTag $work) -ccontains 'v0.2.0' -and -not (Get-Calls).Count) $run.Output

    foreach ($case in @(
            @{ Name = 'release: none'; Landing = '- release: none' },
            @{ Name = 'pre-release: untracked'; Landing = "- release: tag+release`n- pre-release: untracked" },
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

    $work = New-Clone 'bad-policy' '- release: always'
    $run = Invoke-Publish $work
    Check 'an unknown release value: it fails and names it' ($run.Code -ne 0 -and $run.Output -match 'release: always') $run.Output
} finally {
    Remove-Item Env:PUBLISH_RELEASE_TEST_RELEASES -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { "Tests: FAILED ($($failures.Count))"; exit 1 }
'Tests: PASSED'
