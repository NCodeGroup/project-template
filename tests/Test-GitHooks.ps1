<#
.SYNOPSIS
    Test the template's Git hooks: .githooks/commit-msg run through pre-commit, .githooks/pre-push refusing a push to the default branch under protect: hook, and the note the update and adoption scripts warn with when they can't enable .githooks.

.DESCRIPTION
    Builds a fixture repository that runs .githooks/commit-msg as a pre-commit script hook and checks that the hook
    strips the agent attribution from a commit message. Then checks, for the copy of Get-GitHooksSetup in
    .template\Update-Project.ps1 and the one in tools\adopt\Adoption.psm1, whether .githooks is enabled and which note it returns for the script to warn with in
    a clone with other hooks, with pre-commit's hooks or config, with a hooks path of its own (local or global) or on a .githooks folder, and with none. Then pushes from a fixture clone to a local bare
    remote and checks that .githooks/pre-push refuses a push to main only while AGENTS.md's Landing section says protect: hook,
    and lets a branch and a tag through, and refuses the push when awk is missing, run directly with a PATH without it. Then runs .githooks/commit-msg directly and checks that it refuses the commit when grep is missing and lets a message without attribution through. Then checks that the wrapper saved as pre-push.legacy in a clone with pre-commit's pre-push hook refuses a push to main after the same commits were pushed as a branch. Then runs workflow\Get-PlanState.ps1 in fixture clones and checks that its protected line is hook only when the Landing section says protect: hook and Git runs .githooks/pre-push. Prints PASS or FAIL per check and exits 1 on any
    failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-hooks-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-GitHooks.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-hooks-test-$PID")
)
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Invoke-Git {
    git -c user.name=template-test -c user.email=template-test@example.invalid @args
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed." }
}
# A failing hook is the result under test, so this doesn't check the exit code; the caller reads $LASTEXITCODE.
function Invoke-PreCommit {
    $ErrorActionPreference = 'Continue'
    if (Get-Command pre-commit -ErrorAction SilentlyContinue) { & pre-commit @args }
    elseif (Get-Command uvx -ErrorAction SilentlyContinue) { & uvx pre-commit @args }
    else { throw 'pre-commit not found. Install it with: uv tool install pre-commit' }
}
# A refused push is the result under test, so this doesn't check the exit code; the caller reads $LASTEXITCODE.
function Invoke-Push {
    $ErrorActionPreference = 'Continue'
    git push -q origin @args 2>&1 | Out-String
}
# Runs the hook as git does, with $Path as the whole PATH and a push of main on stdin; the caller reads $LASTEXITCODE.
function Invoke-PrePushHook([string]$Path) {
    $ErrorActionPreference = 'Continue'
    $savedHookPath = $env:PATH
    $env:PATH = $Path
    try { "refs/heads/main $zero refs/heads/main $zero`n" | & $sh (Join-Path $pushHooks 'pre-push') origin $pushRemote 2>&1 | Out-String }
    finally { $env:PATH = $savedHookPath }
}
# Runs .githooks/commit-msg as git does, with $Path as the whole PATH; the caller reads $LASTEXITCODE.
function Invoke-CommitMsgHook([string]$Path, [string]$MessageFile) {
    $ErrorActionPreference = 'Continue'
    $savedHookPath = $env:PATH
    $env:PATH = $Path
    try { & $sh (Join-Path $repoRoot 'template\.githooks\commit-msg') $MessageFile 2>&1 | Out-String }
    finally { $env:PATH = $savedHookPath }
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$repo = Join-Path $Work 'pre-commit'
New-Item -ItemType Directory -Force (Join-Path $repo '.githooks') | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'template\.githooks\commit-msg') -Destination (Join-Path $repo '.githooks')
$config = "repos:`n  - repo: local`n    hooks:`n      - id: strip-agent-attribution`n        name: strip agent attribution`n        entry: .githooks/commit-msg`n        language: script`n        stages: [commit-msg]`n"
[IO.File]::WriteAllText((Join-Path $repo '.pre-commit-config.yaml'), $config, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $repo 'msg.txt'), "Hook check`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`n", [Text.UTF8Encoding]::new($false))

