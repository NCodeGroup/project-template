<#
.SYNOPSIS
    Test the template update notice every GitHub project runs weekly, .template\Get-TemplateUpdate.ps1.

.DESCRIPTION
    Builds a fixture template repository whose tags carry a fixture CHANGELOG.md, and a fixture project whose
    .copier-answers.yml names it, so the script reads tags and release notes with Git and no network. A stand-in for
    gh keeps the fixture repository's issues and labels and records every call; the test first checks that `gh`
    resolves to it. Runs the script with the project already current, one version behind, again one version behind,
    three versions behind, and current again, and checks that it opens one issue with the right title, label and
    release notes, leaves it alone when nothing changed, edits and retitles that same issue, closes it once the project
    is current, and ignores tags that aren't versions. Then checks the version from _commit, an existing label, the
    oldest of several open notices, the old address and Copier's shorthands (rewritten to the fixture with Git's
    insteadOf, so nothing reaches the network), a changelog too long for one issue, one with no section for the new
    version, a tag without CHANGELOG.md, and the runs that fail: an unreadable template (with Git's message), no
    _src_path, no version tags, and an unreadable or empty project version.
    Prints PASS or FAIL per check and exits 1 on any failure. The checks take seconds.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-notice-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-TemplateUpdate.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-notice-test-$PID")
)
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Write-Text([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))
}
function Invoke-Git {
    git -c user.name=template-test -c user.email=template-test@example.invalid -c core.autocrlf=false @args
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed." }
}

if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$bin = Join-Path $Work 'bin'
$template = Join-Path $Work 'template'
$project = Join-Path $Work 'project'
New-Item -ItemType Directory -Force $bin, $template, (Join-Path $project '.template') | Out-Null

# The stand-in for gh. It keeps the repository's issues and labels in state.json and records every call in calls.log.
Write-Text (Join-Path $bin 'gh.ps1') @'
$log = Join-Path $PSScriptRoot 'calls.log'
Add-Content -LiteralPath $log -Value ($args -join ' ')
$stateFile = Join-Path $PSScriptRoot 'state.json'
$state = Get-Content -Raw -LiteralPath $stateFile | ConvertFrom-Json -AsHashtable
function Save { Set-Content -LiteralPath $stateFile -Value (ConvertTo-Json -InputObject $state -Depth 5) }
$command = "$($args[0]) $($args[1])"
$i = [array]::IndexOf($args, '--label')
$labelOption = if ($i -ge 0) { $args[$i + 1] }
$i = [array]::IndexOf($args, '--title')
$title = if ($i -ge 0) { $args[$i + 1] }
$i = [array]::IndexOf($args, '--body-file')
$body = if ($i -ge 0) { [IO.File]::ReadAllText($args[$i + 1]) }
switch ($command) {
    'issue list' {
        ConvertTo-Json -InputObject @($state.issues | Where-Object { $_.state -eq 'open' -and $labelOption -in $_.labels } | ForEach-Object { @{ number = $_.number; title = $_.title; body = $_.body } })
        exit 0
    }
    'label list' { ConvertTo-Json -InputObject @($state.labels | ForEach-Object { @{ name = $_ } }); exit 0 }
    'label create' { $state.labels = @($state.labels) + $args[2]; Save; exit 0 }
    'issue create' {
        $number = @($state.issues).Count + 1
        $state.issues = @($state.issues) + @{ number = $number; title = $title; body = $body; labels = @($labelOption); state = 'open'; comments = @() }
        Save
        "https://github.com/owner/project/issues/$number"
        exit 0
    }
    'issue edit' {
        $number = [int]$args[2]
        $issue = $state.issues | Where-Object { $_.number -eq $number }
        $issue.title = $title; $issue.body = $body; Save; exit 0
    }
    'issue close' {
        $number = [int]$args[2]
        $issue = $state.issues | Where-Object { $_.number -eq $number }
        $i = [array]::IndexOf($args, '--comment')
        $issue.state = 'closed'; $issue.comments = @($issue.comments) + $args[$i + 1]; Save; exit 0
    }
}
exit 1
'@
Write-Text (Join-Path $bin 'state.json') '{ "issues": [], "labels": ["bug"] }'

