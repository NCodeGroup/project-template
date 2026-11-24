<#
.SYNOPSIS
    Test template\.template\Publish-Release.ps1, which this repository's .github\workflows\release.yml and a project's
    .github\workflows\tag-release.yml, the Tag and publish release workflow, run to tag and publish a release when it
    merges.

.DESCRIPTION
    Runs the script in a clone of a temporary bare repository, with a stand-in for gh that keeps each release it
    publishes as a file. Checks that it tags the commit with the changelog's newest version and publishes that version's
    section as the release notes; that a second run changes nothing; that a run after a tag without a release publishes
    only the release; that it tags nothing when the remote has a newer version tag, publishes no release with release:
    tag, and does nothing with release: none; that it drops the v when the remote's version tags have none; that a
    release lookup failing other than with a 404 stops it with gh's message; and that -WhatIf pushes and publishes
    nothing. Also checks that the version comes from the merged pull request's Release: line: with pre-release:
    untracked and no release heading it tags the merged commit with that version and publishes the [Unreleased] section,
    it does nothing for another commit's pull request or a description without the line, it accepts a line that agrees
    with the changelog and fails on one that disagrees, and it stops with gh's message when the pull request lookup
    fails. The stand-in also accepts the call that starts publish.yml. Also checks that it starts publish.yml once, on
    the tag, after publishing the release when publish.yml has a workflow_dispatch trigger, starts nothing on a second
    run or without a publish.yml, and fails naming the trigger when publish.yml has none, and fails naming publish.yml
    and the tag when starting it fails. Also checks that with pre-release: untracked the release notes stop at the link
    reference definitions and at the next ## heading. Also checks that release.yml runs the script on a push to main
    that changes CHANGELOG.md, with contents: write and the merged commit. Also checks that -Policy prints the release
    policy and does nothing else, and that tag-release.yml is named Tag and publish release, reads the policy in a
    read-only job and runs its write job only for release: tag or tag+release. Also checks that a merged pull request
    without a Release: line, once the changelog's newest section is tagged and published, tags nothing, publishes
    nothing and starts nothing. Also runs the tag and run-id checks of the template's publish.yml,
    release-provenance.yml and raise-baseline.yml in a pwsh process of their own: each accepts v1.2.3 and v1.2.3-rc.1,
    which raise-baseline.yml reads as 1.2.3 and as a prerelease, and refuses a tag with other Unicode digits, a final
    line break, a capital V or the Kelvin sign, and release-provenance.yml accepts only a run id of ASCII digits.
    Prints PASS or FAIL per check and exits 1 on any failure.

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

$templateWorkflow = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'template/.github/workflows/tag-release.yml')
Check 'tag-release.yml runs on every push to main and by hand' ($templateWorkflow -match '(?m)^  push:\r?\n    branches: \[main\]\r?\n  workflow_dispatch:')
Check 'tag-release.yml gives its job contents: write, actions: write and pull-requests: read' ($templateWorkflow -match '(?m)^    permissions:\r?\n      contents: write\r?\n      actions: write\r?\n      pull-requests: read\r?$')
Check 'tag-release.yml runs the template''s script on the merged commit and names no nuget push' ($templateWorkflow.Contains('run: ./.template/Publish-Release.ps1 -Commit $env:GITHUB_SHA') -and $templateWorkflow -notmatch '(?i)\bnuget(?:\.exe)?\s+push\b')
Check 'tag-release.yml is named Tag and publish release, not Release' ($templateWorkflow -match '(?m)^name: Tag and publish release\r?$')
$policyJob = [regex]::Match($templateWorkflow, '(?ms)^  policy:\r?\n.*?(?=^  (?:test|release):\r?$)').Value
Check 'tag-release.yml reads the release policy on main in a job with no permission of its own and no persisted token' ($policyJob -and $policyJob.Contains("if: github.ref == 'refs/heads/main'") -and $policyJob -notmatch 'permissions:' -and $policyJob.Contains('persist-credentials: false') -and $policyJob.Contains('./.template/Publish-Release.ps1 -Policy') -and $policyJob.Contains('release: ${{ steps.policy.outputs.release }}')) $policyJob
Check 'tag-release.yml runs its one write job after the policy and test jobs, only for release: tag or tag+release' ($templateWorkflow -match '(?m)^    needs: \[policy, test\]\r?\n    if: needs\.policy\.outputs\.release == ''tag'' \|\| needs\.policy\.outputs\.release == ''tag\+release''\r?$' -and [regex]::Matches($templateWorkflow, '(?m)^\s+contents: write\r?$').Count -eq 1)

