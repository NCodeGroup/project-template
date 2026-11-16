<#
.SYNOPSIS
    Test the warning .template\Update-Project.ps1 and Adopt-Project.ps1 print for a repository without a license.

.DESCRIPTION
    Tests a tagged snapshot of the working tree, which tests/New-TemplateSnapshot.ps1 builds. It runs apart from
    tests/Test-ProjectUpdate.ps1 and tests/Test-AdoptEdgeCases.ps1, which are slow enough already. Prints PASS or FAIL
    per check and exits 1 on any failure (ADR-0024).
      scripts      Adopt-Project.ps1 prints the update script's license warning word for word, under the same
                   condition.
      unit         Invoke-TemplateRender passes license= only for answers without a license line, and -Data's
                   license when given.
      no-answer    A project from before the license question, without a license answer: the update records a blank
                   answer, not the Apache-2.0 default, adds no license file and warns with the command that adds
                   Apache-2.0; with -Data @{ license = 'Apache-2.0' } it adds LICENSE.txt and COPYRIGHT.txt, records
                   the license and warns no more.
      own-license  A blank answer beside a LICENSE file of the repository's own: no warning, and the file is kept.
      licensed     The default Apache-2.0 answer: the update keeps the answer, LICENSE.txt and COPYRIGHT.txt, and
                   doesn't warn.
      adopt-unlicensed
                   Adopting a repository without a license: Adopt-Project.ps1 answers blank, not the Apache-2.0
                   default, adds no license file and prints the same warning, with the command that adds Apache-2.0.
      adopt-own-license
                   Adopting a repository with a LICENSE file of its own: no warning, and the file is kept.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-license-warning-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-LicenseWarning.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-license-warning-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Invoke-Copier {
    if (Get-Command copier -ErrorAction SilentlyContinue) { & copier @args }
    elseif (Get-Command uvx -ErrorAction SilentlyContinue) { & uvx --from copier copier @args }
    else { throw 'Copier not found. Install it with: uv tool install copier' }
    if ($LASTEXITCODE) { throw "copier $($args[0]) exited with code $LASTEXITCODE." }
}
# Run a project's own update script with &, collecting its output and its exit code, or -1 when it throws.
function Invoke-Update([string]$Project, [hashtable]$Data = @{}) {
    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $Project '.template\Update-Project.ps1') -Data $Data 2>&1 | ForEach-Object { $lines.Add("$_") }; $code = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $code = -1 }
    [pscustomobject]@{ ExitCode = $code; Output = $lines -join "`n" }
}
. (Join-Path $PSScriptRoot 'AdoptionFixtures.ps1')

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
# A direct run keeps its Copier mirror in its own work folder, not in the user's cache; under tests\Invoke-AllTests.ps1 it keeps the runner's folder.
$copierCache = $env:COPIER_CACHE_DIR
if (-not $copierCache) { $env:COPIER_CACHE_DIR = Join-Path $Work 'copier-cache' }
New-Item -ItemType Directory -Force $Work | Out-Null
$tpl = Join-Path $Work 'template-repo'
$tplUrl = & (Join-Path $PSScriptRoot 'New-TemplateSnapshot.ps1') $tpl

# The update script's warning, from its first line, and the command it prints; Adopt-Project.ps1 prints the same.
$re = "(?m)^\s*'(No license: (?:[^']|'')*)'\s*$"
$warning = [regex]::Match([IO.File]::ReadAllText((Join-Path $repoRoot 'template/.template/Update-Project.ps1')), $re).Groups[1].Value.Replace("''", "'")
$adoptWarning = [regex]::Match([IO.File]::ReadAllText((Join-Path $repoRoot 'Adopt-Project.ps1')), $re).Groups[1].Value.Replace("''", "'")
$command = "  .\.template\Update-Project.ps1 -Data @{ license = 'Apache-2.0' }"
Check 'scripts: Adopt-Project.ps1 prints the update''s license warning word for word' ($warning.Length -gt 100 -and $adoptWarning -eq $warning) "$warning | $adoptWarning"
# The same condition: the license-file pattern and the blank-answer check.
$patternRe = "Where-Object Name -Match '([^']+)'"
$updateText = [IO.File]::ReadAllText((Join-Path $repoRoot 'template/.template/Update-Project.ps1'))
$adoptText = [IO.File]::ReadAllText((Join-Path $repoRoot 'Adopt-Project.ps1'))
$updatePattern = [regex]::Match($updateText, $patternRe).Groups[1].Value
$adoptPattern = [regex]::Match($adoptText, $patternRe).Groups[1].Value
Check 'scripts: Adopt-Project.ps1 looks for a license file with the update''s pattern, after the same blank-answer check' ($updatePattern.StartsWith('^(LICEN') -and $adoptPattern -eq $updatePattern -and $updateText.Contains('"$(Get-Answer ''license'')".Trim()') -and $adoptText.Contains('"$(Get-Answer ''license'')".Trim()')) "$updatePattern | $adoptPattern"