# The fixture template: each version's tag carries a changelog with every section up to it, under an Unreleased section.
# -Filler adds that many lines to each section, for a changelog too long for one issue. -Pad adds that many x characters
# to the end of the newest section's first change line.
function Get-FixtureChangelog([string[]]$Versions, [int]$Filler = 0, [int]$Pad = 0) {
    $text = "# Changelog`n`nWhat each template version changes.`n`n## [Unreleased]`n`n### Added`n`n- Unreleased work.`n`n"
    foreach ($v in $Versions) {
        $padding = if ($v -eq $Versions[0]) { 'x' * $Pad } else { '' }
        $text += "## [$v] - 2026-10-0$($v.Split('.')[1])`n`n### Changed`n`n- Change in $v, with an em dash — and a link ([#$($v.Split('.')[1])](https://example.invalid/$v)).$padding`n"
        $text += "- Another change in $v, one of many.`n" * $Filler
        $text += "`n"
    }
    $text += ($Versions | ForEach-Object { "[$_]: https://example.invalid/compare/$_" }) -join "`n"
    $text + "`n"
}
function Add-TemplateVersion([string]$Version, [string[]]$Versions, [int]$Filler = 0, [int]$Pad = 0, [switch]$Annotated, [switch]$NoChangelog, [switch]$Retag) {
    if ($NoChangelog) { Invoke-Git -C $template rm -q CHANGELOG.md }
    else {
        Write-Text (Join-Path $template 'CHANGELOG.md') (Get-FixtureChangelog $Versions $Filler $Pad)
        Invoke-Git -C $template add CHANGELOG.md
    }
    Invoke-Git -C $template commit -q -m "Release $Version"
    # -Retag moves an existing tag to the new commit.
    $force = @(if ($Retag) { '-f' })
    if ($Annotated) { Invoke-Git -C $template tag @force -a "v$Version" -m "v$Version" } else { Invoke-Git -C $template tag @force "v$Version" }
}
Invoke-Git -C $template init -q -b main
Add-TemplateVersion '0.1.0' @('0.1.0')
Add-TemplateVersion '0.2.0' @('0.2.0', '0.1.0')
# Tags that aren't versions count for nothing.
Invoke-Git -C $template tag 'v0.9.0-rc.1'
Invoke-Git -C $template tag 'latest'

Copy-Item -LiteralPath (Join-Path $repoRoot 'template\.template\Get-TemplateUpdate.ps1') -Destination (Join-Path $project '.template')
$templateUrl = 'file:///' + ($template -replace '\\', '/')
Write-Text (Join-Path $project '.copier-answers.yml') "# Written by Copier`n_commit: v0.1.0`n_src_path: $templateUrl`nproject_name: Fixture`n"
function Set-ProjectVersion([string]$Version) { Write-Text (Join-Path $project '.template-version') "$Version`n" }
function Set-Answer([string]$Text) { Write-Text (Join-Path $project '.copier-answers.yml') "# Written by Copier`n$Text`nproject_name: Fixture`n" }
function Set-GhState([string]$Json) { Write-Text (Join-Path $bin 'state.json') $Json }
function New-Issue([int]$Number, [string]$Title, [string[]]$Labels) {
    @{ number = $Number; title = $Title; body = "Body of #$Number"; labels = $Labels; state = 'open'; comments = @() }
}

$script = Join-Path $project '.template\Get-TemplateUpdate.ps1'
$calls = Join-Path $bin 'calls.log'
function Invoke-Notice {
    if (Test-Path -LiteralPath $calls) { Remove-Item -LiteralPath $calls -Force }
    $output = & pwsh -NoProfile -File $script 2>&1 | Out-String
    [pscustomobject]@{
        Output = $output
        # The output on one line: PowerShell wraps an error to the console's width, continuing it on lines that start with |.
        Flat = ($output -replace '\r?\n\s*\|?\s*', ' ' -replace '\s+', ' ')
        ExitCode = $LASTEXITCODE
        Calls = @(if (Test-Path -LiteralPath $calls) { Get-Content -LiteralPath $calls })
        Issues = @((Get-Content -Raw -LiteralPath (Join-Path $bin 'state.json') | ConvertFrom-Json).issues)
        Labels = @((Get-Content -Raw -LiteralPath (Join-Path $bin 'state.json') | ConvertFrom-Json).labels)
    }
}
function Get-Change($Run) { @($Run.Calls | Where-Object { $_ -match '^(issue (create|edit|close)|label create)' }) }