$temp = Join-Path ([IO.Path]::GetTempPath()) "publish-release-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temp | Out-Null
$releases = Join-Path $temp 'releases'
New-Item -ItemType Directory -Path $releases | Out-Null
$standIn = Join-Path $temp 'gh.ps1'
# A stand-in for gh: `api repos/{owner}/{repo}/releases/tags/<tag>` succeeds when the release's file exists and else fails
# printing gh's 404 message, or a 401 one when PUBLISH_RELEASE_TEST_LOOKUP_ERROR is set; `api
# repos/{owner}/{repo}/releases -f tag_name=<tag> ... -F body=@<file>` copies the notes to it, `api
# repos/{owner}/{repo}/commits/<sha>/pulls` prints pulls.json (or [], or a 500 when PUBLISH_RELEASE_TEST_PULLS_ERROR is set),
# the publish.yml dispatch succeeds (or prints a 500 when PUBLISH_RELEASE_TEST_DISPATCH_ERROR is set), and every call is logged.
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
if ($args[0] -eq 'api' -and $args[1] -eq 'repos/{owner}/{repo}/actions/workflows/publish.yml/dispatches') {
    if ($env:PUBLISH_RELEASE_TEST_DISPATCH_ERROR) { 'gh: Server Error (HTTP 500)'; exit 1 }
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

function Invoke-StepLine([string[]]$Lines, [hashtable]$Variables) {
    $id = [guid]::NewGuid().ToString('N')
    $outputFile = Join-Path $temp "step-output-$id"
    $summaryFile = Join-Path $temp "step-summary-$id"
    New-Item -ItemType File -Path $outputFile, $summaryFile | Out-Null
    $set = @{} + $Variables
    $set['GITHUB_OUTPUT'] = $outputFile
    $set['GITHUB_STEP_SUMMARY'] = $summaryFile
    $saved = @{}
    foreach ($name in $set.Keys) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
    try {
        foreach ($name in $set.Keys) { [Environment]::SetEnvironmentVariable($name, $set[$name]) }
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($Lines -join [char]10)))
        $output = & pwsh -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1
        [pscustomobject]@{
            Code         = $LASTEXITCODE
            Output       = (($output | ForEach-Object { "$_" }) -join "`n")
            GitHubOutput = "$(Get-Content -Raw -LiteralPath $outputFile)"
            Summary      = "$(Get-Content -Raw -LiteralPath $summaryFile)"
        }
    } finally {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
}

