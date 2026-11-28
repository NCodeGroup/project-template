<#
.SYNOPSIS
    Test the baseline calls New-Project.ps1 -CreateRemote makes once it has created and pushed the repository.

.DESCRIPTION
    Runs a copy of New-Project.ps1, with tools\adopt, from a work-folder template whose baseline script is a stand-in
    that records its arguments, with stand-ins for copier and gh, so it needs no network.
    Checks that the real baseline script takes the parameters New-Project.ps1 passes it. It checks that
    after gh repo create the baseline gets the repository, the signed-in user and the template's required checks; that
    -Owner names the owner and the signed-in user isn't read; that -NoBaseline creates the repository and runs no
    baseline; and that a baseline that fails warns with the command to run it again and the run succeeds.
    It checks that copier gets no git_host answer, and that -Data @{ git_host = 'gitlab' } stops
    the script before copier runs.
    It also checks that a local clone of the template as -Template has the first commit name the clone's origin remote
    as _src_path.
    It checks Get-RepositoryNameRefusal (ADR-0045) on names that fit and names that don't, for .NET and other stacks,
    and the name each refusal gives. It checks Get-RepositoryNameWarning, the note Adopt-Project.ps1 prints, on the same
    names.
    It checks that -CreateRemote gives a fitting .NET or Python name to gh repo create, and that a name that doesn't
    fit stops with the fitting name, calls no gh and leaves no folder, before copier runs when -Data answers stack.
    It also checks that a refusal in an existing empty folder leaves the folder empty, that a -Path that ends in a
    separator names the repository without it, and that -Data answering stack dotnet with a fitting name runs copier
    and gh repo create.
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
# Compress without lowercasing, for a case-sensitive check.
function Squeeze([string]$Text) { $Text -replace '[\s|]', '' }

if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$bin = Join-Path $Work 'bin'
$template = Join-Path $Work 'template'
New-Item -ItemType Directory -Force $bin | Out-Null
New-Item -ItemType Directory -Force (Join-Path $template 'tools') | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'New-Project.ps1') -Destination $template
Copy-Item -LiteralPath (Join-Path $repoRoot 'tools/adopt') -Destination (Join-Path $template 'tools') -Recurse

# The baseline stand-in.
$baselineStandIn = @'
Add-Content -LiteralPath $env:NEW_PROJECT_TEST_CALLS -Value ("<name> " + ($args -join ' '))
if ($env:NEW_PROJECT_TEST_FAIL -eq 'baseline') { throw 'Stand-in baseline failed.' }
'@
Write-Text (Join-Path $template 'tools/Set-RepositoryBaseline.ps1') $baselineStandIn.Replace('<name>', 'Set-RepositoryBaseline')
# The stand-in for copier. It records its arguments and writes the answers file the host test asks for.
Write-Text (Join-Path $bin 'copier.ps1') @'
Add-Content -LiteralPath $env:NEW_PROJECT_TEST_CALLS -Value ("copier " + ($args -join ' '))
$dest = $args[-1]
New-Item -ItemType Directory -Force $dest | Out-Null
[IO.File]::WriteAllText((Join-Path $dest '.copier-answers.yml'), "_commit: v0.1.0`n_src_path: $($args[-2])`ngit_host: $env:NEW_PROJECT_TEST_HOST`nstack: $env:NEW_PROJECT_TEST_STACK`n")
exit 0
'@
# The stand-in for gh. It records its arguments, answers the signed-in user, and fails reading it, or prints nothing and succeeds, when asked to.
Write-Text (Join-Path $bin 'gh.ps1') @'
Add-Content -LiteralPath $env:NEW_PROJECT_TEST_CALLS -Value ("gh " + ($args -join ' '))
if ($args[0] -eq 'api' -and $args[1] -eq 'user') {
    if ($env:NEW_PROJECT_TEST_FAIL -eq 'user') { [Console]::Error.WriteLine('gh: not signed in'); exit 1 }
    if ($env:NEW_PROJECT_TEST_FAIL -eq 'user-empty') { exit 0 }
    'tester'
}
exit 0
'@

$newProject = Join-Path $template 'New-Project.ps1'
$calls = Join-Path $Work 'calls.log'

# Runs the copy of New-Project.ps1 in a child pwsh, as a person would, and returns its output, exit code and the calls
# the stand-ins recorded.
function Invoke-NewProject([string]$Name, [string]$GitHost, [string]$Fail = '', [string[]]$Extra = @(), [string]$Template = 'stand-in', [string]$Stack = 'python') {
    if (Test-Path -LiteralPath $calls) { Remove-Item -LiteralPath $calls -Force }
    $dest = Join-Path $Work $Name
    $env:NEW_PROJECT_TEST_HOST = $GitHost
    $env:NEW_PROJECT_TEST_FAIL = $Fail
    $env:NEW_PROJECT_TEST_STACK = $Stack
    $output = & pwsh -NoProfile -File $newProject -Path $dest -Template $Template -CreateRemote @Extra 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{
        Output   = $output
        ExitCode = $exitCode
        Calls    = @(if (Test-Path -LiteralPath $calls) { Get-Content -LiteralPath $calls })
        Path     = $dest
    }
}