$savedPath = $env:PATH
$env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
$gitConfig = 'GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0', 'GIT_CONFIG_KEY_1', 'GIT_CONFIG_VALUE_1'
try {
    # The script runs `gh`; it must reach the stand-in, never a real gh with the runner's credentials.
    $gh = Get-Command gh -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gh -or $gh.Source -ne (Join-Path $bin 'gh.ps1')) { throw "gh resolves to $(if ($gh) { $gh.Source } else { 'nothing' }), not the stand-in in $bin." }

    # 1. Already current: a version between tags counts as the tag before it.
    Set-ProjectVersion 'v0.2.0-3-gabc1234'
    $r = Invoke-Notice
    Check 'current: exits 0 and says the project is on the newest version' ($r.ExitCode -eq 0 -and $r.Output -match 'on project-template v0\.2\.0, the newest version') $r.Output
    Check 'current: opens no issue and creates no label' ((Get-Change $r).Count -eq 0 -and $r.Issues.Count -eq 0) ($r.Calls -join ' | ')

    # 2. One version behind: one issue, with the label created first.
    Set-ProjectVersion 'v0.1.0'
    $r = Invoke-Notice
    $issue = $r.Issues | Select-Object -First 1
    Check 'one behind: exits 0 and opens one issue' ($r.ExitCode -eq 0 -and $r.Issues.Count -eq 1 -and $r.Output -match 'Opened https://github\.com/owner/project/issues/1') $r.Output
    Check 'one behind: creates the missing label, then the issue with it' (((Get-Change $r) -join ' | ') -match '^label create template-update .* \| issue create --title Update to project-template v0\.2\.0 --label template-update --body-file ') ($r.Calls -join ' | ')
    Check 'one behind: the issue is titled with the newest version and labeled template-update' ($issue.title -eq 'Update to project-template v0.2.0' -and @($issue.labels) -contains 'template-update') "$($issue.title) / $($issue.labels -join ',')"
    Check 'one behind: the body says how far behind and how to plan the update' ("$($issue.body)".Contains('This project is on project-template v0.1.0. The newest version is v0.2.0, one version later.') -and "$($issue.body)".Contains('`/plan-issue`') -and "$($issue.body)".Contains('`/plan-template-update v0.2.0`') -and "$($issue.body)".Contains('## Changes since v0.1.0')) $issue.body
    Check 'one behind: the body has the new version''s section, characters intact, and nothing else' ("$($issue.body)".Contains('## [0.2.0] - 2026-10-02') -and "$($issue.body)".Contains('- Change in 0.2.0, with an em dash — and a link ([#2](https://example.invalid/0.2.0)).') -and -not "$($issue.body)".Contains('0.1.0]') -and -not "$($issue.body)".Contains('Unreleased') -and -not "$($issue.body)".Contains('example.invalid/compare')) $issue.body

    # 3. Run again with nothing new: the same issue, untouched.
    $r = Invoke-Notice
    Check 'second run: no new issue, no edit and no label' ($r.ExitCode -eq 0 -and $r.Issues.Count -eq 1 -and (Get-Change $r).Count -eq 0 -and $r.Output -match '#1 already says: Update to project-template v0\.2\.0') "$($r.Output) $($r.Calls -join ' | ')"

    # 4. Three versions behind, once two more versions are out, the newest with an annotated tag: the same issue, retitled.
    Add-TemplateVersion '0.3.0' @('0.3.0', '0.2.0', '0.1.0')
    Add-TemplateVersion '0.4.0' @('0.4.0', '0.3.0', '0.2.0', '0.1.0') -Annotated
    $r = Invoke-Notice
    $issue = $r.Issues | Select-Object -First 1
    Check 'three behind: edits the open issue instead of opening another' ($r.ExitCode -eq 0 -and $r.Issues.Count -eq 1 -and ((Get-Change $r) -join ' | ') -match '^issue edit 1 --title Update to project-template v0\.4\.0 --body-file ' -and $r.Output -match 'Updated #1') "$($r.Output) $($r.Calls -join ' | ')"
    Check 'three behind: the issue is retitled to the newest version' ($issue.title -eq 'Update to project-template v0.4.0') $issue.title
    $at = @('## [0.4.0]', '## [0.3.0]', '## [0.2.0]' | ForEach-Object { "$($issue.body)".IndexOf($_) })
    Check 'three behind: the body has the three newer sections, newest first, and not the project''s own' ("$($issue.body)".Contains('The newest version is v0.4.0, 3 versions later.') -and $at[0] -ge 0 -and $at[0] -lt $at[1] -and $at[1] -lt $at[2] -and -not "$($issue.body)".Contains('## [0.1.0]') -and -not "$($issue.body)".Contains('Unreleased')) $issue.body

    # 5. Updated to the newest version: the issue is closed with a comment.
    Set-ProjectVersion 'v0.4.0'
    $r = Invoke-Notice
    $issue = $r.Issues | Select-Object -First 1
    Check 'updated: closes the issue with a comment' ($r.ExitCode -eq 0 -and $issue.state -eq 'closed' -and @($issue.comments).Count -eq 1 -and "$(@($issue.comments)[0])".Contains('on project-template v0.4.0, the newest version') -and $r.Output -match 'Closed #1') "$($r.Output) $($r.Calls -join ' | ')"

    # 6. Current with no open issue: nothing to do.
    $r = Invoke-Notice
    Check 'current again: changes nothing' ($r.ExitCode -eq 0 -and (Get-Change $r).Count -eq 0 -and $r.Issues.Count -eq 1 -and @($r.Labels | Where-Object { $_ -eq 'template-update' }).Count -eq 1) "$($r.Output) $($r.Calls -join ' | ')"

    # 7. A template it can't read fails the run.
    Write-Text (Join-Path $project '.copier-answers.yml') "_commit: v0.1.0`n_src_path: $templateUrl-missing`n"
    $r = Invoke-Notice
    Check 'unreadable template: exits non-zero and names the address' ($r.ExitCode -ne 0 -and $r.Flat.Contains("Can't read the project template's tags at") -and $r.Flat.Contains('template-missing')) $r.Output
    Check 'unreadable template: the error says what Git said' ($r.Flat -match 'Git says: \S') $r.Output

    # 8. No .template-version: the version is _commit in .copier-answers.yml. The label exists, so it isn't created.
    Remove-Item -LiteralPath (Join-Path $project '.template-version') -Force
    Set-Answer "_commit: v0.3.0`n_src_path: $templateUrl"
    Set-GhState '{ "issues": [], "labels": ["bug", "template-update"] }'
    $r = Invoke-Notice
    $issue = $r.Issues | Select-Object -First 1
    Check 'no .template-version: reads the version from _commit' ($r.ExitCode -eq 0 -and "$($issue.body)".Contains('This project is on project-template v0.3.0. The newest version is v0.4.0, one version later.')) "$($r.Output) $($issue.body)"
    Check 'label exists: opens the issue without creating the label' (((Get-Change $r) -join ' | ') -match '^issue create --title Update to project-template v0\.4\.0 --label template-update --body-file [^|]*$' -and @($r.Labels | Where-Object { $_ -eq 'template-update' }).Count -eq 1) ($r.Calls -join ' | ')

    # 9. Several open notices, listed out of number order, and an issue with another label: the oldest notice is the one
    # edited, then closed, and the others are left alone.
    Set-ProjectVersion 'v0.1.0'
    Set-GhState (ConvertTo-Json -Depth 5 -InputObject @{ labels = @('bug', 'template-update'); issues = @(
                (New-Issue 5 'Update to project-template v0.3.0' @('template-update')),
                (New-Issue 3 'Update to project-template v0.2.0' @('template-update')),
                (New-Issue 2 'A bug' @('bug'))) })
    $r = Invoke-Notice
    $byNumber = @{}; foreach ($i in $r.Issues) { $byNumber[[int]$i.number] = $i }
    Check 'several open: edits the oldest notice only' ($r.ExitCode -eq 0 -and ((Get-Change $r) -join ' | ') -match '^issue edit 3 --title Update to project-template v0\.4\.0 --body-file [^|]*$' -and $byNumber[3].title -eq 'Update to project-template v0.4.0') "$($r.Output) $($r.Calls -join ' | ')"
    Check 'several open: leaves the newer notice and the other issue alone' ($byNumber[5].title -eq 'Update to project-template v0.3.0' -and $byNumber[5].body -eq 'Body of #5' -and $byNumber[2].body -eq 'Body of #2' -and $r.Issues.Count -eq 3) ($r.Issues | ConvertTo-Json -Depth 5)
    Set-ProjectVersion 'v0.4.0'
    $r = Invoke-Notice
    $byNumber = @{}; foreach ($i in $r.Issues) { $byNumber[[int]$i.number] = $i }
    Check 'several open, current: closes the oldest notice only' ($r.ExitCode -eq 0 -and ((Get-Change $r) -join ' | ') -match '^issue close 3 ' -and $byNumber[3].state -eq 'closed' -and $byNumber[5].state -eq 'open' -and $byNumber[2].state -eq 'open') "$($r.Output) $($r.Calls -join ' | ')"

    # From here the project names the template by Copier's shorthand for its old GitHub address. Git rewrites the new
    # address to the fixture, and every other https address to one that doesn't exist, so nothing reaches the network.
    $env:GIT_CONFIG_COUNT = '2'
    $env:GIT_CONFIG_KEY_0 = "url.$templateUrl.insteadOf"
    $env:GIT_CONFIG_VALUE_0 = 'https://github.com/NCodeGroup/project-template.git'
    $env:GIT_CONFIG_KEY_1 = "url.$templateUrl-offline/.insteadOf"
    $env:GIT_CONFIG_VALUE_1 = 'https://'
    Set-Answer "_commit: v0.1.0`n_src_path: gh:polewskm/project-template"

    # 10. A changelog too long for one issue: the oldest sections are left out, with a link to the whole file.
    Add-TemplateVersion '0.5.0' @('0.5.0', '0.4.0', '0.3.0', '0.2.0', '0.1.0') -Filler 700
    Set-ProjectVersion 'v0.1.0'
    Set-GhState '{ "issues": [], "labels": ["bug"] }'
    $r = Invoke-Notice
    $body = "$((@($r.Issues) | Select-Object -First 1).body)"
    Check 'old address: reads the template at its new address' ($r.ExitCode -eq 0 -and $r.Issues.Count -eq 1 -and $body.Contains('The newest version is v0.5.0, 4 versions later.')) "$($r.Output) $($r.Calls -join ' | ')"
    Check 'long changelog: the body fits in an issue and keeps the newest sections' ($body.Length -lt 65536 -and $body.Contains('## [0.5.0]') -and $body.Contains('## [0.4.0]') -and -not $body.Contains('## [0.3.0]') -and -not $body.Contains('## [0.2.0]')) "length $($body.Length)"
    Check 'long changelog: says how many sections are left out and links to CHANGELOG.md at the tag' ($body.TrimEnd().EndsWith("The 2 older section(s) don't fit in an issue; read them in [CHANGELOG.md](https://github.com/NCodeGroup/project-template/blob/v0.5.0/CHANGELOG.md).")) $body.Substring([Math]::Max(0, $body.Length - 300))

    # 11. A changelog with no section for the new version: the body links to it.
    Add-TemplateVersion '0.6.0' @('0.4.0', '0.3.0', '0.2.0', '0.1.0')
    Set-ProjectVersion 'v0.5.0'
    Set-GhState '{ "issues": [], "labels": ["bug"] }'
    $r = Invoke-Notice
    $body = "$((@($r.Issues) | Select-Object -First 1).body)"
    Check 'no section: the body says so and links to CHANGELOG.md at the tag' ($r.ExitCode -eq 0 -and $body.TrimEnd().EndsWith('The release notes have no section for these versions; read [CHANGELOG.md](https://github.com/NCodeGroup/project-template/blob/v0.6.0/CHANGELOG.md).')) "$($r.Output) $body"

    # 12. A tag without CHANGELOG.md: a warning, and a body that links to the release instead.
    Add-TemplateVersion '0.7.0' -NoChangelog
    Set-ProjectVersion 'v0.6.0'
    Set-GhState '{ "issues": [], "labels": ["bug"] }'
    $r = Invoke-Notice
    $body = "$((@($r.Issues) | Select-Object -First 1).body)"
    Check 'no CHANGELOG.md: exits 0 with a warning' ($r.ExitCode -eq 0 -and $r.Flat -match 'no CHANGELOG\.md at v0\.7\.0') $r.Output
    Check 'no CHANGELOG.md: the body says so and links to the release' ($body.TrimEnd().EndsWith('The project template has no CHANGELOG.md at v0.7.0; read [the v0.7.0 release](https://github.com/NCodeGroup/project-template/releases/tag/v0.7.0).')) $body

    # 13. A newest section too long for an issue on its own: no section is listed, and none is called older.
    Add-TemplateVersion '0.8.0' @('0.8.0') -Filler 1600
    Set-ProjectVersion 'v0.7.0'
    Set-GhState '{ "issues": [], "labels": ["bug"] }'
    $r = Invoke-Notice
    $body = "$((@($r.Issues) | Select-Object -First 1).body)"
    Check 'one long section: the body fits and links to CHANGELOG.md at the tag without calling it older' ($r.ExitCode -eq 0 -and $body.Length -lt 60500 -and -not $body.Contains('## [0.8.0]') -and -not $body.Contains('older') -and $body.TrimEnd().EndsWith("The release notes for these versions don't fit in an issue; read them in [CHANGELOG.md](https://github.com/NCodeGroup/project-template/blob/v0.8.0/CHANGELOG.md).")) "$($r.Output) length $($body.Length): $($body.Substring([Math]::Max(0, $body.Length - 300)))"

    # 14. A body exactly at the 60,000-character limit keeps the newest section; one character more leaves it out. A first
    # run measures the body's head and the section, so the next runs can pad the section to the limit.
    Add-TemplateVersion '0.9.0' @('0.9.0')
    Set-ProjectVersion 'v0.8.0'
    Set-GhState '{ "issues": [], "labels": ["bug"] }'
    $r = Invoke-Notice
    $body = "$((@($r.Issues) | Select-Object -First 1).body)"
    $head = $body.IndexOf('## [0.9.0]')
    $section = $body.Length - $head - 1
    Check 'limit: the first run lists the section' ($r.ExitCode -eq 0 -and $head -gt 0) "$($r.Output) length $($body.Length)"
    # The script keeps a section while the body so far, the section and its two line breaks come to at most 60,000.
    $pad = 60000 - $head - $section - 2
    Add-TemplateVersion '0.9.0' @('0.9.0') -Pad $pad -Retag
    Set-GhState '{ "issues": [], "labels": ["bug"] }'
    $r = Invoke-Notice
    $body = "$((@($r.Issues) | Select-Object -First 1).body)"
    Check 'limit: a body exactly at the limit keeps the newest section' ($r.ExitCode -eq 0 -and $body.Contains('## [0.9.0]') -and -not $body.Contains("don't fit") -and $body.Length -eq 59999) "$($r.Output) length $($body.Length)"
    Add-TemplateVersion '0.9.0' @('0.9.0') -Pad ($pad + 1) -Retag
    Set-GhState '{ "issues": [], "labels": ["bug"] }'
    $r = Invoke-Notice
    $body = "$((@($r.Issues) | Select-Object -First 1).body)"
    Check 'limit: one character over leaves the section out and links to CHANGELOG.md' ($r.ExitCode -eq 0 -and -not $body.Contains('## [0.9.0]') -and $body.TrimEnd().EndsWith("The release notes for these versions don't fit in an issue; read them in [CHANGELOG.md](https://github.com/NCodeGroup/project-template/blob/v0.9.0/CHANGELOG.md).")) "$($r.Output) length $($body.Length)"

    # 17. Copier's GitLab shorthand: the error names the address it expands to.
    Set-Answer "_commit: v0.1.0`n_src_path: gl:owner/repo"
    $r = Invoke-Notice
    Check 'GitLab shorthand: reads https://gitlab.com/owner/repo' ($r.ExitCode -ne 0 -and $r.Flat.Contains("Can't read the project template's tags at https://gitlab.com/owner/repo.")) $r.Output

    # 18. No _src_path, a version it can't read, and a template with no version tags each fail the run, saying why.
    Set-Answer '_commit: v0.1.0'
    $r = Invoke-Notice
    Check 'no _src_path: exits non-zero and says so' ($r.ExitCode -ne 0 -and $r.Flat.Contains('.copier-answers.yml has no _src_path')) $r.Output
    $untagged = Join-Path $Work 'untagged'
    Invoke-Git init -q -b main $untagged
    Invoke-Git -C $untagged commit -q --allow-empty -m 'No versions'
    Invoke-Git -C $untagged tag 'latest'
    Set-Answer "_commit: v0.1.0`n_src_path: file:///$($untagged -replace '\\', '/')"
    $r = Invoke-Notice
    Check 'no version tags: exits non-zero and says so' ($r.ExitCode -ne 0 -and $r.Flat.Contains('has no version tags')) $r.Output
    Set-ProjectVersion 'main'
    $r = Invoke-Notice
    Check 'unreadable version: exits non-zero and says so' ($r.ExitCode -ne 0 -and $r.Flat.Contains("Can't read the project's template version from .template-version ('main')")) $r.Output
    Write-Text (Join-Path $project '.template-version') ''
    $r = Invoke-Notice
    Check 'empty .template-version: exits non-zero and says it can''t read the version' ($r.ExitCode -ne 0 -and $r.Flat.Contains("Can't read the project's template version from .template-version ('')")) $r.Output
}
finally {
    $env:PATH = $savedPath
    foreach ($name in $gitConfig) { Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue }
}

''
if ($failures.Count) { "Kept the work folder: $Work"; "Template update notice tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Template update notice tests: PASSED'
exit 0
