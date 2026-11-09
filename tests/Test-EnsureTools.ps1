<#
.SYNOPSIS
    Test the SessionStart hooks that bootstrap a Claude Code cloud session's tools.

.DESCRIPTION
    Checks .claude\hooks\session-start.sh, which the template's and this repository's .claude\settings.json run on
    SessionStart: that both copies are identical, LF and parse as bash, that both settings files run it from
    $CLAUDE_PROJECT_DIR with a timeout of at least 600 seconds, and, with bash, that it does nothing outside a cloud
    session, and in one runs every ensure-*.sh beside it in name order, goes on past one that fails and names it,
    stops one that runs past ENSURE_SCRIPT_TIMEOUT seconds, skips other files, and exits 0. Then checks
    template\.claude\hooks\ensure-nvs.sh with stub nvs, install-nvs.sh and node files: that it does nothing outside
    a cloud session or without a .node-version, accepts the image's matching node without installing nvs, installs
    nvs and selects the .node-version Node.js through use-node.sh when the node on PATH is another release, appends
    the node's folder to CLAUDE_ENV_FILE, uses an nvs already there, and exits 0 with one line when installing or
    selecting fails. Cloning nvs needs the network, so it is not run here. Prints PASS, FAIL or SKIP per check and
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

        $nvsSource = Join-Path $work 'nvs-source'
        New-Item -ItemType Directory -Force (Join-Path $nvsSource 'bin') | Out-Null
        $stubNvs = @'
