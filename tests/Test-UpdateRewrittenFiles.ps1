<#
.SYNOPSIS
    Test that an update suggests project_owned_files for a merged file the project rewrote, and only for that file.

.DESCRIPTION
    Renders a project from v0.1.0 and appends a line to its .github/workflows/ci.yml, then updates it to a v0.2.0 that
    changes the template's ci.yml: the lightly edited file must update without the suggestion. The project then
    replaces ci.yml with its own workflow and the template changes ci.yml again in v0.3.0: the update must name the
    file and print the exact -Data @{ project_owned_files = ... } to run. Last, v0.3.0 rejects a project name that
    v0.4.0 accepts, so Copier can't render the project's version with it: the update to v0.4.0 must warn with Copier's
    error and say it skipped the suggestion, and still finish the update. Then v0.5.0's Update-Project.ps1, which the
    update hands over to, throws while it looks for rewritten files: the update to v0.5.0 must warn with the error, say
    it skipped the suggestion, and still finish. Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-rewritten-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-UpdateRewrittenFiles.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-rewritten-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
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
        if ($Data) { & (Join-Path $path '.template\Update-Project.ps1') -Data $Data *>&1 | ForEach-Object { $lines.Add("$_") } }
        else { & (Join-Path $path '.template\Update-Project.ps1') *>&1 | ForEach-Object { $lines.Add("$_") } }
        $exitCode = $LASTEXITCODE
    }
    catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    [pscustomobject]@{ ExitCode = $exitCode; Output = ($lines -join "`n") }
}

# The update ran to its end: it listed the changes and either committed them or stopped at a conflict, with the answers at the new version.
function Test-UpdateFinished($Result, [string]$From, [string]$To) {
    $committed = $Result.ExitCode -eq 0 -and $Result.Output.Contains("Committed `"Update from project-template $To`"")
    $conflicted = $Result.ExitCode -eq 1 -and $Result.Output.Contains('file(s) conflict')
    $Result.Output.Contains("Template $From -> ${To}:") -and ($committed -or $conflicted) -and
        [bool](Select-String -LiteralPath (Join-Path $path '.copier-answers.yml') -Pattern "^_commit: $([regex]::Escape($To))\s*$")
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
    $validator = 'validator: "{% if not project_name.strip() %}Required{% endif %}"'
    $strictValidator = 'validator: "{% if not project_name.strip() %}Required{% elif project_name == ''Renamed'' %}Not yet{% endif %}"'
    Push-Location $tpl
    try { Edit-File 'copier.yml' $validator $strictValidator; Invoke-Git commit -q -am 'Schedule ci.yml'; Invoke-Git tag v0.3.0 }
    finally { Pop-Location }

    # The update may exit 1 for a conflict in the rewritten file; the suggestion is what's checked.
    $r = Invoke-Update $null
    Check 'rewritten: suggests project_owned_files for the rewritten ci.yml' (($r.Output -match '(?m)^  \.github/workflows/ci\.yml\r?$') -and $r.Output.Contains("-Data @{ project_owned_files = '.github/workflows/ci.yml' }")) "exit $($r.ExitCode)`n$($r.Output.Trim())"

    # Finish that update with the project's own ci.yml, so the project is at v0.3.0.
    if (git status --porcelain) { [IO.File]::WriteAllText($ci, $ownCi); Invoke-Git add -A; Invoke-Git commit -q -m 'Update from project-template v0.3.0' }

    # v0.3.0 rejects the project name that v0.4.0 accepts, so Copier can't render the project's version with it.
    Push-Location $tpl
    try { Edit-File 'copier.yml' $strictValidator $validator; Invoke-Git commit -q -am 'Accept the name again' }
    finally { Pop-Location }
    Push-Location (Join-Path $tpl 'template')
    try { Edit-File ".github/workflows/{% if git_host == 'github' %}ci.yml{% endif %}.jinja" "    - cron: '0 6 * * 1'`n" "    - cron: '0 7 * * 1'`n" }
    finally { Pop-Location }
    Push-Location $tpl
    try { Invoke-Git commit -q -am 'Move the ci.yml schedule'; Invoke-Git tag v0.4.0 }
    finally { Pop-Location }

    $r = Invoke-Update @{ project_name = 'Renamed' }
    Check 'render failure: warns with Copier''s error and says the rewritten-file suggestion was skipped' ($r.Output.Contains("Copier couldn't render template v0.3.0 with this project's answers:") -and $r.Output.Contains('Not yet') -and $r.Output.Contains('Skipped the rewritten-file suggestion') -and -not $r.Output.Contains('project_owned_files =')) "exit $($r.ExitCode)`n$($r.Output.Trim())"
    Check 'render failure: the update still reaches v0.4.0' (Test-UpdateFinished $r 'v0.3.0' 'v0.4.0') "exit $($r.ExitCode)`n$($r.Output.Trim())"

    if (git status --porcelain) { [IO.File]::WriteAllText($ci, $ownCi); Invoke-Git add -A; Invoke-Git commit -q -m 'Update from project-template v0.4.0' }

    # v0.5.0's Update-Project.ps1, which the update hands over to, fails while it looks for rewritten files.
    Push-Location (Join-Path $tpl 'template')
    try {
        Edit-File ".github/workflows/{% if git_host == 'github' %}ci.yml{% endif %}.jinja" "    - cron: '0 7 * * 1'`n" "    - cron: '0 8 * * 1'`n"
        Edit-File '.template/Update-Project.ps1' 'function Get-RewrittenFile([string[]]$Files, [string]$Folder) {' 'function Get-RewrittenFile([string[]]$Files, [string]$Folder) { throw ''Injected rewritten-file failure'''
    }
    finally { Pop-Location }
    Push-Location $tpl
    try { Invoke-Git commit -q -am 'Fail the rewritten-file check'; Invoke-Git tag v0.5.0 }
    finally { Pop-Location }

    $r = Invoke-Update $null
    Check 'check failure: warns with the error and says the rewritten-file suggestion was skipped' ($r.Output.Contains('Skipped the rewritten-file suggestion: checking for merged files this project rewrote failed: Injected rewritten-file failure') -and -not $r.Output.Contains('project_owned_files =')) "exit $($r.ExitCode)`n$($r.Output.Trim())"
    Check 'check failure: the update still reaches v0.5.0' (Test-UpdateFinished $r 'v0.4.0' 'v0.5.0') "exit $($r.ExitCode)`n$($r.Output.Trim())"
}
finally { Pop-Location }
''
if ($failures.Count) { "Kept the work folder: $Work"; "Update rewritten-files tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Update rewritten-files tests: PASSED'
exit 0
