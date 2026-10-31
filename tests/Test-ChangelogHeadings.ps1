<#
.SYNOPSIS
    Test Get-ChangelogDuplicate, the check in workflow\Get-PlanState.ps1 behind its changelog-duplicates line, and check this
    repository's CHANGELOG.md with it.

.DESCRIPTION
    Runs the copy of Get-ChangelogDuplicate in workflow\Get-PlanState.ps1 on changelogs of different shapes, with and without a
    Keep a Changelog heading (### Added, Changed, Deprecated, Removed, Fixed or Security) that a section has twice, and checks
    the sections and headings it names. Then checks that every section of this repository's CHANGELOG.md has at most one of each
    heading: two pull requests that each add the same heading to ## [Unreleased] merge cleanly and leave it twice, and CI runs
    this suite on every pull request and push to main. Prints PASS or FAIL per check, a failure naming the section and heading,
    and exits 1 on any failure. The copies projects run, .template\Get-PlanState.ps1 and template\.template\Get-PlanState.ps1,
    are generated from workflow\Get-PlanState.ps1 by tools\Update-Template.ps1, and Test-Template.ps1 fails when either differs.

.PARAMETER Changelog
    The changelog to check. Defaults to the repository's CHANGELOG.md.

.EXAMPLE
    .\tests\Test-ChangelogHeadings.ps1
#>
[CmdletBinding()]
param(
    [string]$Changelog = (Join-Path (Split-Path -Parent $PSScriptRoot) 'CHANGELOG.md')
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}

$function = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'workflow\Get-PlanState.ps1'), [ref]$null, [ref]$null).FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ChangelogDuplicate' }, $true) | Select-Object -First 1
Check 'Get-PlanState.ps1 defines Get-ChangelogDuplicate' ($null -ne $function)
if ($function) { . ([scriptblock]::Create($function.Extent.Text)) }

$cases = [ordered]@{
    'an empty changelog has none'                                 = @{ Text = ''; Expected = '-' }
    'one of each heading per section has none'                    = @{ Text = "# Changelog`n`n## [Unreleased]`n`n### Added`n`n- A.`n`n### Changed`n`n- B.`n`n### Deprecated`n`n- C.`n`n### Removed`n`n- D.`n`n### Fixed`n`n- E.`n`n### Security`n`n- F.`n`n## [0.1.0] - 2026-01-01`n`n### Added`n`n- G.`n`n### Changed`n`n- H.`n"; Expected = '-' }
    'a heading twice in Unreleased is named'                      = @{ Text = "## [Unreleased]`n`n### Added`n`n- A.`n`n### Changed`n`n- B.`n`n### Changed`n`n- C.`n`n### Fixed`n`n- D.`n"; Expected = '[Unreleased] Changed' }
    'a heading three times is named once'                         = @{ Text = "## [Unreleased]`n`n### Fixed`n`n- A.`n`n### Fixed`n`n- B.`n`n### Fixed`n`n- C.`n"; Expected = '[Unreleased] Fixed' }
    'duplicates in two sections are each named'                   = @{ Text = "## [Unreleased]`n`n### Changed`n`n- A.`n`n### Changed`n`n- B.`n`n## [0.2.0] - 2026-01-02`n`n### Security`n`n- C.`n`n### Security`n`n- D.`n`n## v0.1.0`n`n### Added`n`n- E.`n`n### Added`n`n- F.`n"; Expected = '[Unreleased] Changed, [0.2.0] Security, v0.1.0 Added' }
    'two sections with the same heading have none'                = @{ Text = "## [Unreleased]`n`n### Removed`n`n- A.`n`n## [0.1.0] - 2026-01-01`n`n### Removed`n`n- B.`n"; Expected = '-' }
    'a heading in a fenced block, a fourth level or another word' = @{ Text = "## [Unreleased]`n`n### Added`n`n- A.`n`n``````markdown`n### Added`n```````n`n#### Added`n`n### Notes`n`n### Notes`n"; Expected = '-' }
    'CRLF line endings are read too'                              = @{ Text = "## [Unreleased]`r`n`r`n### Deprecated`r`n`r`n- A.`r`n`r`n### Deprecated`r`n`r`n- B.`r`n"; Expected = '[Unreleased] Deprecated' }
    'headings match case-sensitively'                             = @{ Text = "## [Unreleased]`n`n### Changed`n`n- A.`n`n### changed`n`n- B.`n`n### CHANGED`n`n- C.`n"; Expected = '-' }
    'headings before the first section are not counted'           = @{ Text = "# Changelog`n`n### Added`n`n### Added`n`n## [Unreleased]`n`n### Added`n`n- A.`n"; Expected = '-' }
    'a fenced section heading leaves the section as it was'       = @{ Text = "## [Unreleased]`n`n### Changed`n`n- A.`n`n``````text`n## [0.1.0] - 2026-01-01`n```````n`n### Changed`n`n- B.`n"; Expected = '[Unreleased] Changed' }
    'a heading in a tilde fence'                                  = @{ Text = "## [Unreleased]`n`n### Added`n`n- A.`n`n~~~markdown`n### Added`n### Added`n~~~`n"; Expected = '-' }
    'a tilde line does not close a backtick fence'                = @{ Text = "## [Unreleased]`n`n### Fixed`n`n- A.`n`n```````n~~~`n### Fixed`n```````n`n### Added`n"; Expected = '-' }
    'a backtick line does not close a tilde fence'                = @{ Text = "## [Unreleased]`n`n### Fixed`n`n- A.`n`n~~~`n```````n### Fixed`n~~~`n`n### Added`n"; Expected = '-' }
    'a shorter run or one with text does not close a fence'       = @{ Text = "## [Unreleased]`n`n### Removed`n`n- A.`n`n`````````n```````n``````text`n### Removed`n`````````n`n### Removed`n"; Expected = '[Unreleased] Removed' }
    'a fence that never closes runs to the end'                   = @{ Text = "## [Unreleased]`n`n### Security`n`n- A.`n`n``````powershell`n### Security`n`n### Security`n"; Expected = '-' }
}
if ($function) {
    foreach ($name in $cases.Keys) {
        $result = Get-ChangelogDuplicate ($cases[$name].Text -split "`r?`n")
        Check "duplicates: $name" ($result -eq $cases[$name].Expected) "got '$result', expected '$($cases[$name].Expected)'"
    }

    if (Test-Path -LiteralPath $Changelog -PathType Leaf) {
        $result = Get-ChangelogDuplicate ([IO.File]::ReadAllText($Changelog) -split "`r?`n")
        $detail = @(if ($result -ne '-') { foreach ($pair in $result -split ', ') { $section, $heading = $pair -split ' ', 2; "## $section has more than one ### $heading heading" } }) -join '; '
        Check "repository: every section of $(Split-Path -Leaf $Changelog) has at most one of each heading (merge each duplicate into one heading, keeping every entry)" ($result -eq '-') $detail
    }
    else { Check "repository: $Changelog exists" $false }
}

''
if ($failures.Count) { "Changelog heading tests: FAILED ($($failures.Count))"; exit 1 }
'Changelog heading tests: PASSED'
exit 0
