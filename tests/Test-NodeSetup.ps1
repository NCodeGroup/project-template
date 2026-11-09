<#
.SYNOPSIS
    Test the template's Node.js setup scripts: .template\Initialize-Nvs.ps1, .template\Use-Node.ps1 and .template\use-node.sh.

.DESCRIPTION
    The suite copies the template's four Node.js scripts into fixture project folders under -Work, and tests
    .template\Initialize-Nvs.ps1, Use-Node.ps1, use-node.sh and install-nvs.sh. Checks that Initialize-Nvs.ps1 writes
    the bash and PowerShell profile blocks once and not twice and leaves a profile that already names nvs.ps1 alone;
    that, when nvs.ps1 is missing, it throws the pinned winget text on Windows, and elsewhere installs nvs through
    install-nvs.sh (a stub here) or throws when that fails. Then checks, with a stub nvs that puts a stub node on PATH,
    that Use-Node.ps1 and use-node.sh put that node on PATH, and, with a stub nvs that does nothing and a PATH holding
    no node, that both fail with a message naming Initialize-Nvs.ps1. Both selectors accept a node on PATH that is the
    release .node-version names without calling nvs, select it through a stub nvs otherwise, and fail naming
    Initialize-Nvs.ps1 when neither works, with the same rule: the major version, an exact version, 26.1 refusing
    26.10.0, and a case-sensitive v. The bash checks run under -eo pipefail as GitHub Actions does, so a refusal still
    prints its message. Also checks that both report an empty and a missing .node-version, that install-nvs.sh does
    nothing when the nvs home has nvs.sh and refuses an nvs home that exists without it, and that install-nvs.sh and
    Initialize-Nvs.ps1 pin the same nvs release.
    Every check passes -HomeDirectory and -ProfilePath or sets NVS_HOME itself, so nothing touches the real home folder or
    profile. The Use-Node.ps1 and use-node.sh checks run with a PATH of the system folders alone (System32 on Windows,
    /usr/bin:/bin elsewhere), so an nvs or node the PC has can't stand in for the stubs; the use-node.sh and
    install-nvs.sh checks run only on Linux and macOS, as in CI. Prints PASS or FAIL per check and exits 1 on any
    failure.

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
function Get-TemplateFile([string]$Name) { Join-Path $repoRoot "template/.template/$Name" }

