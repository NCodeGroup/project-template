<#
.SYNOPSIS
    Test the template's Node.js setup scripts: .template\Initialize-Nvs.ps1, .template\Use-Node.ps1 and .template\use-node.sh.

.DESCRIPTION
    The three template files have Jinja-tag file names without a .ps1 extension, so the suite copies each into a fixture
    project folder under -Work first. Checks that Initialize-Nvs.ps1 writes the bash and PowerShell profile blocks once and
    not twice, leaves a profile that already names nvs.ps1 alone, and throws the install text when nvs.ps1 is missing. Then
    checks, with a stub nvs that puts a stub node on PATH, that Use-Node.ps1 and use-node.sh put that node on PATH, and,
    with a stub nvs that does nothing and a PATH holding no node, that both fail with a message naming Initialize-Nvs.ps1.
    Then checks, with no nvs and a stub node on PATH that prints a version, that both accept that node when it is the
    version .node-version names or starts with it and a dot, and refuse it, with the nvs install text, when it is another
    version or missing, running bash with -eo pipefail as GitHub Actions does, so a refusal still prints its message;
    and that use-node.sh, under -eo pipefail too, reports a missing .node-version.
    Every check passes -HomeDirectory and -ProfilePath or sets NVS_HOME itself, so nothing touches the real home folder or
    profile. The Use-Node.ps1 and use-node.sh checks run with a PATH of the system folders alone (System32 on Windows,
    /usr/bin:/bin elsewhere), so an nvs or node the PC has can't stand in for the stubs; the use-node.sh checks run only
    on Linux and macOS, as in CI. Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-node-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-NodeSetup.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-node-test-$PID")
)
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()
$tag = "{% if (uses_node is defined and uses_node) or (uses_node is not defined and stack == 'node') %}"
$endTag = '{% endif %}'
$pwshPath = (Get-Process -Id $PID).Path
# The child processes run with this PATH, so a PC's own nvs or node can't stand in for the fixture's stubs.
$basePath = if ($IsWindows) { Join-Path $env:SystemRoot 'System32' } else { '/usr/bin:/bin' }
$baseHasNode = [bool]($basePath -split [IO.Path]::PathSeparator | Where-Object { (Test-Path (Join-Path $_ 'node')) -or (Test-Path (Join-Path $_ 'node.exe')) })
# The bash checks put Windows paths on a bash PATH, which only Linux and macOS bash can read; CI runs them on Linux.
$bash = if ($IsWindows) { $null } else { Get-Command bash -ErrorAction Ignore }
$noBash = if ($IsWindows) { 'the bash checks run on Linux and macOS' } else { 'bash not found' }

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Skip([string]$Name, [string]$Why) { "SKIP  $Name  $Why" }
function Get-TemplateFile([string]$Name) { Join-Path $repoRoot "template/.template/$tag$Name$endTag" }