$repositoryParameters = (Get-Command (Join-Path $repoRoot 'tools/Set-RepositoryBaseline.ps1')).Parameters
Check 'stand-ins: the real baseline script takes the parameters New-Project.ps1 passes' ($repositoryParameters.ContainsKey('Repo') -and $repositoryParameters.ContainsKey('Owner') -and $repositoryParameters.ContainsKey('RequireChecks')) "repository=$($repositoryParameters.Keys -join ',')"

Import-Module (Join-Path $repoRoot 'tools/adopt/Adoption.psm1') -Force
foreach ($case in @(
        ('Buffers', 'dotnet', ''),
        ('Collections.Providers', 'dotnet', ''),
        ('buffers', 'dotnet', 'Buffers'),
        ('Ncode.Buffers', 'dotnet', 'Buffers'),
        ('ncode.collections.providers', 'dotnet', 'Collections.Providers'),
        ('password-generator', 'dotnet', 'PasswordGenerator'),
        ('qso-viewer', 'python', ''),
        ('QsoViewer', 'node', 'qso-viewer'),
        ('QSO_Viewer', 'other', 'qso-viewer'),
        ('XMLParser', 'powershell', 'xml-parser'),
        ('.github', 'other', ''))) {
    $name, $stack, $expected = $case
    $refusal = Get-RepositoryNameRefusal $name $stack
    if ($expected -eq '') {
        Check "name rule: '$name' fits a $stack repository" ($null -eq $refusal) "refusal=$refusal"
    }
    else {
        Check "name rule: '$name' doesn't fit a $stack repository, and the refusal names '$expected'" ([bool]$refusal -and $refusal.Contains("Name the folder '$expected'.") -and $refusal.Contains('ADR-1001')) "refusal=$refusal"
    }
    $warning = Get-RepositoryNameWarning $name $stack
    if ($expected -eq '') {
        Check "name warning: '$name' fits a $stack repository, so no note" ($null -eq $warning) "warning=$warning"
    }
    else {
        Check "name warning: '$name' gets a note that names '$expected' and what a rename touches" ([bool]$warning -and $warning.Contains("The repository's name, '$name', doesn't fit") -and $warning.Contains("The name that fits is '$expected'.") -and $warning.Contains('1001-a-dotnet-repository-is-named-for-its-root-namespace') -and $warning.Contains('nuget.org trusted publishing policy') -and -not $warning.Contains('New-Project.ps1')) "warning=$warning"
    }
}
$refusal = Get-RepositoryNameRefusal '2fa' 'dotnet'
Check "name rule: '2fa' doesn't fit a dotnet repository, and the refusal names no folder that doesn't fit either" ([bool]$refusal -and -not $refusal.Contains('Name the folder')) "refusal=$refusal"
$warning = Get-RepositoryNameWarning '2fa' 'dotnet'
Check "name warning: '2fa' gets a note that names no name that doesn't fit either" ([bool]$warning -and -not $warning.Contains('The name that fits')) "warning=$warning"
foreach ($case in @(("Buffers`n", 'dotnet'), ("qso-viewer`n", 'python'))) {
    $name, $stack = $case
    Check "name rule: a name that ends in a line break doesn't fit a $stack repository" ($null -ne (Get-RepositoryNameRefusal $name $stack))
}

