<#
.SYNOPSIS
    Test adopting existing repositories into the template.

.DESCRIPTION
    Unit-tests the adoption functions on small inputs and, unless -UnitOnly is given, adopts fixture repositories
    from a tagged snapshot of the working tree (added in later steps). Prints PASS or FAIL per check and exits 1 on
    any failure.

.PARAMETER UnitOnly
    Run only the unit checks, which take seconds.

.PARAMETER SkipDotnetBuild
    Skip the .NET build and pack.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to %TEMP%\project-template-adopt-test.

.EXAMPLE
    .\Test-Adoption.ps1
    .\Test-Adoption.ps1 -UnitOnly
    .\Test-Adoption.ps1 -SkipDotnetBuild
#>
[CmdletBinding()]
param(
    [switch]$UnitOnly,
    [switch]$SkipDotnetBuild,
    [string]$Work = (Join-Path $env:TEMP 'project-template-adopt-test')
)
$ErrorActionPreference = 'Stop'
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Invoke-Git {
    git -c user.name=template-test -c user.email=template-test@example.invalid @args
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed." }
}
# Creates $Work\$Name with the given files (relative paths with forward slashes) and returns its path.
function New-TestFolder([string]$Name, [hashtable]$Files) {
    $folder = Join-Path $Work $Name
    New-Item -ItemType Directory -Force $folder | Out-Null
    foreach ($relative in $Files.Keys) {
        $file = Join-Path $folder $relative
        New-Item -ItemType Directory -Force (Split-Path -Parent $file) | Out-Null
        if ($relative.EndsWith('.png')) { [IO.File]::WriteAllBytes($file, [Convert]::FromBase64String($Files[$relative])) }
        else { [IO.File]::WriteAllText($file, $Files[$relative], [Text.UTF8Encoding]::new($false)) }
    }
    $folder
}

Import-Module (Join-Path $PSScriptRoot 'adopt\Adoption.psm1') -Force
if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

$copierYml = Join-Path $PSScriptRoot 'copier.yml'
$skip = @(Get-CopierList $copierYml '_skip_if_exists')
$merged = @(Get-CopierList $copierYml '_merged_files')
Check 'unit: Get-CopierList reads the file lists' (($skip -join ',') -eq 'AGENTS.md,README.md,Directory.Build.props' -and '.gitignore' -in $merged -and 'global.json' -in $merged) "$($skip -join ',') | $($merged -join ',')"