# A fixture project: <root>/.node-version, <root>/.template/<the three scripts>, <root>/nvs/<stubs>, <root>/stub/node.
function New-Fixture([string]$Name, [string]$NvsPs1, [string]$NvsSh) {
    $root = Join-Path $Work $Name
    New-Item -ItemType Directory -Force (Join-Path $root '.template'), (Join-Path $root 'nvs'), (Join-Path $root 'stub'), (Join-Path $root 'home') | Out-Null
    Set-Content (Join-Path $root '.node-version') '26'
    Copy-Item -LiteralPath (Get-TemplateFile 'Initialize-Nvs.ps1') (Join-Path $root '.template/Initialize-Nvs.ps1')
    Copy-Item -LiteralPath (Get-TemplateFile 'Use-Node.ps1') (Join-Path $root '.template/Use-Node.ps1')
    Copy-Item -LiteralPath (Get-TemplateFile 'use-node.sh') (Join-Path $root '.template/use-node.sh')
    if ($NvsPs1) { Set-Content (Join-Path $root 'nvs/nvs.ps1') $NvsPs1 }
    if ($NvsSh) { Set-Content (Join-Path $root 'nvs/nvs.sh') $NvsSh }
    $stubName = if ($IsWindows) { 'node.cmd' } else { 'node' }
    Set-Content (Join-Path $root "stub/$stubName") $(if ($IsWindows) { '@echo off' } else { '#!/bin/sh' })
    if (-not $IsWindows) { chmod +x (Join-Path $root "stub/$stubName") }
    $root
}
# Runs a script block with the named environment variables set, then restores them.
function Invoke-WithEnv([hashtable]$Env, [scriptblock]$Block) {
    $saved = @{}
    foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
    try { & $Block }
    finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
}
# Runs a command in a child process; the caller reads $LASTEXITCODE.
function Invoke-Child {
    $ErrorActionPreference = 'Continue'
    & $args[0] @($args | Select-Object -Skip 1) 2>&1 | Out-String
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

# --- Initialize-Nvs.ps1 ---
$root = New-Fixture 'init' 'function nvs {}' ''
$init = Join-Path $root '.template/Initialize-Nvs.ps1'
$bashrc = Join-Path $root 'home/.bashrc'
$profilePs1 = Join-Path $root 'home/profile.ps1'
$initArgs = @{ NvsHome = (Join-Path $root 'nvs'); HomeDirectory = (Join-Path $root 'home'); ProfilePath = $profilePs1; SkipNode = $true }
Invoke-WithEnv @{ NVS_HOME = (Join-Path $root 'nvs') } { & $init @initArgs | Out-Null; & $init @initArgs | Out-Null }
Check 'Initialize-Nvs writes the bash block once, not twice' ((Select-String $bashrc -Pattern '>>> nvs' -SimpleMatch).Count -eq 1)
Check 'Initialize-Nvs writes the PowerShell block once, not twice' ((Select-String $profilePs1 -Pattern '>>> nvs' -SimpleMatch).Count -eq 1)

$root = New-Fixture 'init-named' 'function nvs {}' ''
$init = Join-Path $root '.template/Initialize-Nvs.ps1'
$profilePs1 = Join-Path $root 'home/profile.ps1'
Set-Content $profilePs1 '. "$env:LOCALAPPDATA\nvs\nvs.ps1"'
$initArgs = @{ NvsHome = (Join-Path $root 'nvs'); HomeDirectory = (Join-Path $root 'home'); ProfilePath = $profilePs1; SkipNode = $true }
Invoke-WithEnv @{ NVS_HOME = (Join-Path $root 'nvs') } { & $init @initArgs | Out-Null }
Check 'Initialize-Nvs skips a profile that already names nvs.ps1' (-not (Select-String $profilePs1 -Pattern '>>> nvs' -SimpleMatch -Quiet))

$root = New-Fixture 'init-missing' '' ''
$init = Join-Path $root '.template/Initialize-Nvs.ps1'
$message = ''
Invoke-WithEnv @{ NVS_HOME = (Join-Path $root 'nvs') } {
    try { & $init -NvsHome (Join-Path $root 'nvs') -HomeDirectory (Join-Path $root 'home') -ProfilePath (Join-Path $root 'home/profile.ps1') -SkipNode | Out-Null }
    catch { $script:message = $_.Exception.Message }
}
Check 'Initialize-Nvs throws the install text when nvs.ps1 is missing' ($message -like '*nvs is not installed*') $message
Check 'Initialize-Nvs writes nothing when nvs.ps1 is missing' (-not (Test-Path (Join-Path $root 'home/.bashrc')))

# --- Use-Node.ps1 and use-node.sh put the stub node on PATH ---
$stubNvsPs1 = 'function nvs { $env:PATH = "$env:NVS_STUB$([IO.Path]::PathSeparator)$env:PATH" }'
$root = New-Fixture 'use' $stubNvsPs1 'nvs() { PATH="$NVS_STUB:$PATH"; }'
$stubDir = Join-Path $root 'stub'
$stubNode = Join-Path $stubDir $(if ($IsWindows) { 'node.cmd' } else { 'node' })
$useEnv = @{ NVS_HOME = (Join-Path $root 'nvs'); NVS_STUB = $stubDir; PATH = $basePath }
$out = Invoke-WithEnv $useEnv {
    Invoke-Child $pwshPath -NoProfile -NonInteractive -Command ". '$(Join-Path $root '.template/Use-Node.ps1')'; (Get-Command node -ErrorAction Ignore).Source"
}
Check 'Use-Node.ps1 puts the stub node on PATH' ($LASTEXITCODE -eq 0 -and $out.Trim() -eq $stubNode) $out
if ($bash) {
    $out = Invoke-WithEnv $useEnv {
        Invoke-Child $bash.Source -c ". '$(Join-Path $root '.template/use-node.sh')' && command -v node"
    }
    Check 'use-node.sh puts the stub node on PATH' ($LASTEXITCODE -eq 0 -and $out.Trim() -eq $stubNode) $out
}
else { Skip 'use-node.sh puts the stub node on PATH' $noBash }

# --- Both fail when no node appears ---
$root = New-Fixture 'nonode' 'function nvs {}' 'nvs() { :; }'
$noNodeEnv = @{ NVS_HOME = (Join-Path $root 'nvs'); NVS_STUB = (Join-Path $root 'stub'); PATH = $basePath }
if (-not $baseHasNode) {
    $out = Invoke-WithEnv $noNodeEnv {
        Invoke-Child $pwshPath -NoProfile -NonInteractive -Command ". '$(Join-Path $root '.template/Use-Node.ps1')'"
    }
    Check 'Use-Node.ps1 fails naming Initialize-Nvs.ps1 when no node appears' ($LASTEXITCODE -ne 0 -and $out -like '*Initialize-Nvs.ps1*') $out
    if ($bash) {
        $out = Invoke-WithEnv $noNodeEnv {
            Invoke-Child $bash.Source -c ". '$(Join-Path $root '.template/use-node.sh')'"
        }
        Check 'use-node.sh fails naming Initialize-Nvs.ps1 when no node appears' ($LASTEXITCODE -ne 0 -and $out -like '*Initialize-Nvs.ps1*') $out
    }
    else { Skip 'use-node.sh fails naming Initialize-Nvs.ps1 when no node appears' $noBash }
}
else {
    Skip 'Use-Node.ps1 fails naming Initialize-Nvs.ps1 when no node appears' "$basePath holds a node"
    Skip 'use-node.sh fails naming Initialize-Nvs.ps1 when no node appears' "$basePath holds a node"
}

# --- Without nvs, both accept the node on PATH only when it is the version .node-version names ---
$noNvsCases = @(
    @{ Name = 'accepts the node on PATH whose major version .node-version names'; Want = '26'; Have = 'v26.1.0'; Ok = $true }
    @{ Name = 'accepts the node on PATH whose exact version .node-version names'; Want = 'v26.1.0'; Have = 'v26.1.0'; Ok = $true }
    @{ Name = 'refuses a node on PATH of another major version'; Want = '26'; Have = 'v24.3.0'; Ok = $false }
    @{ Name = 'refuses 26.10.0 when .node-version names 26.1'; Want = '26.1'; Have = 'v26.10.0'; Ok = $false }
    @{ Name = 'refuses when no node is on PATH'; Want = '26'; Have = ''; Ok = $false }
    @{ Name = 'refuses a .node-version whose leading V is upper case'; Want = 'V26'; Have = 'v26.1.0'; Ok = $false }
)
for ($i = 0; $i -lt $noNvsCases.Count; $i++) {
    $case = $noNvsCases[$i]
    if (-not $case.Have -and $baseHasNode) { Skip "Use-Node.ps1 without nvs $($case.Name)" "$basePath holds a node"; Skip "use-node.sh without nvs $($case.Name)" "$basePath holds a node"; continue }
    $root = New-Fixture "nonvs-$i" '' ''
    Set-Content (Join-Path $root '.node-version') $case.Want
    $stubDir = Join-Path $root 'stub'
    $stubNode = Join-Path $stubDir $(if ($IsWindows) { 'node.cmd' } else { 'node' })
    Set-Content $stubNode $(if ($IsWindows) { "@echo $($case.Have)" } else { '#!/bin/sh', "echo $($case.Have)" })
    if (-not $IsWindows) { chmod +x $stubNode }
    $noNvsEnv = @{ NVS_HOME = (Join-Path $root 'nvs'); PATH = $(if ($case.Have) { "$stubDir$([IO.Path]::PathSeparator)$basePath" } else { $basePath }) }
    # The child prints the exception message itself, so PowerShell's error view can't wrap the text the check looks for.
    $out = Invoke-WithEnv $noNvsEnv { Invoke-Child $pwshPath -NoProfile -NonInteractive -Command "try { . '$(Join-Path $root '.template/Use-Node.ps1')'; (Get-Command node -ErrorAction Ignore).Source } catch { `$_.Exception.Message; exit 1 }" }
    $ok = if ($case.Ok) { $LASTEXITCODE -eq 0 -and $out.Trim() -eq $stubNode } else { $LASTEXITCODE -ne 0 -and $out -like '*nvs is not installed*Install it with*' }
    Check "Use-Node.ps1 without nvs $($case.Name)" $ok $out
    if ($bash) {
        # GitHub Actions runs bash with -eo pipefail, and a refusal must still print its message there.
        $out = Invoke-WithEnv $noNvsEnv { Invoke-Child $bash.Source -eo pipefail -c ". '$(Join-Path $root '.template/use-node.sh')'; command -v node" }
        $ok = if ($case.Ok) { $LASTEXITCODE -eq 0 -and $out.Trim() -eq $stubNode } else { $LASTEXITCODE -ne 0 -and $out -like '*nvs is not installed*Install it with*' }
        Check "use-node.sh without nvs $($case.Name)" $ok $out
    }
    else { Skip "use-node.sh without nvs $($case.Name)" $noBash }
}

# --- use-node.sh reports a missing .node-version in a set -eo pipefail shell ---
if ($bash) {
    $root = New-Fixture 'noversion' '' ''
    Remove-Item -LiteralPath (Join-Path $root '.node-version')
    $out = Invoke-WithEnv @{ NVS_HOME = (Join-Path $root 'nvs'); PATH = $basePath } { Invoke-Child $bash.Source -eo pipefail -c ". '$(Join-Path $root '.template/use-node.sh')'; command -v node" }
    Check 'use-node.sh reports a missing .node-version under set -eo pipefail' ($LASTEXITCODE -ne 0 -and $out -like '*No Node.js version in*') $out
}
else { Skip 'use-node.sh reports a missing .node-version under set -eo pipefail' $noBash }

if ($failures.Count) { "Kept the work folder: $Work"; "Node.js setup tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Node.js setup tests: PASSED'
# The failing child processes above leave a non-zero $LASTEXITCODE that the caller would read as this suite's result.
$global:LASTEXITCODE = 0
