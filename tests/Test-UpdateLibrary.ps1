<#
.SYNOPSIS
    Update .NET libraries with their own .template\Update-Project.ps1: the license a NuGet package needs, a second
    NuGet publisher and an assembly version to keep.

.DESCRIPTION
    Tests a committed, tagged (v0.1.0) snapshot of the current working tree in the work folder (-Work), without the
    license question's validator, so a library can have no license answer; v0.2.0 is the working tree's copier.yml.
    Renders two libraries (nuget_package) from v0.1.0 and updates each to v0.2.0:
      unlicensed     No license answer, and a release.yml beside a publish.yml without a workflow_dispatch trigger;
                     release.yml runs dotnet nuget push. The update stops before it changes anything, exits 1 and
                     prints the -Data that gives a license; with -Data @{ license = 'MIT' } it updates, warns that
                     both workflows publish, and warns that publish.yml has no workflow_dispatch trigger.
      own-publisher  A release.yml that runs dotnet nuget push and no publish.yml, and a v2.3.0 tag on a commit
                     without build/ProjectTemplate.props. The update leaves publish.yml out and says so, without a
                     workflow_dispatch warning, and names AssemblyVersion 2.3.0.0 to set in Directory.Build.props.
    Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-library-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-UpdateLibrary.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-library-test-$PID"))
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
# Render a library from v0.1.0 into the work folder; $Data adds Copier --data answers.
function New-Library([string]$Name, [string[]]$Data) {
    $folder = Join-Path $Work $Name
    $dataArgs = foreach ($d in $Data) { '--data', $d }
    Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data "project_name=Test $Name" --data stack=dotnet --data git_host=github --data 'workflow_tools=[claude]' --data nuget_package=true @dataArgs $tpl $folder
    $folder
}
# Run a project's own update script with &, collecting its output and its exit code, or -1 when it throws.
function Invoke-Update([string]$Project, [hashtable]$Data = @{}) {
    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $Project '.template\Update-Project.ps1') -Data $Data 2>&1 | ForEach-Object { $lines.Add("$_") }; $code = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $code = -1 }
    [pscustomobject]@{ ExitCode = $code; Output = $lines -join "`n" }
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
# A direct run keeps its Copier mirror in its own work folder, not in the user's cache; under tests\Invoke-AllTests.ps1 it keeps the runner's folder.
$copierCache = $env:COPIER_CACHE_DIR
if (-not $copierCache) { $env:COPIER_CACHE_DIR = Join-Path $Work 'copier-cache' }
$tpl = Join-Path $Work 'template-repo'
$repoRoot = Split-Path -Parent $PSScriptRoot
$validator = '(?m)^  validator: "\{% if \(nuget_package[^\n]*\n'
$null = & (Join-Path $PSScriptRoot 'New-TemplateSnapshot.ps1') $tpl -BeforeCommit {
    $text = [IO.File]::ReadAllText((Join-Path (Get-Location) 'copier.yml'))
    if ($text -notmatch $validator) { throw "copier.yml has no license validator." }
    [IO.File]::WriteAllText((Join-Path (Get-Location) 'copier.yml'), [regex]::Replace($text, $validator, ''))
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'copier.yml') -Destination (Join-Path $tpl 'copier.yml') -Force
Push-Location $tpl
try { Invoke-Git commit -q -am 'Require a license for a NuGet package'; Invoke-Git tag v0.2.0 }
finally { Pop-Location }

$release = "name: release`non: release`njobs:`n  push:`n    runs-on: ubuntu-latest`n    steps:`n      - run: dotnet nuget push out/*.nupkg`n"