$savedPath = $env:PATH
# Git puts its own usr\bin, which has sh, on PATH when it runs a hook; this session doesn't have it.
# Elsewhere sh, awk and grep come from the system: the folder with awk stands in for Git's usr\bin.
$gitUsrBin = if ($IsWindows) { Join-Path (Split-Path (Split-Path (Get-Command git).Source)) 'usr\bin' } else { Split-Path (Get-Command awk).Source }
if (Test-Path $gitUsrBin) { $env:PATH = $gitUsrBin + [IO.Path]::PathSeparator + $env:PATH }
Push-Location $repo
try {
    Invoke-Git init -q
    # pre-commit stashes unstaged changes before it runs a hook, so the hook is staged first.
    Invoke-Git add .githooks/commit-msg .pre-commit-config.yaml
    Invoke-Git update-index --chmod=+x .githooks/commit-msg
    if (-not $IsWindows) { chmod +x .githooks/commit-msg }
    $output = Invoke-PreCommit run --hook-stage commit-msg --commit-msg-filename msg.txt strip-agent-attribution 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
    $env:PATH = $savedPath
}

Check 'pre-commit: runs .githooks/commit-msg as a script hook and strips the attribution' (($exitCode -eq 0) -and -not ([IO.File]::ReadAllText((Join-Path $repo 'msg.txt'))).Contains('anthropic.com')) "exit $exitCode; $output"