# unit: Invoke-TemplateRender with a stand-in Copier that records its arguments: license= only for answers without a license line, -Data's license when given.
$licenseRender = & {
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null)
    foreach ($fnName in 'ConvertTo-CopierValue', 'Get-PreReleaseAnswer', 'Get-Answer', 'Get-CSharpFormatAnswer', 'Get-LicenseData', 'Invoke-TemplateRender') {
        $fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $fnName }, $true)
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    $recorded = [Collections.Generic.List[string]]::new()
    function Invoke-Copier { $recorded.Clear(); foreach ($a in $args) { $recorded.Add("$a") } }
    # Set-Variable: only the loaded functions read TemplateClone and Data, which the script analyzer can't see.
    Set-Variable -Name TemplateClone -Value $tpl
    $cases = [ordered]@{
        'recorded-mit'   = @{ Answers = "stack: python`nlicense: MIT`n"; Data = @{}; Want = '' }
        'recorded-blank' = @{ Answers = "stack: python`nlicense: ''`n"; Data = @{}; Want = '' }
        'no-line'        = @{ Answers = "stack: python`n"; Data = @{}; Want = 'license=' }
        'data-wins'      = @{ Answers = "stack: python`n"; Data = @{ license = 'MIT' }; Want = 'license=MIT' }
    }
    foreach ($name in $cases.Keys) {
        $project = Join-Path $Work "render-$name"
        $null = New-Item -ItemType Directory -Path $project -Force
        Set-Variable -Name Data -Value $cases[$name].Data
        [IO.File]::WriteAllText((Join-Path $project '.copier-answers.yml'), $cases[$name].Answers)
        Push-Location $project
        try { $null = Invoke-TemplateRender v0.1.0 (Join-Path $project 'out') }
        finally { Pop-Location }
        $got = @($recorded | Where-Object { $_ -like 'license=*' }) -join ','
        if ($got -ne $cases[$name].Want) { "${name}: [$got]" }
    }
}
Check 'unit: the render passes license= only for answers without a license line, and -Data''s license when given' (-not $licenseRender) ($licenseRender -join ' | ')

# no-answer: a project whose answers have no license line, as one from before the license question.
$noAnswer = Join-Path $Work 'no-answer'
Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data 'project_name=Test no-answer' --data stack=python --data git_host=github --data 'workflow_tools=[claude]' --data 'license=' $tplUrl $noAnswer
Push-Location $noAnswer
try {
    $answersFile = (Resolve-Path -LiteralPath .copier-answers.yml).Path
    [IO.File]::WriteAllText($answersFile, ([IO.File]::ReadAllText($answersFile) -replace '(?m)^license:.*\r?\n', ''))
    Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Create project'
    $result = Invoke-Update $noAnswer
    Check 'no-answer: the update records a blank license answer, not the Apache-2.0 default, and adds no license file' ($result.ExitCode -eq 0 -and (Get-Content -Raw -LiteralPath .copier-answers.yml) -match "(?m)^license: ''\r?$" -and -not (Test-Path -LiteralPath LICENSE.txt) -and -not (Test-Path -LiteralPath COPYRIGHT.txt)) $result.Output
    Check 'no-answer: the update warns with the command that adds Apache-2.0' ($result.Output.Contains($warning) -and $result.Output.Contains($command)) $result.Output
    $result = Invoke-Update $noAnswer @{ license = 'Apache-2.0' }
    Check 'no-answer: -Data @{ license = ''Apache-2.0'' } adds LICENSE.txt and COPYRIGHT.txt, records the license and warns no more' ($result.ExitCode -eq 0 -and (Test-Path -LiteralPath LICENSE.txt) -and (Test-Path -LiteralPath COPYRIGHT.txt) -and (Get-Content -Raw -LiteralPath .copier-answers.yml) -match '(?m)^license: Apache-2\.0\r?$' -and -not $result.Output.Contains('No license:')) $result.Output
}
finally { Pop-Location }

