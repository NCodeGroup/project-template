<#
.SYNOPSIS
    Test Get-AssemblyVersionFloor and Get-NuGetPublisher, the library release checks in .template\Update-Project.ps1 and tools\adopt\Adoption.psm1.

.DESCRIPTION
    Builds fixture repositories whose version tags shipped different assembly versions, and a folder of workflows that push to
    NuGet. Then, for the copy of each function in .template\Update-Project.ps1 and the one in tools\adopt\Adoption.psm1, checks the
    tag and assembly version that Get-AssemblyVersionFloor returns and the workflows that Get-NuGetPublisher names. Prints PASS or
    FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-library-release-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-LibraryRelease.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-library-release-test-$PID")
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
function Save-Commit([string]$Message, [string]$Tag = '') {
    Invoke-Git add -A
    Invoke-Git commit -q --allow-empty -m $Message
    if ($Tag) { Invoke-Git tag $Tag }
}

$plainProps = '<Project />'
$pinnedProps = '<Project><Target Name="ProjectTemplatePinAssemblyVersion" /></Project>'
$versionedProps = '<Project><PropertyGroup><AssemblyVersion>2.0.0.0</AssemblyVersion></PropertyGroup></Project>'
$pushed = "- run: dotnet nuget push x.nupkg`n"

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$floor = Join-Path $Work 'floor'
$newMajor = Join-Path $Work 'new-major'
$ownVersion = Join-Path $Work 'own-version'
$untagged = Join-Path $Work 'untagged'
$noWorkflows = Join-Path $Work 'no-workflows'
$onlyPublish = Join-Path $Work 'only-publish'
$others = Join-Path $Work 'others'
foreach ($folder in $floor, $newMajor, $ownVersion, $untagged, $noWorkflows, $onlyPublish, $others) {
    New-Item -ItemType Directory -Force $folder | Out-Null
}

Push-Location $floor
try {
    Invoke-Git init -q -b main
    Write-Text (Join-Path $floor 'Directory.Build.props') $plainProps
    Save-Commit 'Release v5.2.0' 'v5.2.0'
    Save-Commit 'Release v5.3.0' 'v5.3.0'
    Write-Text (Join-Path $floor 'build/ProjectTemplate.props') $pinnedProps
    Save-Commit 'Release v5.4.0' 'v5.4.0'
}
finally { Pop-Location }

Push-Location $newMajor
try {
    Invoke-Git init -q -b main
    Write-Text (Join-Path $newMajor 'Directory.Build.props') $plainProps
    Save-Commit 'Release v5.3.0' 'v5.3.0'
    Write-Text (Join-Path $newMajor 'build/ProjectTemplate.props') $pinnedProps
    Save-Commit 'Release v6.0.0' 'v6.0.0'
}
finally { Pop-Location }

Push-Location $ownVersion
try {
    Invoke-Git init -q -b main
    Write-Text (Join-Path $ownVersion 'Directory.Build.props') $versionedProps
    Save-Commit 'Release v2.1.0' 'v2.1.0'
    Write-Text (Join-Path $ownVersion 'Directory.Build.props') $plainProps
    Write-Text (Join-Path $ownVersion 'build/ProjectTemplate.props') $pinnedProps
    Save-Commit 'Pin the assembly version'
}
finally { Pop-Location }

Push-Location $untagged
try {
    Invoke-Git init -q -b main
    Write-Text (Join-Path $untagged 'Directory.Build.props') $plainProps
    Write-Text (Join-Path $untagged 'build/ProjectTemplate.props') $pinnedProps
    Save-Commit 'Start'
}
finally { Pop-Location }

Write-Text (Join-Path $onlyPublish '.github/workflows/publish.yml') $pushed
Write-Text (Join-Path $others '.github/workflows/publish.yml') $pushed
Write-Text (Join-Path $others '.github/workflows/release.yml') "- run: dotnet nuget push out/*.nupkg`n"
Write-Text (Join-Path $others '.github/workflows/deploy.yaml') "- run: nuget push x.nupkg`n"
Write-Text (Join-Path $others '.github/workflows/ci.yml') "- run: dotnet pack`n"

