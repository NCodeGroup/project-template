<#
.SYNOPSIS
    Test Get-ChangelogBackfill, the check in .template\Update-Project.ps1 and tools\adopt\Adoption.psm1 that names the version tags the changelog has no section for.

.DESCRIPTION
    Builds a fixture repository with the tags v0.1.0, v0.2.0 and v0.3.0 on main, a prerelease tag v0.4.0-rc.1, and a tag v0.9.0 on a
    side branch that main doesn't contain. Then, for the copy of Get-ChangelogBackfill in .template\Update-Project.ps1 and the one in
    tools\adopt\Adoption.psm1, writes changelogs of different shapes and checks the changelog file and the range of version tags
    without a section that the function returns. Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-changelog-backfill-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-ChangelogBackfill.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-changelog-backfill-test-$PID")
)
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Invoke-Git {
    git -c user.name=template-test -c user.email=template-test@example.invalid @args
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed." }
}
function Write-Text([string]$Path, [string]$Text) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$repo = Join-Path $Work 'repo'
$empty = Join-Path $Work 'empty'
New-Item -ItemType Directory -Force $repo, $empty | Out-Null
Push-Location $repo
try {
    Invoke-Git init -q -b main
    foreach ($tag in 'v0.1.0', 'v0.2.0', 'v0.3.0') {
        Invoke-Git commit -q --allow-empty -m "Release $tag"
        Invoke-Git tag $tag
    }
    Invoke-Git tag v0.4.0-rc.1
    Invoke-Git switch -q -c side
    Invoke-Git commit -q --allow-empty -m 'Release v0.9.0'
    Invoke-Git tag v0.9.0
    Invoke-Git switch -q main
}
finally { Pop-Location }
Push-Location $empty
try {
    Invoke-Git init -q -b main
    Invoke-Git commit -q --allow-empty -m 'Start'
}
finally { Pop-Location }

$updateFunction = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null).FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ChangelogBackfill' }, $true) | Select-Object -First 1
Import-Module (Join-Path $repoRoot 'tools\adopt\Adoption.psm1') -Force
$sources = [ordered]@{
    update = { if ($updateFunction) { . ([scriptblock]::Create($updateFunction.Extent.Text)); Get-ChangelogBackfill } }
    adopt  = { if ((Get-Module Adoption).ExportedFunctions.ContainsKey('Get-ChangelogBackfill')) { Adoption\Get-ChangelogBackfill } }
}
$cases = [ordered]@{
    'no tags gives -'                                       = @{ Folder = $empty; Files = @{}; File = 'CHANGELOG.md'; Range = '-' }
    'no changelog names every tag merged into HEAD'         = @{ Folder = $repo; Files = @{}; File = 'CHANGELOG.md'; Range = 'v0.1.0..v0.3.0' }
    'an Unreleased section alone names every tag'           = @{ Folder = $repo; Files = @{ 'CHANGELOG.md' = "# Changelog`n`n## [Unreleased]`n" }; File = 'CHANGELOG.md'; Range = 'v0.1.0..v0.3.0' }
    'every tag with a section gives -'                      = @{ Folder = $repo; Files = @{ 'CHANGELOG.md' = "## [Unreleased]`n`n## [0.3.0] - 2026-01-03`n`n## v0.2.0`n`n## [0.1.0] - 2026-01-01 [YANKED]`n`n" }; File = 'CHANGELOG.md'; Range = '-' }
    'a changelog started mid-history names the older tags'  = @{ Folder = $repo; Files = @{ 'CHANGELOG.md' = "## [0.3.0] - 2026-01-03`n" }; File = 'CHANGELOG.md'; Range = 'v0.1.0..v0.2.0' }
    'one tag without a section is named alone'              = @{ Folder = $repo; Files = @{ 'CHANGELOG.md' = "## [0.3.0] - 2026-01-03`n`n## [0.2.0] - 2026-01-02`n" }; File = 'CHANGELOG.md'; Range = 'v0.1.0' }
    'the Landing section names the changelog'               = @{ Folder = $repo; Files = @{ 'AGENTS.md' = "# Fixture`n`n## Landing`n`n- changelog: ``docs/CHANGES.md```n"; 'docs/CHANGES.md' = "# Changes`n`n## 0.3.0`n`n## 0.2.0`n`n## 0.1.0`n" }; File = 'docs/CHANGES.md'; Range = '-' }
}
foreach ($source in $sources.Keys) {
    foreach ($name in $cases.Keys) {
        $case = $cases[$name]
        Push-Location $case.Folder
        try {
            foreach ($leftover in 'CHANGELOG.md', 'AGENTS.md', 'docs') {
                if (Test-Path -LiteralPath $leftover) { Remove-Item -LiteralPath $leftover -Recurse -Force }
            }
            foreach ($file in $case.Files.Keys) { Write-Text (Join-Path $case.Folder $file) $case.Files[$file] }
            $result = & $sources[$source]
        }
        finally { Pop-Location }
        Check "${source}: $name" ($null -ne $result -and $result.File -eq $case.File -and $result.Range -eq $case.Range) "File '$($result.File)', Range '$($result.Range)'; expected '$($case.File)', '$($case.Range)'"
    }
}

''
if ($failures.Count) { "Kept the work folder: $Work"; "Changelog backfill tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Changelog backfill tests: PASSED'
exit 0
