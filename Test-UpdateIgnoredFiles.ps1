<#
.SYNOPSIS
    Test that a project's update succeeds when the project's own .gitignore ignores a large folder that the
    template's doesn't.

.DESCRIPTION
    During an update, Copier overwrites the project's .gitignore with the template's, then passes every path Git
    reports as ignored to one git apply command. A folder only the project ignored, such as node_modules/, is then
    listed file by file, and the command line passes Windows' limit with WinError 206 (the filename or extension is
    too long). Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to %TEMP%\project-template-update-ignored-test.

.PARAMETER Packages
    The number of fake packages in node_modules. Defaults to 700.

.EXAMPLE
    .\Test-UpdateIgnoredFiles.ps1
    .\Test-UpdateIgnoredFiles.ps1 -Packages 1000
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path $env:TEMP 'project-template-update-ignored-test'),
    [int]$Packages = 700
)
$ErrorActionPreference = 'Stop'
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
$tpl = Join-Path $Work 'template-repo'
New-Item -ItemType Directory -Force $tpl | Out-Null
Get-ChildItem -LiteralPath $PSScriptRoot -Force | Where-Object Name -NotIn '.git', '.claude' | Copy-Item -Destination $tpl -Recurse -Force
# Claude Code's plan worktrees are other checkouts, not part of the snapshot.
$claudeCopy = New-Item -ItemType Directory -Force (Join-Path $tpl '.claude')
Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '.claude') -Force | Where-Object Name -NE 'worktrees' | Copy-Item -Destination $claudeCopy.FullName -Recurse -Force
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

    $infoExclude = git rev-parse --path-format=absolute --git-path info/exclude
    $excludeBefore = if (Test-Path -LiteralPath $infoExclude) { [IO.File]::ReadAllText($infoExclude) }

    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $project '.template\Update-Project.ps1') 2>&1 | ForEach-Object { $lines.Add("$_") } } catch { $lines.Add("THROWN: $_") }
    $output = $lines -join "`n"

    Check 'update: no WinError 206' (-not $output.Contains('WinError 206')) $output.Trim()
    Check 'update: succeeds with a folder only the project ignores' ($output -match 'Committed "Update from project-template v0\.1\.0"|Already up to date: template v0\.1\.0') $output.Trim()
    Check 'update: nothing left over' (-not (git status --porcelain)) (git status --porcelain | Out-String)
    $excludeAfter = if (Test-Path -LiteralPath $infoExclude) { [IO.File]::ReadAllText($infoExclude) }
    Check 'update: info/exclude restored' ($excludeAfter -eq $excludeBefore) "before: '$excludeBefore' after: '$excludeAfter'"
    Check 'update: node_modules kept' (Test-Path -LiteralPath node_modules/some-fairly-long-package-name-0001/package.json)
}
finally { Pop-Location }
''
if ($failures.Count) { "Update ignored-files tests: FAILED ($($failures.Count))"; exit 1 }
'Update ignored-files tests: PASSED'
exit 0
