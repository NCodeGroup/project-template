<#
.SYNOPSIS
    Test Get-NuGetLogistics, the stale NuGet logistics check in tools\adopt\Adoption.psm1.

.DESCRIPTION
    Builds one fixture folder per case: a library that follows the template, which gives no finding, and a library for each
    kind of stale logistics, which gives exactly that finding with its message. Prints PASS or FAIL per check and exits 1 on
    any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-nuget-logistics-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-NuGetLogistics.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-nuget-logistics-test-$PID")
)
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Write-Text([string]$Path, [string]$Text, [bool]$Bom = $false) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($Bom))
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

$project = '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup></Project>'
$buildProps = '<Project><Import Project="build/ProjectTemplate.props" /></Project>'
$metadataProps = '<Project><PropertyGroup><Description>A library</Description><PackageTags>a;b</PackageTags></PropertyGroup></Project>'

# Each case: the files to write (a value of @{ Text; Bom } writes a byte order mark) and the expected findings as Kind and Message.
$cases = [ordered]@{
    'clean' = @{
        Files  = @{ 'src/A/A.csproj' = $project; 'Directory.Build.props' = $buildProps; 'A.slnx' = '<Solution />' }
        Expect = @()
    }
    'orphan' = @{
        Files  = @{ 'src/A/A.csproj' = $project; 'src/A/project.props' = $metadataProps }
        Expect = @(@{ Kind = 'OrphanProps'; Message = 'src/A/project.props is imported by no project, so the Description, PackageTags it sets no longer reach the package: import it from Directory.Build.props, after the import of build/ProjectTemplate.props, or move its settings into the project file.' })
    }
    'orphan-without-settings' = @{
        Files  = @{ 'src/A/A.csproj' = $project; 'src/A/extra.props' = '<Project />' }
        Expect = @(@{ Kind = 'OrphanProps'; Message = 'src/A/extra.props is imported by no project: import it or delete it.' })
    }
    'imported' = @{
        Files  = @{ 'src/A/A.csproj' = '<Project Sdk="Microsoft.NET.Sdk"><Import Project="project.props" /></Project>'; 'src/A/project.props' = $metadataProps }
        Expect = @()
    }
    'package-on-build' = @{
        Files  = @{ 'src/A/A.csproj' = '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><GeneratePackageOnBuild>true</GeneratePackageOnBuild></PropertyGroup></Project>' }
        Expect = @(@{ Kind = 'GeneratePackageOnBuild'; Message = 'src/A/A.csproj sets GeneratePackageOnBuild to true, which races with dotnet pack from a clean tree (NU5026): delete it; build/dod.ps1 packs on its own.' })
    }
    'repeated' = @{
        Files  = @{ 'src/A/A.csproj' = '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup><ItemGroup><PackageReference Include="Microsoft.SourceLink.GitHub" Version="8.0.0" PrivateAssets="All" /></ItemGroup></Project>' }
        Expect = @(@{ Kind = 'RepeatedSettings'; Message = 'src/A/A.csproj repeats settings build/ProjectTemplate.props makes: ImplicitUsings, Nullable, Microsoft.SourceLink.GitHub. Delete them, or keep one only to differ from the template on purpose.' })
    }
    'solution' = @{
        Files  = @{ 'A.sln' = 'Microsoft Visual Studio Solution File' }
        Expect = @(@{ Kind = 'Solution'; Message = 'A.sln is a .sln where the template and current SDKs use .slnx: run dotnet sln A.sln migrate, delete the .sln, and rename A.sln.DotSettings to A.slnx.DotSettings if it exists.' })
    }
    'solution-beside-slnx' = @{
        Files  = @{ 'A.sln' = 'Microsoft Visual Studio Solution File'; 'A.slnx' = '<Solution />' }
        Expect = @()
    }
    'bom' = @{
        Files  = @{ 'src/A/Class.cs' = @{ Text = 'class A { }'; Bom = $true } }
        Expect = @(@{ Kind = 'ByteOrderMark'; Message = '1 file(s) start with a UTF-8 byte order mark, which the template''s encoding rule (UTF-8 without BOM) forbids: src/A/Class.cs. Save them without it.' })
    }
    'bom-many' = @{
        Files  = [ordered]@{ 'a.cs' = @{ Text = 'x'; Bom = $true }; 'b.cs' = @{ Text = 'x'; Bom = $true }; 'c.cs' = @{ Text = 'x'; Bom = $true }; 'd.cs' = @{ Text = 'x'; Bom = $true }; 'e.cs' = @{ Text = 'x'; Bom = $true }; 'f.cs' = @{ Text = 'x'; Bom = $true }; 'g.cs' = @{ Text = 'x'; Bom = $true } }
        Expect = @(@{ Kind = 'ByteOrderMark'; Message = '7 file(s) start with a UTF-8 byte order mark, which the template''s encoding rule (UTF-8 without BOM) forbids: a.cs, b.cs, c.cs, d.cs, e.cs, and 2 more. Save them without it.' })
    }
    'bom-in-script' = @{
        Files  = @{ 'build/dod.ps1' = @{ Text = 'Write-Output 1'; Bom = $true } }
        Expect = @()
    }
    'root-project' = @{
        Files  = @{ 'A.csproj' = $project }
        Expect = @(@{ Kind = 'RootProject'; Message = 'A.csproj sit at the repository root: move each project into src/ (a test project into tests/), as the template''s layout has it.' })
    }
    'skipped' = @{
        Files  = @{ 'src/A/obj/Generated.cs' = @{ Text = 'class G { }'; Bom = $true } }
        Expect = @()
    }
}

$updateAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null)
$updateDefinition = $updateAst.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-NuGetLogistics' }, $true) | Select-Object -First 1

Import-Module (Join-Path $repoRoot 'tools\adopt\Adoption.psm1') -Force
$sources = [ordered]@{
    update = {
        if (-not $updateDefinition) { throw 'Update-Project.ps1 has no Get-NuGetLogistics' }
        . ([scriptblock]::Create($updateDefinition.Extent.Text))
        Get-NuGetLogistics
    }
    adopt  = { Adoption\Get-NuGetLogistics }
}

foreach ($name in $cases.Keys) {
    $case = $cases[$name]
    $folder = Join-Path $Work $name
    New-Item -ItemType Directory -Force $folder | Out-Null
    foreach ($relative in $case.Files.Keys) {
        $value = $case.Files[$relative]
        if ($value -is [hashtable]) { Write-Text (Join-Path $folder $relative) $value.Text $value.Bom }
        else { Write-Text (Join-Path $folder $relative) $value }
    }
    foreach ($source in $sources.Keys) {
        Push-Location $folder
        $found = @()
        $failure = $null
        try { $found = @(& $sources[$source]) }
        catch { $failure = $_.Exception.Message }
        finally { Pop-Location }
        $ok = -not $failure -and $found.Count -eq $case.Expect.Count
        for ($i = 0; $ok -and $i -lt $found.Count; $i++) {
            $ok = $found[$i].Kind -eq $case.Expect[$i].Kind -and $found[$i].Message -ceq $case.Expect[$i].Message
        }
        $detail = $(if ($failure) { "Threw: $failure`n" })
        $detail += "Got:`n$(($found | ForEach-Object { "$($_.Kind): $($_.Message)" }) -join "`n")`nExpected:`n$(($case.Expect | ForEach-Object { "$($_.Kind): $($_.Message)" }) -join "`n")"
        Check "${source}: Get-NuGetLogistics: $name" $ok $detail
    }
}

''
if ($failures.Count) { "Kept the work folder: $Work"; "NuGet logistics tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'NuGet logistics tests: PASSED'
exit 0
