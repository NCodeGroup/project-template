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

''
if ($failures.Count) { "Adoption tests: FAILED ($($failures.Count))"; exit 1 }
'Adoption tests: PASSED'
