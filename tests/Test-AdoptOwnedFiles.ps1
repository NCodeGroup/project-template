<#
.SYNOPSIS
    Test that adopting a repository keeps a project-owned merged file and that a later update shows the template's change.

.DESCRIPTION
    Adopts a repository that has its own .github/workflows/ci.yml with -Data @{ project_owned_files = ... } naming that
    file. The adoption must leave ci.yml exactly as the repository had it, record the answer in .copier-answers.yml and
    make one commit. A file that isn't merged must stop the adoption before it changes anything. Then it changes the
    template's ci.yml and updates the repository: the update must leave ci.yml alone and show the template's change.
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
$tpl = Join-Path $Work 'template-repo'
New-Item -ItemType Directory -Force $tpl | Out-Null
Get-ChildItem -LiteralPath $repoRoot -Force | Where-Object Name -NotIn '.git', '.claude' | Copy-Item -Destination $tpl -Recurse -Force
# Claude Code's plan worktrees are other checkouts, not part of the snapshot.
$claudeCopy = New-Item -ItemType Directory -Force (Join-Path $tpl '.claude')
Get-ChildItem -LiteralPath (Join-Path $repoRoot '.claude') -Force | Where-Object Name -NE 'worktrees' | Copy-Item -Destination $claudeCopy.FullName -Recurse -Force
Push-Location $tpl
try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Snapshot'; Invoke-Git tag v0.1.0 }
finally { Pop-Location }

$ownCi = "name: Own CI`non: push`njobs:`n  gate:`n    runs-on: windows-latest`n    steps:`n      - run: ./build.ps1`n      - run: ./test.ps1`n"

$repo = Join-Path $Work 'owned'
New-Item -ItemType Directory -Force (Join-Path $repo '.github/workflows') | Out-Null
[IO.File]::WriteAllText((Join-Path $repo 'README.md'), "# Owned`n")
[IO.File]::WriteAllText((Join-Path $repo 'main.py'), "print('hi')`n")
[IO.File]::WriteAllText((Join-Path $repo 'pyproject.toml'), "[project]`nname = ""owned""`n")
$ci = Join-Path $repo '.github/workflows/ci.yml'
[IO.File]::WriteAllText($ci, $ownCi)
Push-Location $repo
try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m Initial }
finally { Pop-Location }

$adopt = Join-Path $repoRoot 'Adopt-Project.ps1'
$answers = Join-Path $repo '.copier-answers.yml'

$msg = try { & $adopt -Path $repo -Template $tpl -Ref v0.1.0 -Data @{ project_owned_files = 'CLAUDE.md' } -NoVerify | Out-Null } catch { $_.Exception.Message }
$status = git -C $repo status --porcelain
Check "reject: a file that isn't merged stops the adoption before it changes anything" ("$msg".Contains("which isn't a merged file") -and -not $status -and -not (Test-Path -LiteralPath $answers)) "$msg`n$($status | Out-String)"

$out = & $adopt -Path $repo -Template $tpl -Ref v0.1.0 -Data @{ project_owned_files = '.github/workflows/ci.yml'; workflow_tools = @('claude') } -NoVerify | Out-String
Check 'adopt: ci.yml kept as the repository had it' (([IO.File]::ReadAllText($ci) -eq $ownCi) -and $out.Contains('Owned .github/workflows/ci.yml')) $out.Trim()
Check 'adopt: .copier-answers.yml records project_owned_files' ([IO.File]::ReadAllText($answers) -match '(?m)^project_owned_files:\r?\n- \.github/workflows/ci\.yml\r?$') ([IO.File]::ReadAllText($answers))
Check 'adopt: one commit' ((git -C $repo log -1 --format=%s) -eq 'Adopt project-template v0.1.0')

Push-Location (Join-Path $tpl 'template')
try { Edit-File ".github/workflows/{% if git_host == 'github' %}ci.yml{% endif %}.jinja" "    runs-on: ubuntu-latest`n    timeout-minutes: 30`n    defaults:" "    runs-on: ubuntu-latest`n    timeout-minutes: 45`n    defaults:" }
finally { Pop-Location }
Push-Location $tpl
try { Invoke-Git commit -q -am 'Change ci.yml'; Invoke-Git tag v0.2.0 }
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
    Check "update: shows the template's ci.yml change and leaves the file alone" (($exitCode -eq 0) -and ([IO.File]::ReadAllText($ci) -eq $ownCi) -and ($updateOut -match '(?m)^  \.github/workflows/ci\.yml:\r?$') -and $updateOut.Contains('+    timeout-minutes: 45')) "exit $exitCode`n$updateOut"
}
finally { Pop-Location }
''
if ($failures.Count) { "Kept the work folder: $Work"; "Adopt owned-files tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Adopt owned-files tests: PASSED'
exit 0
