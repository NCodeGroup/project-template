<#
.SYNOPSIS
    Test that an update suggests project_owned_files for a merged file the project rewrote, and only for that file.

.DESCRIPTION
    Renders a project from v0.1.0 and appends a line to its .github/workflows/ci.yml, then updates it to a v0.2.0 that
    changes the template's ci.yml: the lightly edited file must update without the suggestion. The project then
    replaces ci.yml with its own workflow and the template changes ci.yml again in v0.3.0: the update must name the
    file and print the exact -Data @{ project_owned_files = ... } to run. Prints PASS or FAIL per check and exits 1 on
    any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-rewritten-test in the temp folder.

.EXAMPLE
    .\tests\Test-UpdateRewrittenFiles.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) 'project-template-update-rewritten-test'))
$ErrorActionPreference = 'Stop'
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

$path = Join-Path $Work 'rewritten'
Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data 'project_name=Rewritten' --data stack=python --data git_host=github --data 'workflow_tools=[claude]' $tpl $path | Out-Null
$ci = Join-Path $path '.github/workflows/ci.yml'
[IO.File]::AppendAllText($ci, "# Own note`n")
Push-Location $path
try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Render project-template v0.1.0' }
finally { Pop-Location }

Push-Location (Join-Path $tpl 'template')
try { Edit-File ".github/workflows/{% if git_host == 'github' %}ci.yml{% endif %}.jinja" "    runs-on: ubuntu-latest`n    defaults:" "    runs-on: ubuntu-latest`n    timeout-minutes: 30`n    defaults:" }
finally { Pop-Location }
Push-Location $tpl
try { Invoke-Git commit -q -am 'Change ci.yml'; Invoke-Git tag v0.2.0 }
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
    $r = Invoke-Update $null
    Check 'light: a lightly edited ci.yml updates without the suggestion' (($r.ExitCode -eq 0) -and $r.Output.Contains('Committed "Update from project-template v0.2.0"') -and -not $r.Output.Contains('project_owned_files')) "exit $($r.ExitCode)`n$($r.Output.Trim())"

    $ownCi = "name: Own CI`non: push`njobs:`n  gate:`n    runs-on: windows-latest`n    steps:`n      - run: ./build.ps1`n      - run: ./test.ps1`n      - run: ./publish.ps1`n"
    [IO.File]::WriteAllText($ci, $ownCi)
    Invoke-Git commit -q -am 'Own CI'

    Push-Location (Join-Path $tpl 'template')
    try { Edit-File ".github/workflows/{% if git_host == 'github' %}ci.yml{% endif %}.jinja" "  workflow_dispatch:`n" "  workflow_dispatch:`n  schedule:`n    - cron: '0 6 * * 1'`n" }
    finally { Pop-Location }
    Push-Location $tpl
    try { Invoke-Git commit -q -am 'Schedule ci.yml'; Invoke-Git tag v0.3.0 }
    finally { Pop-Location }

    # The update may exit 1 for a conflict in the rewritten file; the suggestion is what's checked.
    $r = Invoke-Update $null
    Check 'rewritten: suggests project_owned_files for the rewritten ci.yml' (($r.Output -match '(?m)^  \.github/workflows/ci\.yml\r?$') -and $r.Output.Contains("-Data @{ project_owned_files = '.github/workflows/ci.yml' }")) "exit $($r.ExitCode)`n$($r.Output.Trim())"
}
finally { Pop-Location }
''
if ($failures.Count) { "Update rewritten-files tests: FAILED ($($failures.Count))"; exit 1 }
'Update rewritten-files tests: PASSED'
exit 0