$updateFunctions = @{}
$updateAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null)
foreach ($function in 'Get-AssemblyVersionFloor', 'Get-NuGetPublisher') {
    $updateFunctions[$function] = $updateAst.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $function }, $true) | Select-Object -First 1
}
Import-Module (Join-Path $repoRoot 'tools\adopt\Adoption.psm1') -Force
$sources = [ordered]@{
    update = { param($Function) if ($updateFunctions[$Function]) { . ([scriptblock]::Create($updateFunctions[$Function].Extent.Text)); & $Function } else { 'MISSING' } }
    adopt  = { param($Function) if ((Get-Module Adoption).ExportedFunctions.ContainsKey($Function)) { & "Adoption\$Function" } else { 'MISSING' } }
}

$floorCases = [ordered]@{
    'the highest assembly version above the major pin is named' = @{ Folder = $floor; Files = @{}; Expect = @{ Tag = 'v5.3.0'; AssemblyVersion = '5.3.0.0'; Major = 5 } }
    'a Directory.Build.props that sets AssemblyVersion gives nothing' = @{ Folder = $floor; Files = @{ 'Directory.Build.props' = '<Project><PropertyGroup><AssemblyVersion>5.3.0.0</AssemblyVersion></PropertyGroup></Project>' }; Expect = $null }
    'build/ProjectTemplate.props without the pin gives nothing' = @{ Folder = $floor; Files = @{ 'build/ProjectTemplate.props' = $plainProps }; Expect = $null }
    'a new major with the pin from its first tag gives nothing' = @{ Folder = $newMajor; Files = @{}; Expect = $null }
    'a tag whose Directory.Build.props set the version gives nothing' = @{ Folder = $ownVersion; Files = @{}; Expect = $null }
    'no tag gives nothing' = @{ Folder = $untagged; Files = @{}; Expect = $null }
}
$publisherCases = [ordered]@{
    'no workflows folder gives nothing' = @{ Folder = $noWorkflows; Expect = '' }
    'publish.yml alone gives nothing' = @{ Folder = $onlyPublish; Expect = '' }
    'the other workflows that push to NuGet are named' = @{ Folder = $others; Expect = '.github/workflows/deploy.yaml,.github/workflows/release.yml' }
}

foreach ($source in $sources.Keys) {
    foreach ($name in $floorCases.Keys) {
        $case = $floorCases[$name]
        Push-Location $case.Folder
        try {
            foreach ($file in $case.Files.Keys) { Write-Text (Join-Path $case.Folder $file) $case.Files[$file] }
            $result = & $sources[$source] 'Get-AssemblyVersionFloor'
        }
        finally {
            Invoke-Git checkout -q -- .
            Pop-Location
        }
        $expect = $case.Expect
        $ok = if ($expect) {
            $null -ne $result -and $result.Tag -eq $expect.Tag -and $result.AssemblyVersion -eq $expect.AssemblyVersion -and $result.Major -eq $expect.Major
        }
        else { $null -eq $result }
        $detail = if ($expect) { "Got Tag '$($result.Tag)', AssemblyVersion '$($result.AssemblyVersion)', Major '$($result.Major)'; expected '$($expect.Tag)', '$($expect.AssemblyVersion)', '$($expect.Major)'" } else { "Got '$result'; expected nothing" }
        Check "${source}: Get-AssemblyVersionFloor: $name" $ok $detail
    }
    foreach ($name in $publisherCases.Keys) {
        $case = $publisherCases[$name]
        Push-Location $case.Folder
        try { $result = @(& $sources[$source] 'Get-NuGetPublisher') -join ',' }
        finally { Pop-Location }
        Check "${source}: Get-NuGetPublisher: $name" ($result -eq $case.Expect) "Got '$result'; expected '$($case.Expect)'"
    }
}

''
if ($failures.Count) { "Kept the work folder: $Work"; "Library release check tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Library release check tests: PASSED'
exit 0
