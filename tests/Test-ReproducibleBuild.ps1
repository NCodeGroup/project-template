<#
.SYNOPSIS
    Test template/.template/Test-ReproducibleBuild.ps1, which packs twice and compares the packages, on a fixture.

.DESCRIPTION
    Builds a class library fixture and runs the script on it: a deterministic build whose package and symbol package
    match entry by entry, whose own bin and obj folders it deletes and whose own .claude, artifacts and node_modules
    folders keep their build output, the same fixture once a Directory.Build.targets writes the clock into the
    Copyright, and a fixture that packs nothing. Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-reproducible-build-test-<process ID> in
    the temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-ReproducibleBuild.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-reproducible-build-test-$PID")
)
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repoRoot 'template\.template\Test-ReproducibleBuild.ps1'
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Write-Text([string]$Path, [string]$Text) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    Set-Content -LiteralPath $Path -Value $Text -Encoding utf8NoBOM
}
function New-Fixture([string]$Name, [string]$Properties) {
    $folder = Join-Path $Work $Name
    New-Item -ItemType Directory -Force $folder | Out-Null
    & dotnet new classlib -o (Join-Path $folder 'src/Lib') --no-restore | Out-Null
    if ($LASTEXITCODE) { throw "dotnet new classlib failed for $Name." }
    & dotnet new sln -n Fixture -o $folder | Out-Null
    if ($LASTEXITCODE) { throw "dotnet new sln failed for $Name." }
    & dotnet sln $folder add (Join-Path $folder 'src/Lib') | Out-Null
    if ($LASTEXITCODE) { throw "dotnet sln add failed for $Name." }
    Write-Text (Join-Path $folder 'Directory.Build.props') "<Project><PropertyGroup><Deterministic>true</Deterministic><Version>1.0.0</Version>$Properties</PropertyGroup></Project>"
    New-Item -ItemType Directory -Force (Join-Path $folder '.template') | Out-Null
    Copy-Item -LiteralPath $script -Destination (Join-Path $folder '.template/Test-ReproducibleBuild.ps1')
    $folder
}
function Invoke-Check([string]$Folder) {
    $out = & pwsh -NoProfile -File (Join-Path $Folder '.template/Test-ReproducibleBuild.ps1') -Root $Folder 2>&1 | Out-String
    [pscustomobject]@{ Exit = $LASTEXITCODE; Output = $out }
}

if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

$packable = New-Fixture 'packable' '<IncludeSymbols>true</IncludeSymbols><SymbolPackageFormat>snupkg</SymbolPackageFormat>'
$worktreeOutput = @('bin/Release/keep.txt', 'obj/keep.txt' | ForEach-Object { Join-Path $packable ".claude/worktrees/wt/src/Lib/$_" })
foreach ($file in $worktreeOutput) { Write-Text $file 'keep' }
$skippedOutput = @('artifacts/old/bin/keep.txt', 'node_modules/pkg/obj/keep.txt' | ForEach-Object { Join-Path $packable $_ })
foreach ($file in $skippedOutput) { Write-Text $file 'keep' }
$staleOutput = @('bin/stale.txt', 'obj/stale.txt' | ForEach-Object { Join-Path $packable "src/Lib/$_" })
foreach ($file in $staleOutput) { Write-Text $file 'stale' }
$result = Invoke-Check $packable
Check 'a deterministic library is reproducible' ($result.Exit -eq 0 -and $result.Output.Contains('Reproducible: 2 packages match')) "exit=$($result.Exit) $($result.Output)"
$gone = @($worktreeOutput | Where-Object { -not (Test-Path -LiteralPath $_) })
Check 'the build output of a plan''s worktree under the repository''s own .claude folder is left in place' ($gone.Count -eq 0) "Deleted: $($gone -join ', ')"
$gone = @($skippedOutput | Where-Object { -not (Test-Path -LiteralPath $_) })
Check 'the bin and obj folders under artifacts and node_modules are left in place' ($gone.Count -eq 0) "Deleted: $($gone -join ', ')"
$kept = @($staleOutput | Where-Object { Test-Path -LiteralPath $_ })
Check 'the bin and obj folders of the repository''s own project are deleted before each pack' ($kept.Count -eq 0) "Kept: $($kept -join ', ')"

Write-Text (Join-Path $packable 'Directory.Build.targets') '<Project><PropertyGroup><Copyright>$([System.DateTime]::UtcNow.Ticks)</Copyright></PropertyGroup></Project>'
$result = Invoke-Check $packable
Check 'a build that writes the clock into the package is not reproducible' ($result.Exit -eq 1 -and $result.Output.Contains('Not reproducible:')) "exit=$($result.Exit) $($result.Output)"

$unpackable = New-Fixture 'unpackable' '<IsPackable>false</IsPackable>'
$result = Invoke-Check $unpackable
Check 'a project that packs nothing has no packages to compare' ($result.Exit -eq 0 -and $result.Output.Contains('No packages to compare.')) "exit=$($result.Exit) $($result.Output)"

function New-MarkerFixture([string]$Name, [bool]$StartPresent, [string]$Content) {
    $folder = New-Fixture $Name ''
    Write-Text (Join-Path $folder 'extra.txt') 'extra'
    $marker = Join-Path $folder 'marker.txt'
    if ($StartPresent) { Write-Text $marker 'present' }
    # Each pack flips the marker, which the next pack's evaluation reads, so the first and second pack differ.
    $flip = if ($StartPresent) { '<Delete Files="$(Marker)" />' } else { '<WriteLinesToFile File="$(Marker)" Lines="present" Overwrite="true" />' }
    Write-Text (Join-Path $folder 'Directory.Build.targets') @"
<Project>
  <PropertyGroup><Marker>`$(MSBuildThisFileDirectory)marker.txt</Marker></PropertyGroup>
$Content
  <Target Name="FlipMarker" BeforeTargets="CoreCompile">
    $flip
  </Target>
</Project>
"@
    $folder
}

$extraItem = '  <ItemGroup Condition="Exists(''$(Marker)'')"><None Include="$(MSBuildThisFileDirectory)extra.txt" Pack="true" PackagePath="extra/" /></ItemGroup>'
$folder = New-MarkerFixture 'entry-missing-second' $true $extraItem
$result = Invoke-Check $folder
Check 'an entry only the first build packs is reported missing from the second build' ($result.Exit -eq 1 -and $result.Output.Contains('extra/extra.txt is missing from the second build')) "exit=$($result.Exit) $($result.Output)"

$folder = New-MarkerFixture 'entry-missing-first' $false $extraItem
$result = Invoke-Check $folder
Check 'an entry only the second build packs is reported missing from the first build' ($result.Exit -eq 1 -and $result.Output.Contains('extra/extra.txt is missing from the first build')) "exit=$($result.Exit) $($result.Output)"

$folder = New-MarkerFixture 'package-missing-second' $true '  <PropertyGroup Condition="Exists(''$(Marker)'')"><IsPackable>true</IsPackable></PropertyGroup><PropertyGroup Condition="!Exists(''$(Marker)'')"><IsPackable>false</IsPackable></PropertyGroup>'
$result = Invoke-Check $folder
Check 'a package only the first build produces is reported missing from the second build' ($result.Exit -eq 1 -and $result.Output.Contains('the package is missing from the second build')) "exit=$($result.Exit) $($result.Output)"

if ($failures.Count) { "Kept the work folder: $Work"; "Reproducible build tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Reproducible build tests: PASSED'
exit 0
