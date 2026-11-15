<#
.SYNOPSIS
    Test Get-AssemblyVersionFloor, Get-NuGetPublisher, Update-VersionFile, Test-PackageValidationBaseline and Get-CSharpFileWithoutHeader, the library release checks in .template\Update-Project.ps1 and tools\adopt\Adoption.psm1.

.DESCRIPTION
    Builds fixture repositories whose version tags shipped different assembly versions, and a folder of workflows that push to
    NuGet. Then, for the copy of each function in .template\Update-Project.ps1 and the one in tools\adopt\Adoption.psm1, checks the
    tag and assembly version that Get-AssemblyVersionFloor returns, the workflows that Get-NuGetPublisher names, and the
    version.json that Update-VersionFile fills (the patch after the newest tag and the assembly version with its precision),
    whether Test-PackageValidationBaseline finds a package validation baseline, and the C# files that
    Get-CSharpFileWithoutHeader names for lacking the .editorconfig header.
    Prints PASS or FAIL per check and exits 1 on any failure.

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
foreach ($function in 'Get-AssemblyVersionFloor', 'Get-NuGetPublisher', 'Get-PublishedPackageVersion', 'Update-VersionFile', 'Get-CSharpFileWithoutHeader') {
    $updateFunctions[$function] = $updateAst.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $function }, $true) | Select-Object -First 1
}
Import-Module (Join-Path $repoRoot 'tools\adopt\Adoption.psm1') -Force
$sources = [ordered]@{
    update = { param($Function) if ($updateFunctions[$Function]) { foreach ($definition in $updateFunctions.Values) { if ($definition) { . ([scriptblock]::Create($definition.Extent.Text)) } }; & $Function } else { 'MISSING' } }
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
$versionText = [IO.File]::ReadAllText((Join-Path $repoRoot 'template/version.json'))
$precisionMajor = '"assemblyVersion": { "precision": "major" }'
$versionCases = [ordered]@{
    'the patch after the newest tag and the floor from the pin' = @{ Folder = $floor; Write = $true; Files = @{}; Expect = @{ Version = '5.4.1'; Tag = 'v5.4.0'; AssemblyVersion = '5.3'; Precision = 'minor' }; Keeps = @() }
    'an AssemblyVersion in Directory.Build.props wins over the floor' = @{ Folder = $floor; Write = $true; Files = @{ 'Directory.Build.props' = '<Project><PropertyGroup><AssemblyVersion>5.3.2.0</AssemblyVersion></PropertyGroup></Project>' }; Expect = @{ Version = '5.4.1'; Tag = 'v5.4.0'; AssemblyVersion = '5.3.2'; Precision = 'build' }; Keeps = @() }
    'a new major keeps the major precision' = @{ Folder = $newMajor; Write = $true; Files = @{}; Expect = @{ Version = '6.0.1'; Tag = 'v6.0.0'; AssemblyVersion = $null; Precision = $null }; Keeps = @($precisionMajor) }
    'no tag leaves the file unchanged' = @{ Folder = $untagged; Write = $true; Files = @{}; Expect = @{ Version = $null; Tag = $null; AssemblyVersion = $null; Precision = $null }; Keeps = @($versionText) }
    'no version.json gives nothing' = @{ Folder = $untagged; Write = $false; Files = @{}; Expect = $null; Keeps = @() }
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
    foreach ($name in $versionCases.Keys) {
        $case = $versionCases[$name]
        $versionPath = Join-Path $case.Folder 'version.json'
        Push-Location $case.Folder
        try {
            foreach ($file in $case.Files.Keys) { Write-Text (Join-Path $case.Folder $file) $case.Files[$file] }
            if ($case.Write) { Write-Text $versionPath $versionText }
            $result = & $sources[$source] 'Update-VersionFile'
            $written = if (Test-Path -LiteralPath $versionPath) { [IO.File]::ReadAllText($versionPath) } else { '' }
        }
        finally {
            Invoke-Git checkout -q -- .
            Remove-Item version.json -ErrorAction SilentlyContinue
            Pop-Location
        }
        $expect = $case.Expect
        $ok = if ($expect) {
            $null -ne $result -and $result.Version -eq $expect.Version -and $result.Tag -eq $expect.Tag -and $result.AssemblyVersion -eq $expect.AssemblyVersion -and $result.Precision -eq $expect.Precision
        }
        else { $null -eq $result }
        if ($ok -and $expect.Version) { $ok = $written.Contains("`"version`": `"$($expect.Version)`"") }
        if ($ok -and $expect.AssemblyVersion) { $ok = $written.Contains("`"version`": `"$($expect.AssemblyVersion)`", `"precision`": `"$($expect.Precision)`"") }
        if ($ok) { foreach ($keep in $case.Keeps) { if (-not $written.Contains($keep)) { $ok = $false } } }
        $detail = if ($expect) { "Got Version '$($result.Version)', Tag '$($result.Tag)', AssemblyVersion '$($result.AssemblyVersion)', Precision '$($result.Precision)'; expected '$($expect.Version)', '$($expect.Tag)', '$($expect.AssemblyVersion)', '$($expect.Precision)'; file:`n$written" } else { "Got '$result'; expected nothing" }
        Check "${source}: Update-VersionFile: $name" $ok $detail
    }
    foreach ($name in $publisherCases.Keys) {
        $case = $publisherCases[$name]
        Push-Location $case.Folder
        try { $result = @(& $sources[$source] 'Get-NuGetPublisher') -join ',' }
        finally { Pop-Location }
        Check "${source}: Get-NuGetPublisher: $name" ($result -eq $case.Expect) "Got '$result'; expected '$($case.Expect)'"
    }
}

# Get-PublishedPackageVersion: Fetch stands in for nuget.org.
$published = Join-Path $Work 'published'
Write-Text (Join-Path $published 'src/Foo/Foo.csproj') '<Project Sdk="Microsoft.NET.Sdk" />'
Write-Text (Join-Path $published 'src/Foo.Tests/Foo.Tests.csproj') '<Project Sdk="Microsoft.NET.Sdk" />'
Write-Text (Join-Path $published 'src/Tool/Tool.csproj') '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><IsPackable>false</IsPackable></PropertyGroup></Project>'
Write-Text (Join-Path $published 'src/Broken/Broken.csproj') '<Project Sdk="Microsoft.NET.Sdk" />'
Write-Text (Join-Path $published 'src/Named/Named.csproj') '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><PackageId>Other.Name</PackageId></PropertyGroup></Project>'
. ([scriptblock]::Create($updateFunctions['Get-PublishedPackageVersion'].Extent.Text))
$queried = [Collections.Generic.List[string]]::new()
$fetch = {
    param($Uri)
    $queried.Add($Uri)
    if ($Uri -match '/broken/') { throw 'offline' }
    @{ versions = '1.0.0', '1.1.0', '2.0.0-rc.1' }
}
$publishedCalls = [ordered]@{
    update = { Get-PublishedPackageVersion -Fetch $fetch }
    adopt  = { Adoption\Get-PublishedPackageVersion -Fetch $fetch }
}
foreach ($source in $publishedCalls.Keys) {
    $queried.Clear()
    Push-Location $published
    try { $versions = @(& $publishedCalls[$source]) }
    finally { Pop-Location }
    $foo = @($versions | Where-Object Id -eq 'Foo')
    Check "${source}: Get-PublishedPackageVersion: only the packable project is named, with the newest stable version" ($foo.Count -eq 1 -and $foo[0].Version -eq '1.1.0' -and -not ($versions | Where-Object { $_.Id -in 'Foo.Tests', 'Tool' })) "Got '$($versions | ForEach-Object { "$($_.Id) $($_.Version)" })'"
    Check "${source}: Get-PublishedPackageVersion: a lookup that throws yields nothing" (-not ($versions | Where-Object Id -eq 'Broken')) "Got '$($versions | ForEach-Object { $_.Id })'"
    Check "${source}: Get-PublishedPackageVersion: a PackageId is queried in lower case" ($queried -contains 'https://api.nuget.org/v3-flatcontainer/other.name/index.json') "Queried '$($queried -join ', ')'"
}

# Test-PackageValidationBaseline: whether the project already sets a baseline.
$baselineCases = [ordered]@{
    'no mention gives false'                                 = @{ Files = @{ 'Directory.Build.props' = '<Project />'; 'src/A/A.csproj' = '<Project Sdk="Microsoft.NET.Sdk" />' }; Expect = $false }
    'Directory.Build.props with the property gives true'     = @{ Files = @{ 'Directory.Build.props' = '<Project><PropertyGroup><PackageValidationBaselineVersion>1.0.0</PackageValidationBaselineVersion></PropertyGroup></Project>' }; Expect = $true }
    'a project file with the property gives true'            = @{ Files = @{ 'src/A/A.csproj' = '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><PackageValidationBaselineVersion>1.0.0</PackageValidationBaselineVersion></PropertyGroup></Project>' }; Expect = $true }
    'a project file under obj with the property gives false' = @{ Files = @{ 'src/A/obj/A.csproj' = '<Project><PropertyGroup><PackageValidationBaselineVersion>1.0.0</PackageValidationBaselineVersion></PropertyGroup></Project>' }; Expect = $false }
}
$baselineIndex = 0
foreach ($name in $baselineCases.Keys) {
    $baselineIndex++
    $case = $baselineCases[$name]
    $folder = Join-Path $Work "baseline$baselineIndex"
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    foreach ($relative in $case.Files.Keys) { Write-Text (Join-Path $folder $relative) $case.Files[$relative] }
    Push-Location $folder
    try { $result = Adoption\Test-PackageValidationBaseline }
    finally { Pop-Location }
    Check "adopt: Test-PackageValidationBaseline: $name" ($result -eq $case.Expect) "Got '$result'; expected '$($case.Expect)'"
}

# Get-CSharpFileWithoutHeader: the C# files that don't start with the header .editorconfig sets.
$editorconfig = "[*.cs]`nfile_header_template = Copyright $([char]0xA9) Ada\nSPDX-License-Identifier: MIT`n"
$header = "// Copyright $([char]0xA9) Ada`n// SPDX-License-Identifier: MIT`n"
$headerCases = [ordered]@{
    'a file that starts with the header gives nothing' = @{ Files = @{ '.editorconfig' = $editorconfig; 'src/A.cs' = $header + "class A { }`n" }; Expect = '' }
    'a file with CRLF line breaks and a byte order mark gives nothing' = @{ Files = @{ '.editorconfig' = $editorconfig; 'src/A.cs' = [string][char]0xFEFF + (($header + "class A { }`n") -replace "`n", "`r`n") }; Expect = '' }
    'a file without the header is named' = @{ Files = @{ '.editorconfig' = $editorconfig; 'src/B.cs' = "class B { }`n" }; Expect = 'src/B.cs' }
    'an old region header is named' = @{ Files = @{ '.editorconfig' = $editorconfig; 'src/C.cs' = "#region Copyright Preamble`n// old`n#endregion`nclass C { }`n" }; Expect = 'src/C.cs' }
    'bin, obj, Migrations, generated and designer files are skipped' = @{ Files = @{ '.editorconfig' = $editorconfig; 'src/bin/D.cs' = "class X { }`n"; 'src/obj/D.cs' = "class X { }`n"; 'src/Migrations/D.cs' = "class X { }`n"; 'src/E.g.cs' = "class X { }`n"; 'src/F.Designer.cs' = "class X { }`n"; 'src/G.cs' = "class G { }`n" }; Expect = 'src/G.cs' }
    'two files are listed in order' = @{ Files = @{ '.editorconfig' = $editorconfig; 'src/B.cs' = "class B { }`n"; 'src/A.cs' = "class A { }`n" }; Expect = 'src/A.cs,src/B.cs' }
    'no header setting gives nothing' = @{ Files = @{ '.editorconfig' = "[*.cs]`nindent_size = 4`n"; 'src/B.cs' = "class B { }`n" }; Expect = '' }
    'no .editorconfig gives nothing' = @{ Files = @{ 'src/B.cs' = "class B { }`n" }; Expect = '' }
}
foreach ($source in $sources.Keys) {
    $headerIndex = 0
    foreach ($name in $headerCases.Keys) {
        $headerIndex++
        $case = $headerCases[$name]
        $folder = Join-Path $Work "header-$source-$headerIndex"
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        foreach ($relative in $case.Files.Keys) { Write-Text (Join-Path $folder $relative) $case.Files[$relative] }
        Push-Location $folder
        try { $result = @(& $sources[$source] 'Get-CSharpFileWithoutHeader') -join ',' }
        finally { Pop-Location }
        Check "${source}: Get-CSharpFileWithoutHeader: $name" ($result -eq $case.Expect) "Got '$result'; expected '$($case.Expect)'"
    }
}

''
if ($failures.Count) { "Kept the work folder: $Work"; "Library release check tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Library release check tests: PASSED'
exit 0