$updateFunction = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null).FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-GitHooksSetup' }, $true) | Select-Object -First 1
Import-Module (Join-Path $repoRoot 'tools\adopt\Adoption.psm1') -Force
$sources = [ordered]@{
    update = { if ($updateFunction) { . ([scriptblock]::Create($updateFunction.Extent.Text)); Get-GitHooksSetup } }
    adopt  = { if ((Get-Module Adoption).ExportedFunctions.ContainsKey('Get-GitHooksSetup')) { Adoption\Get-GitHooksSetup } }
}
$preCommitHook = "#!/usr/bin/env bash`n# File generated by pre-commit: https://pre-commit.com`n"
$protectAgents = "# Fixture`n`n## Landing`n`n- integrate: pull-request`n- protect: hook`n`n## Conventions`n"
$wrapper = "#!/usr/bin/env sh`nexec .githooks/pre-push `"`$@`"`n"
$cases = [ordered]@{
    'other hooks in .git/hooks get the run-both note'                            = @{ Hook = "#!/bin/sh`n"; HooksPath = $false; Note = @('has hooks of its own in .git/hooks (pre-commit)', 'call .githooks/commit-msg from your commit-msg hook') }
    'pre-commit hooks get the pre-commit hook to add'                            = @{ Hook = $preCommitHook; HooksPath = $false; Note = @('pre-commit install --hook-type commit-msg', 'entry: .githooks/commit-msg', 'language: script', 'stages: [commit-msg]') }
    'a pre-commit config without hooks installed gets the pre-commit hook to add' = @{ Config = "repos: []`n"; HooksPath = $false; Note = @('pre-commit install --hook-type commit-msg', 'entry: .githooks/commit-msg') }
    'a pre-commit config that runs the hook gets no note'                        = @{ Hook = $preCommitHook; Config = $config; HooksPath = $false; Note = @() }
    'no hooks enables core.hooksPath'                                            = @{ HooksPath = $true; Note = @() }
    'protect: hook with pre-commit gets the pre-push wrapper to add'             = @{ Hook = $preCommitHook; Config = $config; Agents = $protectAgents; HooksPath = $false; Note = @('says protect: hook', '.git/hooks/pre-push and', '#!/usr/bin/env sh', 'exec .githooks/pre-push "$@"') }
    'protect: hook with pre-commit''s pre-push hook gets the legacy wrapper'     = @{ Hook = $preCommitHook; Config = $config; Agents = $protectAgents; PushHook = $preCommitHook; HooksPath = $false; Note = @('.git/hooks/pre-push.legacy', 'exec .githooks/pre-push "$@"') }
    'protect: hook with the wrapper in place gets no note'                       = @{ Hook = $preCommitHook; Config = $config; Agents = $protectAgents; PushHook = $wrapper; HooksPath = $false; Note = @() }
    'protect: none with pre-commit gets no pre-push note'                        = @{ Hook = $preCommitHook; Config = $config; Agents = $protectAgents.Replace('- protect: hook', '- protect: none'); HooksPath = $false; Note = @() }
    'other hooks with protect: hook get the pre-push wrapper to add'             = @{ Hook = "#!/bin/sh`n"; Agents = $protectAgents; HooksPath = $false; Note = @('has hooks of its own in .git/hooks (pre-commit)', 'exec .githooks/pre-push "$@"') }
    'an own pre-push hook with protect: hook gets the call to add'               = @{ PushHook = "#!/bin/sh`n"; Agents = $protectAgents; HooksPath = $false; Note = @('Call .githooks/pre-push from .git/hooks/pre-push') }
    'protect: hook with pre-commit and an own pre-push.legacy gets the call to add' = @{ Hook = $preCommitHook; Config = $config; Agents = $protectAgents; PushHook = $preCommitHook; LegacyHook = "#!/bin/sh`n"; HooksPath = $false; Note = @('Call .githooks/pre-push from .git/hooks/pre-push.legacy') }
    'core.hooksPath on .githooks already gets no note'                           = @{ SetHooksPath = '.githooks'; HooksPath = $false; Note = @() }
    'another core.hooksPath is kept and gets the command to run'                 = @{ SetHooksPath = '.husky'; HooksPath = $false; Note = @('core.hooksPath is already .husky', 'call .githooks/commit-msg from .husky/commit-msg', 'run: git config core.hooksPath .githooks') }
    'another core.hooksPath with a pre-commit config is kept and gets the command to run' = @{ Hook = $preCommitHook; Config = "repos: []`n"; SetHooksPath = '.husky'; HooksPath = $false; Note = @('core.hooksPath is already .husky', 'run: git config core.hooksPath .githooks') }
    'another core.hooksPath with protect: hook gets the pre-push call too'       = @{ SetHooksPath = '.husky'; Agents = $protectAgents; HooksPath = $false; Note = @('core.hooksPath is already .husky', '.githooks/pre-push from .husky/pre-push', 'run: git config core.hooksPath .githooks') }
    'core.hooksPath on template/.githooks gets no note'                          = @{ SetHooksPath = 'template/.githooks'; HooksPath = $false; Note = @() }
    'core.hooksPath on template/.githooks/ with a trailing slash gets no note'   = @{ SetHooksPath = 'template/.githooks/'; HooksPath = $false; Note = @() }
    'core.hooksPath on an absolute .githooks folder gets no note'                = @{ SetHooksPath = (Join-Path $Work 'shared\.githooks\'); HooksPath = $false; Note = @() }
    'core.hooksPath on .githooks-old is kept and gets the command to run'        = @{ SetHooksPath = '.githooks-old'; HooksPath = $false; Note = @('core.hooksPath is already .githooks-old', 'run: git config core.hooksPath .githooks') }
    'a global core.hooksPath is kept and gets the command to run'                = @{ GlobalHooksPath = (Join-Path $Work 'global-hooks'); HooksPath = $false; Note = @('global-hooks (git config --show-origin', 'run: git config core.hooksPath .githooks') }
}
$n = 0
foreach ($name in $cases.Keys) {
    $case = $cases[$name]
    $n++
    $folder = Join-Path $Work "setup-$n"
    New-Item -ItemType Directory -Force $folder | Out-Null
    Push-Location $folder
    try {
        Invoke-Git init -q
        if ($case.Hook) { [IO.File]::WriteAllText((Join-Path $folder '.git\hooks\pre-commit'), $case.Hook, [Text.UTF8Encoding]::new($false)) }
        if ($case.Config) { [IO.File]::WriteAllText((Join-Path $folder '.pre-commit-config.yaml'), $case.Config, [Text.UTF8Encoding]::new($false)) }
        if ($case.Agents) { [IO.File]::WriteAllText((Join-Path $folder 'AGENTS.md'), $case.Agents, [Text.UTF8Encoding]::new($false)) }
        if ($case.PushHook) { [IO.File]::WriteAllText((Join-Path $folder '.git\hooks\pre-push'), $case.PushHook, [Text.UTF8Encoding]::new($false)) }
        if ($case.LegacyHook) { [IO.File]::WriteAllText((Join-Path $folder '.git\hooks\pre-push.legacy'), $case.LegacyHook, [Text.UTF8Encoding]::new($false)) }
        if ($case.SetHooksPath) { Invoke-Git config core.hooksPath $case.SetHooksPath }
        # A global hooks path, set through the environment as Git reads it from any config file.
        if ($case.GlobalHooksPath) { $env:GIT_CONFIG_COUNT = '1'; $env:GIT_CONFIG_KEY_0 = 'core.hooksPath'; $env:GIT_CONFIG_VALUE_0 = $case.GlobalHooksPath }
        foreach ($source in $sources.Keys) {
            $setup = & $sources[$source]
            $note = "$($setup.Note)"
            $ok = [bool]$setup -and ($setup.HooksPath -eq $case.HooksPath)
            if ($ok) {
                if ($case.Note.Count) { foreach ($part in $case.Note) { if (-not $note.Contains($part)) { $ok = $false } } }
                else { $ok = ($note -eq '') }
            }
            Check "${source}: $name" $ok "HooksPath $($setup.HooksPath); note: $note"
        }
    }
    finally {
        Pop-Location
        Remove-Item Env:GIT_CONFIG_COUNT, Env:GIT_CONFIG_KEY_0, Env:GIT_CONFIG_VALUE_0 -ErrorAction SilentlyContinue
    }
}

# pre-push: refuses a push to the default branch only when AGENTS.md's Landing section says protect: hook.
$pushHooks = Join-Path $Work 'push-hooks'
$pushRemote = Join-Path $Work 'push-remote.git'
$pushClone = Join-Path $Work 'push-clone'
New-Item -ItemType Directory -Force $pushHooks, $pushRemote, $pushClone | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'template\.githooks\pre-push') -Destination $pushHooks
if (-not $IsWindows) { chmod +x (Join-Path $pushHooks 'pre-push') }
Invoke-Git init -q --bare -b main $pushRemote
Push-Location $pushClone
try {
    Invoke-Git init -q -b main
    Invoke-Git config core.hooksPath $pushHooks
    Invoke-Git remote add origin $pushRemote
    $agents = "# Fixture`n`n## Landing`n`n- integrate: pull-request`n- protect: hook`n`n## Conventions`n"
    [IO.File]::WriteAllText((Join-Path $pushClone 'AGENTS.md'), $agents, [Text.UTF8Encoding]::new($false))
    Invoke-Git add AGENTS.md
    Invoke-Git commit -q -m 'Protect main'
    $mainOut = Invoke-Push HEAD:refs/heads/main; $mainCode = $LASTEXITCODE
    $branchOut = Invoke-Push HEAD:refs/heads/feature; $branchCode = $LASTEXITCODE
    Invoke-Git tag -a v1.0.0 -m v1.0.0
    $tagOut = Invoke-Push refs/tags/v1.0.0; $tagCode = $LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $pushClone 'AGENTS.md'), $agents.Replace('- protect: hook', '- protect: none'), [Text.UTF8Encoding]::new($false))
    Invoke-Git commit -q -am 'Open main'
    $openOut = Invoke-Push HEAD:refs/heads/main; $openCode = $LASTEXITCODE
}
finally { Pop-Location }

