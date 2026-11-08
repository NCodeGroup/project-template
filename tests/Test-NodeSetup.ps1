<#
.SYNOPSIS
    Test the template's Node.js setup scripts: .template\Initialize-Nvs.ps1, .template\Use-Node.ps1 and .template\use-node.sh.

.DESCRIPTION
    The three template files have Jinja-tag file names without a .ps1 extension, so the suite copies each into a fixture
    project folder under -Work first. Checks that Initialize-Nvs.ps1 writes the bash and PowerShell profile blocks once and
    not twice, leaves a profile that already names nvs.ps1 alone, and throws the install text when nvs.ps1 is missing. Then
    checks, with a stub nvs that puts a stub node on PATH, that Use-Node.ps1 and use-node.sh put that node on PATH, and,
    with a stub nvs that does nothing and a PATH holding no node, that both fail with a message naming Initialize-Nvs.ps1.
    Every check passes -HomeDirectory and -ProfilePath or sets NVS_HOME itself, so nothing touches the real home folder or
    profile. Prints PASS or FAIL per check and exits 1 on any failure.

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
$tag = "{% if uses_node | default(stack == 'node') %}"
$endTag = '{% endif %}'
$pwshPath = (Get-Process -Id $PID).Path

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
$sep = [IO.Path]::PathSeparator
$stubNvsPs1 = 'function nvs { $env:PATH = "$env:NVS_STUB$([IO.Path]::PathSeparator)$env:PATH" }'
$root = New-Fixture 'use' $stubNvsPs1 'nvs() { PATH="$NVS_STUB:$PATH"; }'
$stubDir = Join-Path $root 'stub'
$stubNode = Join-Path $stubDir $(if ($IsWindows) { 'node.cmd' } else { 'node' })
$useEnv = @{ NVS_HOME = (Join-Path $root 'nvs'); NVS_STUB = $stubDir }
$out = Invoke-WithEnv $useEnv {
    Invoke-Child $pwshPath -NoProfile -NonInteractive -Command ". '$(Join-Path $root '.template/Use-Node.ps1')'; (Get-Command node -ErrorAction Ignore).Source"
}
Check 'Use-Node.ps1 puts the stub node on PATH' ($LASTEXITCODE -eq 0 -and $out.Trim() -eq $stubNode) $out
$bash = Get-Command bash -ErrorAction Ignore
if ($bash) {
    $out = Invoke-WithEnv $useEnv {
        Invoke-Child $bash.Source -c ". '$(Join-Path $root '.template/use-node.sh')' && command -v node"
    }
    Check 'use-node.sh puts the stub node on PATH' ($LASTEXITCODE -eq 0 -and $out.Trim() -eq $stubNode) $out
}
else { Skip 'use-node.sh puts the stub node on PATH' 'bash not found' }

# --- Both fail when no node appears ---
$root = New-Fixture 'nonode' 'function nvs {}' 'nvs() { :; }'
$noNodeEnv = @{ NVS_HOME = (Join-Path $root 'nvs'); NVS_STUB = (Join-Path $root 'stub') }
$restricted = $false
if (-not $IsWindows) {
    $restricted = -not ((Test-Path /usr/bin/node) -or (Test-Path /bin/node))
    if ($restricted) { $noNodeEnv['PATH'] = '/usr/bin:/bin' }
}
if ($restricted) {
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
    else { Skip 'use-node.sh fails naming Initialize-Nvs.ps1 when no node appears' 'bash not found' }
}
else {
    Skip 'Use-Node.ps1 fails naming Initialize-Nvs.ps1 when no node appears' 'cannot build a PATH without node here'
    Skip 'use-node.sh fails naming Initialize-Nvs.ps1 when no node appears' 'cannot build a PATH without node here'
}

if ($failures.Count) { "Kept the work folder: $Work"; "Node.js setup tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Node.js setup tests: PASSED'
# The failing child processes above leave a non-zero $LASTEXITCODE that the caller would read as this suite's result.
$global:LASTEXITCODE = 0
