<#
.SYNOPSIS
    Check that the working tree's template renders, and updates a project, exactly as the template at -Base does.

.DESCRIPTION
    Builds a template repository whose v0.1.0 holds the template files (copier.yml, .gitattributes and template/) of
    the commit -Base and whose v0.2.0 holds those of the working tree. For each of six answer sets it renders a
    project from both versions and checks that they hold the same files with the same bytes, apart from
    .copier-answers.yml and .template-version. It then updates each v0.1.0 render to v0.2.0 and checks that the result
    matches the v0.2.0 render in every file but .copier-answers.yml. Prints PASS or FAIL per check and exits 1 on any failure.

    It is not named Test-*.ps1, so tests/Invoke-AllTests.ps1 doesn't run it: it needs a base commit to compare with.
    It is a tool for refactors that must not change what a project gets.

.PARAMETER Base
    The commit, tag or branch whose template the working tree's template must match.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-compare-<process ID> in the temp folder,
    the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Compare-Renders.ps1 -Base 9bcb4c8557733dd1c8aea5d7370552d53b493a71
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Base, [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-compare-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$failures = [Collections.Generic.List[string]]::new()
$repoRoot = Split-Path -Parent $PSScriptRoot

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
function Get-RenderedFileHash([string]$Folder) {
    $root = (Resolve-Path -LiteralPath $Folder).Path.TrimEnd('\', '/')
    $hashes = @{}
    foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        if ($relative -eq '.git' -or $relative.StartsWith('.git/')) { continue }
        $hashes[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    $hashes
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
# A direct run keeps its Copier mirror in its own work folder, not in the user's cache; under tests\Invoke-AllTests.ps1 it keeps the runner's folder.
$copierCache = $env:COPIER_CACHE_DIR
if (-not $copierCache) { $env:COPIER_CACHE_DIR = Join-Path $Work 'copier-cache' }
$tpl = Join-Path $Work 'template-repo'
$null = New-Item -ItemType Directory -Path $tpl -Force

$templateFiles = 'copier.yml', '.gitattributes', 'template'
git -C $repoRoot archive --format=tar -o (Join-Path $Work 'base.tar') $Base -- @templateFiles
if ($LASTEXITCODE) { throw "git archive of $Base failed." }
tar -xf (Join-Path $Work 'base.tar') -C $tpl
if ($LASTEXITCODE) { throw "tar failed to extract the template of $Base." }
Push-Location $tpl
try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m Base; Invoke-Git tag v0.1.0 }
finally { Pop-Location }

foreach ($name in $templateFiles) { Remove-Item -LiteralPath (Join-Path $tpl $name) -Recurse -Force }
foreach ($name in $templateFiles) { Copy-Item -LiteralPath (Join-Path $repoRoot $name) -Destination $tpl -Recurse }
Push-Location $tpl
try { Invoke-Git add -A; Invoke-Git commit -q --allow-empty -m 'Working tree'; Invoke-Git tag v0.2.0 }
finally { Pop-Location }

$cases = [ordered]@{
    'dotnet-github'         = 'stack=dotnet', 'git_host=github', 'workflow_tools=[claude, copilot]'
    'dotnet-library-github' = 'stack=dotnet', 'git_host=github', 'workflow_tools=[claude, copilot]', 'nuget_package=true', 'license=MIT'
    'dotnet-library-gitlab' = 'stack=dotnet', 'git_host=gitlab', 'workflow_tools=[copilot]', 'nuget_package=true', 'license=Apache-2.0', 'package_icon=icon.png'
    'node-github-claude'    = 'stack=node', 'git_host=github', 'workflow_tools=[claude]'
    'python-gitlab-node'    = 'stack=python', 'git_host=gitlab', 'workflow_tools=[claude, copilot, local]', 'uses_node=true'
    'other-github'          = 'stack=other', 'git_host=github', 'workflow_tools=[claude, copilot]'
}

foreach ($name in $cases.Keys) {
    $data = @("project_name=Test $name") + $cases[$name] | ForEach-Object { '--data'; $_ }
    $before = Join-Path $Work "$name/before"
    $after = Join-Path $Work "$name/after"
    Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 @data $tpl $before
    Invoke-Copier copy --defaults --quiet --vcs-ref v0.2.0 @data $tpl $after
    $beforeHash = Get-RenderedFileHash $before
    $afterHash = Get-RenderedFileHash $after

    $onlyBefore = @($beforeHash.Keys | Where-Object { -not $afterHash.ContainsKey($_) } | Sort-Object)
    $onlyAfter = @($afterHash.Keys | Where-Object { -not $beforeHash.ContainsKey($_) } | Sort-Object)
    Check "${name}: v0.1.0 and v0.2.0 render the same files" (-not $onlyBefore -and -not $onlyAfter) "only in v0.1.0: $($onlyBefore -join ', '); only in v0.2.0: $($onlyAfter -join ', ')"

    $different = @($beforeHash.Keys | Where-Object { $afterHash.ContainsKey($_) -and $_ -notin '.copier-answers.yml', '.template-version' -and $beforeHash[$_] -ne $afterHash[$_] } | Sort-Object)
    Check "${name}: every file holds the same bytes" (-not $different) "different: $($different -join ', ')"

    Push-Location $before
    try {
        Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m Project
        Invoke-Copier update --defaults --quiet --vcs-ref v0.2.0
    }
    finally { Pop-Location }
    $updatedHash = Get-RenderedFileHash $before
    $onlyUpdated = @($updatedHash.Keys | Where-Object { -not $afterHash.ContainsKey($_) } | Sort-Object)
    $onlyAfter = @($afterHash.Keys | Where-Object { -not $updatedHash.ContainsKey($_) } | Sort-Object)
    $different = @($updatedHash.Keys | Where-Object { $afterHash.ContainsKey($_) -and $_ -ne '.copier-answers.yml' -and $updatedHash[$_] -ne $afterHash[$_] } | Sort-Object)
    Check "${name}: copier update from v0.1.0 to v0.2.0 gives the v0.2.0 render" (-not $onlyUpdated -and -not $onlyAfter -and -not $different) "only in the updated project: $($onlyUpdated -join ', '); only in the v0.2.0 render: $($onlyAfter -join ', '); different: $($different -join ', ')"
}

''
$env:COPIER_CACHE_DIR = $copierCache
if ($failures.Count) { "Kept the work folder: $Work"; "Render comparison: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Render comparison: PASSED'
exit 0
