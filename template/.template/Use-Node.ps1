<#
.SYNOPSIS
    Puts the project's Node.js on PATH in the current PowerShell session through nvs, or checks the one already there.

.DESCRIPTION
    From the project template; template updates replace this file. Dot-source it, so that nvs and the PATH change stay
    in your session: ". ./.template/Use-Node.ps1". It is also the AGENTS.md prelude of a project that uses Node.js.
    It reads the version from the first line of the project's .node-version, loads nvs when the session has no nvs
    command, and runs "nvs use" for that version, adding it with "nvs add" first when it is not installed. Where nvs is
    not installed at all, as in GitHub CI, Copilot's cloud agent and a Claude Code cloud session, it checks the node on
    PATH instead, and accepts it when "node --version", without its leading v, is the .node-version version or starts
    with it and a dot: 26 accepts 26.1.0, and 26.1 accepts 26.1.4 but not 26.10.0. It throws when .node-version is
    missing, when nvs is not installed and the node on PATH is missing or another version (with the install command),
    or when node is still not on PATH after nvs use. It does not change $ErrorActionPreference or the strict mode of
    the session, and it never calls exit.
    The nvs home is $env:NVS_HOME when set, else $env:LOCALAPPDATA\nvs on Windows, else ~/.nvs. Install nvs on Windows
    with: winget install --id jasongin.nvs -e; elsewhere with: git clone https://github.com/jasongin/nvs "$HOME/.nvs";
    . "$HOME/.nvs/nvs.sh" install
    Initialize-Nvs.ps1 and use-node.sh in this folder carry the same nvs home lookup and install text, because each
    script runs on its own; change all three together.

.EXAMPLE
    . ./.template/Use-Node.ps1
#>
#Requires -Version 7.4

$nodeVersionFile = Join-Path $PSScriptRoot '../.node-version'
if (-not (Test-Path -LiteralPath $nodeVersionFile)) { throw "No .node-version at $nodeVersionFile; cannot choose a Node.js version." }
$nodeVersion = ([IO.File]::ReadAllLines($nodeVersionFile) | Select-Object -First 1).Trim()
if (-not $nodeVersion) { throw "$nodeVersionFile is empty; it must name a Node.js version." }

$nodeHasNvs = [bool](Get-Command nvs -ErrorAction Ignore)
if (-not $nodeHasNvs) {
    $nodeNvsHome = if ($env:NVS_HOME) { $env:NVS_HOME }
    elseif ($IsWindows) { Join-Path $env:LOCALAPPDATA 'nvs' }
    else { Join-Path $HOME '.nvs' }
    $nodeNvsScript = Join-Path $nodeNvsHome 'nvs.ps1'
    if (Test-Path -LiteralPath $nodeNvsScript) {
        $env:NVS_HOME = $nodeNvsHome
        . $nodeNvsScript
        $nodeHasNvs = $true
    }
}

if ($nodeHasNvs) {
    $global:LASTEXITCODE = 0
    nvs use $nodeVersion
    if (-not $? -or $LASTEXITCODE) {
        $global:LASTEXITCODE = 0
        nvs add $nodeVersion
        nvs use $nodeVersion
    }
    if (-not (Get-Command node -ErrorAction Ignore)) {
        throw "Node.js $nodeVersion is not on PATH after nvs use; run ./.template/Initialize-Nvs.ps1"
    }
}
else {
    # No nvs, as in CI and cloud sessions that install Node.js another way: accept the node on PATH when it matches.
    $nodeWanted = $nodeVersion -creplace '^v', ''
    $nodeActual = ''
    if (Get-Command node -ErrorAction Ignore) {
        try { $nodeActual = "$(node --version 2>$null | Select-Object -First 1)".Trim() -creplace '^v', '' } catch { $nodeActual = '' }
        $global:LASTEXITCODE = 0
    }
    if (-not $nodeActual -or ($nodeActual -cne $nodeWanted -and -not $nodeActual.StartsWith("$nodeWanted.", [StringComparison]::Ordinal))) {
        $nodeFound = if ($nodeActual) { $nodeActual } else { 'none' }
        $nodeInstall = if ($IsWindows) { 'winget install --id jasongin.nvs -e' } else { 'git clone https://github.com/jasongin/nvs "$HOME/.nvs"; . "$HOME/.nvs/nvs.sh" install' }
        throw "nvs is not installed: $nodeNvsScript does not exist, and the node on PATH ($nodeFound) is not the $nodeVersion that .node-version names. Install it with: $nodeInstall"
    }
}

Remove-Variable -Name nodeVersionFile, nodeVersion, nodeNvsHome, nodeNvsScript, nodeInstall, nodeHasNvs, nodeWanted, nodeActual, nodeFound -ErrorAction Ignore
