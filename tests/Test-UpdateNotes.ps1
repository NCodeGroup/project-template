<#
.SYNOPSIS
    Test what .template\Update-Project.ps1 adds to an update: the opt-in answers it gives an existing project, and the
    notes it prints.

.DESCRIPTION
    Needs no template snapshot, Copier or network. Prints PASS or FAIL per check and exits 1 on any failure (ADR-0024).
      opt-in    Invoke-TemplateRender, with a stand-in Copier that records its arguments, passes <answer>=false for
                each opt-in answer the answers file lacks and -Data doesn't set, and nothing for one it has.
      adopt     Get-AdoptionAnswers answers node_lint = $false for a Node.js repository, and coverage_gate = $false
                and file_headers = $false for every repository.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-notes-test-<process ID> in the temp
    folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-UpdateNotes.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-notes-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

# opt-in: Invoke-TemplateRender with a stand-in Copier that records its arguments.
$optIns = 'csharp_format', 'node_lint', 'coverage_gate', 'file_headers'
$optInRender = & {
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null)
    foreach ($fnName in 'ConvertTo-CopierValue', 'Get-PreReleaseAnswer', 'Get-Answer', 'Get-OptInData', 'Get-LicenseData', 'Invoke-TemplateRender') {
        $fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $fnName }, $true)
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    $recorded = [Collections.Generic.List[string]]::new()
    function Invoke-Copier { $recorded.Clear(); foreach ($a in $args) { $recorded.Add("$a") } }
    # Set-Variable: only the loaded functions read TemplateClone, Data and project, which the script analyzer can't see.
    Set-Variable -Name TemplateClone -Value (Join-Path $Work 'template-repo')
    $allTrue = (($optIns | ForEach-Object { "${_}: true" }) -join "`n") + "`n"
    $cases = [ordered]@{
        'lacking'  = @{ Answers = "stack: node`n"; Data = @{}; Want = ($optIns | ForEach-Object { "$_=false" }) }
        'recorded' = @{ Answers = "stack: node`n$allTrue"; Data = @{}; Want = @() }
        'data-on'  = @{ Answers = "stack: node`n"; Data = @{ node_lint = $true }; Want = ($optIns | ForEach-Object { if ($_ -eq 'node_lint') { "$_=True" } else { "$_=false" } }) }
    }
    foreach ($name in $cases.Keys) {
        $folder = Join-Path $Work "render-$name"
        $null = New-Item -ItemType Directory -Path $folder -Force
        Set-Variable -Name project -Value $folder
        Set-Variable -Name Data -Value $cases[$name].Data
        [IO.File]::WriteAllText((Join-Path $folder '.copier-answers.yml'), $cases[$name].Answers)
        Push-Location $folder
        try { $null = Invoke-TemplateRender v0.1.0 (Join-Path $folder 'out') }
        finally { Pop-Location }
        $got = (@($recorded | Where-Object { $_ -match "^($($optIns -join '|'))=" }) | Sort-Object) -join ','
        $want = (@($cases[$name].Want) | Sort-Object) -join ','
        Check "opt-in: $name" ($got -eq $want) "got [$got], want [$want]"
    }
}
$optInRender

# adopt: a Node.js repository is adopted with node_lint off, and every repository with coverage_gate off.
Import-Module (Join-Path $repoRoot 'tools/adopt/Adoption.psm1') -Force
$adoptNode = Join-Path $Work 'adopt-node'
New-Item -ItemType Directory -Force $adoptNode | Out-Null
[IO.File]::WriteAllText((Join-Path $adoptNode 'package.json'), '{"name":"adopt-node","scripts":{"test":"node --test"}}', [Text.UTF8Encoding]::new($false))
$adoptAnswers = Get-AdoptionAnswers $adoptNode
Check 'adopt: a Node.js repository is adopted with node_lint off' ($adoptAnswers.node_lint -eq $false) ($adoptAnswers | ConvertTo-Json -Compress)
Check 'adopt: a Node.js repository is adopted with coverage_gate off' ($adoptAnswers.coverage_gate -eq $false) ($adoptAnswers | ConvertTo-Json -Compress)
Check 'adopt: a Node.js repository is adopted with file_headers off' ($adoptAnswers.file_headers -eq $false) ($adoptAnswers | ConvertTo-Json -Compress)
$adoptPython = Join-Path $Work 'adopt-python'
New-Item -ItemType Directory -Force $adoptPython | Out-Null
[IO.File]::WriteAllText((Join-Path $adoptPython 'requirements.txt'), "pytest`n", [Text.UTF8Encoding]::new($false))
$pythonAnswers = Get-AdoptionAnswers $adoptPython
Check 'adopt: a Python repository is adopted with coverage_gate off' ($pythonAnswers.stack -eq 'python' -and $pythonAnswers.coverage_gate -eq $false) ($pythonAnswers | ConvertTo-Json -Compress)
Check 'adopt: a Python repository is adopted with file_headers off' ($pythonAnswers.file_headers -eq $false) ($pythonAnswers | ConvertTo-Json -Compress)

''
if ($failures.Count) { "Kept the work folder: $Work"; "Update notes tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Update notes tests: PASSED'
exit 0
