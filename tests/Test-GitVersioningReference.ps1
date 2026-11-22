<#
.SYNOPSIS
    Test Remove-GitVersioningReference, which drops a repository's own Nerdbank.GitVersioning reference, in tools\adopt\Adoption.psm1.

.DESCRIPTION
    Builds one fixture folder per case and passes it to Remove-GitVersioningReference: a project file, a Directory.Build.props
    and a Directory.Packages.props that carry the reference, and the files that must stay as they are, among them every file of a repository whose build/ProjectTemplate.props doesn't reference Nerdbank.GitVersioning, or that has none. Prints PASS or FAIL per
    check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-gitversioning-reference-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-GitVersioningReference.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-gitversioning-reference-test-$PID")
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
function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path) }

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

Import-Module (Join-Path $repoRoot 'tools\adopt\Adoption.psm1') -Force

# build/ProjectTemplate.props as a library's: it references Nerdbank.GitVersioning, so a repository's own reference is a second one.
$template = @'
<Project>
  <ItemGroup>
    <PackageReference Include="Nerdbank.GitVersioning" PrivateAssets="all" />
  </ItemGroup>
</Project>
'@

# (a) a project file with a self-closing reference and another package
$a = Join-Path $Work 'a'
$csproj = @'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="Nerdbank.GitVersioning" PrivateAssets="all" />
    <PackageReference Include="Serilog" />
  </ItemGroup>
</Project>
'@
Write-Text (Join-Path $a 'src/A/A.csproj') $csproj
Write-Text (Join-Path $a 'build/ProjectTemplate.props') $template
$result = @(Remove-GitVersioningReference $a)
$text = Read-Text (Join-Path $a 'src/A/A.csproj')
Check 'self-closing: the reference is gone' (-not $text.Contains('Nerdbank.GitVersioning')) $text
Check 'self-closing: the other package stays' ($text.Contains('<PackageReference Include="Serilog" />')) $text
Check 'self-closing: one result for the project file' ($result.Count -eq 1 -and $result[0].File -ceq 'src/A/A.csproj') "Got $($result.Count): $(($result | ForEach-Object File) -join ', ')"

# (b) a Directory.Build.props whose only ItemGroup holds a multi-line reference
$b = Join-Path $Work 'b'
$props = @'
<Project>
  <ItemGroup>
    <PackageReference Include="Nerdbank.GitVersioning" Version="3.6.0">
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
  </ItemGroup>
</Project>
'@
Write-Text (Join-Path $b 'Directory.Build.props') $props
Write-Text (Join-Path $b 'build/ProjectTemplate.props') $template
$result = @(Remove-GitVersioningReference $b)
$text = Read-Text (Join-Path $b 'Directory.Build.props')
Check 'multi-line: the reference is gone' (-not $text.Contains('Nerdbank.GitVersioning') -and -not $text.Contains('PrivateAssets')) $text
Check 'multi-line: the emptied ItemGroup is gone' (-not $text.Contains('ItemGroup')) $text
Check 'multi-line: the file is still well-formed XML' ([bool]([xml]$text)) $text
Check 'multi-line: one result with the version' ($result.Count -eq 1 -and $result[0].File -ceq 'Directory.Build.props' -and $result[0].Version -ceq '3.6.0') "Got $($result.Count): $(($result | ForEach-Object { "$($_.File) $($_.Version)" }) -join ', ')"

# (c) a Directory.Packages.props with two PackageVersion lines
$c = Join-Path $Work 'c'
$central = @'
<Project>
  <ItemGroup>
    <PackageVersion Include="Nerdbank.GitVersioning" Version="3.7.115" />
    <PackageVersion Include="Serilog" Version="4.0.0" />
    <PackageVersion Include="Nerdbank.GitVersioning" Version="3.6.0" />
  </ItemGroup>
</Project>
'@
Write-Text (Join-Path $c 'Directory.Packages.props') $central
Write-Text (Join-Path $c 'build/ProjectTemplate.props') $template
$result = @(Remove-GitVersioningReference $c)
$text = Read-Text (Join-Path $c 'Directory.Packages.props')
Check 'two versions: the first stays' ($text.Contains('Version="3.7.115"')) $text
Check 'two versions: the second is gone' (-not $text.Contains('Version="3.6.0"')) $text
Check 'two versions: the other package stays' ($text.Contains('<PackageVersion Include="Serilog" Version="4.0.0" />')) $text
Check 'two versions: one result with the removed version' ($result.Count -eq 1 -and $result[0].File -ceq 'Directory.Packages.props' -and $result[0].Version -ceq '3.6.0') "Got $($result.Count)"

# (d) a Directory.Packages.props with one PackageVersion line
$d = Join-Path $Work 'd'
$one = $central -replace '(?m)^.*Version="3\.6\.0".*\r?\n', ''
Write-Text (Join-Path $d 'Directory.Packages.props') $one
$result = @(Remove-GitVersioningReference $d)
Check 'one version: unchanged' ((Read-Text (Join-Path $d 'Directory.Packages.props')) -ceq $one)
Check 'one version: no result' ($result.Count -eq 0) "Got $($result.Count)"