# Run the hook directly, as git does but with a PATH that lacks Git's usr\bin, which a real push can't reproduce.
$sh = if ($IsWindows) { Join-Path $gitUsrBin 'sh.exe' } else { (Get-Command sh).Source }
# Git's cmd folder has git but no awk or grep. Not the folder git came from: a GitHub runner finds Git's bin folder first, which sh reads as /bin, Git's usr\bin.
# Elsewhere git sits next to awk and grep, so a folder with only a link to git stands in for it.
if ($IsWindows) { $gitDir = Join-Path (Split-Path (Split-Path (Get-Command git).Source)) 'cmd' }
else {
    $gitDir = Join-Path $Work 'git-only'
    New-Item -ItemType Directory -Force $gitDir | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $gitDir 'git') -Target (Get-Command git).Source | Out-Null
}
$zero = '0' * 40
Push-Location $pushClone
try {
    [IO.File]::WriteAllText((Join-Path $pushClone 'AGENTS.md'), $agents, [Text.UTF8Encoding]::new($false))
    $noAwkOut = Invoke-PrePushHook $gitDir; $noAwkCode = $LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $pushClone 'AGENTS.md'), $agents.Replace("`n", "`r`n"), [Text.UTF8Encoding]::new($false))
    $crlfOut = Invoke-PrePushHook ($gitUsrBin + [IO.Path]::PathSeparator + $gitDir); $crlfCode = $LASTEXITCODE
}
finally { Pop-Location }

