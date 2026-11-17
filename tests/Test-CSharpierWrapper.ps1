<#
.SYNOPSIS
    Test both copies of Get-CSharpierWrapper, the check in template\.template\Update-Project.ps1 and tools\adopt\Adoption.psm1
    for a project's own build script that runs CSharpier's check a second time.

.DESCRIPTION
    Builds one fixture folder per case and calls each copy of the function from it. A check passes only when both copies give
    the expected output. Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-csharpier-wrapper-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-CSharpierWrapper.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-csharpier-wrapper-test-$PID")
)
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Write-Text([string]$Path, [string]$Text) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

$manifest = '{"version":1,"isRoot":true,"tools":{"csharpier":{"version":"1.4.0","commands":["csharpier"]}}}'
$otherManifest = '{"version":1,"isRoot":true,"tools":{"dotnet-ef":{"version":"9.0.0","commands":["dotnet-ef"]}}}'
$check = "dotnet csharpier check .`n"
$templateFiles = 'build/dod.ps1', 'build/Install-Dotnet.ps1'

$cases = [ordered]@{
    'a script that runs the check, with the tool in the manifest' = @{
        Files  = @{ '.config/dotnet-tools.json' = $manifest; 'build/check.ps1' = $check }
        Expect = @('build/check.ps1')
    }
    'no manifest' = @{
        Files  = @{ 'build/check.ps1' = $check }
        Expect = @()
    }
    'a manifest without csharpier' = @{
        Files  = @{ '.config/dotnet-tools.json' = $otherManifest; 'build/check.ps1' = $check }
        Expect = @()
    }
    'the template''s own build/dod.ps1' = @{
        Files  = @{ '.config/dotnet-tools.json' = $manifest; 'build/dod.ps1' = $check }
        Expect = @()
    }
    'the check only in a comment' = @{
        Files  = @{ '.config/dotnet-tools.json' = $manifest; 'build/check.ps1' = "# dotnet csharpier check .`n" }
        Expect = @()
    }
    'the check only named in comment-based help' = @{
        Files  = @{ '.config/dotnet-tools.json' = $manifest; 'build/gate.ps1' = "<#`n.SYNOPSIS`n    The gate: build/dod.ps1, whose Format stage runs the CSharpier check.`n    dotnet csharpier check .`n#>`nparam()`n& ./build/dod.ps1`n" }
        Expect = @()
    }
    'the check only named in a string' = @{
        Files  = @{ '.config/dotnet-tools.json' = $manifest; 'build/check.ps1' = "Write-Host 'Run dotnet csharpier check . to see the files'`n" }
        Expect = @()
    }
    'CSharpier in another case' = @{
        Files  = @{ '.config/dotnet-tools.json' = $manifest; 'build/check.ps1' = "dotnet CSharpier check .`n" }
        Expect = @()
    }
    'a script block runs the check' = @{
        Files  = @{ '.config/dotnet-tools.json' = $manifest; 'build/check.ps1' = "Invoke-Stage 'Format' { dotnet csharpier check . }`n" }
        Expect = @('build/check.ps1')
    }
    'csharpier check at the start of a statement' = @{
        Files  = @{ '.config/dotnet-tools.json' = $manifest; 'build/check.ps1' = "if (`$true) { csharpier check . }`n" }
        Expect = @('build/check.ps1')
    }
    'dotnet.exe runs the check' = @{
        Files  = @{ '.config/dotnet-tools.json' = $manifest; 'build/check.ps1' = "dotnet.exe csharpier check .`n" }
        Expect = @('build/check.ps1')
    }
    'dotnet tool run runs the check' = @{
        Files  = @{ '.config/dotnet-tools.json' = $manifest; 'build/check.ps1' = "dotnet tool run csharpier check .`n" }
        Expect = @('build/check.ps1')
    }
    'another csharpier command' = @{
        Files  = @{ '.config/dotnet-tools.json' = $manifest; 'build/check.ps1' = "dotnet csharpier format .`n" }
        Expect = @()
    }
    'a script with a syntax error still runs the check' = @{
        Files  = @{ '.config/dotnet-tools.json' = $manifest; 'build/check.ps1' = "dotnet csharpier check .`nif (`n" }
        Expect = @('build/check.ps1')
    }
    'two scripts come back in name order' = @{
        Files  = [ordered]@{ '.config/dotnet-tools.json' = $manifest; 'build/b.ps1' = $check; 'build/a.ps1' = $check }
        Expect = @('build/a.ps1', 'build/b.ps1')
    }
    'no build folder' = @{
        Files  = @{ '.config/dotnet-tools.json' = $manifest }
        Expect = @()
    }
}

$updateAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null)
$updateDefinition = $updateAst.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-CSharpierWrapper' }, $true) | Select-Object -First 1

Import-Module (Join-Path $repoRoot 'tools\adopt\Adoption.psm1') -Force
$sources = [ordered]@{
    update = {
        if (-not $updateDefinition) { throw 'Update-Project.ps1 has no Get-CSharpierWrapper' }
        . ([scriptblock]::Create($updateDefinition.Extent.Text))
        Get-CSharpierWrapper -TemplateFiles $templateFiles
    }
    adopt  = { Adoption\Get-CSharpierWrapper -TemplateFiles $templateFiles }
}

$index = 0
foreach ($name in $cases.Keys) {
    $case = $cases[$name]
    $index++
    $folder = Join-Path $Work "case$index"
    New-Item -ItemType Directory -Force $folder | Out-Null
    foreach ($relative in $case.Files.Keys) { Write-Text (Join-Path $folder $relative) $case.Files[$relative] }
    $ok = $true
    $detail = ''
    foreach ($source in $sources.Keys) {
        Push-Location $folder
        $found = @()
        $failure = $null
        try { $found = @(& $sources[$source]) }
        catch { $failure = $_.Exception.Message }
        finally { Pop-Location }
        $ok = $ok -and -not $failure -and ($found -join '|') -ceq ($case.Expect -join '|')
        $detail += "${source}: "
        if ($failure) { $detail += "Threw: $failure " }
        $detail += "Got: $($found -join ', ') Expected: $($case.Expect -join ', ')  "
    }
    Check "Get-CSharpierWrapper: $name" $ok $detail
}

''
if ($failures.Count) { "Kept the work folder: $Work"; "CSharpier wrapper tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'CSharpier wrapper tests: PASSED'
exit 0
