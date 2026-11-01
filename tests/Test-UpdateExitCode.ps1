<#
.SYNOPSIS
    Test that a project's update exits 0 when it succeeds: staged with -NoCommit while it shows a project-owned
    change, and with nothing to update. It also checks that the update asks to backfill the changelog from a tag it
    has no section for.

.DESCRIPTION
    Run with &, the script used to leave $LASTEXITCODE at 1 from the git commands that show a project-owned change.
    Renders a project from v0.1.0, changes README.md and the update script in v0.2.0, then updates with -NoCommit and
    checks the exit code, and updates again with nothing to do. Prints PASS or FAIL per check and exits 1 on any
    failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-exit-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-UpdateExitCode.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-exit-test-$PID"))
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

$handoffMarker = 'Update-Project.ps1 from v0.2.0 is running.'
$project = Join-Path $Work 'project'
Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data 'project_name=Test Exit Code' --data stack=python --data git_host=github --data 'workflow_tools=[claude]' $tpl $project
Push-Location $project
try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Create project'; Invoke-Git tag v1.0.0 }
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
    Check 'update: asks to backfill the changelog from a tag it has no section for' ($output.Contains('/plan-migration Backfill CHANGELOG.md from the releases v1.0.0')) $output.Trim()

    Invoke-Git commit -q -m 'Update from project-template v0.2.0'
    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $project '.template\Update-Project.ps1') 2>&1 | ForEach-Object { $lines.Add("$_") }; $exitCode = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    $output = $lines -join "`n"
    Check 'update: a run with nothing to update exits 0' (($exitCode -eq 0) -and $output.Contains('Already up to date: template v0.2.0.')) $output.Trim()

    # A project whose answers still name polewskm/project-template moves to NCodeGroup/project-template with its next update,
    # even at the newest version. Git serves the new address from the local snapshot, as a host would.
    $oldSource = 'https://github.com/polewskm/project-template.git'
    $newSource = 'https://github.com/NCodeGroup/project-template.git'
    $answersFile = Join-Path $project '.copier-answers.yml'
    $answers = [IO.File]::ReadAllText($answersFile)
    [IO.File]::WriteAllText($answersFile, [regex]::Replace($answers, '(?m)^_src_path:[^\r\n]*', "_src_path: $oldSource"))
    Invoke-Git commit -q -am 'Name the old template address'
    $before = git rev-parse HEAD
    $answers = [IO.File]::ReadAllText($answersFile)
    $snapshot = $tpl -replace '\\', '/'
    $savedConfig = @{ Count = $env:GIT_CONFIG_COUNT; Key0 = $env:GIT_CONFIG_KEY_0; Value0 = $env:GIT_CONFIG_VALUE_0; Key1 = $env:GIT_CONFIG_KEY_1; Value1 = $env:GIT_CONFIG_VALUE_1 }
    $env:GIT_CONFIG_COUNT = '2'
    $env:GIT_CONFIG_KEY_0 = "url.$snapshot.insteadOf"
    $env:GIT_CONFIG_VALUE_0 = $newSource
    $env:GIT_CONFIG_KEY_1 = "url.$snapshot.insteadOf"
    $env:GIT_CONFIG_VALUE_1 = $oldSource
    try {
        $lines = [Collections.Generic.List[string]]::new()
        try { & (Join-Path $project '.template\Update-Project.ps1') 2>&1 | ForEach-Object { $lines.Add("$_") }; $exitCode = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
        $output = $lines -join "`n"
    }
    finally {
        $env:GIT_CONFIG_COUNT = $savedConfig.Count
        $env:GIT_CONFIG_KEY_0 = $savedConfig.Key0; $env:GIT_CONFIG_VALUE_0 = $savedConfig.Value0
        $env:GIT_CONFIG_KEY_1 = $savedConfig.Key1; $env:GIT_CONFIG_VALUE_1 = $savedConfig.Value1
    }
    $answersAfter = [IO.File]::ReadAllText($answersFile)
    $changed = @(git diff --name-only $before HEAD)
    Check 'update: a project that names polewskm/project-template moves to NCodeGroup/project-template' (($exitCode -eq 0) -and $output.Contains("The template moved to $newSource") -and ($answersAfter -match "(?m)^_src_path: $([regex]::Escape($newSource))\r?$") -and ((git rev-parse HEAD) -ne $before) -and ($changed.Count -eq 1) -and ($changed[0] -eq '.copier-answers.yml') -and -not (git status --porcelain)) "exit=$exitCode changed=$($changed -join ',') $output"
    $otherAnswers = @($answersAfter -split '\r?\n' | Where-Object { $_ -notmatch '^_src_path:' }) -join "`n"
    $otherAnswersBefore = @($answers -split '\r?\n' | Where-Object { $_ -notmatch '^_src_path:' }) -join "`n"
    Check 'update: moving the template address changes no other answer' ($otherAnswers -eq $otherAnswersBefore)
}
finally { Pop-Location }
''
if ($failures.Count) { "Kept the work folder: $Work"; "Update exit code tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Update exit code tests: PASSED'
exit 0