# Run commit-msg directly: without grep it must refuse the commit, and with grep it must let a message without attribution through unchanged.
$noGrepFile = Join-Path $Work 'no-grep-msg.txt'
$cleanFile = Join-Path $Work 'clean-msg.txt'
$cleanText = "Hook check`n`nNo attribution here.`n"
[IO.File]::WriteAllText($noGrepFile, "Hook check`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`n", [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($cleanFile, $cleanText, [Text.UTF8Encoding]::new($false))
$noGrepOut = Invoke-CommitMsgHook $gitDir $noGrepFile; $noGrepCode = $LASTEXITCODE
$cleanOut = Invoke-CommitMsgHook ($gitUsrBin + [IO.Path]::PathSeparator + $gitDir) $cleanFile; $cleanCode = $LASTEXITCODE

# The wrapper as pre-push.legacy, run by the pre-push hook pre-commit installed, refuses a push to main even after the same commits were pushed as a branch.
$legacyClone = Join-Path $Work 'push-legacy'
$legacyRemote = Join-Path $Work 'push-legacy.git'
New-Item -ItemType Directory -Force $legacyClone, $legacyRemote | Out-Null
Invoke-Git init -q --bare -b main $legacyRemote
$savedLegacyPath = $env:PATH
if (Test-Path $gitUsrBin) { $env:PATH = $gitUsrBin + [IO.Path]::PathSeparator + $env:PATH }
Push-Location $legacyClone
try {
    Invoke-Git init -q -b main
    Invoke-Git remote add origin $legacyRemote
    New-Item -ItemType Directory -Force (Join-Path $legacyClone '.githooks') | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'template\.githooks\pre-push') -Destination (Join-Path $legacyClone '.githooks')
    if (-not $IsWindows) { chmod +x .githooks/pre-push }
    [IO.File]::WriteAllText((Join-Path $legacyClone 'AGENTS.md'), $protectAgents, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $legacyClone '.pre-commit-config.yaml'), "repos: []`n", [Text.UTF8Encoding]::new($false))
    Invoke-Git add .githooks/pre-push AGENTS.md .pre-commit-config.yaml
    Invoke-Git commit -q -m 'Protect main'
    Invoke-PreCommit install --hook-type pre-push | Out-Null
    [IO.File]::WriteAllText((Join-Path $legacyClone '.git\hooks\pre-push.legacy'), $wrapper, [Text.UTF8Encoding]::new($false))
    if (-not $IsWindows) { chmod +x .git/hooks/pre-push.legacy }
    $legacyBranchOut = Invoke-Push HEAD:refs/heads/feature; $legacyBranchCode = $LASTEXITCODE
    $legacyMainOut = Invoke-Push HEAD:refs/heads/main; $legacyMainCode = $LASTEXITCODE
}
finally {
    Pop-Location
    $env:PATH = $savedLegacyPath
}

