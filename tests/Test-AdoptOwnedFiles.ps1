<#
.SYNOPSIS
    Test that adopting a repository keeps its project-owned files and that a later update shows the template's changes.

.DESCRIPTION
    Adopts a repository that has its own .github/workflows/ci.yml (a merged file) and CLAUDE.md (a template-owned file)
    with -Data @{ project_owned_files = ... } naming both. The adoption must leave both exactly as the repository had
    them, record the answer in .copier-answers.yml and make one commit. One of the update's own files must stop the
    adoption before it changes anything. Then it changes the template's ci.yml and CLAUDE.md and updates the
    repository: the update must leave both alone and show the template's changes.
    Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-adopt-owned-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-AdoptOwnedFiles.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-adopt-owned-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Edit-File([string]$Path, [string]$Old, [string]$New) {
    $full = (Resolve-Path -LiteralPath $Path).Path
    $text = [IO.File]::ReadAllText($full)
    if (-not $text.Contains($Old)) { throw "'$Old' not found in $full." }
    [IO.File]::WriteAllText($full, $text.Replace($Old, $New))
}
function Invoke-Git {
    git -c user.name=template-test -c user.email=template-test@example.invalid @args
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed." }
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
# A direct run keeps its Copier mirror in its own work folder, not in the user's cache; under tests\Invoke-AllTests.ps1 it keeps the runner's folder.
$copierCache = $env:COPIER_CACHE_DIR
if (-not $copierCache) { $env:COPIER_CACHE_DIR = Join-Path $Work 'copier-cache' }
$tpl = Join-Path $Work 'template-repo'
$null = & (Join-Path $PSScriptRoot 'New-TemplateSnapshot.ps1') $tpl

$ownCi = "name: Own CI`non: push`njobs:`n  gate:`n    runs-on: windows-latest`n    steps:`n      - run: ./build.ps1`n      - run: ./test.ps1`n"
$ownClaude = "# Own CLAUDE.md`n"

$repo = Join-Path $Work 'owned'
New-Item -ItemType Directory -Force (Join-Path $repo '.github/workflows') | Out-Null
[IO.File]::WriteAllText((Join-Path $repo 'README.md'), "# Owned`n")
[IO.File]::WriteAllText((Join-Path $repo 'main.py'), "print('hi')`n")
[IO.File]::WriteAllText((Join-Path $repo 'pyproject.toml'), "[project]`nname = ""owned""`n")
$ci = Join-Path $repo '.github/workflows/ci.yml'
[IO.File]::WriteAllText($ci, $ownCi)
$claude = Join-Path $repo 'CLAUDE.md'
[IO.File]::WriteAllText($claude, $ownClaude)
Push-Location $repo
try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m Initial }
finally { Pop-Location }

$adopt = Join-Path $repoRoot 'Adopt-Project.ps1'
$answers = Join-Path $repo '.copier-answers.yml'

$msg = try { & $adopt -Path $repo -Template $tpl -Ref v0.1.0 -Data @{ project_owned_files = '.template/Update-Project.ps1' } -NoVerify | Out-Null } catch { $_.Exception.Message }
$status = git -C $repo status --porcelain
Check "reject: one of the update's own files stops the adoption before it changes anything" ("$msg".Contains("project_owned_files names .template/Update-Project.ps1, which the template doesn't render or the update itself needs") -and -not $status -and -not (Test-Path -LiteralPath $answers)) "$msg`n$($status | Out-String)"

$out = & $adopt -Path $repo -Template $tpl -Ref v0.1.0 -Data @{ project_owned_files = '.github/workflows/ci.yml', 'CLAUDE.md'; workflow_tools = @('claude') } -NoVerify | Out-String
Check 'adopt: ci.yml and CLAUDE.md kept as the repository had them' (([IO.File]::ReadAllText($ci) -eq $ownCi) -and ([IO.File]::ReadAllText($claude) -eq $ownClaude) -and $out.Contains('Owned .github/workflows/ci.yml') -and $out.Contains('Owned CLAUDE.md')) $out.Trim()
Check 'adopt: .copier-answers.yml records project_owned_files' ([IO.File]::ReadAllText($answers) -match '(?m)^project_owned_files:\r?\n- \.github/workflows/ci\.yml\r?\n- CLAUDE\.md\r?$') ([IO.File]::ReadAllText($answers))
Check 'adopt: one commit' ((git -C $repo log -1 --format=%s) -eq 'Adopt project-template v0.1.0')

Push-Location (Join-Path $tpl 'template')
try { Edit-File ".github/workflows/{% if git_host == 'github' %}ci.yml{% endif %}.jinja" "    runs-on: ubuntu-latest`n    timeout-minutes: 30`n    defaults:" "    runs-on: ubuntu-latest`n    timeout-minutes: 45`n    defaults:"
    Edit-File CLAUDE.md "## Claude Code`n" "## Claude Code`n`nOwned-test line from the template.`n"
}
finally { Pop-Location }
Push-Location $tpl
try { Invoke-Git commit -q -am 'Change ci.yml and CLAUDE.md'; Invoke-Git tag v0.2.0 }
finally { Pop-Location }

Push-Location $repo
try {
    $lines = [Collections.Generic.List[string]]::new()
    $exitCode = 0
    try {
        & (Join-Path $repo '.template\Update-Project.ps1') 2>&1 | ForEach-Object { $lines.Add("$_") }
        $exitCode = $LASTEXITCODE
    }
    catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    $updateOut = $lines -join "`n"
    Check "update: shows the template's changes to ci.yml and CLAUDE.md and leaves both alone" (($exitCode -eq 0) -and ([IO.File]::ReadAllText($ci) -eq $ownCi) -and ([IO.File]::ReadAllText($claude) -eq $ownClaude) -and ($updateOut -match '(?m)^  \.github/workflows/ci\.yml:\r?$') -and $updateOut.Contains('+    timeout-minutes: 45') -and ($updateOut -match '(?m)^  CLAUDE\.md:\r?$') -and $updateOut.Contains('+Owned-test line from the template.')) "exit $exitCode`n$updateOut"
}
finally { Pop-Location }
''
$env:COPIER_CACHE_DIR = $copierCache
if ($failures.Count) { "Kept the work folder: $Work"; "Adopt owned-files tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Adopt owned-files tests: PASSED'
exit 0