# unlicensed: no license answer, and a workflow of its own that publishes beside publish.yml.
$unlicensed = New-Library 'unlicensed'
Push-Location $unlicensed
try {
    [IO.File]::WriteAllText((Join-Path $unlicensed '.github/workflows/release.yml'), $release)
    $publishYml = Join-Path $unlicensed '.github/workflows/publish.yml'
    [IO.File]::WriteAllText($publishYml, [regex]::Replace([IO.File]::ReadAllText($publishYml), '(?m)^  workflow_dispatch:\r?\n(?:    .*\r?\n)*', ''))
    Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Create project'
    Check 'fixture: unlicensed has no license answer, and publish.yml' (-not (Select-String -LiteralPath .copier-answers.yml -Pattern '^license: *[^\s'']' -Quiet) -and (Test-Path -LiteralPath .github/workflows/publish.yml))
    $head = git rev-parse HEAD
    # The exit code of a run in its own process, and the message from a run with &, which PowerShell's error view doesn't wrap.
    $update = Join-Path $unlicensed '.template\Update-Project.ps1'
    $null = pwsh -NoProfile -NonInteractive -File $update 2>&1
    $code = $LASTEXITCODE
    $message = try { & $update | Out-Null; 'no stop' } catch { $_.Exception.Message }
    Check 'unlicensed: the update stops with exit code 1 and names the -Data that gives a license' ($code -eq 1 -and $message.Contains('A NuGet package needs a license') -and $message.Contains("-Data @{ license = '<SPDX expression, such as MIT or Apache-2.0>' }")) "exit=$code $message"
    Check 'unlicensed: the update changes nothing' (((git rev-parse HEAD) -eq $head) -and -not (git status --porcelain --untracked-files=all)) (git status --porcelain --untracked-files=all | Out-String)
    $result = Invoke-Update $unlicensed @{ license = 'MIT' }
    Check 'unlicensed: with -Data @{ license = ''MIT'' } the update commits v0.2.0 and records the license' ($result.ExitCode -eq 0 -and (git log -1 --format=%s) -eq 'Update from project-template v0.2.0' -and (Select-String -LiteralPath .copier-answers.yml -Pattern '^license: MIT$' -Quiet) -and -not (git status --porcelain)) $result.Output
    Check 'unlicensed: the update warns that publish.yml and release.yml both push NuGet packages' ($result.Output.Contains('Both .github/workflows/publish.yml and .github/workflows/release.yml push NuGet packages') -and (Test-Path -LiteralPath .github/workflows/publish.yml)) $result.Output
    Check 'unlicensed: the update warns that publish.yml has no workflow_dispatch trigger' ($result.Output.Contains('.github/workflows/publish.yml has no workflow_dispatch trigger') -and (Test-Path -LiteralPath .github/workflows/tag-release.yml)) $result.Output
}
finally { Pop-Location }

# own-publisher: a release tagged on a commit without build/ProjectTemplate.props, and a workflow of its own that publishes, without publish.yml.
$ownPublisher = New-Library 'own-publisher' 'license=MIT'
Push-Location $ownPublisher
try {
    Invoke-Git init -q -b main; Invoke-Git commit -q --allow-empty -m 'Release 2.3.0'; Invoke-Git tag v2.3.0
    Remove-Item -LiteralPath .github/workflows/publish.yml
    [IO.File]::WriteAllText((Join-Path $ownPublisher '.github/workflows/release.yml'), $release)
    Invoke-Git add -A; Invoke-Git commit -q -m 'Create project'
    $result = Invoke-Update $ownPublisher
    Check 'own-publisher: the update leaves publish.yml out beside release.yml, and says so' ($result.ExitCode -eq 0 -and -not (Test-Path -LiteralPath .github/workflows/publish.yml) -and $result.Output.Contains('Left out .github/workflows/publish.yml: .github/workflows/release.yml already push NuGet packages')) $result.Output
    Check 'own-publisher: without publish.yml, no workflow_dispatch warning' (-not $result.Output.Contains('has no workflow_dispatch trigger')) $result.Output
    Check 'own-publisher: the update names the AssemblyVersion v2.3.0 shipped' ($result.Output.Contains('v2.3.0 was released with AssemblyVersion 2.3.0.0') -and $result.Output.Contains('  <PropertyGroup><AssemblyVersion>2.3.0.0</AssemblyVersion></PropertyGroup>')) $result.Output
}
finally { Pop-Location }

''
$env:COPIER_CACHE_DIR = $copierCache
if ($failures.Count) { "Kept the work folder: $Work"; "Library update tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Library update tests: PASSED'
exit 0
