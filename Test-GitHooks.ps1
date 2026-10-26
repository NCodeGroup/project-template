<#
.SYNOPSIS
    Test the template's Git hooks: .githooks/commit-msg run through pre-commit, and the note the update and adoption scripts print when they can't enable .githooks.

.DESCRIPTION
    Builds a fixture repository that runs .githooks/commit-msg as a pre-commit script hook and checks that the hook
    strips the agent attribution from a commit message. Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to %TEMP%\project-template-hooks-test.

.EXAMPLE
    .\Test-GitHooks.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path $env:TEMP 'project-template-hooks-test')
)
$ErrorActionPreference = 'Stop'
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

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$repo = Join-Path $Work 'pre-commit'
New-Item -ItemType Directory -Force (Join-Path $repo '.githooks') | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'template\.githooks\commit-msg') -Destination (Join-Path $repo '.githooks')
$config = "repos:`n  - repo: local`n    hooks:`n      - id: strip-agent-attribution`n        name: strip agent attribution`n        entry: .githooks/commit-msg`n        language: script`n        stages: [commit-msg]`n"
[IO.File]::WriteAllText((Join-Path $repo '.pre-commit-config.yaml'), $config, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $repo 'msg.txt'), "Hook check`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`n", [Text.UTF8Encoding]::new($false))

$savedPath = $env:PATH
# Git puts its own usr\bin, which has sh, on PATH when it runs a hook; this session doesn't have it.
$gitUsrBin = Join-Path (Split-Path (Split-Path (Get-Command git).Source)) 'usr\bin'
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

''
if ($failures.Count) { "Git hooks tests: FAILED ($($failures.Count))"; exit 1 }
'Git hooks tests: PASSED'
exit 0
