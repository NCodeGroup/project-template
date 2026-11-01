<#
.SYNOPSIS
    Test that a project's update keeps a hooks path Git already has, and the root wrapper's update by -Path.

.DESCRIPTION
    Tests a committed, tagged (v0.1.0) snapshot of the current working tree in the work folder (-Work), so
    uncommitted template changes are tested too. Renders a python project and runs its .template\Update-Project.ps1
    to a v0.2.0 tag with core.hooksPath set to a path of its own, and then with a global hooks path set through the
    environment, and checks that each is kept and that the warning names the command to run. Then renders a node
    project with a hook of its own in .git/hooks and updates it from the repository root's Update-Project.ps1 by
    -Path, and checks that the root wrapper hands the update over to the v0.2.0 script, commits it, and leaves
    core.hooksPath alone with a warning. Prints PASS or FAIL per check and exits 1 on any failure.

.EXAMPLE
    .\tests\Test-ProjectUpdateHooks.ps1

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-hooks-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-hooks-test-$PID")
)
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
# Serve the snapshot as a host does: over a URL with partial clones allowed, so a --filter=blob:none clone really is blob-filtered; Git ignores the filter for a plain path.
Invoke-Git -C $tpl config uploadpack.allowFilter true
Invoke-Git -C $tpl config uploadpack.allowAnySHA1InWant true
$tplUrl = 'file:///' + ($tpl -replace '\\', '/') + '/.git'

# Renders a project of the stack at v0.1.0 and commits it in a repository of its own; returns its folder.
function New-TestProject([string]$Name) {
    $dest = Join-Path $Work $Name
    Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data "project_name=Test $Name" --data "stack=$Name" --data 'git_host=github' --data 'workflow_tools=[claude, copilot, local]' $tplUrl $dest
    Push-Location $dest
    try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Create project' }
    finally { Pop-Location }
    $dest
}

$project = New-TestProject python
# Each project runs its own copy of the update script.
$updateProject = Join-Path $project '.template\Update-Project.ps1'
Invoke-Git -C $project config core.hooksPath .husky
$output = & $updateProject 3>&1 | Out-String
Check 'update: keeps a hooks path of its own and warns with the command to run' (((git -C $project config core.hooksPath) -join '') -eq '.husky' -and $output.Contains('core.hooksPath is already .husky') -and $output.Contains('git config core.hooksPath .githooks')) $output.Trim()
# A global hooks path, set through the environment as New-Project's check does, is kept too: no local one is written.
Invoke-Git -C $project config --unset core.hooksPath
$env:GIT_CONFIG_COUNT = '1'; $env:GIT_CONFIG_KEY_0 = 'core.hooksPath'; $env:GIT_CONFIG_VALUE_0 = Join-Path $Work 'global-hooks'
try { $output = & $updateProject 3>&1 | Out-String }
finally { Remove-Item Env:GIT_CONFIG_COUNT, Env:GIT_CONFIG_KEY_0, Env:GIT_CONFIG_VALUE_0 -ErrorAction SilentlyContinue }
Check 'update: keeps a global hooks path and warns with the command to run' (-not (git -C $project config --local core.hooksPath) -and $output.Contains('global-hooks (git config --show-origin') -and $output.Contains('git config core.hooksPath .githooks')) $output.Trim()

$handoffMarker = 'Update-Project.ps1 from v0.2.0 is running.'

# v0.2.0 has a new version of the update script, which the project's v0.1.0 copy hands the update over to.
Push-Location (Join-Path $tpl 'template')
try { Edit-File .template/Update-Project.ps1 "`$ErrorActionPreference = 'Stop'`n" "`$ErrorActionPreference = 'Stop'`n'$handoffMarker'`n" }
finally { Pop-Location }
Push-Location $tpl
try { Invoke-Git add -A; Invoke-Git commit -q -m 'Template change'; Invoke-Git tag v0.2.0 }
finally { Pop-Location }

# The repository root's wrapper updates another project from this clone, handing over to the newest script.
$other = New-TestProject node
[IO.File]::WriteAllText((Join-Path $other '.git\hooks\pre-commit'), "#!/bin/sh`n")
$output = & (Join-Path $repoRoot 'Update-Project.ps1') -Path $other 3>&1 | Out-String
Check 'update: the root wrapper updates a project by -Path' (($LASTEXITCODE -eq 0) -and $output.Contains('Handing the update over to the v0.2.0 version') -and ((git -C $other log -1 --format=%s) -eq 'Update from project-template v0.2.0') -and -not (git -C $other status --porcelain)) $output.Trim()
Check 'update: leaves core.hooksPath alone when the clone has hooks in .git/hooks, and warns' (-not (git -C $other config core.hooksPath) -and $output.Contains('has hooks of its own in .git/hooks (pre-commit)')) $output.Trim()

''
if ($failures.Count) { "Kept the work folder: $Work"; "Update hooks tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Update hooks tests: PASSED'
exit 0
