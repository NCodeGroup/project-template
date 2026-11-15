<#
.SYNOPSIS
    Test template/build/Update-Baseline.ps1, which raises PackageValidationBaselineVersion, without nuget.org.

.DESCRIPTION
    Builds one fixture folder per case and runs the script with -SkipNugetCheck: the file edits, the changelog entry, the
    cases that change nothing, a custom changelog file named by AGENTS.md, CRLF and byte order mark preservation, and a
    prerelease version. Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-baseline-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-UpdateBaseline.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-baseline-test-$PID")
)
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repoRoot 'template\build\Update-Baseline.ps1'
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Write-Text([string]$Path, [string]$Text, [bool]$Bom = $false) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($Bom))
}
function New-Case([string]$Name, [hashtable]$Files) {
    $folder = Join-Path $Work $Name
    New-Item -ItemType Directory -Force $folder | Out-Null
    foreach ($relative in $Files.Keys) {
        $value = $Files[$relative]
        if ($value -is [hashtable]) { Write-Text (Join-Path $folder $relative) $value.Text $value.Bom }
        else { Write-Text (Join-Path $folder $relative) $value }
    }
    $folder
}
function Read-Text([string]$Folder, [string]$Relative) {
    [IO.File]::ReadAllText((Join-Path $Folder $Relative))
}
function Test-Bom([string]$Folder, [string]$Relative) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $Folder $Relative))
    $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
}
function Invoke-Baseline([string]$Folder, [string]$Version = 'v5.0.2') {
    , @(& $script -Version $Version -Root $Folder -SkipNugetCheck 6>$null)
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

$changelogHead = "# Changelog`n`n## [Unreleased]`n"
$changelogTail = "`n## [5.0.1] - 2026-11-14`n`n### Added`n`n- Old.`n`n[unreleased]: https://example.test/compare/v5.0.1...HEAD`n"
$entry = '- Package validation compares each package with the published 5.0.2 package.'
$csproj = 'src/Fixture.A/Fixture.A.csproj'
function Get-Project([string]$Baseline) {
    "<Project Sdk=`"Microsoft.NET.Sdk`"><PropertyGroup><PackageId>Fixture.A</PackageId><PackageValidationBaselineVersion>$Baseline</PackageValidationBaselineVersion></PropertyGroup></Project>`n"
}

# The changelog cases: the Unreleased body before and after.
$changelogCases = [ordered]@{
    'empty body'       = @{ Body = "`n"; Expect = "`n### Changed`n`n$entry`n" }
    'Changed section'  = @{ Body = "`n### Changed`n`n- Old entry.`n"; Expect = "`n### Changed`n`n$entry`n- Old entry.`n" }
    'Added section'    = @{ Body = "`n### Added`n`n- New.`n"; Expect = "`n### Added`n`n- New.`n`n### Changed`n`n$entry`n" }
    'Fixed section'    = @{ Body = "`n### Fixed`n`n- A bug.`n"; Expect = "`n### Changed`n`n$entry`n`n### Fixed`n`n- A bug.`n" }
}
foreach ($name in $changelogCases.Keys) {
    $case = $changelogCases[$name]
    $folder = New-Case "changelog-$($name -replace ' ', '-')" @{ $csproj = Get-Project '5.0.0'; 'CHANGELOG.md' = "$changelogHead$($case.Body)$changelogTail" }
    $out = Invoke-Baseline $folder
    $actual = Read-Text $folder 'CHANGELOG.md'
    $expected = "$changelogHead$($case.Expect)$changelogTail"
    $ok = $out.Count -eq 1 -and $out[0] -eq '5.0.2' -and (Read-Text $folder $csproj) -ceq (Get-Project '5.0.2') -and $actual -ceq $expected
    Check "Update-Baseline: $name" $ok "Output: $($out -join ', ')`nGot:`n$actual`nExpected:`n$expected"
    if ($name -eq 'empty body') { $first = $folder }
}

foreach ($baseline in '5.0.2', '5.1.0') {
    $changelog = "$changelogHead`n$changelogTail"
    $folder = New-Case "baseline-$baseline" @{ $csproj = Get-Project $baseline; 'CHANGELOG.md' = $changelog }
    $out = Invoke-Baseline $folder
    $ok = $out.Count -eq 0 -and (Read-Text $folder $csproj) -ceq (Get-Project $baseline) -and (Read-Text $folder 'CHANGELOG.md') -ceq $changelog
    Check "Update-Baseline: baseline $baseline is kept" $ok "Output: $($out -join ', ')"
}

$before = @{ Project = Read-Text $first $csproj; Changelog = Read-Text $first 'CHANGELOG.md' }
$out = Invoke-Baseline $first '5.0.2'
$ok = $out.Count -eq 0 -and (Read-Text $first $csproj) -ceq $before.Project -and (Read-Text $first 'CHANGELOG.md') -ceq $before.Changelog
Check 'Update-Baseline: a second run changes nothing' $ok "Output: $($out -join ', ')"

$props = "<Project><PropertyGroup><PackageValidationBaselineVersion>5.0.0</PackageValidationBaselineVersion></PropertyGroup></Project>`n"
$folder = New-Case 'props-and-project' @{ 'Directory.Build.props' = $props; $csproj = Get-Project '6.0.0' }
$out = Invoke-Baseline $folder
$ok = $out.Count -eq 1 -and $out[0] -eq '5.0.2' -and (Read-Text $folder 'Directory.Build.props') -ceq $props.Replace('5.0.0', '5.0.2') -and (Read-Text $folder $csproj) -ceq (Get-Project '6.0.0')
Check 'Update-Baseline: only the file below the version changes' $ok "Output: $($out -join ', ')"

$changelog = "$changelogHead`n$changelogTail"
$plain = '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><PackageId>Fixture.A</PackageId></PropertyGroup></Project>' + "`n"
$folder = New-Case 'no-setting' @{ $csproj = $plain; 'CHANGELOG.md' = $changelog }
$out = Invoke-Baseline $folder
$ok = $out.Count -eq 0 -and (Read-Text $folder $csproj) -ceq $plain -and (Read-Text $folder 'CHANGELOG.md') -ceq $changelog
Check 'Update-Baseline: no file sets the baseline' $ok "Output: $($out -join ', ')"

$noRelease = "# Changelog`n`n## [Unreleased]`n`n### Added`n`n- A thing.`n"
$folder = New-Case 'no-release-section' @{ $csproj = Get-Project '5.0.0'; 'CHANGELOG.md' = $noRelease }
$out = Invoke-Baseline $folder
$ok = $out.Count -eq 1 -and $out[0] -eq '5.0.2' -and (Read-Text $folder $csproj) -ceq (Get-Project '5.0.2') -and (Read-Text $folder 'CHANGELOG.md') -ceq $noRelease
Check 'Update-Baseline: a changelog without a release section is left alone' $ok "Output: $($out -join ', ')"

$agents = "# A`n`n## Landing`n`n- changelog: ``docs/CHANGES.md```n"
$main = "$changelogHead`n$changelogTail"
$folder = New-Case 'agents-changelog' @{ $csproj = Get-Project '5.0.0'; 'AGENTS.md' = $agents; 'CHANGELOG.md' = $main; 'docs/CHANGES.md' = "$changelogHead`n$changelogTail" }
$out = Invoke-Baseline $folder
$expected = "$changelogHead`n### Changed`n`n$entry`n$changelogTail"
$ok = $out.Count -eq 1 -and (Read-Text $folder 'docs/CHANGES.md') -ceq $expected -and (Read-Text $folder 'CHANGELOG.md') -ceq $main
Check 'Update-Baseline: the entry goes to the changelog AGENTS.md names' $ok "Output: $($out -join ', ')`nGot:`n$(Read-Text $folder 'docs/CHANGES.md')"

$crlfText = "$changelogHead`n$changelogTail".Replace("`n", "`r`n")
$folder = New-Case 'crlf-bom' @{ $csproj = @{ Text = (Get-Project '5.0.0'); Bom = $true }; 'CHANGELOG.md' = $crlfText }
$out = Invoke-Baseline $folder
$expected = "$changelogHead`n### Changed`n`n$entry`n$changelogTail".Replace("`n", "`r`n")
$actual = Read-Text $folder 'CHANGELOG.md'
Check 'Update-Baseline: a CRLF changelog keeps CRLF' ($out.Count -eq 1 -and $actual -ceq $expected) "Got:`n$($actual.Replace("`r", '\r'))"
Check 'Update-Baseline: a project file with a byte order mark keeps it' ((Test-Bom $folder $csproj) -and (Read-Text $folder $csproj).Contains('>5.0.2<')) ''

$folder = New-Case 'prerelease' @{ $csproj = Get-Project '5.0.0'; 'CHANGELOG.md' = $changelog }
try { Invoke-Baseline $folder '5.0.2-rc.1' | Out-Null; $threw = $false } catch { $threw = $true }
$ok = $threw -and (Read-Text $folder $csproj) -ceq (Get-Project '5.0.0') -and (Read-Text $folder 'CHANGELOG.md') -ceq $changelog
Check 'Update-Baseline: a prerelease version throws and changes nothing' $ok "Threw: $threw"

''
if ($failures.Count) { "Kept the work folder: $Work"; "Update baseline tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Update baseline tests: PASSED'
exit 0
