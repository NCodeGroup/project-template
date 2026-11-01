<#
.SYNOPSIS
    Test that an update leaves the template-owned files a project owns as the project has them, and names a renamed merged file once.

.DESCRIPTION
    Renders a project from v0.1.0, then replaces CLAUDE.md, adds scripts/check.ps1 and rewrites .vscode/extensions.json with
    the project's own versions, and updates it to a v0.2.0 that changes CLAUDE.md, adds its own scripts/check.ps1 and renames
    .vscode/extensions.json.jinja to .vscode/extensions.json, all with project_owned_files naming CLAUDE.md and
    scripts/check.ps1. The update must leave both owned files as the project has them, not reset them as local edits, show
    the template's change to each, and name .vscode/extensions.json, a file whose template source was renamed, only once in
    its rewritten-file note and in the -Data it suggests. It then resets the project and updates again with all three files
    named: the update must commit and leave all three as the project has them with a clean working tree, show
    .vscode/extensions.json's template change once, and record the three files in .copier-answers.yml. Prints PASS or FAIL
    per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-owned-template-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-UpdateOwnedTemplateFiles.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-owned-template-test-$PID"))
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
# A direct run keeps its Copier mirror in its own work folder, not in the user's cache; under tests\Invoke-AllTests.ps1 it keeps the runner's folder.
$copierCache = $env:COPIER_CACHE_DIR
if (-not $copierCache) { $env:COPIER_CACHE_DIR = Join-Path $Work 'copier-cache' }
$tpl = Join-Path $Work 'template-repo'
$null = & (Join-Path $PSScriptRoot 'New-TemplateSnapshot.ps1') $tpl

$ownClaude = "# Own CLAUDE.md`n"
$ownCheck = "Write-Output 'own check'`n"
$ownExtensions = "{""recommendations"": [""own.extension-one"", ""own.extension-two""]}`n"

$path = Join-Path $Work 'owner'
Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data 'project_name=Owner' --data stack=python --data git_host=github --data 'workflow_tools=[claude]' $tpl $path | Out-Null
[IO.File]::WriteAllText((Join-Path $path 'CLAUDE.md'), $ownClaude)
$null = New-Item -ItemType Directory -Path (Join-Path $path 'scripts') -Force
[IO.File]::WriteAllText((Join-Path $path 'scripts/check.ps1'), $ownCheck)
[IO.File]::WriteAllText((Join-Path $path '.vscode/extensions.json'), $ownExtensions)
Push-Location $path
try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Render project-template v0.1.0' }
finally { Pop-Location }

Push-Location (Join-Path $tpl 'template')
try {
    Edit-File CLAUDE.md "## Claude Code`n" "## Claude Code`n`nOwned-test line from the template.`n"
    $null = New-Item -ItemType Directory -Path scripts -Force
    [IO.File]::WriteAllText((Join-Path (Get-Location) 'scripts/check.ps1'), "Write-Output 'template check'`n")
    Invoke-Git mv .vscode/extensions.json.jinja .vscode/extensions.json
    [IO.File]::WriteAllText((Join-Path (Get-Location) '.vscode/extensions.json'), "{""recommendations"": [""owned-test.renamed""]}`n")
}
finally { Pop-Location }
Push-Location $tpl
try { Invoke-Git add -- template; Invoke-Git commit -q -m 'Own-file changes'; Invoke-Git tag v0.2.0 }
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
    $r = Invoke-Update @{ project_owned_files = 'CLAUDE.md', 'scripts/check.ps1' }
    $detail = "exit $($r.ExitCode)`n$($r.Output.Trim())"
    Check "owned: the project's own CLAUDE.md and scripts/check.ps1 stay as they are" (([IO.File]::ReadAllText((Join-Path $path 'CLAUDE.md')) -eq $ownClaude) -and ([IO.File]::ReadAllText((Join-Path $path 'scripts/check.ps1')) -eq $ownCheck)) $detail
    Check "owned: an owned template-owned file isn't reset as a local edit" (-not $r.Output.Contains('Local edits discarded')) $detail
    Check "owned: shows the template's change to each owned file" (($r.Output -match '(?m)^  CLAUDE\.md:\r?$') -and ($r.Output -match '(?m)^  scripts/check\.ps1:\r?$') -and $r.Output.Contains('+Owned-test line from the template.') -and $r.Output.Contains("+Write-Output 'template check'")) $detail
    Check 'renamed: the rewritten-file note and its -Data name a merged file with a renamed source once' (([regex]::Matches($r.Output, '(?m)^  \.vscode/extensions\.json\r?$').Count -eq 1) -and $r.Output.Contains("-Data @{ project_owned_files = 'CLAUDE.md', 'scripts/check.ps1', '.vscode/extensions.json' }")) $detail

    Invoke-Git reset -q --hard $head; Invoke-Git clean -fdq
    $r = Invoke-Update @{ project_owned_files = 'CLAUDE.md', 'scripts/check.ps1', '.vscode/extensions.json' }
    $status = git status --porcelain
    $detail = "exit $($r.ExitCode)`n$($r.Output.Trim())"
    Check 'owned: the update commits and leaves all three files as the project has them' (($r.ExitCode -eq 0) -and $r.Output.Contains('Committed "Update from project-template v0.2.0"') -and -not $status -and ([IO.File]::ReadAllText((Join-Path $path 'CLAUDE.md')) -eq $ownClaude) -and ([IO.File]::ReadAllText((Join-Path $path 'scripts/check.ps1')) -eq $ownCheck) -and ([IO.File]::ReadAllText((Join-Path $path '.vscode/extensions.json')) -eq $ownExtensions)) $detail
    Check 'renamed: shows an owned file whose template source was renamed once' ([regex]::Matches($r.Output, '(?m)^  \.vscode/extensions\.json:\r?$').Count -eq 1) $detail
    Check 'owned: .copier-answers.yml records the three files' ([IO.File]::ReadAllText((Join-Path $path '.copier-answers.yml')) -match '(?m)^project_owned_files:\r?\n- CLAUDE\.md\r?\n- scripts/check\.ps1\r?\n- \.vscode/extensions\.json\r?$') $detail
}
finally { Pop-Location }
''
$env:COPIER_CACHE_DIR = $copierCache
if ($failures.Count) { "Kept the work folder: $Work"; "Update owned template-files tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Update owned template-files tests: PASSED'
exit 0
