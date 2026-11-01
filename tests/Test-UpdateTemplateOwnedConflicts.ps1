<#
.SYNOPSIS
    Test that an update that stops on a conflict in a template-owned file suggests making it project-owned.

.DESCRIPTION
    Renders a project from v0.1.0, then adds its own scripts/check.ps1 and rewrites .vscode/extensions.json, and updates it
    to a v0.2.0 that adds its own scripts/check.ps1 and renames .vscode/extensions.json.jinja to .vscode/extensions.json,
    with no project_owned_files. The update must stop on the conflict in scripts/check.ps1, name that file as a template-owned
    file the project has its own version of, and suggest one -Data that names both the rewritten merged file and the
    conflicting file. It then resets the project and updates again with .vscode/extensions.json already named: the update
    must still stop on the conflict, and the -Data it suggests must add scripts/check.ps1 to the answer. Prints PASS or FAIL
    per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-template-owned-conflicts-test-<process ID>
    in the temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-UpdateTemplateOwnedConflicts.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-template-owned-conflicts-test-$PID"))
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

$ownCheck = "Write-Output 'own check'`n"
$ownExtensions = "{""recommendations"": [""own.extension-one"", ""own.extension-two""]}`n"

$path = Join-Path $Work 'conflicts'
Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data 'project_name=Conflicts' --data stack=python --data git_host=github --data 'workflow_tools=[claude]' $tpl $path | Out-Null
$null = New-Item -ItemType Directory -Path (Join-Path $path 'scripts') -Force
[IO.File]::WriteAllText((Join-Path $path 'scripts/check.ps1'), $ownCheck)
[IO.File]::WriteAllText((Join-Path $path '.vscode/extensions.json'), $ownExtensions)
Push-Location $path
try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Render project-template v0.1.0' }
finally { Pop-Location }

Push-Location (Join-Path $tpl 'template')
try {
    $null = New-Item -ItemType Directory -Path scripts -Force
    [IO.File]::WriteAllText((Join-Path (Get-Location) 'scripts/check.ps1'), "Write-Output 'template check'`n")
    Invoke-Git mv .vscode/extensions.json.jinja .vscode/extensions.json
    [IO.File]::WriteAllText((Join-Path (Get-Location) '.vscode/extensions.json'), "{""recommendations"": [""owned-test.renamed""]}`n")
}
finally { Pop-Location }
Push-Location $tpl
try { Invoke-Git add -- template; Invoke-Git commit -q -m 'Conflicting-file changes'; Invoke-Git tag v0.2.0 }
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
    $head = git rev-parse HEAD
    $command = "  .\.template\Update-Project.ps1 -Data @{ project_owned_files = '.vscode/extensions.json', 'scripts/check.ps1' }"

    $r = Invoke-Update $null
    $detail = "exit $($r.ExitCode)`n$($r.Output.Trim())"
    Check 'conflict: the update stops on the conflict in scripts/check.ps1' (($r.ExitCode -eq 1) -and ($r.Output -match '(?m)^  conflict  scripts/check\.ps1\r?$')) $detail
    Check 'conflict: the rewritten merged file conflicts too, so the note has a merged file to leave out' ($r.Output -match '(?m)^  conflict  \.vscode/extensions\.json\r?$') $detail
    Check 'conflict: a note names the template-owned file and not the merged one' ($r.Output -match '(?m)^These files are template-owned in v0\.2\.0, and this project has its own version of each, so they conflict:\r?\n  scripts/check\.ps1\r?\nTo keep ') $detail
    Check 'conflict: one -Data names the rewritten merged file and the conflicting file' (([regex]::Matches($r.Output, [regex]::Escape($command)).Count -eq 1) -and $r.Output.Contains(', with the merged files above,') -and -not $r.Output.Contains('To make them project-owned')) $detail

    Invoke-Git reset -q --hard $head; Invoke-Git clean -fdq
    $r = Invoke-Update @{ project_owned_files = '.vscode/extensions.json' }
    $detail = "exit $($r.ExitCode)`n$($r.Output.Trim())"
    Check 'owned: with the merged file owned, the -Data adds the conflicting file to the answer' (($r.ExitCode -eq 1) -and $r.Output.Contains('These files are template-owned in v0.2.0') -and -not $r.Output.Contains('These merged files share less than half') -and ([regex]::Matches($r.Output, [regex]::Escape($command)).Count -eq 1)) $detail
}
finally { Pop-Location }
''
$env:COPIER_CACHE_DIR = $copierCache
if ($failures.Count) { "Kept the work folder: $Work"; "Update template-owned conflict tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Update template-owned conflict tests: PASSED'
exit 0