# A fixture project: <root>/.node-version, <root>/.template/<the four scripts>, <root>/nvs/<stubs>, <root>/stub/node.
function New-Fixture([string]$Name, [string]$NvsPs1, [string]$NvsSh) {
    $root = Join-Path $Work $Name
    New-Item -ItemType Directory -Force (Join-Path $root '.template'), (Join-Path $root 'nvs'), (Join-Path $root 'stub'), (Join-Path $root 'home') | Out-Null
    Set-Content (Join-Path $root '.node-version') '26'
    Copy-Item -LiteralPath (Get-TemplateFile 'Initialize-Nvs.ps1') (Join-Path $root '.template/Initialize-Nvs.ps1')
    Copy-Item -LiteralPath (Get-TemplateFile 'Use-Node.ps1') (Join-Path $root '.template/Use-Node.ps1')
    Copy-Item -LiteralPath (Get-TemplateFile 'use-node.sh') (Join-Path $root '.template/use-node.sh')
    Copy-Item -LiteralPath (Get-TemplateFile 'install-nvs.sh') (Join-Path $root '.template/install-nvs.sh')
    if ($NvsPs1) { Set-Content (Join-Path $root 'nvs/nvs.ps1') $NvsPs1 }
    if ($NvsSh) { Set-Content (Join-Path $root 'nvs/nvs.sh') $NvsSh }
    $stubName = if ($IsWindows) { 'node.cmd' } else { 'node' }
    Set-Content (Join-Path $root "stub/$stubName") $(if ($IsWindows) { '@echo v26.1.0' } else { '#!/bin/sh', 'echo v26.1.0' })
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

if ($IsWindows) {
    $root = New-Fixture 'init-missing' '' ''
    $init = Join-Path $root '.template/Initialize-Nvs.ps1'
    $message = ''
    Invoke-WithEnv @{ NVS_HOME = (Join-Path $root 'nvs') } {
        try { & $init -NvsHome (Join-Path $root 'nvs') -HomeDirectory (Join-Path $root 'home') -ProfilePath (Join-Path $root 'home/profile.ps1') -SkipNode | Out-Null }
        catch { $script:message = $_.Exception.Message }
    }
    Check 'Initialize-Nvs throws the pinned winget command when nvs.ps1 is missing' ($message -like '*winget install --id jasongin.nvs -e --version 1.7.1*') $message
    Check 'Initialize-Nvs writes nothing when nvs.ps1 is missing' (-not (Test-Path (Join-Path $root 'home/.bashrc')))
}
else {
    # A stub install-nvs.sh stands in for the real one, which clones nvs from the network.
    $root = New-Fixture 'init-install-fails' '' ''
    $init = Join-Path $root '.template/Initialize-Nvs.ps1'
    [IO.File]::WriteAllText((Join-Path $root '.template/install-nvs.sh'), "echo `"install-nvs: stub failure`" >&2`nexit 1`n")
    $message = ''
    Invoke-WithEnv @{ NVS_HOME = (Join-Path $root 'nvs') } {
        try { & $init -NvsHome (Join-Path $root 'nvs') -HomeDirectory (Join-Path $root 'home') -ProfilePath (Join-Path $root 'home/profile.ps1') -SkipNode 2>&1 | Out-Null }
        catch { $script:message = $_.Exception.Message }
    }
    Check 'Initialize-Nvs throws when install-nvs.sh cannot install nvs' ($message -like '*could not install it*') $message
    Check 'Initialize-Nvs writes nothing when install-nvs.sh fails' (-not (Test-Path (Join-Path $root 'home/.bashrc')))

    $root = New-Fixture 'init-installs' '' ''
    $init = Join-Path $root '.template/Initialize-Nvs.ps1'
    Remove-Item -LiteralPath (Join-Path $root 'nvs') -Recurse -Force
    [IO.File]::WriteAllText((Join-Path $root '.template/install-nvs.sh'), "mkdir -p `"`$NVS_HOME`"`necho 'function nvs {}' > `"`$NVS_HOME/nvs.ps1`"`necho 'nvs() { :; }' > `"`$NVS_HOME/nvs.sh`"`n")
    $out = Invoke-WithEnv @{ NVS_HOME = (Join-Path $root 'nvs') } {
        & $init -NvsHome (Join-Path $root 'nvs') -HomeDirectory (Join-Path $root 'home') -ProfilePath (Join-Path $root 'home/profile.ps1') -SkipNode | Out-String
    }
    Check 'Initialize-Nvs installs nvs through install-nvs.sh, then writes the profile blocks' ($out -like '*Installed nvs in*' -and (Select-String (Join-Path $root 'home/.bashrc') -Pattern '>>> nvs' -SimpleMatch -Quiet)) $out
}

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

# --- With nvs, both leave a matching node on PATH alone and fix a wrong one ---
$root = New-Fixture 'skip' 'function nvs { Add-Content (Join-Path $env:NVS_HOME ''calls'') "$args" }' 'nvs() { echo "$*" >> "$NVS_HOME/calls"; }'
$stubDir = Join-Path $root 'stub'
$stubNode = Join-Path $stubDir $(if ($IsWindows) { 'node.cmd' } else { 'node' })
$calls = Join-Path $root 'nvs/calls'
$skipEnv = @{ NVS_HOME = (Join-Path $root 'nvs'); PATH = "$stubDir$([IO.Path]::PathSeparator)$basePath" }
$out = Invoke-WithEnv $skipEnv { Invoke-Child $pwshPath -NoProfile -NonInteractive -Command "try { . '$(Join-Path $root '.template/Use-Node.ps1')'; (Get-Command node -ErrorAction Ignore).Source } catch { `$_.Exception.Message; exit 1 }" }
Check 'Use-Node.ps1 accepts a matching node on PATH without calling nvs' ($LASTEXITCODE -eq 0 -and $out.Trim() -eq $stubNode -and -not (Test-Path $calls)) $out
if (Test-Path $calls) { Remove-Item -LiteralPath $calls -Force }
if ($bash) {
    $out = Invoke-WithEnv $skipEnv { Invoke-Child $bash.Source -eo pipefail -c ". '$(Join-Path $root '.template/use-node.sh')'; command -v node" }
    Check 'use-node.sh accepts a matching node on PATH without calling nvs' ($LASTEXITCODE -eq 0 -and $out.Trim() -eq $stubNode -and -not (Test-Path $calls)) $out
}
else { Skip 'use-node.sh accepts a matching node on PATH without calling nvs' $noBash }

foreach ($variant in 'fix', 'stays-wrong') {
    $fixes = $variant -eq 'fix'
    $root = New-Fixture $variant $(if ($fixes) { 'function nvs { $env:PATH = "$env:NVS_STUB$([IO.Path]::PathSeparator)$env:PATH" }' } else { 'function nvs {}' }) $(if ($fixes) { 'nvs() { PATH="$NVS_STUB:$PATH"; }' } else { 'nvs() { :; }' })
    $stubDir = Join-Path $root 'stub'
    $stub26 = Join-Path $root 'stub26'
    New-Item -ItemType Directory -Force $stub26 | Out-Null
    $nodeName = if ($IsWindows) { 'node.cmd' } else { 'node' }
    Set-Content (Join-Path $stubDir $nodeName) $(if ($IsWindows) { '@echo v24.3.0' } else { '#!/bin/sh', 'echo v24.3.0' })
    Set-Content (Join-Path $stub26 $nodeName) $(if ($IsWindows) { '@echo v26.1.0' } else { '#!/bin/sh', 'echo v26.1.0' })
    if (-not $IsWindows) { chmod +x (Join-Path $stubDir $nodeName) (Join-Path $stub26 $nodeName) }
    $wrongEnv = @{ NVS_HOME = (Join-Path $root 'nvs'); NVS_STUB = $stub26; PATH = "$stubDir$([IO.Path]::PathSeparator)$basePath" }
    $out = Invoke-WithEnv $wrongEnv { Invoke-Child $pwshPath -NoProfile -NonInteractive -Command "try { . '$(Join-Path $root '.template/Use-Node.ps1')'; (Get-Command node -ErrorAction Ignore).Source } catch { `$_.Exception.Message; exit 1 }" }
    if ($fixes) { Check 'Use-Node.ps1 selects the .node-version node through nvs over a wrong one' ($LASTEXITCODE -eq 0 -and $out.Trim() -eq (Join-Path $stub26 $nodeName)) $out }
    else { Check 'Use-Node.ps1 fails naming Initialize-Nvs.ps1 when nvs leaves a wrong node' ($LASTEXITCODE -ne 0 -and $out -like '*found node 24.3.0*Initialize-Nvs.ps1*') $out }
    $bashName = if ($fixes) { 'use-node.sh selects the .node-version node through nvs over a wrong one' } else { 'use-node.sh fails naming Initialize-Nvs.ps1 when nvs leaves a wrong node' }
    if ($bash) {
        $out = Invoke-WithEnv $wrongEnv { Invoke-Child $bash.Source -eo pipefail -c ". '$(Join-Path $root '.template/use-node.sh')'; command -v node" }
        $ok = if ($fixes) { $LASTEXITCODE -eq 0 -and $out.Trim() -eq (Join-Path $stub26 $nodeName) } else { $LASTEXITCODE -ne 0 -and $out -like '*found node 24.3.0*Initialize-Nvs.ps1*' }
        Check $bashName $ok $out
    }
    else { Skip $bashName $noBash }
}

# --- Without nvs, both accept the node on PATH only when it is the release .node-version names ---
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
    $ok = if ($case.Ok) { $LASTEXITCODE -eq 0 -and $out.Trim() -eq $stubNode } else { $LASTEXITCODE -ne 0 -and $out -like '*from .node-version is not on PATH*Initialize-Nvs.ps1*' }
    Check "Use-Node.ps1 without nvs $($case.Name)" $ok $out
    if ($bash) {
        # GitHub Actions runs bash with -eo pipefail, and a refusal must still print its message there.
        $out = Invoke-WithEnv $noNvsEnv { Invoke-Child $bash.Source -eo pipefail -c ". '$(Join-Path $root '.template/use-node.sh')'; command -v node" }
        $ok = if ($case.Ok) { $LASTEXITCODE -eq 0 -and $out.Trim() -eq $stubNode } else { $LASTEXITCODE -ne 0 -and $out -like '*from .node-version is not on PATH*Initialize-Nvs.ps1*' }
        Check "use-node.sh without nvs $($case.Name)" $ok $out
    }
    else { Skip "use-node.sh without nvs $($case.Name)" $noBash }
}

# --- use-node.sh reports a missing .node-version in a set -eo pipefail shell ---
if ($bash) {
    $root = New-Fixture 'noversion' '' ''
    Remove-Item -LiteralPath (Join-Path $root '.node-version') -Force
    $out = Invoke-WithEnv @{ NVS_HOME = (Join-Path $root 'nvs'); PATH = $basePath } { Invoke-Child $bash.Source -eo pipefail -c ". '$(Join-Path $root '.template/use-node.sh')'; command -v node" }
    Check 'use-node.sh reports a missing .node-version under set -eo pipefail' ($LASTEXITCODE -ne 0 -and $out -like '*No Node.js version in*') $out
}
else { Skip 'use-node.sh reports a missing .node-version under set -eo pipefail' $noBash }

# --- Both report a missing or empty .node-version ---
$root = New-Fixture 'empty-version' '' ''
[IO.File]::WriteAllText((Join-Path $root '.node-version'), '')
$out = Invoke-WithEnv @{ NVS_HOME = (Join-Path $root 'nvs'); PATH = $basePath } { Invoke-Child $pwshPath -NoProfile -NonInteractive -Command "try { . '$(Join-Path $root '.template/Use-Node.ps1')' } catch { `$_.Exception.Message; exit 1 }" }
Check 'Use-Node.ps1 reports an empty .node-version' ($LASTEXITCODE -ne 0 -and $out -like '*is empty; it must name a Node.js version*') $out
if ($bash) {
    $out = Invoke-WithEnv @{ NVS_HOME = (Join-Path $root 'nvs'); PATH = $basePath } { Invoke-Child $bash.Source -eo pipefail -c ". '$(Join-Path $root '.template/use-node.sh')'; command -v node" }
    Check 'use-node.sh reports an empty .node-version' ($LASTEXITCODE -ne 0 -and $out -like '*No Node.js version in*') $out
}
else { Skip 'use-node.sh reports an empty .node-version' $noBash }

# --- install-nvs.sh, without the network ---
$installNvs = Get-TemplateFile 'install-nvs.sh'
if ($bash) {
    $null = Invoke-Child $bash.Source -n $installNvs
    Check 'install-nvs.sh parses as bash' ($LASTEXITCODE -eq 0)

    $has = Join-Path $Work 'pinned-has'
    New-Item -ItemType Directory -Force $has | Out-Null
    Set-Content (Join-Path $has 'nvs.sh') 'nvs() { :; }'
    $out = Invoke-WithEnv @{ NVS_HOME = $has; PATH = $basePath } { Invoke-Child $bash.Source $installNvs }
    Check 'install-nvs.sh does nothing when the nvs home has nvs.sh' ($LASTEXITCODE -eq 0 -and -not $out.Trim() -and @(Get-ChildItem $has).Count -eq 1) $out

    $empty = Join-Path $Work 'pinned-empty'
    New-Item -ItemType Directory -Force $empty | Out-Null
    $out = Invoke-WithEnv @{ NVS_HOME = $empty; PATH = $basePath } { Invoke-Child $bash.Source $installNvs }
    Check 'install-nvs.sh leaves an nvs home without nvs.sh alone' ($LASTEXITCODE -ne 0 -and $out -like '*exists without nvs.sh*' -and @(Get-ChildItem $empty).Count -eq 0) $out
}
else {
    foreach ($name in 'install-nvs.sh parses as bash', 'install-nvs.sh does nothing when the nvs home has nvs.sh', 'install-nvs.sh leaves an nvs home without nvs.sh alone') { Skip $name $noBash }
}
$installText = [IO.File]::ReadAllText($installNvs)
$initText = [IO.File]::ReadAllText((Get-TemplateFile 'Initialize-Nvs.ps1'))
$tagMatch = [regex]::Match($installText, '(?m)^NVS_TAG=v(\d+\.\d+\.\d+)$')
$wingetMatch = [regex]::Match($initText, '--version (\d+\.\d+\.\d+)')
Check 'install-nvs.sh and Initialize-Nvs.ps1 pin the same nvs release' ($tagMatch.Success -and $wingetMatch.Success -and $tagMatch.Groups[1].Value -eq $wingetMatch.Groups[1].Value -and $installText -cmatch '(?m)^NVS_COMMIT=[0-9a-f]{40}$') "tag $($tagMatch.Groups[1].Value), winget $($wingetMatch.Groups[1].Value)"

if ($failures.Count) { "Kept the work folder: $Work"; "Node.js setup tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Node.js setup tests: PASSED'
# The failing child processes above leave a non-zero $LASTEXITCODE that the caller would read as this suite's result.
$global:LASTEXITCODE = 0
