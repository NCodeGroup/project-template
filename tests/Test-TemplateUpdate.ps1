<#
.SYNOPSIS
    Test the template update notice every GitHub project runs weekly, .template\Get-TemplateUpdate.ps1.

.DESCRIPTION
    Builds a fixture template repository whose tags carry a fixture CHANGELOG.md, and a fixture project whose
    .copier-answers.yml names it, so the script reads tags and release notes with Git and no network. A stand-in for
    gh keeps the fixture repository's issues and labels and records every call. Runs the script with the project
    already current, one version behind, again one version behind, three versions behind, and current again, and
    checks that it opens one issue with the right title, label and release notes, leaves it alone when nothing changed,
    edits and retitles that same issue, closes it once the project is current, and ignores tags that aren't versions.
    Prints PASS or FAIL per check and exits 1 on any failure. The checks take seconds.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-notice-test in the temp folder.

.EXAMPLE
    .\tests\Test-TemplateUpdate.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) 'project-template-update-notice-test')
)
$ErrorActionPreference = 'Stop'
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
function Get-FixtureChangelog([string[]]$Versions) {
    $text = "# Changelog`n`nWhat each template version changes.`n`n## [Unreleased]`n`n### Added`n`n- Unreleased work.`n`n"
    foreach ($v in $Versions) { $text += "## [$v] - 2026-10-0$($v.Split('.')[1])`n`n### Changed`n`n- Change in $v, with an em dash — and a link ([#$($v.Split('.')[1])](https://example.invalid/$v)).`n`n" }
    $text += ($Versions | ForEach-Object { "[$_]: https://example.invalid/compare/$_" }) -join "`n"
    $text + "`n"
}
function Add-TemplateVersion([string]$Version, [string[]]$Versions, [switch]$Annotated) {
    Write-Text (Join-Path $template 'CHANGELOG.md') (Get-FixtureChangelog $Versions)
    Invoke-Git -C $template add CHANGELOG.md
    Invoke-Git -C $template commit -q -m "Release $Version"
    if ($Annotated) { Invoke-Git -C $template tag -a "v$Version" -m "v$Version" } else { Invoke-Git -C $template tag "v$Version" }
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

$script = Join-Path $project '.template\Get-TemplateUpdate.ps1'
$calls = Join-Path $bin 'calls.log'
function Invoke-Notice {
    if (Test-Path -LiteralPath $calls) { Remove-Item -LiteralPath $calls -Force }
    $output = & pwsh -NoProfile -File $script 2>&1 | Out-String
    [pscustomobject]@{
        Output = $output
        ExitCode = $LASTEXITCODE
        Calls = @(if (Test-Path -LiteralPath $calls) { Get-Content -LiteralPath $calls })
        Issues = @((Get-Content -Raw -LiteralPath (Join-Path $bin 'state.json') | ConvertFrom-Json).issues)
        Labels = @((Get-Content -Raw -LiteralPath (Join-Path $bin 'state.json') | ConvertFrom-Json).labels)
    }
}
function Get-Change($Run) { @($Run.Calls | Where-Object { $_ -match '^(issue (create|edit|close)|label create)' }) }

$savedPath = $env:PATH
$env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
try {
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
    Check 'unreadable template: exits non-zero and names the address' ($r.ExitCode -ne 0 -and $r.Output.Contains("Can't read the project template's tags at") -and $r.Output.Contains('template-missing')) $r.Output
}
finally {
    $env:PATH = $savedPath
}

''
if ($failures.Count) { "Template update notice tests: FAILED ($($failures.Count))"; exit 1 }
'Template update notice tests: PASSED'
exit 0