try {
    $workflowDir = Join-Path $repoRoot 'template/.github/workflows'
    function Get-WorkflowLine([string]$File, [string[]]$Starts) {
        @(Get-Content -LiteralPath (Join-Path $workflowDir $File) | ForEach-Object { $_.Trim() } | Where-Object { $line = $_; $Starts | Where-Object { $line.StartsWith($_) } })
    }
    $publishTag = @(Get-WorkflowLine 'publish.yml' 'if ($env:TAG -')
    $provenanceTag = @(Get-WorkflowLine 'release-provenance.yml' 'if ($env:TAG -')
    $provenanceRun = @(Get-WorkflowLine 'release-provenance.yml' 'if ($env:RUN_ID -')
    $baselineTag = @(Get-WorkflowLine 'raise-baseline.yml' 'if ($env:TAG -', 'throw "The tag ''')
    Check 'tag check: the workflows have the lines this test runs' ($publishTag.Count -eq 1 -and $provenanceTag.Count -eq 1 -and $provenanceRun.Count -eq 1 -and $baselineTag.Count -eq 3) "$($publishTag.Count), $($provenanceTag.Count), $($provenanceRun.Count), $($baselineTag.Count)"

    $tagCases = [ordered]@{
        'v1.2.3'             = 'v1.2.3'
        'v1.2.3-rc.1'        = 'v1.2.3-rc.1'
        'other digits'       = "v$([char]0x0661).2.3"
        'a final line break' = "v1.2.3$([char]10)"
        'a capital V'        = 'V1.2.3'
        'the Kelvin sign'    = "v1.2.3-$([char]0x212A)"
    }
    foreach ($file in 'publish.yml', 'release-provenance.yml') {
        $lines = @(if ($file -eq 'publish.yml') { $publishTag } else { $provenanceTag })
        $wrong = foreach ($case in $tagCases.Keys) {
            $result = Invoke-StepLine ($lines + '"matched=$($Matches[1])"') @{ TAG = $tagCases[$case] }
            $ok = switch ($case) {
                'v1.2.3' { $result.Code -eq 0 -and ($result.Output -split "`n") -contains 'matched=1.2.3' }
                'v1.2.3-rc.1' { $result.Code -eq 0 -and ($result.Output -split "`n") -contains 'matched=1.2.3-rc.1' }
                default { $result.Code -ne 0 }
            }
            if (-not $ok) { $case }
        }
        Check "tag check: $file accepts v1.2.3 and v1.2.3-rc.1 and refuses other digits, a final line break, a capital V and the Kelvin sign" (-not $wrong) (@($wrong) -join ', ')
    }

    $runCases = [ordered]@{ '4242' = $true; "4$([char]0x0662)" = $false; "4242$([char]10)" = $false; '42a' = $false }
    $wrong = foreach ($id in $runCases.Keys) {
        $result = Invoke-StepLine $provenanceRun @{ RUN_ID = $id }
        if (($result.Code -eq 0) -ne $runCases[$id]) { "run id $($id.Length) characters: code $($result.Code)" }
    }
    Check 'tag check: release-provenance.yml accepts a run id of ASCII digits only' (-not $wrong) (@($wrong) -join ', ')

    $wrong = foreach ($case in $tagCases.Keys) {
        $result = Invoke-StepLine $baselineTag @{ TAG = $tagCases[$case] }
        $ok = switch ($case) {
            'v1.2.3' { $result.Code -eq 0 -and $result.GitHubOutput.Trim() -eq 'version=1.2.3' }
            'v1.2.3-rc.1' { $result.Code -eq 0 -and -not $result.GitHubOutput.Trim() -and $result.Summary.Contains('is a prerelease') }
            default { $result.Code -ne 0 }
        }
        if (-not $ok) { $case }
    }
    Check 'tag check: raise-baseline.yml reads v1.2.3 as 1.2.3, calls v1.2.3-rc.1 a prerelease and refuses the rest' (-not $wrong) (@($wrong) -join ', ')

    $work = New-Clone 'full' '- release: tag+release'
    $head = (& git -C $work rev-parse HEAD)
    $run = Invoke-Publish $work
    Check 'a new version: the script exits 0' ($run.Code -eq 0) $run.Output
    Check 'a new version: origin gets the tag v0.2.0' ((Get-OriginTag $work) -ccontains 'v0.2.0') ((Get-OriginTag $work) -join ', ')
    Check 'a new version: the tag is annotated and names the commit' ((& git -C $work cat-file -t 'refs/tags/v0.2.0') -eq 'tag' -and (& git -C $work rev-parse 'v0.2.0^{commit}') -eq $head)
    Check 'a new version: without -Sign the tag carries no signature' (-not ((& git -C $work cat-file -p 'refs/tags/v0.2.0') -join "`n").Contains('-----BEGIN')) ''
    $notesPath = Join-Path $releases 'v0.2.0'
    $notes = if (Test-Path -LiteralPath $notesPath) { (Get-Content -Raw -LiteralPath $notesPath).Trim() } else { '' }
    Check 'a new version: the release has the section without its heading or the link references' ($notes -eq "### Added`n`n- The second thing.") $notes
    Check 'a new version: the release is named with the version and created once' ((@(Get-Calls) -match '^api repos/\{owner\}/\{repo\}/releases -f tag_name=v0\.2\.0 -f name=v0\.2\.0 -F body=@').Count -eq 1) ((Get-Calls) -join ' | ')
    Check 'no publish.yml: it starts nothing' (-not (@(Get-Calls) -match 'dispatches')) ((Get-Calls) -join ' | ')

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

    $work = New-Clone 'other-digits' '- release: tag+release' $changelog.Replace('## [0.2.0] - 2026-11-08', "## [$([char]0x0661).3.0] - 2026-11-15")
    $run = Invoke-Publish $work
    Check 'a release heading in other digits: it tags nothing and says the release isn''t shaped like 1.2.3' ($run.Code -eq 0 -and $run.Output -match 'isn''t shaped like 1\.2\.3' -and -not (Get-OriginTag $work)) $run.Output

    $work = New-Clone 'signed' '- release: tag+release'
    # A stand-in for the signing program: it reads the tag's text, reports a signature on Git's status file descriptor and prints one.
    $signer = Join-Path $temp 'fake-sign'
    $signerLines = @(
        '#!/bin/sh',
        'cat >/dev/null',
        "printf '\n[GNUPG:] SIG_CREATED \n' >&2",
        "printf '%s\n' '-----BEGIN SIGNED MESSAGE-----' 'c3RhbmQtaW4=' '-----END SIGNED MESSAGE-----'"
    )
    [IO.File]::WriteAllText($signer, (($signerLines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    if (-not $IsWindows) { & chmod +x $signer }
    & git -C $work config gpg.format x509
    & git -C $work config gpg.x509.program ($signer -replace '\\', '/')
    $run = Invoke-Publish $work @('-Sign')
    Check '-Sign: the script exits 0' ($run.Code -eq 0) $run.Output
    Check '-Sign: origin gets the tag v0.2.0' ((Get-OriginTag $work) -ccontains 'v0.2.0') ((Get-OriginTag $work) -join ', ')
    Check '-Sign: the tag holds the signature' (((& git -C $work cat-file -p 'refs/tags/v0.2.0') -join "`n").Contains('-----BEGIN SIGNED MESSAGE-----')) ((& git -C $work cat-file -p 'refs/tags/v0.2.0') -join "`n")

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

    $policyCases = @(
        @{ Landing = '- release: tag+release'; Want = 'tag+release' },
        @{ Landing = '- release: tag'; Want = 'tag' },
        @{ Landing = '- release: none'; Want = 'none' },
        @{ Landing = '- integrate: pull-request'; Want = 'none' })
    for ($i = 0; $i -lt $policyCases.Count; $i++) {
        $case = $policyCases[$i]
        $work = New-Clone "policy-$i" $case.Landing
        $run = Invoke-Publish $work @('-Policy')
        Check "-Policy prints $($case.Want) for '$($case.Landing)', tags nothing and calls no gh" ($run.Code -eq 0 -and $run.Output.Trim() -ceq $case.Want -and -not (Get-OriginTag $work).Count -and -not (Get-Calls).Count) $run.Output
    }
    $work = New-Clone 'policy-no-agents' '- release: tag+release'
    Remove-Item -LiteralPath (Join-Path $work 'AGENTS.md')
    $run = Invoke-Publish $work @('-Policy')
    Check '-Policy prints none without AGENTS.md' ($run.Code -eq 0 -and $run.Output.Trim() -ceq 'none') $run.Output
    $work = New-Clone 'policy-bad' '- release: always'
    $run = Invoke-Publish $work @('-Policy')
    Check '-Policy fails on an unknown release value and names it' ($run.Code -ne 0 -and $run.Output -match 'release: always') $run.Output

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

    $work = New-Clone 'version-file-disagrees' '- release: tag+release' -Files @{ 'version.json' = '{ "version": "0.1.0" }' }
    Remove-Item -LiteralPath (Join-Path $releases 'pulls.json'), (Join-Path $releases 'v0.2.0') -ErrorAction SilentlyContinue
    $run = Invoke-Publish $work
    Check 'a version.json that disagrees with the changelog: it fails, names both versions and tags nothing' ($run.Code -ne 0 -and $run.Output -match '0\.1\.0' -and $run.Output -match '0\.2\.0' -and -not (Get-OriginTag $work).Count) $run.Output

    $work = New-Clone 'version-file-agrees' '- release: tag+release' -Files @{ 'version.json' = '{ "version": "0.2.0" }' }
    Remove-Item -LiteralPath (Join-Path $releases 'pulls.json'), (Join-Path $releases 'v0.2.0') -ErrorAction SilentlyContinue
    $run = Invoke-Publish $work
    Check 'a version.json that agrees with the changelog: it tags v0.2.0' ($run.Code -eq 0 -and (Get-OriginTag $work) -ccontains 'v0.2.0') $run.Output

    $work = New-Clone 'version-file-unreadable' '- release: tag+release' -Files @{ 'version.json' = 'not json' }
    Remove-Item -LiteralPath (Join-Path $releases 'pulls.json'), (Join-Path $releases 'v0.2.0') -ErrorAction SilentlyContinue
    $run = Invoke-Publish $work
    Check 'a version.json that isn''t JSON: it fails and tags nothing' ($run.Code -ne 0 -and -not (Get-OriginTag $work).Count) $run.Output

    $work = New-Clone 'pulls-error' '- release: tag+release'
    Remove-Item -LiteralPath (Join-Path $releases 'pulls.json'), (Join-Path $releases 'v0.2.0') -ErrorAction SilentlyContinue
    $env:PUBLISH_RELEASE_TEST_PULLS_ERROR = '1'
    try { $run = Invoke-Publish $work } finally { Remove-Item Env:PUBLISH_RELEASE_TEST_PULLS_ERROR }
    Check 'a pull request lookup that fails: it fails with gh''s message and tags nothing' ($run.Code -ne 0 -and $run.Output -match 'HTTP 500' -and -not (Get-OriginTag $work).Count) $run.Output

    $publishWith = "name: Publish packages`non:`n  release:`n    types: [published]`n  workflow_dispatch:`n    inputs:`n      tag:`n        required: true`n        type: string`njobs: {}`n"
    $publishWithout = "name: Publish packages`non:`n  release:`n    types: [published]`njobs: {}`n"

    $work = New-Clone 'publish-dispatch' '- release: tag+release' -Files @{ '.github/workflows/publish.yml' = $publishWith }
    Remove-Item -LiteralPath (Join-Path $releases 'pulls.json'), (Join-Path $releases 'v0.2.0') -ErrorAction SilentlyContinue
    $run = Invoke-Publish $work
    Check 'publish.yml with workflow_dispatch: it starts publish.yml once, on the tag, with the tag as input' ($run.Code -eq 0 -and (@(Get-Calls) -match '^api repos/\{owner\}/\{repo\}/actions/workflows/publish\.yml/dispatches -f ref=v0\.2\.0 -f inputs\[tag\]=v0\.2\.0').Count -eq 1) ($run.Output + ' | ' + ((Get-Calls) -join ' | '))
    $run = Invoke-Publish $work
    Check 'publish.yml with workflow_dispatch: a second run starts nothing' ($run.Code -eq 0 -and -not (@(Get-Calls) -match 'dispatches')) ($run.Output + ' | ' + ((Get-Calls) -join ' | '))

    # A merged pull request without a Release: line, such as a plan's that changes nothing a release ships, after the newest section's release: it tags nothing, publishes nothing and starts nothing (#439).
    $work = New-Clone 'no-release-line' '- release: tag+release' -Files @{ '.github/workflows/publish.yml' = $publishWith }
    Remove-Item -LiteralPath (Join-Path $releases 'pulls.json'), (Join-Path $releases 'v0.2.0') -ErrorAction SilentlyContinue
    $null = Invoke-Publish $work
    Set-Content -LiteralPath (Join-Path $work 'CHANGELOG.md') -Encoding utf8NoBOM -Value ($changelog -replace '(?m)^## \[Unreleased\]\r?$', "## [Unreleased]`n`n### Changed`n`n- The site's pages read better.")
    & git -C $work commit -q -am 'Change only the site'
    & git -C $work push -q origin HEAD:refs/heads/main 2>$null
    $head = (& git -C $work rev-parse HEAD)
    Set-Pulls $head "Summary.`n`nCloses #5"
    $run = Invoke-Publish $work
    Check 'a pull request without a Release: line after the newest section''s release: it tags nothing, publishes nothing and starts nothing (#439)' ($run.Code -eq 0 -and @(Get-OriginTag $work).Count -eq 1 -and (& git -C $work rev-parse 'v0.2.0^{commit}') -ne $head -and -not (@(Get-Calls) -match '^api repos/\{owner\}/\{repo\}/releases -f|dispatches') -and $run.Output -match 'has the tag v0\.2\.0 already' -and $run.Output -match 'has the release v0\.2\.0 already') ($run.Output + ' | ' + ((Get-Calls) -join ' | '))

    $work = New-Clone 'publish-no-dispatch' '- release: tag+release' -Files @{ '.github/workflows/publish.yml' = $publishWithout }
    Remove-Item -LiteralPath (Join-Path $releases 'pulls.json'), (Join-Path $releases 'v0.2.0') -ErrorAction SilentlyContinue
    $run = Invoke-Publish $work
    Check 'publish.yml without workflow_dispatch: it publishes the release, then fails and names the trigger' ($run.Code -ne 0 -and (Test-Path -LiteralPath (Join-Path $releases 'v0.2.0')) -and $run.Output -match 'workflow_dispatch' -and -not (@(Get-Calls) -match 'dispatches')) ($run.Output + ' | ' + ((Get-Calls) -join ' | '))

    $notesChangelogBase = "# Changelog`n`n## [Unreleased]`n`n### Added`n`n- The product does a thing.`n`n"
    $stopCases = @(
        @{ Name = 'pre-release: untracked, the release notes stop at the link reference definitions'; Dir = 'untracked-notes-links'; Changelog = $notesChangelogBase + "[unreleased]: https://example.com/compare/v0.2.0...HEAD`n" }
        @{ Name = 'pre-release: untracked, the release notes stop at the next ## heading'; Dir = 'untracked-notes-heading'; Changelog = $notesChangelogBase + "## Notes`n`n- Not part of the release.`n" }
    )
    foreach ($case in $stopCases) {
        $work = New-Clone $case.Dir $untrackedLanding $case.Changelog
        $head = (& git -C $work rev-parse HEAD)
        Remove-Item -LiteralPath (Join-Path $releases 'pulls.json'), (Join-Path $releases 'v0.3.0') -ErrorAction SilentlyContinue
        Set-Pulls $head $body030
        $run = Invoke-Publish $work
        $notesPath = Join-Path $releases 'v0.3.0'
        $notes = if (Test-Path -LiteralPath $notesPath) { (Get-Content -Raw -LiteralPath $notesPath).Trim() } else { '' }
        Check $case.Name ($run.Code -eq 0 -and $notes -eq "### Added`n`n- The product does a thing.") ($run.Output + ' | ' + $notes)
    }

    $work = New-Clone 'publish-dispatch-error' '- release: tag+release' -Files @{ '.github/workflows/publish.yml' = $publishWith }
    Remove-Item -LiteralPath (Join-Path $releases 'pulls.json'), (Join-Path $releases 'v0.2.0') -ErrorAction SilentlyContinue
    $env:PUBLISH_RELEASE_TEST_DISPATCH_ERROR = '1'
    try { $run = Invoke-Publish $work } finally { Remove-Item Env:PUBLISH_RELEASE_TEST_DISPATCH_ERROR }
    Check 'publish.yml start that fails: it fails and names publish.yml and the tag' ($run.Code -ne 0 -and $run.Output -match 'publish\.yml' -and $run.Output -match 'v0\.2\.0' -and (Test-Path -LiteralPath (Join-Path $releases 'v0.2.0'))) $run.Output
} finally {
    Remove-Item Env:PUBLISH_RELEASE_TEST_RELEASES -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { "Tests: FAILED ($($failures.Count))"; exit 1 }
'Tests: PASSED'
# The last git or pwsh call above may have failed on purpose; a caller that reads $LASTEXITCODE, as CI's pwsh shell does, sees 0.
exit 0
