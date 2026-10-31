<#
.SYNOPSIS
    Test that a project's update succeeds when the project's own .gitignore ignores a large folder that the
    template's doesn't.

.DESCRIPTION
    During an update, Copier overwrites the project's .gitignore with the template's, then passes every path Git
    reports as ignored to one git apply command. A folder only the project ignored, such as node_modules/, is then
    listed file by file, and the command line passes Windows' limit with WinError 206 (the filename or extension is
    too long). Checks that the update succeeds, that .git/info/exclude ends as it was, without the copy a killed
    update left behind, and that a later update stopped by a conflict restores it too. Prints PASS or FAIL per check
    and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-ignored-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.PARAMETER Packages
    The number of fake packages in node_modules. Defaults to 700.

.EXAMPLE
    .\tests\Test-UpdateIgnoredFiles.ps1
    .\tests\Test-UpdateIgnoredFiles.ps1 -Packages 1000
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-ignored-test-$PID"),
    [int]$Packages = 700
)
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

$project = Join-Path $Work 'project'
Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data 'project_name=Test Ignored' --data stack=dotnet --data git_host=github --data 'workflow_tools=[claude]' $tpl $project

Push-Location $project
try {
    $gitignore = Join-Path $project '.gitignore'
    $templateRules = [IO.File]::ReadAllText($gitignore)
    [IO.File]::AppendAllText($gitignore, "node_modules/`n")
    Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Create project'
    foreach ($i in 1..$Packages) {
        $package = Join-Path $project ('node_modules/some-fairly-long-package-name-{0:d4}' -f $i)
        [void][IO.Directory]::CreateDirectory((Join-Path $package 'bin'))
        [IO.File]::WriteAllText((Join-Path $package 'package.json'), '{}')
        [IO.File]::WriteAllText((Join-Path $package 'bin/cli.js'), 'x')
    }

    # Under the template's rules alone, the ignored paths must overflow a Windows command line, or the test proves nothing.
    $projectRules = [IO.File]::ReadAllText($gitignore)
    [IO.File]::WriteAllText($gitignore, $templateRules)
    $length = (git status --ignored --porcelain | Where-Object { $_.StartsWith('!! ') } | ForEach-Object { $_.Length + 8 } | Measure-Object -Sum).Sum
    [IO.File]::WriteAllText($gitignore, $projectRules)
    Check 'fixture: under the template''s .gitignore alone, the ignored paths overflow a Windows command line' ($length -gt 32767) "$length characters"

    # The project's own line, and the copy an update killed before its cleanup leaves behind. The copy ignores another
    # folder, so it can't keep node_modules/ ignored and hide the overflow.
    $infoExclude = git rev-parse --path-format=absolute --git-path info/exclude
    $projectExclude = "# kept by the project`n"
    $leftover = "`n# Update-Project.ps1: the project's .gitignore, in force while Copier updates`nstale-leftover/`n# Update-Project.ps1: end of the .gitignore copy`n"
    New-Item -ItemType Directory -Force (Split-Path $infoExclude) | Out-Null
    [IO.File]::WriteAllText($infoExclude, "$projectExclude$leftover")

    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $project '.template\Update-Project.ps1') 2>&1 | ForEach-Object { $lines.Add("$_") } } catch { $lines.Add("THROWN: $_") }
    $output = $lines -join "`n"

    Check 'update: no WinError 206' (-not $output.Contains('WinError 206')) $output.Trim()
    Check 'update: succeeds with a folder only the project ignores' ($output -match 'Committed "Update from project-template v0\.1\.0"|Already up to date: template v0\.1\.0') $output.Trim()
    Check 'update: nothing left over' (-not (git status --porcelain)) (git status --porcelain | Out-String)
    $excludeAfter = [IO.File]::ReadAllText($infoExclude)
    Check 'update: info/exclude keeps the project''s lines and drops a killed update''s copy' ($excludeAfter -eq $projectExclude) "after: '$excludeAfter'"
    Check 'update: node_modules kept' (Test-Path -LiteralPath node_modules/some-fairly-long-package-name-0001/package.json)

    # The project and v0.2.0 change the same .gitignore line, so the next update stops on a conflict.
    Edit-File .gitignore 'Thumbs.db' 'Thumbs.db # project'
    Invoke-Git commit -q -am 'Local .gitignore edit'
}
finally { Pop-Location }
Push-Location (Join-Path $tpl 'template')
try { Edit-File .gitignore.jinja 'Thumbs.db' 'Thumbs.db # template' }
finally { Pop-Location }
Push-Location $tpl
try { Invoke-Git commit -q -am 'Conflicting template change'; Invoke-Git tag v0.2.0 }
finally { Pop-Location }

Push-Location $project
try {
    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $project '.template\Update-Project.ps1') 2>&1 | ForEach-Object { $lines.Add("$_") }; $exitCode = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    $output = $lines -join "`n"
    Check 'conflict: the update stops on the .gitignore conflict' (($exitCode -eq 1) -and $output.Contains('conflict  .gitignore') -and -not $output.Contains('WinError 206')) $output.Trim()
    $excludeAfter = [IO.File]::ReadAllText($infoExclude)
    Check 'conflict: info/exclude restored' ($excludeAfter -eq $projectExclude) "after: '$excludeAfter'"
}
finally { Pop-Location }
''
if ($failures.Count) { "Kept the work folder: $Work"; "Update ignored-files tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) {
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Work) { "Couldn't delete the work folder: $Work" }
}
'Update ignored-files tests: PASSED'
exit 0