# own-license: a blank answer, and a LICENSE file of the repository's own.
$ownLicense = Join-Path $Work 'own-license'
Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data 'project_name=Test own-license' --data stack=python --data git_host=github --data 'workflow_tools=[claude]' --data 'license=' $tplUrl $ownLicense
Push-Location $ownLicense
try {
    [IO.File]::WriteAllText((Join-Path $ownLicense 'LICENSE'), "Own license.`n", [Text.UTF8Encoding]::new($false))
    Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Create project'
    $result = Invoke-Update $ownLicense
    Check 'own-license: a blank answer beside a LICENSE file of the repository''s own gets no warning' ($result.ExitCode -eq 0 -and -not $result.Output.Contains('No license:') -and [IO.File]::ReadAllText((Join-Path $ownLicense 'LICENSE')) -eq "Own license.`n") $result.Output
}
finally { Pop-Location }

# licensed: the default Apache-2.0 answer, with the LICENSE.txt and COPYRIGHT.txt it writes.
$licensed = Join-Path $Work 'licensed'
Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data 'project_name=Test licensed' --data stack=python --data git_host=github --data 'workflow_tools=[claude]' $tplUrl $licensed
Push-Location $licensed
try {
    Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Create project'
    $licenseHashes = (Get-FileHash -LiteralPath LICENSE.txt, COPYRIGHT.txt).Hash -join ','
    $result = Invoke-Update $licensed
    Check 'licensed: the update keeps the Apache-2.0 answer, LICENSE.txt and COPYRIGHT.txt, and doesn''t warn' ($result.ExitCode -eq 0 -and (Get-Content -Raw -LiteralPath .copier-answers.yml) -match '(?m)^license: Apache-2\.0\r?$' -and (Test-Path -LiteralPath LICENSE.txt) -and (Test-Path -LiteralPath COPYRIGHT.txt) -and ((Get-FileHash -LiteralPath LICENSE.txt, COPYRIGHT.txt).Hash -join ',') -eq $licenseHashes -and -not $result.Output.Contains('No license')) $result.Output
}
finally { Pop-Location }

# adopt-unlicensed: Adopt-Project.ps1 on a repository without a license, answering nothing about one.
$adopt = Join-Path $repoRoot 'Adopt-Project.ps1'
$adoptUnlicensed = New-Fixture 'adopt-unlicensed' @{ 'README.md' = "# Adopt Unlicensed`n" } 'https://github.com/example/adopt-unlicensed.git'
$adoptOut = & $adopt -Path $adoptUnlicensed -Template $tpl -Ref v0.1.0 -NoVerify | Out-String
Check 'adopt-unlicensed: answers a blank license, not the Apache-2.0 default, and adds no license file' ((Get-Content -Raw -LiteralPath (Join-Path $adoptUnlicensed '.copier-answers.yml')) -match "(?m)^license: ''\r?$" -and -not (Test-Path -LiteralPath (Join-Path $adoptUnlicensed 'LICENSE.txt')) -and -not (Test-Path -LiteralPath (Join-Path $adoptUnlicensed 'COPYRIGHT.txt'))) $adoptOut
Check 'adopt-unlicensed: warns, word for word as the update does, with the command that adds Apache-2.0' ($adoptOut.Contains($warning) -and $adoptOut.Contains($command)) $adoptOut

# adopt-own-license: a LICENSE file of the repository's own.
$adoptOwn = New-Fixture 'adopt-own-license' @{ 'README.md' = "# Adopt Own License`n"; 'LICENSE' = "Own license.`n" } 'https://github.com/example/adopt-own-license.git'
$adoptOwnOut = & $adopt -Path $adoptOwn -Template $tpl -Ref v0.1.0 -NoVerify | Out-String
Check 'adopt-own-license: a repository with a LICENSE file of its own gets no warning' (-not $adoptOwnOut.Contains('No license:') -and [IO.File]::ReadAllText((Join-Path $adoptOwn 'LICENSE')) -eq "Own license.`n") $adoptOwnOut

''
$env:COPIER_CACHE_DIR = $copierCache
if ($failures.Count) { "Kept the work folder: $Work"; "License warning tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'License warning tests: PASSED'
exit 0
