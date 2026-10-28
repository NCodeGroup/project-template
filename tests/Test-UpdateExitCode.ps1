<#
.SYNOPSIS
    Test that a project's update exits 0 when it succeeds: staged with -NoCommit while it shows a project-owned
    change, and with nothing to update.

.DESCRIPTION
    Run with &, the script used to leave $LASTEXITCODE at 1 from the git commands that show a project-owned change.
    Renders a project from v0.1.0, changes README.md and the update script in v0.2.0, then updates with -NoCommit and
    checks the exit code, and updates again with nothing to do. Prints PASS or FAIL per check and exits 1 on any
    failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-exit-test in the temp folder.

.EXAMPLE
    .\tests\Test-UpdateExitCode.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) 'project-template-update-exit-test'))
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

$handoffMarker = 'Update-Project.ps1 from v0.2.0 is running.'
$project = Join-Path $Work 'project'
Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data 'project_name=Test Exit Code' --data stack=python --data git_host=github --data 'workflow_tools=[claude]' $tpl $project
Push-Location $project
try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Create project' }
finally { Pop-Location }

# v0.2.0 changes a heading in README.md, which the project owns and the update shows but doesn't apply, and ships a new
# version of the update script, which the project's v0.1.0 copy must hand the update over to.
Push-Location (Join-Path $tpl 'template')
try {
    Edit-File README.md.jinja '## AI-Assisted Workflow' '## AI-Assisted Workflow, Updated'
    Edit-File .template/Update-Project.ps1 "`$ErrorActionPreference = 'Stop'`n" "`$ErrorActionPreference = 'Stop'`n'$handoffMarker'`n"
}
finally { Pop-Location }
Push-Location $tpl
try { Invoke-Git commit -q -am 'Template change'; Invoke-Git tag v0.2.0 }
finally { Pop-Location }

Push-Location $project
try {
    $head = git rev-parse HEAD
    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $project '.template\Update-Project.ps1') -NoCommit 2>&1 | ForEach-Object { $lines.Add("$_") }; $exitCode = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    $output = $lines -join "`n"
    Check 'fixture: the update hands over to the v0.2.0 script and shows a README.md change the project lacks' ($output.Contains($handoffMarker) -and $output -match '(?m)^  README\.md:\r?$' -and $output.Contains('+## AI-Assisted Workflow, Updated')) $output.Trim()
    Check 'update -NoCommit: stages the update and exits 0' (($exitCode -eq 0) -and $output.Contains('Staged for review') -and ((git rev-parse HEAD) -eq $head) -and (@(git diff --cached --name-only) -contains '.copier-answers.yml')) $output.Trim()

    Invoke-Git commit -q -m 'Update from project-template v0.2.0'
    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $project '.template\Update-Project.ps1') 2>&1 | ForEach-Object { $lines.Add("$_") }; $exitCode = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    $output = $lines -join "`n"
    Check 'update: a run with nothing to update exits 0' (($exitCode -eq 0) -and $output.Contains('Already up to date: template v0.2.0.')) $output.Trim()
}
finally { Pop-Location }
''
if ($failures.Count) { "Update exit code tests: FAILED ($($failures.Count))"; exit 1 }
'Update exit code tests: PASSED'
exit 0