$demo = New-TestFolder 'demo' @{
    'src/NCode.Demo.slnx'   = '<Solution />'
    'Directory.Build.props' = "<Project>`n  <PropertyGroup>`n    <Authors>NCode Group</Authors>`n  </PropertyGroup>`n</Project>`n"
}
Push-Location $demo
try { Invoke-Git init -q -b main; Invoke-Git remote add origin https://gitlab.com/example/demo.git }
finally { Pop-Location }
$a = Get-AdoptionAnswers $demo
$detail = ($a.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; '
Check 'unit: Get-AdoptionAnswers works out a .NET repository' (($a.stack -eq 'dotnet') -and ($a.project_name -eq 'NCode.Demo') -and ($a.git_host -eq 'gitlab') -and ($a.author_name -eq 'NCode Group') -and ($a.build_command -eq 'dotnet build src/NCode.Demo.slnx') -and ($a.test_command -eq 'dotnet test src/NCode.Demo.slnx')) $detail

$others = [ordered]@{
    'only-node'   = @{ File = 'package.json'; Stack = 'node' }
    'only-python' = @{ File = 'pyproject.toml'; Stack = 'python' }
    'only-ps'     = @{ File = 'tool.ps1'; Stack = 'powershell' }
    'only-other'  = @{ File = 'main.tf'; Stack = 'other' }
}
$bad = foreach ($name in $others.Keys) {
    $folder = New-TestFolder $name @{ $others[$name].File = "x`n" }
    $a = Get-AdoptionAnswers $folder
    if (-not ($a.stack -eq $others[$name].Stack -and $a.git_host -eq 'github' -and $a.project_name -eq $name -and -not $a.Contains('build_command'))) {
        "${name}: $(($a.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ')"
    }
}
Check 'unit: Get-AdoptionAnswers works out other stacks' (-not $bad) ($bad -join ' | ')

$m = Merge-AdoptedFile '.gitignore' "bin/`nmine.log`n" "*.user`nobj/`n"
Check 'unit: Merge-AdoptedFile appends lines' ($m.Strategy -eq 'Lines' -and $m.Text.StartsWith("*.user`nobj/`n") -and $m.Text.EndsWith("`nbin/`nmine.log`n")) $m.Text

$m = Merge-AdoptedFile '.editorconfig' "root = true`n`n[*.cs]`nindent_size = 4`n" "root = true`n`n[*]`nindent_style = space`n"
Check 'unit: Merge-AdoptedFile keeps one editorconfig root' (@($m.Text -split "`n" | Where-Object { $_ -match '^\s*root\s*=' }).Count -eq 1 -and $m.Text.Contains('[*.cs]')) $m.Text

$m = Merge-AdoptedFile '.vscode/settings.json' ('{' + "`n" + '  // mine' + "`n" + '  "files.eol": "\r\n", "recommendations": ["a","b"], "editor.rulers": [100]' + "`n" + '}') '{"files.eol":"\n","recommendations":["a"]}'
$j = $m.Text | ConvertFrom-Json -AsHashtable
Check 'unit: Merge-AdoptedFile merges JSON' ($m.Strategy -eq 'Json' -and ($j.Keys -join ',') -eq 'files.eol,recommendations,editor.rulers' -and $j['files.eol'] -eq "`r`n" -and ($j.recommendations -join ',') -eq 'a,b' -and $m.Note -like '*comments*') $m.Text
$m = Merge-AdoptedFile 'x.json' '{"l":["a"]}' '{"l":["a"],"z":1}'
Check 'unit: Merge-AdoptedFile keeps a single-item JSON list' ($m.Text -match '"l":\s*\[\s*"a"\s*\]') $m.Text

$m = Merge-AdoptedFile 'Directory.Build.props' "<Project>`n  <PropertyGroup><LangVersion>latest</LangVersion></PropertyGroup>`n</Project>`n" "<Project>`n  <PropertyGroup>`n    <Nullable>enable</Nullable>`n  </PropertyGroup>`n</Project>`n"
$i1 = $m.Text.IndexOf('<Nullable>'); $i2 = $m.Text.IndexOf('<!-- Kept'); $i3 = $m.Text.IndexOf('<LangVersion>')
Check 'unit: Merge-AdoptedFile appends MSBuild elements' ($m.Strategy -eq 'MSBuild' -and $i1 -ge 0 -and $i1 -lt $i2 -and $i2 -lt $i3 -and $m.Text.EndsWith("</Project>`n")) $m.Text

$m = Merge-AdoptedFile '.github/workflows/ci.yml' "name: mine`n" "name: template`n"
Check 'unit: Merge-AdoptedFile keeps YAML' ($m.Strategy -eq 'Keep' -and $m.Text -eq "name: mine`n") $m.Strategy

$m = Merge-AdoptedFile '.gitignore' "bin/`n" "bin/`n`n"
Check 'unit: Merge-AdoptedFile leaves a matching file' ($m.Strategy -eq 'Same') $m.Strategy

$entryMarker = 'project-template.instructions.md'
$r = Add-TemplateIndexEntry "# Guide`n`n## Instructions`n`n- @a.md - mine`n`n## Layout`n"
$lines = $r -split "`n"
$h = [array]::IndexOf($lines, '## Instructions')
Check 'unit: Add-TemplateIndexEntry under Instructions' ($h -ge 0 -and $lines[$h + 1] -eq '' -and $lines[$h + 2].Contains($entryMarker) -and $lines[$h + 3] -eq '- @a.md - mine' -and $r.EndsWith("## Layout`n")) $r
$r = Add-TemplateIndexEntry "# Guide`n`nSome text.`n`n## Layout`n- x`n"
$lines = $r -split "`n"
$pt = [array]::IndexOf($lines, '## Project Template'); $ly = [array]::IndexOf($lines, '## Layout')
Check 'unit: Add-TemplateIndexEntry before the first section' ($lines[2] -eq 'Some text.' -and $pt -eq 4 -and $lines[3] -eq '' -and $lines[5] -eq '' -and $lines[6].Contains($entryMarker) -and $lines[7] -eq '' -and $ly -eq 8 -and $r.EndsWith("`n") -and -not $r.EndsWith("`n`n")) $r
Check 'unit: Add-TemplateIndexEntry once' ((Add-TemplateIndexEntry $r) -eq $r) ''
$x = "<?xml version=""1.0""?>`n<Project>`n  <PropertyGroup>`n    <A>1</A>`n  </PropertyGroup>`n</Project>`n"
$r = Add-ProjectTemplateImport $x
Check 'unit: Add-ProjectTemplateImport' ($r.StartsWith("<?xml version=""1.0""?>`n<Project>`n") -and $r.Contains('<Import Project="$(MSBuildThisFileDirectory)build/ProjectTemplate.props" />') -and $r.IndexOf('<Import') -lt $r.IndexOf('<PropertyGroup>') -and (Add-ProjectTemplateImport $r) -eq $r) $r
$central = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "template\{% if stack == 'dotnet' %}Directory.Packages.props{% endif %}")
$folder = New-TestFolder 'central' @{
    'Directory.Packages.props' = $central
    'A/A.csproj'               = "<Project Sdk=""Microsoft.NET.Sdk"">`n  <ItemGroup>`n    <PackageReference Include=""Foo"" Version=""1.0.0"" />`n  </ItemGroup>`n</Project>`n"
    'B/B.csproj'               = "<Project Sdk=""Microsoft.NET.Sdk"">`n  <ItemGroup>`n    <PackageReference Version=""1.2.0"" Include=""Foo"" />`n    <PackageReference Include=""Bar"" Version=""2.0.0"" PrivateAssets=""all"" />`n  </ItemGroup>`n</Project>`n"
}
$report = @(Move-PackageVersionsToCentral $folder)
$pa = Get-Content -Raw -LiteralPath (Join-Path $folder 'A/A.csproj')
$pb = Get-Content -Raw -LiteralPath (Join-Path $folder 'B/B.csproj')
$pp = Get-Content -Raw -LiteralPath (Join-Path $folder 'Directory.Packages.props')
$iBar = $pp.IndexOf('<PackageVersion Include="Bar" Version="2.0.0" />')
$iFoo = $pp.IndexOf('<PackageVersion Include="Foo" Version="1.2.0" />')
Check 'unit: Move-PackageVersionsToCentral' (-not $pa.Contains('Version="') -and -not $pb.Contains('Version="') -and $pb.Contains('PrivateAssets="all"') -and $iBar -ge 0 -and $iBar -lt $iFoo -and 'Foo: 1.0.0, 1.2.0 -> 1.2.0' -in $report) "$pa | $pb | $pp | $($report -join ' / ')"
''
if ($failures.Count) { "Adoption tests: FAILED ($($failures.Count))"; exit 1 }
'Adoption tests: PASSED'
