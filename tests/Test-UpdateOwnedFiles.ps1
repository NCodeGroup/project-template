<#
.SYNOPSIS
    Test that an update leaves a project-owned merged file as the project has it and shows the template's change.

.DESCRIPTION
    Renders a project from v0.1.0 that lists .github/workflows/ci.yml in project_owned_files and replaces that file with
    its own, then updates it to a v0.2.0 that changes the template's ci.yml and .gitignore. The update must leave the
    project's ci.yml alone without a conflict, show the template's change to it, and still merge .gitignore. A file that
    isn't merged must stop the update before it changes anything, and an empty list must give the file back and
    leave the answer empty (project_owned_files: []). Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-owned-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-UpdateOwnedFiles.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-owned-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
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
$null = & (Join-Path $PSScriptRoot 'New-TemplateSnapshot.ps1') $tpl

$ownCi = "name: Own CI`non: push`njobs:`n  gate:`n    runs-on: ubuntu-latest`n    steps:`n      - name: Checkout`n        uses: actions/checkout@v7`n"
$answerPattern = '(?m)^project_owned_files:\r?\n- \.github/workflows/ci\.yml\r?$'

$path = Join-Path $Work 'owned'
Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data 'project_name=Owned' --data stack=python --data git_host=github --data 'workflow_tools=[claude]' --data 'project_owned_files=[.github/workflows/ci.yml]' $tpl $path | Out-Null
$ci = Join-Path $path '.github/workflows/ci.yml'
[IO.File]::WriteAllText($ci, $ownCi)
Push-Location $path
try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Render project-template v0.1.0' }
finally { Pop-Location }

Push-Location (Join-Path $tpl 'template')
try {
    Edit-File ".github/workflows/{% if git_host == 'github' %}ci.yml{% endif %}.jinja" "    runs-on: ubuntu-latest`n    timeout-minutes: 30`n    defaults:" "    runs-on: ubuntu-latest`n    timeout-minutes: 45`n    defaults:"
    Edit-File .gitignore.jinja "`n/secrets/`n" "`n/secrets/`n/owned-test/`n"
}
finally { Pop-Location }
Push-Location $tpl
try { Invoke-Git commit -q -am 'Change ci.yml and .gitignore'; Invoke-Git tag v0.2.0 }
finally { Pop-Location }

function Invoke-Update([hashtable]$Data) {
    $lines = [Collections.Generic.List[string]]::new()
    $exitCode = 0
    try {
        if ($Data) { & (Join-Path $path '.template\Update-Project.ps1') -Data $Data 2>&1 | ForEach-Object { $lines.Add("$_") } }
        else { & (Join-Path $path '.template\Update-Project.ps1') 2>&1 | ForEach-Object { $lines.Add("$_") } }
        $exitCode = $LASTEXITCODE
    }
    catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    [pscustomobject]@{ ExitCode = $exitCode; Output = ($lines -join "`n") }
}

Push-Location $path
try {
    $answers = Join-Path $path '.copier-answers.yml'
    Check 'fixture: .copier-answers.yml records project_owned_files' ([IO.File]::ReadAllText($answers) -match $answerPattern) ([IO.File]::ReadAllText($answers))

    $r = Invoke-Update $null
    $status = git status --porcelain
    Check "update: the project's own ci.yml is untouched and nothing conflicts" (($r.ExitCode -eq 0) -and $r.Output.Contains('Committed "Update from project-template v0.2.0"') -and -not $status -and ([IO.File]::ReadAllText($ci) -eq $ownCi)) "exit $($r.ExitCode)`n$($r.Output.Trim())`n$($status | Out-String)"
    Check "update: shows the template's ci.yml change as a project-owned change" (($r.Output -match '(?m)^  \.github/workflows/ci\.yml:\r?$') -and $r.Output.Contains('+    timeout-minutes: 45')) $r.Output.Trim()
    Check "update: other merged files still take the template's changes" ([IO.File]::ReadAllText((Join-Path $path '.gitignore')).Contains("`n/owned-test/`n"))
    Check 'update: .copier-answers.yml still records project_owned_files' ([IO.File]::ReadAllText($answers) -match $answerPattern) ([IO.File]::ReadAllText($answers))

    $head = git rev-parse HEAD
    $r = Invoke-Update @{ project_owned_files = 'CLAUDE.md' }
    $status = git status --porcelain
    Check "reject: a file that isn't merged stops the update before it changes anything" (($r.ExitCode -ne 0) -and $r.Output.Contains("which isn't a merged file") -and -not $status -and ((git rev-parse HEAD) -eq $head)) "exit $($r.ExitCode)`n$($r.Output.Trim())`n$($status | Out-String)"

    $r = Invoke-Update @{ project_owned_files = @() }
    $text = [IO.File]::ReadAllText($answers)
    Check 'clear: an empty list gives the file back and leaves the answer empty' (($r.ExitCode -eq 0) -and $text -match '(?m)^project_owned_files: \[\]\r?$' -and ([IO.File]::ReadAllText($ci) -eq $ownCi)) "exit $($r.ExitCode)`n$($r.Output.Trim())`n$text"
}
finally { Pop-Location }
''
if ($failures.Count) { "Kept the work folder: $Work"; "Update owned-files tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Update owned-files tests: PASSED'
exit 0