nvs() {
    echo "$*" >> "$NVS_HOME/calls"
    case "$1" in
        use) [ -f "$NVS_HOME/added" ] || return 1; PATH="$NVS_HOME/bin:$PATH" ;;
        add) [ -z "$NVS_STUB_FAIL" ] || return 1; touch "$NVS_HOME/added" ;;
    esac
}
'@
        [IO.File]::WriteAllText((Join-Path $nvsSource 'nvs.sh'), $stubNvs.Replace("`r`n", "`n") + "`n")
        $sourceNode = Join-Path $nvsSource 'bin/node'
        [IO.File]::WriteAllText($sourceNode, "#!/bin/sh`necho v22.1.0`n")
        & chmod +x $sourceNode

        function New-NvsCase([string]$Name, [string]$Have) {
            $case = Join-Path $work $Name
            $templateFolder = Join-Path $case 'project/.template'
            New-Item -ItemType Directory -Force $templateFolder | Out-Null
            [IO.File]::WriteAllText((Join-Path $case 'project/.node-version'), "22`n")
            Copy-Item -LiteralPath (Join-Path $repoRoot 'template/.template/use-node.sh') -Destination $templateFolder
            $install = "touch `"`$NVS_HOME.install-ran`"`n" +
                "if [ -n `"`$STUB_INSTALL_FAIL`" ]; then echo `"install-nvs: stub failure`" >&2; exit 1; fi`n" +
                "cp -R `"`$STUB_NVS_SOURCE`" `"`$NVS_HOME`"`n"
            [IO.File]::WriteAllText((Join-Path $templateFolder 'install-nvs.sh'), $install)
            if ($Have) {
                $stubDir = Join-Path $case 'stub'
                New-Item -ItemType Directory -Force $stubDir | Out-Null
                $node = Join-Path $stubDir 'node'
                [IO.File]::WriteAllText($node, "#!/bin/sh`necho $Have`n")
                & chmod +x $node
            }
            $case
        }

        function Invoke-Ensure([string]$Case, [string]$Remote = 'true', [string]$InstallFail, [string]$NvsFail) {
            $path = if (Test-Path -LiteralPath (Join-Path $Case 'stub')) { "$Case/stub:/usr/bin:/bin" } else { '/usr/bin:/bin' }
            Invoke-Hook @{
                CLAUDE_CODE_REMOTE = $(if ($Remote) { $Remote } else { $null })
                CLAUDE_PROJECT_DIR = Join-Path $Case 'project'
                NVS_HOME = Join-Path $Case 'nvs'
                CLAUDE_ENV_FILE = Join-Path $Case 'env'
                STUB_NVS_SOURCE = $nvsSource
                STUB_INSTALL_FAIL = $(if ($InstallFail) { $InstallFail } else { $null })
                NVS_STUB_FAIL = $(if ($NvsFail) { $NvsFail } else { $null })
                PATH = $path
            } $nvsScript
        }

        function Read-CaseFile([string]$Path) {
            if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { '' }
        }

        $case = New-NvsCase 'outside' 'v24.0.0'
        $r = Invoke-Ensure $case -Remote ''
        Check 'ensure-nvs.sh outside a cloud session exits 0, prints nothing and installs nothing' ($r.Code -eq 0 -and $r.Output -eq '' -and -not (Test-Path "$case/nvs.install-ran") -and -not (Test-Path "$case/env")) "exit $($r.Code): $($r.Output)"

        $case = New-NvsCase 'noversion' 'v24.0.0'
        [IO.File]::WriteAllText((Join-Path $case 'project/.node-version'), '')
        $r = Invoke-Ensure $case
        Check 'ensure-nvs.sh without a .node-version exits 0, prints nothing and installs nothing' ($r.Code -eq 0 -and $r.Output -eq '' -and -not (Test-Path "$case/nvs.install-ran") -and -not (Test-Path "$case/env")) "exit $($r.Code): $($r.Output)"

        $case = New-NvsCase 'matches' 'v22.4.0'
        $r = Invoke-Ensure $case
        Check "ensure-nvs.sh accepts the image's matching node without installing nvs" ($r.Code -eq 0 -and $r.Output -eq '' -and -not (Test-Path "$case/nvs.install-ran")) "exit $($r.Code): $($r.Output)"
        $envText = Read-CaseFile "$case/env"
        Check "ensure-nvs.sh puts the matching node's folder on PATH through CLAUDE_ENV_FILE" ($envText -eq ('export PATH="{0}/stub:$PATH"' -f $case) + "`n") $envText

        $case = New-NvsCase 'installs' 'v24.0.0'
        $r = Invoke-Ensure $case
        $calls = (Read-CaseFile "$case/nvs/calls").Trim().Replace("`n", '|')
        $envText = Read-CaseFile "$case/env"
        Check 'ensure-nvs.sh installs nvs and selects the .node-version Node.js when the node on PATH is another release' ($r.Code -eq 0 -and $r.Output -eq 'ensure-nvs: Node.js v22.1.0 from .node-version is on PATH through nvs.' -and $calls -eq 'use 22|add 22|use 22' -and $envText -eq ('export PATH="{0}/nvs/bin:$PATH"' -f $case) + "`n") "exit $($r.Code): $($r.Output) calls: $calls env: $envText"

        $case = New-NvsCase 'install-fails' 'v24.0.0'
        $r = Invoke-Ensure $case -InstallFail '1'
        Check "ensure-nvs.sh exits 0 with install-nvs.sh's line when it cannot install nvs" ($r.Code -eq 0 -and $r.Output -eq 'install-nvs: stub failure' -and -not (Test-Path "$case/env")) "exit $($r.Code): $($r.Output)"

        $case = New-NvsCase 'nvs-fails' 'v24.0.0'
        $r = Invoke-Ensure $case -NvsFail '1'
        Check 'ensure-nvs.sh exits 0 with one line when nvs cannot select Node.js' ($r.Code -eq 0 -and $r.Output -eq 'ensure-nvs: nvs could not put the .node-version Node.js on PATH.') "exit $($r.Code): $($r.Output)"

        $case = New-NvsCase 'resumed' 'v24.0.0'
        & cp -R $nvsSource "$case/nvs"
        [IO.File]::WriteAllText((Join-Path $case 'nvs/added'), '')
        $r = Invoke-Ensure $case
        $calls = (Read-CaseFile "$case/nvs/calls").Trim().Replace("`n", '|')
        $envText = Read-CaseFile "$case/env"
        Check 'ensure-nvs.sh uses an nvs already there without installing it' ($r.Code -eq 0 -and $r.Output -eq '' -and -not (Test-Path "$case/nvs.install-ran") -and $calls -eq 'use 22' -and $envText -eq ('export PATH="{0}/nvs/bin:$PATH"' -f $case) + "`n") "exit $($r.Code): $($r.Output) calls: $calls env: $envText"
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count) { "Tests: FAILED ($($failures.Count))"; exit 1 }
'Tests: PASSED'