Check 'pre-push: refuses a push to main when the Landing section says protect: hook' (($mainCode -ne 0) -and $mainOut.Contains('says protect: hook')) "exit $mainCode; $mainOut"
Check 'pre-push: lets a branch and a tag through' (($branchCode -eq 0) -and ($tagCode -eq 0)) "branch exit $branchCode; $branchOut; tag exit $tagCode; $tagOut"
Check 'pre-push: lets a push to main through without protect: hook' ($openCode -eq 0) "exit $openCode; $openOut"
Check 'pre-push: refuses the push when awk is missing' ((Test-Path (Join-Path $gitDir 'awk.exe')) -eq $false -and ($noAwkCode -ne 0) -and $noAwkOut.Contains('awk is missing')) "exit $noAwkCode; $noAwkOut"
Check 'pre-push: refuses a push to main when AGENTS.md has CRLF line endings' (($crlfCode -ne 0) -and $crlfOut.Contains('says protect: hook')) "exit $crlfCode; $crlfOut"
Check 'commit-msg: refuses the commit when grep is missing' ((Test-Path (Join-Path $gitDir 'grep.exe')) -eq $false -and ($noGrepCode -ne 0) -and $noGrepOut.Contains('grep is missing')) "exit $noGrepCode; $noGrepOut"
Check 'commit-msg: lets a message without attribution through unchanged' (($cleanCode -eq 0) -and ([IO.File]::ReadAllText($cleanFile) -eq $cleanText)) "exit $cleanCode; $cleanOut"
Check 'pre-push: the wrapper in pre-push.legacy refuses a push to main under pre-commit, after the commits were pushed as a branch' (($legacyBranchCode -eq 0) -and ($legacyMainCode -ne 0) -and $legacyMainOut.Contains('says protect: hook')) "branch exit $legacyBranchCode; $legacyBranchOut; main exit $legacyMainCode; $legacyMainOut"

# The state script: protected is hook only when the Landing section says protect: hook and Git runs .githooks/pre-push.
$runCases = [ordered]@{
    'pre-commit''s pre-push hook alone'                              = @{ PushHook = $preCommitHook; Protect = 'hook'; Expected = $false }
    'the wrapper as pre-push'                                        = @{ PushHook = $wrapper; Protect = 'hook'; Expected = $true }
    'pre-commit''s pre-push hook and the wrapper as pre-push.legacy' = @{ PushHook = $preCommitHook; LegacyHook = $wrapper; Protect = 'hook'; Expected = $true }
    'pre-commit''s pre-push hook and an own pre-push.legacy'         = @{ PushHook = $preCommitHook; LegacyHook = "#!/bin/sh`n"; Protect = 'hook'; Expected = $false }
    'core.hooksPath .githooks'                                       = @{ HooksPath = '.githooks'; Protect = 'hook'; Expected = $true }
    'core.hooksPath template/.githooks'                              = @{ HooksPath = 'template/.githooks'; Protect = 'hook'; Expected = $true }
    'no pre-push hook'                                               = @{ Protect = 'hook'; Expected = $false }
    'the wrapper as pre-push under protect: none'                    = @{ PushHook = $wrapper; Protect = 'none'; Expected = $false }
}
$n = 0
foreach ($name in $runCases.Keys) {
    $case = $runCases[$name]
    $n++
    $folder = Join-Path $Work "state-script-$n"
    New-Item -ItemType Directory -Force $folder | Out-Null
    Push-Location $folder
    try {
        Invoke-Git init -q
        $agentsText = if ($case.Protect -eq 'none') { $protectAgents.Replace('- protect: hook', '- protect: none') } else { $protectAgents }
        [IO.File]::WriteAllText((Join-Path $folder 'AGENTS.md'), $agentsText, [Text.UTF8Encoding]::new($false))
        if ($case.PushHook) { [IO.File]::WriteAllText((Join-Path $folder '.git\hooks\pre-push'), $case.PushHook, [Text.UTF8Encoding]::new($false)) }
        if ($case.LegacyHook) { [IO.File]::WriteAllText((Join-Path $folder '.git\hooks\pre-push.legacy'), $case.LegacyHook, [Text.UTF8Encoding]::new($false)) }
        if ($case.HooksPath) {
            $hooksFolder = Join-Path $folder $case.HooksPath
            New-Item -ItemType Directory -Force $hooksFolder | Out-Null
            Copy-Item -LiteralPath (Join-Path $repoRoot 'template\.githooks\pre-push') -Destination $hooksFolder
            Invoke-Git config core.hooksPath $case.HooksPath
        }
        $line = & pwsh -NoProfile -File (Join-Path $repoRoot 'workflow\Get-PlanState.ps1') -Path $folder -NoFetch 2>$null | Where-Object { "$_" -like 'protected: *' } | Select-Object -First 1
        $result = ("$line" -eq 'protected: hook')
        Check "state script: protected is hook with $name" ($result -eq $case.Expected) "line: $line"
    }
    finally { Pop-Location }
}

''
if ($failures.Count) { "Kept the work folder: $Work"; "Git hooks tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Git hooks tests: PASSED'
exit 0
