<#
.SYNOPSIS
    Test the SessionStart hooks that bootstrap a Claude Code cloud session's tools.

.DESCRIPTION
    Checks .claude\hooks\session-start.sh, which the template's and this repository's .claude\settings.json run on
    SessionStart: that both copies are identical, LF and parse as bash, that both settings files run it from
    $CLAUDE_PROJECT_DIR with a timeout of at least 600 seconds, and, with bash, that it does nothing outside a cloud
    session, and in one runs every ensure-*.sh beside it in name order, goes on past one that fails and names it, skips
    other files, and exits 0. Prints PASS, FAIL or SKIP per check and exits 1 on any failure.

.EXAMPLE
    .\tests\Test-EnsureTools.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}

$copies = [ordered]@{
    'template' = Join-Path $repoRoot 'template/.claude/hooks/session-start.sh'
    'repository' = Join-Path $repoRoot '.claude/hooks/session-start.sh'
}
foreach ($name in $copies.Keys) { Check "the $name copy of session-start.sh exists" (Test-Path -LiteralPath $copies[$name]) $copies[$name] }
if (-not ((Test-Path -LiteralPath $copies['template']) -and (Test-Path -LiteralPath $copies['repository']))) {
    "Tests: FAILED ($($failures.Count))"
    exit 1
}
$script = $copies['template']
Check 'both copies of session-start.sh are identical' ((Get-FileHash $copies['template']).Hash -eq (Get-FileHash $copies['repository']).Hash)
Check 'session-start.sh has LF line endings' (-not ((Get-Content -Raw -LiteralPath $script) -match "`r"))

foreach ($settings in 'template/.claude/settings.json', '.claude/settings.json') {
    $json = Get-Content -Raw -LiteralPath (Join-Path $repoRoot $settings) | ConvertFrom-Json
    $entries = @($json.hooks.SessionStart.hooks)
    Check "$settings runs session-start.sh as its one SessionStart hook" ($entries.Count -eq 1 -and $entries[0].type -eq 'command' -and $entries[0].command -eq 'bash "$CLAUDE_PROJECT_DIR/.claude/hooks/session-start.sh"') "$($entries.command)"
    Check "$settings gives the hook a timeout of at least 600 seconds" ($entries[0].timeout -ge 600)
}

$bash = Get-Command bash -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $bash) {
    'SKIP  bash is not on the PATH, so the scripts are not run'
} else {
    function Invoke-Hook([hashtable]$Environment, [string]$ScriptPath = $script) {
        $saved = @{}
        foreach ($key in $Environment.Keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key); [Environment]::SetEnvironmentVariable($key, $Environment[$key]) }
        try {
            $output = & $bash.Source $ScriptPath 2>&1
            [pscustomobject]@{ Code = $LASTEXITCODE; Output = (($output | ForEach-Object { "$_" }) -join "`n").Trim() }
        } finally {
            foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key]) }
        }
    }

    & $bash.Source -n $script
    Check 'session-start.sh parses as bash' ($LASTEXITCODE -eq 0)

    $work = Join-Path ([IO.Path]::GetTempPath()) "ensure-tools-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    New-Item -ItemType Directory -Force $work | Out-Null
    try {
        # A hooks folder with the dispatcher, three ensure scripts (the middle one fails) and a file that is not one.
        $hooks = Join-Path $work 'hooks'
        New-Item -ItemType Directory -Force $hooks | Out-Null
        Copy-Item -LiteralPath $script -Destination (Join-Path $hooks 'session-start.sh')
        [IO.File]::WriteAllText((Join-Path $hooks 'ensure-a.sh'), "echo a ran`n")
        [IO.File]::WriteAllText((Join-Path $hooks 'ensure-b.sh'), "echo b ran`nexit 3`n")
        [IO.File]::WriteAllText((Join-Path $hooks 'ensure-c.sh'), "echo c ran`n")
        [IO.File]::WriteAllText((Join-Path $hooks 'other.sh'), "echo other ran`n")
        $dispatcher = Join-Path $hooks 'session-start.sh'

        $r = Invoke-Hook @{ CLAUDE_CODE_REMOTE = $null } $dispatcher
        Check 'outside a cloud session the dispatcher exits 0 and prints nothing' ($r.Code -eq 0 -and $r.Output -eq '') "exit $($r.Code): $($r.Output)"
        $r = Invoke-Hook @{ CLAUDE_CODE_REMOTE = 'true' } $dispatcher
        Check 'in a cloud session it runs each ensure-*.sh in name order, names the one that failed, and exits 0' ($r.Code -eq 0 -and $r.Output -eq "a ran`nb ran`nsession-start: ensure-b.sh exited 3`nc ran") "exit $($r.Code): $($r.Output)"

        $empty = Join-Path $work 'empty'
        New-Item -ItemType Directory -Force $empty | Out-Null
        Copy-Item -LiteralPath $script -Destination (Join-Path $empty 'session-start.sh')
        $r = Invoke-Hook @{ CLAUDE_CODE_REMOTE = 'true' } (Join-Path $empty 'session-start.sh')
        Check 'with no ensure-*.sh it exits 0 and prints nothing' ($r.Code -eq 0 -and $r.Output -eq '') "exit $($r.Code): $($r.Output)"
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count) { "Tests: FAILED ($($failures.Count))"; exit 1 }
'Tests: PASSED'