# (e) a repository with no reference
$e = Join-Path $Work 'e'
$plain = '<Project Sdk="Microsoft.NET.Sdk">' + "`r`n" + '  <ItemGroup>' + "`r`n" + '    <PackageReference Include="Serilog" />' + "`r`n" + '  </ItemGroup>' + "`r`n" + '</Project>' + "`r`n"
$emptyGroup = '<Project>' + "`n" + '  <ItemGroup>' + "`n" + '  </ItemGroup>' + "`n" + '</Project>' + "`n"
Write-Text (Join-Path $e 'src/A/A.csproj') $plain
Write-Text (Join-Path $e 'Directory.Build.props') $emptyGroup
$before = @(Get-ChildItem -LiteralPath $e -Recurse -File | Sort-Object FullName | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash })
$result = @(Remove-GitVersioningReference $e)
$after = @(Get-ChildItem -LiteralPath $e -Recurse -File | Sort-Object FullName | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash })
Check 'no reference: no result' ($result.Count -eq 0) "Got $($result.Count)"
Check 'no reference: the files are byte-for-byte unchanged' (($before -join ',') -ceq ($after -join ',')) "$($before -join ',') vs $($after -join ',')"

# (f) build/ProjectTemplate.props with the reference
$f = Join-Path $Work 'f'
Write-Text (Join-Path $f 'build/ProjectTemplate.props') $template
$result = @(Remove-GitVersioningReference $f)
Check 'template props: untouched' ((Read-Text (Join-Path $f 'build/ProjectTemplate.props')) -ceq $template)
Check 'template props: no result' ($result.Count -eq 0) "Got $($result.Count)"

# (g) a self-closing reference followed by a multi-line reference
$g = Join-Path $Work 'g'
$followed = @'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="Nerdbank.GitVersioning" PrivateAssets="all" />
    <PackageReference Include="Serilog" Version="1">
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
  </ItemGroup>
</Project>
'@
Write-Text (Join-Path $g 'src/G/G.csproj') $followed
Write-Text (Join-Path $g 'build/ProjectTemplate.props') $template
$result = @(Remove-GitVersioningReference $g)
$text = Read-Text (Join-Path $g 'src/G/G.csproj')
Check 'self-closing before multi-line: the reference is gone' (-not $text.Contains('Nerdbank.GitVersioning')) $text
Check 'self-closing before multi-line: the next element stays whole' ($text.Contains('<PackageReference Include="Serilog" Version="1">') -and $text.Contains('<PrivateAssets>all</PrivateAssets>') -and $text.Contains('</PackageReference>')) $text
Check 'self-closing before multi-line: one result' ($result.Count -eq 1) "Got $($result.Count)"

# (h) a repository that isn't a library: build/ProjectTemplate.props doesn't reference Nerdbank.GitVersioning, so the repository's own reference is its only one
$h = Join-Path $Work 'h'
Write-Text (Join-Path $h 'build/ProjectTemplate.props') ("<Project>`n  <PropertyGroup>`n    <Nullable>enable</Nullable>`n  </PropertyGroup>`n</Project>`n")
Write-Text (Join-Path $h 'Directory.Build.props') $props
Write-Text (Join-Path $h 'src/H/H.csproj') $csproj
Write-Text (Join-Path $h 'Directory.Packages.props') $central
$before = @(Get-ChildItem -LiteralPath $h -Recurse -File | Sort-Object FullName | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash })
$result = @(Remove-GitVersioningReference $h)
$after = @(Get-ChildItem -LiteralPath $h -Recurse -File | Sort-Object FullName | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash })
Check 'not a library: no result' ($result.Count -eq 0) "Got $($result.Count)"
Check 'not a library: the files are byte-for-byte unchanged' (($before -join ',') -ceq ($after -join ',')) "$($before -join ',') vs $($after -join ',')"

# (i) a repository without build/ProjectTemplate.props
$i = Join-Path $Work 'i'
Write-Text (Join-Path $i 'src/I/I.csproj') $csproj
$before = @(Get-ChildItem -LiteralPath $i -Recurse -File | Sort-Object FullName | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash })
$result = @(Remove-GitVersioningReference $i)
$after = @(Get-ChildItem -LiteralPath $i -Recurse -File | Sort-Object FullName | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash })
Check 'no template props: no result' ($result.Count -eq 0) "Got $($result.Count)"
Check 'no template props: the files are byte-for-byte unchanged' (($before -join ',') -ceq ($after -join ',')) "$($before -join ',') vs $($after -join ',')"

''
if ($failures.Count) { "Kept the work folder: $Work"; "GitVersioning reference tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'GitVersioning reference tests: PASSED'
exit 0
