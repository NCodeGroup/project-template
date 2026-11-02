<#
.SYNOPSIS
    Test the baseline calls New-Project.ps1 -CreateRemote makes once it has created and pushed the repository.

.DESCRIPTION
    Runs a copy of New-Project.ps1, with tools\adopt, from a work-folder template whose baseline scripts are stand-ins
    that record their arguments, with stand-ins for copier, gh and glab, so it needs no network.
    Checks that the real baseline scripts take the parameters New-Project.ps1 passes them. For GitHub, it checks that
    after gh repo create the baseline gets the repository, the signed-in user and the template's required checks; that
    -Owner names the owner and the signed-in user isn't read; that -NoBaseline creates the repository and runs no
    baseline; and that a baseline that fails warns with the command to run it again and the run succeeds.
    Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-new-project-remote-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-NewProjectRemote.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-new-project-remote-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Write-Text([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n")) }
# Lets a check hold however the console wraps a warning or cases a drive letter.
function Compress([string]$Text) { ($Text -replace '[\s|]', '').ToLowerInvariant() }

if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$bin = Join-Path $Work 'bin'
$template = Join-Path $Work 'template'
New-Item -ItemType Directory -Force $bin | Out-Null
New-Item -ItemType Directory -Force (Join-Path $template 'tools') | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'New-Project.ps1') -Destination $template
Copy-Item -LiteralPath (Join-Path $repoRoot 'tools/adopt') -Destination (Join-Path $template 'tools') -Recurse

# The two baseline stand-ins: one here-string, written twice.
$baselineStandIn = @'
Add-Content -LiteralPath $env:NEW_PROJECT_TEST_CALLS -Value ("<name> " + ($args -join ' '))
if ($env:NEW_PROJECT_TEST_FAIL -eq 'baseline') { throw 'Stand-in baseline failed.' }
'@
Write-Text (Join-Path $template 'tools/Set-RepositoryBaseline.ps1') $baselineStandIn.Replace('<name>', 'Set-RepositoryBaseline')
Write-Text (Join-Path $template 'tools/Set-GitLabBaseline.ps1') $baselineStandIn.Replace('<name>', 'Set-GitLabBaseline')
# The stand-in for copier. It records its arguments and writes the answers file the host test asks for.
Write-Text (Join-Path $bin 'copier.ps1') @'
Add-Content -LiteralPath $env:NEW_PROJECT_TEST_CALLS -Value ("copier " + ($args -join ' '))
$dest = $args[-1]
New-Item -ItemType Directory -Force $dest | Out-Null
[IO.File]::WriteAllText((Join-Path $dest '.copier-answers.yml'), "_commit: v0.1.0`ngit_host: $env:NEW_PROJECT_TEST_HOST`n")
exit 0
'@
# The stand-in for gh. It records its arguments, answers the signed-in user, and fails reading it when asked to.
Write-Text (Join-Path $bin 'gh.ps1') @'
Add-Content -LiteralPath $env:NEW_PROJECT_TEST_CALLS -Value ("gh " + ($args -join ' '))
if ($args[0] -eq 'api' -and $args[1] -eq 'user') {
    if ($env:NEW_PROJECT_TEST_FAIL -eq 'user') { [Console]::Error.WriteLine('gh: not signed in'); exit 1 }
    'tester'
}
exit 0
'@
# The stand-in for glab. It records its arguments and makes a bare repository the project's origin remote.
Write-Text (Join-Path $bin 'glab.ps1') @'
Add-Content -LiteralPath $env:NEW_PROJECT_TEST_CALLS -Value ("glab " + ($args -join ' '))
$origin = Join-Path (Split-Path -Parent $PSScriptRoot) "origins/$($args[2]).git"
git init -q --bare -b main $origin
git remote add origin $origin
exit 0
'@

$newProject = Join-Path $template 'New-Project.ps1'
$calls = Join-Path $Work 'calls.log'

# Runs the copy of New-Project.ps1 in a child pwsh, as a person would, and returns its output, exit code and the calls
# the stand-ins recorded.
function Invoke-NewProject([string]$Name, [string]$GitHost, [string]$Fail = '', [string[]]$Extra = @()) {
    if (Test-Path -LiteralPath $calls) { Remove-Item -LiteralPath $calls -Force }
    $dest = Join-Path $Work $Name
    $env:NEW_PROJECT_TEST_HOST = $GitHost
    $env:NEW_PROJECT_TEST_FAIL = $Fail
    $output = & pwsh -NoProfile -File $newProject -Path $dest -Template stand-in -CreateRemote @Extra 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{
        Output   = $output
        ExitCode = $exitCode
        Calls    = @(if (Test-Path -LiteralPath $calls) { Get-Content -LiteralPath $calls })
        Path     = $dest
    }
}

$repositoryParameters = (Get-Command (Join-Path $repoRoot 'tools/Set-RepositoryBaseline.ps1')).Parameters
$gitlabParameters = (Get-Command (Join-Path $repoRoot 'tools/Set-GitLabBaseline.ps1')).Parameters
Check 'stand-ins: the real baseline scripts take the parameters New-Project.ps1 passes' ($repositoryParameters.ContainsKey('Repo') -and $repositoryParameters.ContainsKey('Owner') -and $repositoryParameters.ContainsKey('RequireChecks') -and $gitlabParameters.ContainsKey('Path')) "repository=$($repositoryParameters.Keys -join ',') gitlab=$($gitlabParameters.Keys -join ',')"

$savedNames = 'PATH', 'NEW_PROJECT_TEST_CALLS', 'NEW_PROJECT_TEST_HOST', 'NEW_PROJECT_TEST_FAIL', 'GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0', 'GIT_CONFIG_KEY_1', 'GIT_CONFIG_VALUE_1'
$saved = @{}
foreach ($savedName in $savedNames) { $saved[$savedName] = [Environment]::GetEnvironmentVariable($savedName) }
try {
    $env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
    $env:NEW_PROJECT_TEST_CALLS = $calls
    $env:GIT_CONFIG_COUNT = '2'
    $env:GIT_CONFIG_KEY_0 = 'user.name'
    $env:GIT_CONFIG_VALUE_0 = 'template-test'
    $env:GIT_CONFIG_KEY_1 = 'user.email'
    $env:GIT_CONFIG_VALUE_1 = 'template-test@example.invalid'
    $checks = 'build-and-test,Commit attribution'

    # 1. GitHub.
    $r = Invoke-NewProject 'gh-app' 'github'
    $expected = @('gh repo create gh-app --public --source . --remote origin --push', 'gh api user --jq .login', "Set-RepositoryBaseline -Repo gh-app -Owner tester -RequireChecks $checks") -join '|'
    Check 'github: after gh repo create, the baseline gets the repository, the signed-in user and the template''s checks' ($r.ExitCode -eq 0 -and (($r.Calls | Select-Object -Skip 1) -join '|') -eq $expected) "calls=$($r.Calls -join '|') output=$($r.Output)"
    $r = Invoke-NewProject 'gh-owner' 'github' '' @('-Owner', 'org')
    $expected = @('gh repo create org/gh-owner --public --source . --remote origin --push', "Set-RepositoryBaseline -Repo gh-owner -Owner org -RequireChecks $checks") -join '|'
    Check 'github owner: -Owner names the owner, and the signed-in user isn''t read' ($r.ExitCode -eq 0 -and (($r.Calls | Select-Object -Skip 1) -join '|') -eq $expected) "calls=$($r.Calls -join '|') output=$($r.Output)"
    $r = Invoke-NewProject 'gh-none' 'github' '' @('-NoBaseline')
    Check 'github -NoBaseline: the repository is created and the baseline isn''t run' ($r.ExitCode -eq 0 -and [bool]($r.Calls -like 'gh repo create gh-none *') -and -not [bool]($r.Calls -like 'Set-*') -and -not [bool]($r.Calls -like 'gh api *')) "calls=$($r.Calls -join '|') output=$($r.Output)"
    $r = Invoke-NewProject 'gh-fail' 'github' 'baseline'
    Check 'github failed: a baseline that fails warns with the command to run it again and the run succeeds' ($r.ExitCode -eq 0 -and (Compress $r.Output).Contains((Compress "Couldn't protect the default branch: Stand-in baseline failed. Run it again with:")) -and (Compress $r.Output).Contains((Compress "Set-RepositoryBaseline.ps1 -Repo gh-fail -Owner tester -RequireChecks '$checks'"))) "calls=$($r.Calls -join '|') output=$($r.Output)"

    # 2. GitLab.
    $r = Invoke-NewProject 'gl-app' 'gitlab'
    $origin = Join-Path $Work 'origins/gl-app.git'
    $pushed = git --git-dir=$origin rev-parse --verify -q refs/heads/main
    Check 'gitlab: after glab repo create and the push, the baseline gets the new project''s folder' ($r.ExitCode -eq 0 -and $pushed -and $r.Calls.Count -eq 3 -and $r.Calls[1] -eq 'glab repo create gl-app --public --defaultBranch main' -and $r.Calls[2] -eq "Set-GitLabBaseline -Path $($r.Path)") "calls=$($r.Calls -join '|') output=$($r.Output)"
    $r = Invoke-NewProject 'gl-group' 'gitlab' '' @('-Owner', 'grp')
    Check 'gitlab owner: -Owner names the group' ($r.ExitCode -eq 0 -and $r.Calls[1] -eq 'glab repo create gl-group --public --defaultBranch main --group grp' -and $r.Calls[2] -eq "Set-GitLabBaseline -Path $($r.Path)") "calls=$($r.Calls -join '|') output=$($r.Output)"
    $r = Invoke-NewProject 'gl-none' 'gitlab' '' @('-NoBaseline')
    Check 'gitlab -NoBaseline: the project is created and the baseline isn''t run' ($r.ExitCode -eq 0 -and [bool]($r.Calls -like 'glab repo create gl-none *') -and -not [bool]($r.Calls -like 'Set-*')) "calls=$($r.Calls -join '|') output=$($r.Output)"
    $r = Invoke-NewProject 'gl-fail' 'gitlab' 'baseline'
    Check 'gitlab failed: a baseline that fails warns with the command to run it again and the run succeeds' ($r.ExitCode -eq 0 -and (Compress $r.Output).Contains((Compress 'Stand-in baseline failed. Run it again with:')) -and (Compress $r.Output).Contains((Compress "Set-GitLabBaseline.ps1 -Path '$($r.Path)'"))) "calls=$($r.Calls -join '|') output=$($r.Output)"
}
finally {
    foreach ($savedName in $savedNames) { [Environment]::SetEnvironmentVariable($savedName, $saved[$savedName]) }
}

''
if ($failures.Count) { "Kept the work folder: $Work"; "New-Project remote tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'New-Project remote tests: PASSED'
exit 0
