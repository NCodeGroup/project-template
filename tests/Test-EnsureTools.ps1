<#
.SYNOPSIS
    Test the SessionStart hooks that bootstrap a Claude Code cloud session's tools.

.DESCRIPTION
    Checks .claude\hooks\session-start.sh, which the template's and this repository's .claude\settings.json run on
    SessionStart: that both copies are identical, LF and parse as bash, that both settings files run it from
    $CLAUDE_PROJECT_DIR with a timeout of at least 600 seconds, and, with bash, that it does nothing outside a cloud
    session, and in one runs every ensure-*.sh beside it in name order, goes on past one that fails and names it, stops
    one that runs past ENSURE_SCRIPT_TIMEOUT seconds, skips other files, and exits 0. Then checks template\.claude\hooks\ensure-nvs.sh with a stub nvs home: that it does nothing
    outside a cloud session or without a .node-version, leaves an nvs home without nvs.sh alone, links the .node-version
    Node.js, adding it first when linking fails, writes NVS_HOME and the PATH to CLAUDE_ENV_FILE, and exits 0 with one
    line when nvs fails. Cloning nvs needs the network, so it is not run here. Prints PASS, FAIL or SKIP per check and
    exits 1 on any failure.

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

        $r = Invoke-Hook @{ CLAUDE_CODE_REMOTE = $null; ENSURE_SCRIPT_TIMEOUT = $null } $dispatcher
        Check 'outside a cloud session the dispatcher exits 0 and prints nothing' ($r.Code -eq 0 -and $r.Output -eq '') "exit $($r.Code): $($r.Output)"
        $r = Invoke-Hook @{ CLAUDE_CODE_REMOTE = 'true'; ENSURE_SCRIPT_TIMEOUT = $null } $dispatcher
        Check 'in a cloud session it runs each ensure-*.sh in name order, names the one that failed, and exits 0' ($r.Code -eq 0 -and $r.Output -eq "a ran`nb ran`nsession-start: ensure-b.sh exited 3`nc ran") "exit $($r.Code): $($r.Output)"

        $empty = Join-Path $work 'empty'
        New-Item -ItemType Directory -Force $empty | Out-Null
        Copy-Item -LiteralPath $script -Destination (Join-Path $empty 'session-start.sh')
        $r = Invoke-Hook @{ CLAUDE_CODE_REMOTE = 'true'; ENSURE_SCRIPT_TIMEOUT = $null } (Join-Path $empty 'session-start.sh')
        Check 'with no ensure-*.sh it exits 0 and prints nothing' ($r.Code -eq 0 -and $r.Output -eq '') "exit $($r.Code): $($r.Output)"

        $slow = Join-Path $work 'slow'
        New-Item -ItemType Directory -Force $slow | Out-Null
        Copy-Item -LiteralPath $script -Destination (Join-Path $slow 'session-start.sh')
        [IO.File]::WriteAllText((Join-Path $slow 'ensure-a.sh'), "while :; do :; done`n")
        [IO.File]::WriteAllText((Join-Path $slow 'ensure-b.sh'), "echo b ran`n")
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-Hook @{ CLAUDE_CODE_REMOTE = 'true'; ENSURE_SCRIPT_TIMEOUT = '1' } (Join-Path $slow 'session-start.sh')
        $watch.Stop()
        Check 'it stops a script that runs past ENSURE_SCRIPT_TIMEOUT, names it, and runs the next' ($r.Code -eq 0 -and $r.Output -eq "session-start: ensure-a.sh timed out after 1 seconds`nb ran" -and $watch.Elapsed.TotalSeconds -lt 10) "exit $($r.Code) after $($watch.Elapsed.TotalSeconds) s: $($r.Output)"

        # --- ensure-nvs.sh, with a stub nvs ---
        $nvsScript = Join-Path $repoRoot 'template/.claude/hooks/ensure-nvs.sh'
        Check 'ensure-nvs.sh has LF line endings' (-not ((Get-Content -Raw -LiteralPath $nvsScript) -match "`r"))
        & $bash.Source -n $nvsScript
        Check 'ensure-nvs.sh parses as bash' ($LASTEXITCODE -eq 0)

        $project = Join-Path $work 'project'
        New-Item -ItemType Directory -Force $project | Out-Null
        [IO.File]::WriteAllText((Join-Path $project '.node-version'), "22`n")
        $noVersion = Join-Path $work 'noversion'
        New-Item -ItemType Directory -Force $noVersion | Out-Null
        $nvsEmpty = Join-Path $work 'nvs-empty'
        New-Item -ItemType Directory -Force $nvsEmpty | Out-Null
        $nvsNone = Join-Path $work 'nvs-none'

        function New-StubNvs([string]$Name, [switch]$Added) {
            $stubHome = Join-Path $work $Name
            $nodeDir = Join-Path $stubHome 'default/bin'
            New-Item -ItemType Directory -Force $nodeDir | Out-Null
            $stub = 'nvs() { echo "$*" >> "$NVS_HOME/calls"; case "$1" in link) [ -f "$NVS_HOME/added" ] ;; add) [ -z "$NVS_STUB_FAIL" ] && touch "$NVS_HOME/added" ;; esac; }'
            [IO.File]::WriteAllText((Join-Path $stubHome 'nvs.sh'), "$stub`ntrue`n")
            $node = Join-Path $nodeDir 'node'
            [IO.File]::WriteAllText($node, "#!/bin/sh`necho v22.1.0`n")
            & chmod +x $node
            if ($Added) { [IO.File]::WriteAllText((Join-Path $stubHome 'added'), '') }
            $stubHome
        }

        function Invoke-Nvs([string]$Remote, [string]$ProjectDir, [string]$NvsHome, [string]$EnvFile, [string]$StubFail) {
            Invoke-Hook @{
                CLAUDE_CODE_REMOTE = $Remote
                CLAUDE_PROJECT_DIR = $ProjectDir
                NVS_HOME = $NvsHome
                CLAUDE_ENV_FILE = $EnvFile
                NVS_STUB_FAIL = $StubFail
            } $nvsScript
        }

        $r = Invoke-Nvs $null $project $nvsNone $null $null
        Check 'ensure-nvs.sh outside a cloud session exits 0, prints nothing and clones nothing' ($r.Code -eq 0 -and $r.Output -eq '' -and -not (Test-Path $nvsNone)) "exit $($r.Code): $($r.Output)"
        $r = Invoke-Nvs 'true' $noVersion $nvsNone $null $null
        Check 'ensure-nvs.sh without a .node-version exits 0, prints nothing and clones nothing' ($r.Code -eq 0 -and $r.Output -eq '' -and -not (Test-Path $nvsNone)) "exit $($r.Code): $($r.Output)"
        $r = Invoke-Nvs 'true' $project $nvsEmpty $null $null
        Check 'ensure-nvs.sh leaves an nvs home without nvs.sh alone' ($r.Code -eq 0 -and $r.Output -match '^ensure-nvs: [^\n]*exists without nvs\.sh[^\n]*$' -and @(Get-ChildItem -LiteralPath $nvsEmpty -Force).Count -eq 0) "exit $($r.Code): $($r.Output)"

        $linked = New-StubNvs 'nvs-linked' -Added
        $envFile = Join-Path $work 'env-linked'
        $r = Invoke-Nvs 'true' $project $linked $envFile $null
        $calls = [IO.File]::ReadAllText((Join-Path $linked 'calls')).Trim()
        Check 'ensure-nvs.sh links an installed Node.js without adding it' ($r.Code -eq 0 -and $calls -eq 'link 22' -and $r.Output -eq 'ensure-nvs: Node.js v22.1.0 from .node-version is linked through nvs.') "exit $($r.Code): $($r.Output) calls: $calls"
        $envText = if (Test-Path -LiteralPath $envFile) { [IO.File]::ReadAllText($envFile) } else { '' }
        Check 'ensure-nvs.sh puts the linked Node.js first on PATH through CLAUDE_ENV_FILE' ($envText -eq ('export NVS_HOME="{0}"' -f $linked) + "`n" + ('export PATH="{0}/default/bin:$PATH"' -f $linked) + "`n") $envText

        $fresh = New-StubNvs 'nvs-new'
        $r = Invoke-Nvs 'true' $project $fresh $null $null
        $calls = @([IO.File]::ReadAllText((Join-Path $fresh 'calls')).Trim() -split "`n")
        Check 'ensure-nvs.sh adds the .node-version Node.js when linking fails, then links it' ($r.Code -eq 0 -and ($calls -join '|') -eq 'link 22|add 22|link 22') "exit $($r.Code): $($r.Output) calls: $($calls -join '|')"

        $failing = New-StubNvs 'nvs-fail'
        $r = Invoke-Nvs 'true' $project $failing $null '1'
        Check 'ensure-nvs.sh exits 0 with one line when nvs cannot install Node.js' ($r.Code -eq 0 -and $r.Output -eq 'ensure-nvs: nvs could not install Node.js 22.') "exit $($r.Code): $($r.Output)"
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count) { "Tests: FAILED ($($failures.Count))"; exit 1 }
'Tests: PASSED'