$savedNames = 'PATH', 'NEW_PROJECT_TEST_CALLS', 'NEW_PROJECT_TEST_HOST', 'NEW_PROJECT_TEST_FAIL', 'NEW_PROJECT_TEST_STACK', 'GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0', 'GIT_CONFIG_KEY_1', 'GIT_CONFIG_VALUE_1'
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
    $checks = 'build-and-test'

    # 1. GitHub.
    $r = Invoke-NewProject 'gh-app' 'github'
    $expected = @('gh repo create gh-app --public --source . --remote origin --push', 'gh api user --jq .login', "Set-RepositoryBaseline -Repo gh-app -Owner tester -RequireChecks $checks") -join '|'
    Check 'github: after gh repo create, the baseline gets the repository, the signed-in user and the template''s checks' ($r.ExitCode -eq 0 -and (($r.Calls | Select-Object -Skip 1) -join '|') -eq $expected) "calls=$($r.Calls -join '|') output=$($r.Output)"
    Check 'github: copier gets no git_host answer, since copier.yml asks no host question' (-not [bool]($r.Calls[0] -like '*git_host*')) "calls=$($r.Calls -join '|')"
    $r = Invoke-NewProject 'gh-owner' 'github' '' @('-Owner', 'org')
    $expected = @('gh repo create org/gh-owner --public --source . --remote origin --push', "Set-RepositoryBaseline -Repo gh-owner -Owner org -RequireChecks $checks") -join '|'
    Check 'github owner: -Owner names the owner, and the signed-in user isn''t read' ($r.ExitCode -eq 0 -and (($r.Calls | Select-Object -Skip 1) -join '|') -eq $expected) "calls=$($r.Calls -join '|') output=$($r.Output)"
    $r = Invoke-NewProject 'gh-none' 'github' '' @('-NoBaseline')
    Check 'github -NoBaseline: the repository is created and the baseline isn''t run' ($r.ExitCode -eq 0 -and [bool]($r.Calls -like 'gh repo create gh-none *') -and -not [bool]($r.Calls -like 'Set-*') -and -not [bool]($r.Calls -like 'gh api *')) "calls=$($r.Calls -join '|') output=$($r.Output)"
    $r = Invoke-NewProject 'gh-fail' 'github' 'baseline'
    Check 'github failed: a baseline that fails warns with the command to run it again and the run succeeds' ($r.ExitCode -eq 0 -and (Compress $r.Output).Contains((Compress "Couldn't protect the default branch: Stand-in baseline failed. Run it again with:")) -and (Compress $r.Output).Contains((Compress "Set-RepositoryBaseline.ps1 -Repo gh-fail -Owner tester -RequireChecks '$checks'"))) "calls=$($r.Calls -join '|') output=$($r.Output)"
    $r = Invoke-NewProject 'gh-user' 'github' 'user'
    Check 'github no user: a signed-in user gh can''t read warns with the command to run, naming the owner to fill in, and the run succeeds' ($r.ExitCode -eq 0 -and -not [bool]($r.Calls -like 'Set-*') -and (Compress $r.Output).Contains((Compress "Couldn't protect the default branch: Couldn't read the signed-in GitHub user. Run it again with:")) -and (Compress $r.Output).Contains((Compress "Set-RepositoryBaseline.ps1 -Repo gh-user -Owner <owner> -RequireChecks '$checks'"))) "calls=$($r.Calls -join '|') output=$($r.Output)"
    $r = Invoke-NewProject 'gh-user-empty' 'github' 'user-empty'
    Check 'github empty user: a gh that prints no signed-in user warns with the command to run, naming the owner to fill in, and the run succeeds' ($r.ExitCode -eq 0 -and -not [bool]($r.Calls -like 'Set-*') -and (Compress $r.Output).Contains((Compress "Couldn't protect the default branch: Couldn't read the signed-in GitHub user. Run it again with:")) -and (Compress $r.Output).Contains((Compress "Set-RepositoryBaseline.ps1 -Repo gh-user-empty -Owner <owner> -RequireChecks '$checks'"))) "calls=$($r.Calls -join '|') output=$($r.Output)"

    # 2. Any host but GitHub.
    if (Test-Path -LiteralPath $calls) { Remove-Item -LiteralPath $calls -Force }
    $message = try { & $newProject -Path (Join-Path $Work 'gl-app') -Template 'stand-in' -CreateRemote -Data @{ git_host = 'gitlab' }; '' } catch { $_.Exception.Message }
    $recorded = @(if (Test-Path -LiteralPath $calls) { Get-Content -LiteralPath $calls })
    Check 'gitlab: -Data git_host gitlab stops the script with the GitHub-only message' $message.Contains('NCodeGroup''s GitHub repositories only') "message=$message"
    Check 'gitlab: the script stops before copier runs, so no folder is made' (-not (Test-Path -LiteralPath (Join-Path $Work 'gl-app'))) "message=$message"
    Check 'gitlab: no stand-in is called' ($recorded.Count -eq 0) "calls=$($recorded -join '|')"

    # 3. A local clone of the template.
    $clone = Join-Path $Work 'template-clone'
    git init -q $clone
    git -C $clone remote add origin https://example.invalid/fork/project-template.git
    $r = Invoke-NewProject 'gh-clone' 'github' '' @('-NoBaseline') $clone
    $answers = (git -C $r.Path show HEAD:.copier-answers.yml) -join "`n"
    Check 'local clone: the first commit names the clone''s origin as the template''s address' ($r.ExitCode -eq 0 -and $answers.Contains('_src_path: https://example.invalid/fork/project-template.git') -and (Compress $r.Output).Contains((Compress 'the origin remote of'))) "answers=$answers output=$($r.Output)"

    # 4. The repository's name (ADR-0045).
    foreach ($fit in @(
            ('Buffers', 'dotnet', 'a .NET project named Buffers is created on GitHub'),
            ('Collections.Providers', 'dotnet', 'a .NET project named Collections.Providers is created on GitHub'),
            ('qso-viewer', 'python', 'a Python project named qso-viewer is created on GitHub'))) {
        $fitName, $fitStack, $fitTitle = $fit
        $r = Invoke-NewProject $fitName 'github' '' @('-NoBaseline') 'stand-in' $fitStack
        Check "name: $fitTitle" ($r.ExitCode -eq 0 -and $r.Calls -ccontains "gh repo create $fitName --public --source . --remote origin --push") "calls=$($r.Calls -join '|') output=$($r.Output)"
    }
    foreach ($misfit in @(
            ('password-generator', 'dotnet', 'PasswordGenerator', 'a .NET project named password-generator stops after copier, naming PasswordGenerator, with no gh call and no folder left'),
            ('QsoViewer', 'python', 'qso-viewer', 'a Python project named QsoViewer stops after copier, naming qso-viewer, with no gh call and no folder left'))) {
        $misfitName, $misfitStack, $suggested, $misfitTitle = $misfit
        $r = Invoke-NewProject $misfitName 'github' '' @('-NoBaseline') 'stand-in' $misfitStack
        Check "name: $misfitTitle" ($r.ExitCode -ne 0 -and (Squeeze $r.Output).Contains((Squeeze "Name the folder '$suggested'.")) -and -not [bool]($r.Calls -like 'gh *') -and [bool]($r.Calls -like 'copier *') -and -not (Test-Path -LiteralPath $r.Path)) "calls=$($r.Calls -join '|') output=$($r.Output)"
    }
    if (Test-Path -LiteralPath $calls) { Remove-Item -LiteralPath $calls -Force }
    $message = try { & $newProject -Path (Join-Path $Work 'NCode.Disposables') -Template 'stand-in' -CreateRemote -Data @{ stack = 'dotnet' }; '' } catch { $_.Exception.Message }
    $recorded = @(if (Test-Path -LiteralPath $calls) { Get-Content -LiteralPath $calls })
    Check 'name: -Data stack dotnet with NCode.Disposables stops before copier runs, naming Disposables' ($message.Contains("Name the folder 'Disposables'. Nothing was created.") -and $recorded.Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $Work 'NCode.Disposables'))) "message=$message calls=$($recorded -join '|')"
    New-Item -ItemType Directory -Force (Join-Path $Work 'existing-buffers') | Out-Null
    $r = Invoke-NewProject 'existing-buffers' 'github' '' @('-NoBaseline') 'stand-in' 'dotnet'
    Check 'name: a .NET project in an existing empty folder named existing-buffers stops after copier, naming ExistingBuffers, with no gh call, and leaves the folder empty' ($r.ExitCode -ne 0 -and (Squeeze $r.Output).Contains((Squeeze "Name the folder 'ExistingBuffers'.")) -and -not [bool]($r.Calls -like 'gh *') -and [bool]($r.Calls -like 'copier *') -and (Test-Path -LiteralPath $r.Path -PathType Container) -and -not (Get-ChildItem -LiteralPath $r.Path -Force)) "calls=$($r.Calls -join '|') output=$($r.Output)"
    $r = Invoke-NewProject 'trailing-separator/' 'github' '' @('-NoBaseline') 'stand-in' 'python'
    Check 'name: a -Path that ends in a separator names the repository trailing-separator' ($r.ExitCode -eq 0 -and $r.Calls -ccontains 'gh repo create trailing-separator --public --source . --remote origin --push') "calls=$($r.Calls -join '|') output=$($r.Output)"
    if (Test-Path -LiteralPath $calls) { Remove-Item -LiteralPath $calls -Force }
    $env:NEW_PROJECT_TEST_HOST = 'github'
    $env:NEW_PROJECT_TEST_FAIL = ''
    $env:NEW_PROJECT_TEST_STACK = 'dotnet'
    $message = try { & $newProject -Path (Join-Path $Work 'Disposables') -Template 'stand-in' -CreateRemote -NoBaseline -Data @{ stack = 'dotnet' } *>&1 | Out-Null; '' } catch { $_.Exception.Message }
    $recorded = @(if (Test-Path -LiteralPath $calls) { Get-Content -LiteralPath $calls })
    Check 'name: -Data stack dotnet with Disposables runs copier and creates Disposables on GitHub' ($message -eq '' -and [bool]($recorded -like 'copier *stack=dotnet*') -and $recorded -ccontains 'gh repo create Disposables --public --source . --remote origin --push') "message=$message calls=$($recorded -join '|')"
}
finally {
    foreach ($savedName in $savedNames) { [Environment]::SetEnvironmentVariable($savedName, $saved[$savedName]) }
}

''
if ($failures.Count) { "Kept the work folder: $Work"; "New-Project remote tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'New-Project remote tests: PASSED'
exit 0
