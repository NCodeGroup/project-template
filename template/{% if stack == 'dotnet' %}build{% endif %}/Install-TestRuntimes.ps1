<#
.SYNOPSIS
    Installs the .NET runtimes build/Get-TestRuntimes.ps1 names, beside the SDK's own.

.DESCRIPTION
    From the project template; template updates replace this file. For each channel, reads the release metadata at
    https://builds.dotnet.microsoft.com/dotnet/release-metadata/<major.minor>/releases.json and takes the ASP.NET Core
    runtime archive of the channel's latest release for this machine; it holds the .NET runtime too. Installs nothing
    unless the archive's SHA-512 equals the one in the metadata. Adds only the shared/<framework>/<version> folders to
    the installation, so the SDK's own host stays, and skips a version that is already there.

    .gitlab-ci.yml runs it before the build; on GitHub, actions/setup-dotnet installs the same channels. Run it as an
    administrator or with sudo when .NET is installed system-wide.

.PARAMETER Channel
    The channels to install, such as 8.0.x. Defaults to what build/Get-TestRuntimes.ps1 prints.

.PARAMETER InstallDir
    The .NET installation to add the runtimes to. Defaults to the installation that dotnet --list-runtimes shows for
    Microsoft.NETCore.App.

.EXAMPLE
    ./build/Install-TestRuntimes.ps1

.EXAMPLE
    ./build/Install-TestRuntimes.ps1 -Channel 8.0.x -InstallDir ~/.dotnet
#>
[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+(\.x)?$')]
    [string[]]$Channel,
    [string]$InstallDir
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if (-not $PSBoundParameters.ContainsKey('Channel')) {
    $Channel = @(& (Join-Path $PSScriptRoot 'Get-TestRuntimes.ps1'))
}
if (-not $Channel) { return }

if (-not $InstallDir) {
    $listed = @(dotnet --list-runtimes) | Where-Object { $_.StartsWith('Microsoft.NETCore.App ') -and $_ -match '\[(.+)\]$' } |
        Select-Object -First 1
    if (-not $listed) { throw 'dotnet --list-runtimes shows no Microsoft.NETCore.App: pass -InstallDir.' }
    $null = "$listed" -match '\[(.+)\]$'
    $InstallDir = Split-Path -Parent (Split-Path -Parent $Matches[1])
}
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

$os = if ($IsWindows) { 'win' } elseif ($IsMacOS) { 'osx' } elseif (Test-Path -LiteralPath '/etc/alpine-release') { 'linux-musl' } else { 'linux' }
$arch = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
$name = "aspnetcore-runtime-$os-$arch$(if ($IsWindows) { '.zip' } else { '.tar.gz' })"
$scratch = Join-Path $InstallDir ".install-test-runtimes-$PID"

try {
    foreach ($c in $Channel) {
        $number = $c -replace '\.x$', ''
        $metadata = Invoke-RestMethod "https://builds.dotnet.microsoft.com/dotnet/release-metadata/$number/releases.json"
        $release = @($metadata.releases | Where-Object { $_.'release-version' -eq $metadata.'latest-release' })[0]
        $version = $release.'release-version'
        $runtimeVersion = $release.runtime.version
        $aspNetVersion = $release.'aspnetcore-runtime'.version
        if ((Test-Path -LiteralPath (Join-Path $InstallDir "shared/Microsoft.NETCore.App/$runtimeVersion")) -and
            (Test-Path -LiteralPath (Join-Path $InstallDir "shared/Microsoft.AspNetCore.App/$aspNetVersion"))) {
            "Microsoft.NETCore.App $runtimeVersion and Microsoft.AspNetCore.App $aspNetVersion are already in $InstallDir"
            continue
        }

        $file = @($release.'aspnetcore-runtime'.files | Where-Object { $_.name -eq $name })[0]
        if (-not $file) { throw "Microsoft publishes no $name for .NET $version." }

        if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $scratch | Out-Null
        $archive = Join-Path $scratch $name
        Invoke-WebRequest -Uri $file.url -OutFile $archive
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA512).Hash -ne $file.hash) {
            throw "$name for .NET $version doesn't match the SHA-512 in Microsoft's release metadata; nothing was installed."
        }

        $content = Join-Path $scratch 'content'
        if ($IsWindows) {
            Expand-Archive -LiteralPath $archive -DestinationPath $content
        }
        else {
            New-Item -ItemType Directory -Force -Path $content | Out-Null
            tar -xzf $archive -C $content
            if ($LASTEXITCODE) { throw "tar -xzf $name failed with exit code $LASTEXITCODE." }
        }

        $shared = Join-Path $content 'shared'
        foreach ($framework in @(Get-ChildItem -LiteralPath $shared -Directory)) {
            foreach ($versionDir in @(Get-ChildItem -LiteralPath $framework.FullName -Directory)) {
                $target = Join-Path $InstallDir "shared/$($framework.Name)/$($versionDir.Name)"
                if (Test-Path -LiteralPath $target) { continue }
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
                Move-Item -LiteralPath $versionDir.FullName -Destination $target
                "Installed $($framework.Name) $($versionDir.Name) in $InstallDir"
            }
        }
        Remove-Item -LiteralPath $scratch -Recurse -Force
    }
}
finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
