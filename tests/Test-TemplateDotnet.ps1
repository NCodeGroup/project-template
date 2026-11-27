<#
.SYNOPSIS
    Render the template's .NET cases and check that the .NET layer builds, tests and packs.

.DESCRIPTION
    First runs the template's build/Install-Dotnet.ps1 in this process against stand-ins for Microsoft's release metadata and downloads, offline. Then runs build/Test-DotnetSupport.ps1 against a stand-in releases index, offline, and build/Get-TestRuntimes.ps1 on a fixture solution; the fixture solutions need dotnet on PATH. Renders the dotnet and dotnet-library-apache cases of tests\Test-Template.ps1 from a committed, tagged (v0.1.0) snapshot of the working tree in the work folder (-Work), checks that each fresh render passes dotnet csharpier check . before anything formats it, runs the .NET build checks on them, prints PASS or FAIL per check and exits 1 on any failure. With -SkipDotnetBuild it renders nothing and exits 0.

.EXAMPLE
    .\tests\Test-TemplateDotnet.ps1

.PARAMETER SkipDotnetBuild
    Render nothing and run no .NET check; exit 0.

.PARAMETER InstallerOnly
    Run only the offline checks of build/Install-Dotnet.ps1, build/Test-DotnetSupport.ps1 and build/Get-TestRuntimes.ps1: render nothing and build nothing.

.PARAMETER FormatOnly
    Run the installer checks, offline, then render the two cases and run only the check that each fresh render passes CSharpier's check: build nothing.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-dotnet-test-<process ID> in the temp folder, the
    run's own: deleted when every check passes, kept when one fails.
#>
[CmdletBinding()]
param(
    [switch]$SkipDotnetBuild,
    [switch]$InstallerOnly,
    [switch]$FormatOnly,
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-dotnet-test-$PID")
)
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
if ($SkipDotnetBuild) { 'Template .NET tests: skipped (-SkipDotnetBuild)'; exit 0 }
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}

# IDE0073 is a warning in a rendered project, so a C# file must start with the header its .editorconfig sets: prepend it, in the current folder's project, to a file without it.
function Add-FileHeader([string]$Path) {
    $template = [regex]::Match([IO.File]::ReadAllText((Join-Path (Get-Location) '.editorconfig')), '(?m)^file_header_template = (.+?)\r?$').Groups[1].Value
    if (-not $template) { throw "no file_header_template in $(Join-Path (Get-Location) '.editorconfig')" }
    $header = (($template -split '\\n') | ForEach-Object { "// $_" }) -join "`n"
    $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
    if (-not $text.StartsWith($header)) { $text = "$header`n`n$text" }
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }

$stubRoot = Join-Path $Work 'installer'
New-Item -ItemType Directory -Force -Path $stubRoot | Out-Null
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'template/build/Install-Dotnet.ps1'
$os = if ($IsWindows) { 'win' } elseif ($IsMacOS) { 'osx' } elseif (Test-Path -LiteralPath '/etc/alpine-release') { 'linux-musl' } else { 'linux' }
$arch = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
$suffix = "$os-$arch$(if ($IsWindows) { '.zip' } else { '.tar.gz' })"

function Invoke-StubInstaller {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Stand-ins for the installer''s network calls, seen only by the installer this function runs.')]
    param([hashtable]$Metadata, [hashtable]$Downloads, [hashtable]$Arguments, [hashtable]$Failures = @{}, [string[]]$ListedRuntimes = @())
    $calls = [Collections.Generic.List[string]]::new(); $sleeps = [Collections.Generic.List[int]]::new(); $byPath = $Metadata; $byUrl = $Downloads; $runtimeLines = $ListedRuntimes
    $pending = @{}
    foreach ($url in $Failures.Keys) { $pending[$url] = [Collections.Generic.Queue[object]]::new([object[]]$Failures[$url]) }
    # Every request must carry the installer's timeouts; a URL in -Failures throws its exceptions, one a call, before it answers.
    function Confirm-StubRequest([string]$Uri, [int]$ConnectionTimeoutSeconds, [int]$OperationTimeoutSeconds) {
        $calls.Add($Uri)
        if ($ConnectionTimeoutSeconds -ne 30 -or $OperationTimeoutSeconds -ne 60) { throw "no 30- and 60-second timeouts on $Uri" }
        if ($pending.ContainsKey($Uri) -and $pending[$Uri].Count) { throw $pending[$Uri].Dequeue() }
    }
    function Invoke-RestMethod([string]$Uri, [int]$ConnectionTimeoutSeconds, [int]$OperationTimeoutSeconds) { Confirm-StubRequest $Uri $ConnectionTimeoutSeconds $OperationTimeoutSeconds; $key = $Uri -replace '^.*/release-metadata/', ''; if (-not $byPath.ContainsKey($key)) { throw "unexpected metadata $Uri" }; $byPath[$key] | ConvertFrom-Json }
    function Invoke-WebRequest([string]$Uri, [string]$OutFile, [int]$ConnectionTimeoutSeconds, [int]$OperationTimeoutSeconds) { Confirm-StubRequest $Uri $ConnectionTimeoutSeconds $OperationTimeoutSeconds; if (-not $byUrl.ContainsKey($Uri)) { throw "unexpected download $Uri" }; [IO.File]::WriteAllBytes($OutFile, $byUrl[$Uri]) }
    function Start-Sleep([int]$Milliseconds) { $sleeps.Add($Milliseconds) }
    # The largest number Get-Random can give, so that each wait, with its random part, is known.
    function Get-Random([int]$Maximum) { $Maximum - 1 }
    function dotnet { if ("$args" -ne '--list-runtimes') { throw "unexpected dotnet $args" }; $runtimeLines }
    $printed = ''; $failed = ''
    try { $printed = (& $installer @Arguments 2>&1 | Out-String).Trim() } catch { $failed = "$_" }
    [pscustomobject]@{ Printed = $printed; Calls = @($calls); Sleeps = @($sleeps); Error = $failed }
}

function New-StubSdk([string]$Version, [object[]]$Files = @()) {
    @{ version = $Version; files = $Files }
}

function New-StubChannel([string]$Release, [object[]]$Sdks, [object[]]$RuntimeFiles = @()) {
    ConvertTo-Json -Depth 10 @{ 'latest-release' = $Release; releases = @(@{ 'release-version' = $Release; runtime = @{ version = $Release }; 'aspnetcore-runtime' = @{ version = $Release; files = $RuntimeFiles }; sdks = $Sdks }) }
}

function New-StubInstallDir([string]$Name, [string[]]$Sdks = @(), [switch]$NoRuntime) {
    $dir = Join-Path $stubRoot $Name
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    foreach ($version in $Sdks) { New-Item -ItemType Directory -Force -Path (Join-Path $dir "sdk/$version") | Out-Null }
    if (-not $NoRuntime) {
        New-Item -ItemType Directory -Force -Path (Join-Path $dir 'shared/Microsoft.NETCore.App/8.0.11') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $dir 'shared/Microsoft.AspNetCore.App/8.0.11') | Out-Null
    }
    $dir
}

$dir = New-StubInstallDir 'sha'
$globalJson = Join-Path $stubRoot 'sha.json'
[IO.File]::WriteAllText($globalJson, '{"sdk":{"version":"8.0.404"}}')
$sdkUrl = 'https://stub.invalid/dotnet-sdk'
$r = Invoke-StubInstaller @{ '8.0/releases.json' = New-StubChannel '8.0.11' @(New-StubSdk '8.0.404' @(@{ name = "dotnet-sdk-$suffix"; url = $sdkUrl; hash = ('0' * 128) })) } @{ $sdkUrl = [Text.Encoding]::UTF8.GetBytes('not the archive the metadata describes') } @{ GlobalJson = $globalJson; InstallDir = $dir; Channel = '8.0' }
Check 'installer: build/Install-Dotnet.ps1 refuses an archive whose SHA-512 differs from the release metadata''s, installs nothing and leaves no scratch folder' ($r.Error.Contains("doesn't match the SHA-512") -and $r.Calls -contains $sdkUrl -and -not (Test-Path -LiteralPath (Join-Path $dir 'sdk')) -and -not @(Get-ChildItem -LiteralPath $dir -Force -Filter '.install-dotnet-*')) "$($r.Error) | $($r.Printed)"

$selectMetadata = @{
    'releases-index.json' = @{ 'releases-index' = @(@{ 'channel-version' = '8.0'; 'latest-sdk' = '8.0.404' }, @{ 'channel-version' = '10.0'; 'latest-sdk' = '10.0.100' }, @{ 'channel-version' = '11.0'; 'latest-sdk' = '11.0.100-preview.1.25000.1' }) } | ConvertTo-Json -Depth 5
    '8.0/releases.json' = New-StubChannel '8.0.11' @((New-StubSdk '8.0.100'), (New-StubSdk '8.0.110'), (New-StubSdk '8.0.300'), (New-StubSdk '8.0.404'))
    '10.0/releases.json' = New-StubChannel '10.0.0' @((New-StubSdk '10.0.100-rc.1.25451.107'), (New-StubSdk '10.0.100'))
    '11.0/releases.json' = New-StubChannel '11.0.0-preview.1' @(New-StubSdk '11.0.100-preview.1.25000.1')
}
$selectInstalled = '8.0.100', '8.0.110', '8.0.300', '8.0.404', '10.0.100-rc.1.25451.107', '10.0.100', '11.0.100-preview.1.25000.1'
$selectCases = @(
    @('8.0.100', '', '8.0.100'),
    @('8.0.100', 'disable', '8.0.100'),
    @('8.0.100', 'latestPatch', '8.0.110'),
    @('8.0.100', 'latestFeature', '8.0.404'),
    @('8.0.100', 'latestMinor', '8.0.404'),
    @('8.0.100', 'latestMajor', '10.0.100'),
    @('10.0.100-rc.1.25451.107', 'latestFeature', '10.0.100-rc.1.25451.107')
)
$misses = [Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $selectCases.Count; $i++) {
    $version, $rollForward, $expected = $selectCases[$i]
    $dir = New-StubInstallDir "select$i" $selectInstalled
    $sdkSetting = @{ version = $version }
    if ($rollForward) { $sdkSetting.rollForward = $rollForward }
    $globalJson = Join-Path $stubRoot "select$i.json"
    [IO.File]::WriteAllText($globalJson, (@{ sdk = $sdkSetting } | ConvertTo-Json))
    $r = Invoke-StubInstaller $selectMetadata @{} @{ GlobalJson = $globalJson; InstallDir = $dir; Channel = '8.0' }
    if ($r.Error -or -not $r.Printed.Contains(".NET SDK $expected is already in")) { $misses.Add("$version ${rollForward}: $($r.Error)$($r.Printed)") }
}
Check 'installer: build/Install-Dotnet.ps1 selects the SDK global.json names, or the newest its rollForward policy allows' (-not $misses) ($misses -join ' | ')

$errorMetadata = @{ '8.0/releases.json' = New-StubChannel '8.0.11' @((New-StubSdk '8.0.100'), (New-StubSdk '8.0.404')) }
$errorCases = @(
    @{ Name = 'error1'; Version = '8.0'; Expect = 'names no full SDK version' },
    @{ Name = 'error2'; Version = '8.0.999'; Expect = 'lists no .NET SDK that' },
    @{ Name = 'error3'; Version = '8.0.404'; Expect = "Microsoft publishes no dotnet-sdk-$suffix for .NET SDK 8.0.404" },
    @{ Name = 'error4'; NoRuntime = $true; Expect = "Microsoft publishes no aspnetcore-runtime-$suffix for .NET 8.0.11" }
)
$misses = [Collections.Generic.List[string]]::new()
foreach ($case in $errorCases) {
    $dir = New-StubInstallDir $case.Name -NoRuntime:([bool]$case.NoRuntime)
    if ($case.NoRuntime) {
        $arguments = @{ SkipSdk = $true; InstallDir = $dir; Channel = '8.0' }
    }
    else {
        $globalJson = Join-Path $stubRoot "$($case.Name).json"
        [IO.File]::WriteAllText($globalJson, (@{ sdk = @{ version = $case.Version } } | ConvertTo-Json))
        $arguments = @{ GlobalJson = $globalJson; InstallDir = $dir; Channel = '8.0' }
    }
    $r = Invoke-StubInstaller $errorMetadata @{} $arguments
    if (-not $r.Error.Contains($case.Expect) -or (Test-Path -LiteralPath (Join-Path $dir 'sdk')) -or @(Get-ChildItem -LiteralPath $dir -Force -Filter '.install-dotnet-*')) { $misses.Add("$($case.Name): $($r.Error)") }
}
Check 'installer: build/Install-Dotnet.ps1 stops with its own error when global.json or the release metadata gives it nothing to install' (-not $misses) ($misses -join ' | ')

$archiveSource = Join-Path $stubRoot 'archive-src'
New-Item -ItemType Directory -Force -Path (Join-Path $archiveSource 'sdk/8.0.404') | Out-Null
[IO.File]::WriteAllText((Join-Path $archiveSource 'dotnet'), 'from the archive')
[IO.File]::WriteAllText((Join-Path $archiveSource 'sdk/8.0.404/marker'), 'sdk')
$archive = Join-Path $stubRoot "stub-dotnet-sdk-$suffix"
if ($IsWindows) { Compress-Archive -Path (Join-Path $archiveSource '*') -DestinationPath $archive }
else { tar -czf $archive -C $archiveSource . }
$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA512).Hash
$dir = New-StubInstallDir 'merge'
[IO.File]::WriteAllText((Join-Path $dir 'dotnet'), 'already there')
$globalJson = Join-Path $stubRoot 'merge.json'
[IO.File]::WriteAllText($globalJson, '{"sdk":{"version":"8.0.404"}}')
$r = Invoke-StubInstaller @{ '8.0/releases.json' = New-StubChannel '8.0.11' @(New-StubSdk '8.0.404' @(@{ name = "dotnet-sdk-$suffix"; url = $sdkUrl; hash = $archiveHash })) } @{ $sdkUrl = [IO.File]::ReadAllBytes($archive) } @{ GlobalJson = $globalJson; InstallDir = $dir; Channel = '8.0' }
Check 'installer: build/Install-Dotnet.ps1 adds the files of a verified SDK archive that the installation lacks and replaces none' (-not $r.Error -and $r.Printed.Contains('Installed .NET SDK 8.0.404 in') -and [IO.File]::ReadAllText((Join-Path $dir 'dotnet')) -eq 'already there' -and [IO.File]::ReadAllText((Join-Path $dir 'sdk/8.0.404/marker')) -eq 'sdk' -and -not @(Get-ChildItem -LiteralPath $dir -Force -Filter '.install-dotnet-*')) "$($r.Error) | $($r.Printed)"

$dir = New-StubInstallDir 'listed'
$listedRuntimes = "Microsoft.AspNetCore.App 8.0.11 [$([IO.Path]::Combine($dir, 'shared', 'Microsoft.AspNetCore.App'))]", "Microsoft.NETCore.App 8.0.11 [$([IO.Path]::Combine($dir, 'shared', 'Microsoft.NETCore.App'))]"
$listed = Invoke-StubInstaller @{ '8.0/releases.json' = New-StubChannel '8.0.11' @() } @{} @{ SkipSdk = $true; Channel = '8.0' } -ListedRuntimes $listedRuntimes
$unlisted = Invoke-StubInstaller @{} @{} @{ SkipSdk = $true; Channel = '8.0' } -ListedRuntimes $listedRuntimes[0]
Check 'installer: build/Install-Dotnet.ps1 without -InstallDir adds to the installation dotnet --list-runtimes shows for Microsoft.NETCore.App, and stops when it shows none' (-not $listed.Error -and $listed.Printed.Contains("are already in $dir") -and $unlisted.Error.Contains('dotnet --list-runtimes shows no Microsoft.NETCore.App')) "$($listed.Error) $($listed.Printed) | $($unlisted.Error)"

$metadataUrl = 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/8.0/releases.json'
$mergeMetadata = @{ '8.0/releases.json' = New-StubChannel '8.0.11' @(New-StubSdk '8.0.404' @(@{ name = "dotnet-sdk-$suffix"; url = $sdkUrl; hash = $archiveHash })) }
# An HttpResponseException as Invoke-RestMethod and Invoke-WebRequest throw it, with a Retry-After header when given
# one: a TimeSpan for a number of seconds, a DateTimeOffset for a date.
function New-StubHttpError([Net.HttpStatusCode]$Status, [object]$RetryAfter) {
    $response = [Net.Http.HttpResponseMessage]::new($Status)
    if ($RetryAfter) { $response.Headers.RetryAfter = [Net.Http.Headers.RetryConditionHeaderValue]::new($RetryAfter) }
    [Microsoft.PowerShell.Commands.HttpResponseException]::new("Response status code does not indicate success: $([int]$Status) ($($response.ReasonPhrase)).", $response)
}
$unavailable = New-StubHttpError ServiceUnavailable
$rateLimited = New-StubHttpError TooManyRequests
$timedOut = New-StubHttpError RequestTimeout
$notFound = New-StubHttpError NotFound
$rateLimitedFor20 = New-StubHttpError TooManyRequests ([TimeSpan]::FromSeconds(20))
$unavailableForAnHour = New-StubHttpError ServiceUnavailable ([DateTimeOffset]::UtcNow.AddHours(1))
# What Invoke-WebRequest throws when -OperationTimeoutSeconds ends a download that stalls partway.
$stalled = [AggregateException]::new([TimeoutException]::new('The request was canceled due to the configured OperationTimeout of 60 seconds elapsing'))
$dir = New-StubInstallDir 'retry'
$retried = Invoke-StubInstaller $mergeMetadata @{ $sdkUrl = [IO.File]::ReadAllBytes($archive) } @{ GlobalJson = $globalJson; InstallDir = $dir; Channel = '8.0' } @{ $metadataUrl = @($unavailable, $timedOut); $sdkUrl = @($stalled, $rateLimitedFor20) }
$retriedOk = -not $retried.Error -and $retried.Printed.Contains('Installed .NET SDK 8.0.404 in') -and @($retried.Calls | Where-Object { $_ -eq $metadataUrl }).Count -eq 4 -and @($retried.Calls | Where-Object { $_ -eq $sdkUrl }).Count -eq 3 -and ($retried.Sleeps -join ',') -eq '5999,10999,5999,20999'
$dir = New-StubInstallDir 'throttled'
$throttled = Invoke-StubInstaller $mergeMetadata @{} @{ SkipSdk = $true; InstallDir = $dir; Channel = '8.0' } @{ $metadataUrl = @($rateLimited, $unavailableForAnHour) }
$throttledOk = -not $throttled.Error -and $throttled.Calls.Count -eq 3 -and ($throttled.Sleeps -join ',') -eq '5999,60999'
$dir = New-StubInstallDir 'unavailable'
$gaveUp = Invoke-StubInstaller $mergeMetadata @{} @{ GlobalJson = $globalJson; InstallDir = $dir; Channel = '8.0' } @{ $metadataUrl = @($unavailable, $unavailable, $unavailable) }
$gaveUpOk = $gaveUp.Error.Contains('503') -and $gaveUp.Calls.Count -eq 3 -and ($gaveUp.Sleeps -join ',') -eq '5999,10999' -and -not (Test-Path -LiteralPath (Join-Path $dir 'sdk'))
$dir = New-StubInstallDir 'notfound'
$missing = Invoke-StubInstaller $mergeMetadata @{} @{ GlobalJson = $globalJson; InstallDir = $dir; Channel = '8.0' } @{ $metadataUrl = @($notFound) }
$missingOk = $missing.Error.Contains('404') -and $missing.Calls.Count -eq 1 -and -not $missing.Sleeps
Check 'installer: build/Install-Dotnet.ps1 gives every request a 30-second answer and 60-second stall timeout, tries a failed or stalled one twice more, 5 and then 10 seconds later, or after the Retry-After of a 429 or 503 up to 60 seconds, each plus up to a second at random, retries a 408, and fails at once on a 404' ($retriedOk -and $throttledOk -and $gaveUpOk -and $missingOk) "$($retried.Error) $($retried.Calls -join ',') $($retried.Sleeps -join ',') | $($throttled.Error) $($throttled.Sleeps -join ',') | $($gaveUp.Error) $($gaveUp.Sleeps -join ',') | $($missing.Error) $($missing.Calls.Count)"
$support = Join-Path (Split-Path -Parent $PSScriptRoot) 'template/build/Test-DotnetSupport.ps1'
$supportIndex = Join-Path $stubRoot 'releases-index.json'
[IO.File]::WriteAllText($supportIndex, (@{ 'releases-index' = @(
            @{ 'channel-version' = '10.0'; 'release-type' = 'lts'; 'support-phase' = 'active'; 'eol-date' = '2028-11-14' },
            @{ 'channel-version' = '11.0'; 'release-type' = 'sts'; 'support-phase' = 'active'; 'eol-date' = '2028-11-14' },
            @{ 'channel-version' = '8.0'; 'release-type' = 'lts'; 'support-phase' = 'eol'; 'eol-date' = '2026-11-10' },
            @{ 'channel-version' = '6.0'; 'release-type' = 'lts'; 'support-phase' = 'maintenance'; 'eol-date' = '2027-05-11' },
            @{ 'channel-version' = '12.0'; 'release-type' = 'lts'; 'support-phase' = 'preview'; 'eol-date' = '2031-11-11' }
        ) } | ConvertTo-Json -Depth 5))

function Invoke-Support([string]$Sdk, [string]$GitHubActions = '', [switch]$WarnOnly, [string]$Name = '', [hashtable]$Files = @{}) {
    $dir = Join-Path $stubRoot "support-$Sdk-$GitHubActions-$([int][bool]$WarnOnly)-$Name"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    if ($Sdk) { [IO.File]::WriteAllText((Join-Path $dir 'global.json'), "{`"sdk`":{`"version`":`"$Sdk`"}}") }
    if ($Files.Count) {
        foreach ($path in $Files.Keys) {
            $file = Join-Path $dir $path
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
            [IO.File]::WriteAllText($file, $Files[$path])
        }
        Push-Location $dir
        try {
            dotnet new sln -n Fixture --no-update-check | Out-Null
            dotnet sln add @($Files.Keys | Where-Object { $_.EndsWith('.csproj') }) | Out-Null
        }
        finally { Pop-Location }
    }
    $arguments = @('-NoProfile', '-File', $support, '-Root', $dir, '-ReleasesIndex', $supportIndex)
    if ($WarnOnly) { $arguments += '-WarnOnly' }
    $previous = $env:GITHUB_ACTIONS
    $env:GITHUB_ACTIONS = $GitHubActions
    try {
        $printed = (pwsh @arguments 2>&1 | Out-String).Trim()
        [pscustomobject]@{ Printed = $printed; ExitCode = $LASTEXITCODE }
    }
    finally { $env:GITHUB_ACTIONS = $previous }
}

$r = Invoke-Support '10.0.100'
Check 'support: build/Test-DotnetSupport.ps1 passes an active LTS pinned in global.json' ($r.ExitCode -eq 0 -and $r.Printed.Contains('10.0 (global.json): LTS, supported until 2028-11-14') -and $r.Printed.Contains('.NET support: PASSED')) $r.Printed
$r = Invoke-Support '11.0.100'
Check 'support: build/Test-DotnetSupport.ps1 fails a Standard Term Support release' ($r.ExitCode -eq 1 -and $r.Printed.Contains('Error: .NET 11.0 (global.json) is a Standard Term Support release') -and $r.Printed.Contains('.NET support: FAILED (1)')) $r.Printed
$r = Invoke-Support '8.0.404'
Check 'support: build/Test-DotnetSupport.ps1 fails an LTS release past its end of support' ($r.ExitCode -eq 1 -and $r.Printed.Contains('Error: .NET 8.0 (global.json) reached its end of support on 2026-11-10')) $r.Printed
$r = Invoke-Support '6.0.100'
Check 'support: build/Test-DotnetSupport.ps1 warns, without failing, for an LTS release in maintenance' ($r.ExitCode -eq 0 -and $r.Printed.Contains('Warning: .NET 6.0 (global.json) ends its support on 2027-05-11')) $r.Printed
$warned = Invoke-Support '6.0.100' 'true'
$errored = Invoke-Support '8.0.404' 'true'
Check 'support: build/Test-DotnetSupport.ps1 prints workflow annotations on GitHub Actions' ($warned.Printed.Contains('::warning::.NET 6.0 (global.json)') -and $errored.Printed.Contains('::error::.NET 8.0 (global.json)')) "$($warned.Printed) | $($errored.Printed)"
$r = Invoke-Support '8.0.404' -WarnOnly
Check 'support: build/Test-DotnetSupport.ps1 reports a failure as a warning and exits 0 with -WarnOnly' ($r.ExitCode -eq 0 -and $r.Printed.Contains('Warning: .NET 8.0 (global.json) reached its end of support') -and $r.Printed.Contains('.NET support: PASSED')) $r.Printed
$r = Invoke-Support '99.0.100'
Check 'support: build/Test-DotnetSupport.ps1 fails a channel Microsoft''s release metadata lacks' ($r.ExitCode -eq 1 -and $r.Printed.Contains('Microsoft''s release metadata lists no .NET 99.0 (global.json).')) $r.Printed
$r = Invoke-Support ''
Check 'support: build/Test-DotnetSupport.ps1 passes a repository without global.json' ($r.ExitCode -eq 0 -and $r.Printed.Contains('.NET support: PASSED')) $r.Printed
# MSBuild writes an evaluation warning, here MSB4011 naming a path with a brace, to stderr: the script must parse only the JSON on stdout.
$r = Invoke-Support '' -Name 'braces' -Files @{ 'src/Braces/Braces{1}.props' = '<Project />'; 'src/Braces/Braces.csproj' = '<Project Sdk="Microsoft.NET.Sdk"><Import Project="Braces{1}.props" /><Import Project="Braces{1}.props" /><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>' }
Check 'support: build/Test-DotnetSupport.ps1 reads the target frameworks of a project MSBuild warns about, parsing only the JSON on stdout' ($r.ExitCode -eq 0 -and $r.Printed.Contains('10.0 (src/Braces/Braces.csproj): LTS, supported until 2028-11-14') -and $r.Printed.Contains('.NET support: PASSED')) $r.Printed
$r = Invoke-Support '12.0.100-preview.1.26000.1'
Check 'support: build/Test-DotnetSupport.ps1 fails a release in a phase other than active or maintenance, such as preview' ($r.ExitCode -eq 1 -and $r.Printed.Contains('Error: .NET 12.0 (global.json) is a preview release, not one Microsoft supports') -and $r.Printed.Contains('.NET support: FAILED (1)')) $r.Printed
$r = Invoke-Support '' -Name 'multi' -Files @{ 'src/Multi/Multi.csproj' = '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFrameworks>net10.0;netstandard2.0;net48</TargetFrameworks></PropertyGroup></Project>' }
Check 'support: build/Test-DotnetSupport.ps1 checks only the net channel of a project that also targets netstandard2.0 and net48' ($r.ExitCode -eq 0 -and $r.Printed.Contains('10.0 (src/Multi/Multi.csproj): LTS, supported until 2028-11-14') -and -not $r.Printed.Contains('lists no') -and @($r.Printed -split "`n" | Where-Object { $_ -match '^\d+\.\d+ \(' }).Count -eq 1 -and $r.Printed.Contains('.NET support: PASSED')) $r.Printed
# build/Get-TestRuntimes.ps1 reads a test project MSBuild warns about: MSB4011, naming a path with a brace, goes to stderr, and the script must parse only the JSON on stdout.
$runtimesRoot = Join-Path $stubRoot 'runtimes-braces'
New-Item -ItemType Directory -Force -Path (Join-Path $runtimesRoot 'build') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $runtimesRoot 'tests/Braces.Tests') | Out-Null
Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'template/build/Get-TestRuntimes.ps1') -Destination (Join-Path $runtimesRoot 'build')
[IO.File]::WriteAllText((Join-Path $runtimesRoot 'tests/Braces.Tests/Braces{1}.props'), '<Project />')
[IO.File]::WriteAllText((Join-Path $runtimesRoot 'tests/Braces.Tests/Braces.Tests.csproj'), '<Project Sdk="Microsoft.NET.Sdk"><Import Project="Braces{1}.props" /><Import Project="Braces{1}.props" /><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup></Project>')
Push-Location $runtimesRoot
try {
    dotnet new sln -n Fixture --no-update-check | Out-Null
    dotnet sln add tests/Braces.Tests/Braces.Tests.csproj | Out-Null
    $runtimes = @(pwsh -NoProfile -File build/Get-TestRuntimes.ps1 2>&1 | ForEach-Object { "$_" })
    $runtimesCode = $LASTEXITCODE
}
finally { Pop-Location }
Check 'runtimes: build/Get-TestRuntimes.ps1 reads the target frameworks of a test project MSBuild warns about, parsing only the JSON on stdout' ($runtimesCode -eq 0 -and ($runtimes -join ',') -eq '8.0.x') ($runtimes -join "`n")
if ($InstallerOnly) {
    ''
    if ($failures.Count) { "Kept the work folder: $Work"; "Template .NET tests: FAILED ($($failures.Count))"; exit 1 }
    if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
    'Template .NET tests: PASSED'
    exit 0
}

$tpl = Join-Path $Work 'template-repo'
$tplUrl = & (Join-Path $PSScriptRoot 'New-TemplateSnapshot.ps1') $tpl
$copierCommand = @(if (Get-Command copier -ErrorAction SilentlyContinue) { 'copier' } elseif (Get-Command uvx -ErrorAction SilentlyContinue) { 'uvx', '--from', 'copier', 'copier' } else { throw 'Copier not found. Install it with: uv tool install copier' })
$exe = $copierCommand[0]
$prefix = @($copierCommand | Select-Object -Skip 1)
# A direct run keeps its Copier mirror in its own work folder, not in the user's cache; under tests\Invoke-AllTests.ps1 it keeps the runner's folder.
$copierCache = $env:COPIER_CACHE_DIR
if (-not $copierCache) { $env:COPIER_CACHE_DIR = Join-Path $Work 'copier-cache' }
# These answers repeat the dotnet and dotnet-library-apache cases of $cases in tests\Test-Template.ps1: change both together.
try {
    $output = & $exe @prefix copy --defaults --quiet --vcs-ref v0.1.0 --data "project_name=Test dotnet" --data 'stack=dotnet' --data 'git_host=github' --data "workflow_tools=[claude, copilot, local]" $tplUrl (Join-Path $Work 'dotnet') 2>&1 | Out-String
    if ($LASTEXITCODE) { throw "copier copy for dotnet exited with code ${LASTEXITCODE}: $($output.Trim())" }
    $output = & $exe @prefix copy --defaults --quiet --vcs-ref v0.1.0 --data "project_name=Test dotnet-library-apache" --data 'stack=dotnet' --data 'git_host=github' --data "workflow_tools=[claude, copilot]" --data 'nuget_package=true' --data 'license=Apache-2.0' $tplUrl (Join-Path $Work 'dotnet-library-apache') 2>&1 | Out-String
    if ($LASTEXITCODE) { throw "copier copy for dotnet-library-apache exited with code ${LASTEXITCODE}: $($output.Trim())" }
}
finally { $env:COPIER_CACHE_DIR = $copierCache }
# Each fresh render passes CSharpier's check before anything formats it: the template renders every file CSharpier checks in the form CSharpier prints it. CSharpier checks exactly Directory.Build.props and Directory.Packages.props, because .csharpierignore skips the template-owned build/ProjectTemplate.props and nuget.config, so a file that drops out of the check fails it.
foreach ($case in 'dotnet', 'dotnet-library-apache') {
    Push-Location (Join-Path $Work $case)
    try {
        $restoreOutput = dotnet tool restore 2>&1 | Out-String
        if ($LASTEXITCODE) { throw "dotnet tool restore for ${case} exited with code ${LASTEXITCODE}: $($restoreOutput.Trim())" }
        $formatOutput = dotnet csharpier check . 2>&1 | Out-String
        $formatExit = $LASTEXITCODE
    }
    finally { Pop-Location }
    $checked = if ($formatOutput -match 'Checked (\d+) files') { [int]$Matches[1] } else { 0 }
    Check "${case}: a fresh render passes CSharpier's check before anything formats it" ($formatExit -eq 0 -and $checked -eq 2) $formatOutput
}
if ($FormatOnly) {
    ''
    if ($failures.Count) { "Kept the work folder: $Work"; "Template .NET tests: FAILED ($($failures.Count))"; exit 1 }
    if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
    'Template .NET tests: PASSED'
    exit 0
}
Push-Location (Join-Path $Work 'dotnet')
try {
    dotnet new classlib -o src/Demo | Out-Null
    dotnet new xunit -o tests/Demo.Tests --no-restore | Out-Null
    foreach ($scaffolded in 'src/Demo/Class1.cs', 'tests/Demo.Tests/UnitTest1.cs') { Add-FileHeader (Join-Path (Get-Location) $scaffolded) }
    # As AGENTS.md tells the executor: move the template's PackageReference versions into Directory.Packages.props.
    $projPath = (Resolve-Path 'tests/Demo.Tests/Demo.Tests.csproj').Path
    $proj = [xml](Get-Content -LiteralPath $projPath -Raw)
    $versions = foreach ($ref in $proj.SelectNodes('//PackageReference[@Version]')) {
        "    <PackageVersion Include=""$($ref.Include)"" Version=""$($ref.Version)"" />"
        $ref.RemoveAttribute('Version')
    }
    $proj.Save($projPath)
    $propsPath = (Resolve-Path 'Directory.Packages.props').Path
    $props = [IO.File]::ReadAllText($propsPath) -replace '(?s)  <ItemGroup>\s*</ItemGroup>', ("  <ItemGroup>`n" + ($versions -join "`n") + "`n  </ItemGroup>")
    [IO.File]::WriteAllText($propsPath, $props)
    dotnet add tests/Demo.Tests reference src/Demo | Out-Null
    # As AGENTS.md tells the executor: every project joins the root solution, so the default commands cover it.
    dotnet new sln | Out-Null
    dotnet sln add src/Demo tests/Demo.Tests | Out-Null
    $output = dotnet build 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { $output = dotnet test 2>&1 | Out-String }
    $errors = ($output -split "`n" | Select-String -Pattern ' error ' | Select-Object -First 3) -join ' | '
    Check 'dotnet: classlib and xunit in the root solution pass dotnet build and dotnet test' ($LASTEXITCODE -eq 0) $errors

    # A malformed or mistyped entry in build/BannedSymbols.txt bans nothing, silently: a bare M:Type.Method matches only
    # the overload without parameters. Each probe line calls one banned method or property overload, and every line
    # must fail the build with RS0030; the type entries (Newtonsoft.Json) need the package, so they are checked by form.
    $entries = @(Get-Content -LiteralPath 'build/BannedSymbols.txt' | Where-Object { $_ -and -not $_.StartsWith('#') })
    $malformed = @($entries | Where-Object { $_ -notmatch '^[TMPFE]:[^;\s]+;\S.*$' })
    Check 'dotnet: every banned symbol is a documentation ID with a message' ($entries.Count -gt 0 -and -not $malformed) ($malformed -join ' | ')
    $calls = @(
        '_ = t.Result;', '_ = vt.Result;', 'task.Wait();', 'task.Wait(1);', 'task.Wait(TimeSpan.Zero);', 'task.Wait(CancellationToken.None);',
        'task.Wait(1, CancellationToken.None);', 'task.Wait(TimeSpan.Zero, CancellationToken.None);', 'Task.WaitAll(tasks);', 'Task.WaitAll(task);',
        'Task.WaitAll(tasks, TimeSpan.Zero);', 'Task.WaitAll(tasks, 1);', 'Task.WaitAll(tasks, CancellationToken.None);', 'Task.WaitAll(tasks, 1, CancellationToken.None);',
        'Task.WaitAll(new List<Task> { task }, CancellationToken.None);', 'Task.WaitAny(tasks);', 'Task.WaitAny(tasks, TimeSpan.Zero);', 'Task.WaitAny(tasks, CancellationToken.None);',
        'Task.WaitAny(tasks, 1);', 'Task.WaitAny(tasks, 1, CancellationToken.None);', 'task.GetAwaiter().GetResult();', '_ = t.GetAwaiter().GetResult();',
        'v.GetAwaiter().GetResult();', '_ = vt.GetAwaiter().GetResult();', 'JsonDocument.Parse("{}").Dispose();', 'JsonDocument.Parse(new ReadOnlyMemory<byte>([])).Dispose();',
        'JsonDocument.Parse("{}".AsMemory()).Dispose();', 'JsonDocument.Parse(new ReadOnlySequence<byte>([])).Dispose();', 'JsonDocument.Parse(stream).Dispose();',
        '_ = JsonDocument.ParseAsync(stream);', 'JsonDocument.ParseValue(ref reader).Dispose();', '_ = JsonDocument.TryParseValue(ref reader, out _);')
    $methodEntries = @($entries | Where-Object { $_ -match '^[MP]:' })
    $probe = "using System.Buffers;`nusing System.Text.Json;`n`nnamespace Demo;`n`ninternal static class BannedProbe`n{`n    public static void Run(Task task, Task<int> t, ValueTask<int> vt, ValueTask v, Stream stream)`n    {`n        Task[] tasks = [task];`n        var reader = new Utf8JsonReader(""{}""u8);`n" + (($calls | ForEach-Object { "        $_" }) -join "`n") + "`n    }`n}`n"
    $first = 12
    [IO.File]::WriteAllText((Join-Path (Get-Location) 'src/Demo/BannedProbe.cs'), $probe)
    try { $probeOutput = dotnet build src/Demo 2>&1 | Out-String }
    finally { [IO.File]::Delete((Join-Path (Get-Location) 'src/Demo/BannedProbe.cs')) }
    $hitLines = @([regex]::Matches($probeOutput, 'BannedProbe\.cs\((\d+),\d+\): error RS0030') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique)
    $missed = @(for ($i = 0; $i -lt $calls.Count; $i++) { if (($first + $i) -notin $hitLines) { $calls[$i] } })
    Check 'dotnet: every banned method and property overload fails the build with RS0030' ($calls.Count -eq $methodEntries.Count -and -not $missed) "$($calls.Count) probe calls for $($methodEntries.Count) method and property entries; not banned: $($missed -join ' ')"

    # The null-forgiving operator fails the build outside test projects.
    [IO.File]::WriteAllText((Join-Path (Get-Location) 'src/Demo/Forgiving.cs'), "namespace Demo;`n`ninternal static class Forgiving`n{`n    public static int Length(string? text) => text!.Length;`n}`n")
    try { $forgivingOutput = dotnet build src/Demo 2>&1 | Out-String }
    finally { [IO.File]::Delete((Join-Path (Get-Location) 'src/Demo/Forgiving.cs')) }
    Check 'dotnet: the null-forgiving operator fails the build' ($forgivingOutput -match 'Forgiving\.cs\(\d+,\d+\): error NX000\d') (($forgivingOutput -split "`n" | Select-String -Pattern ' error ' | Select-Object -First 3) -join ' | ')

    # An xUnit v3 project on VSTest, as .github/instructions/csharp-tests.instructions.md says: xunit.v3.mtp-off with xunit.runner.visualstudio and Microsoft.NET.Test.Sdk.
    $tfm = [regex]::Match((Get-Content -Raw -LiteralPath src/Demo/Demo.csproj), '<TargetFramework>([^<]+)</TargetFramework>').Groups[1].Value
    New-Item -ItemType Directory -Force tests/Demo.V3.Tests | Out-Null
    [IO.File]::WriteAllText((Join-Path (Get-Location) 'tests/Demo.V3.Tests/Demo.V3.Tests.csproj'), "<Project Sdk=""Microsoft.NET.Sdk"">`n  <PropertyGroup>`n    <TargetFramework>$tfm</TargetFramework>`n    <OutputType>Exe</OutputType>`n  </PropertyGroup>`n  <ItemGroup>`n    <PackageReference Include=""xunit.v3.mtp-off"" />`n    <PackageReference Include=""xunit.runner.visualstudio"" />`n    <PackageReference Include=""Microsoft.NET.Test.Sdk"" />`n  </ItemGroup>`n  <ItemGroup>`n    <ProjectReference Include=""../../src/Demo/Demo.csproj"" />`n  </ItemGroup>`n</Project>`n")
    [IO.File]::WriteAllText((Join-Path (Get-Location) 'tests/Demo.V3.Tests/V3Tests.cs'), "namespace Demo.V3.Tests;`n`npublic class V3Tests`n{`n    [Xunit.Fact]`n    public void Passes_WhenRun_Succeeds() => Xunit.Assert.True(true);`n}`n")
    Add-FileHeader (Join-Path (Get-Location) 'tests/Demo.V3.Tests/V3Tests.cs')
    $props = [IO.File]::ReadAllText($propsPath) `
        -replace '(<PackageVersion Include="Microsoft\.NET\.Test\.Sdk" Version=")[^"]*', '${1}18.12.0' `
        -replace '(<PackageVersion Include="xunit\.runner\.visualstudio" Version=")[^"]*', '${1}4.0.1' `
        -replace '(?m)^(\s*<PackageVersion Include="xunit" Version="[^"]*" />)\r?$', "`$1`n    <PackageVersion Include=""xunit.v3.mtp-off"" Version=""4.0.3"" />"
    [IO.File]::WriteAllText($propsPath, $props)
    dotnet sln add tests/Demo.V3.Tests | Out-Null

    # The scaffolded and test-written files are not yet formatted, and the Format stage would fail on them.
    dotnet tool restore | Out-Null
    dotnet csharpier format . | Out-Null
    $dodOutput = pwsh -NoProfile -File build/dod.ps1 2>&1 | Out-String
    Check 'dotnet: build/dod.ps1 passes and says so' ($LASTEXITCODE -eq 0 -and $dodOutput.TrimEnd().EndsWith('Definition of Done: PASSED') -and $dodOutput.Contains('== Decisions') -and $dodOutput.Contains('== Test') -and -not $dodOutput.Contains('== Pack')) $dodOutput
    Check 'dotnet: build/dod.ps1 checks the coverage of the tests' ($dodOutput.Contains('== Coverage')) $dodOutput
    Check 'dotnet: an xUnit v3 test project on xunit.v3.mtp-off, with xunit.runner.visualstudio and Microsoft.NET.Test.Sdk, builds under the banned APIs and runs in build/dod.ps1' ($dodOutput.TrimEnd().EndsWith('Definition of Done: PASSED') -and $dodOutput -match 'Passed!.*Demo\.V3\.Tests\.dll') $dodOutput
    $filterOutput = pwsh -NoProfile -File build/dod.ps1 -Fast -Filter 'FullyQualifiedName~UnitTest1' 2>&1 | Out-String
    Check 'dotnet: build/dod.ps1 -Filter runs the tests it matches and skips the coverage stage' ($LASTEXITCODE -eq 0 -and $filterOutput.Contains('== Test') -and -not $filterOutput.Contains('== Coverage')) $filterOutput

    # The runtimes script names the older framework a test project targets, and nothing for the SDK's own.
    $runtimesNone = @(pwsh -NoProfile -File build/Get-TestRuntimes.ps1 2>&1)
    $runtimesNoneCode = $LASTEXITCODE
    $dotnetRoot = Join-Path $Work 'dotnet-install'
    $installNone = @(pwsh -NoProfile -File build/Install-Dotnet.ps1 -SkipSdk -InstallDir $dotnetRoot 2>&1)
    $installNoneCode = $LASTEXITCODE
    $installNoneCreated = Test-Path -LiteralPath $dotnetRoot
    New-Item -ItemType Directory -Force tests/Legacy.Tests | Out-Null
    [IO.File]::WriteAllText((Join-Path (Get-Location) 'tests/Legacy.Tests/Legacy.Tests.csproj'), '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFrameworks>net8.0;net10.0</TargetFrameworks></PropertyGroup></Project>')
    dotnet sln add tests/Legacy.Tests | Out-Null
    $runtimesLegacy = @(pwsh -NoProfile -File build/Get-TestRuntimes.ps1 2>&1)
    $runtimesLegacyCode = $LASTEXITCODE
    Check 'dotnet: build/Get-TestRuntimes.ps1 names the runtime of an older framework a test project targets, and none for the SDK''s own' ($runtimesNoneCode -eq 0 -and $runtimesNone.Count -eq 0 -and $runtimesLegacyCode -eq 0 -and $runtimesLegacy.Count -eq 1 -and $runtimesLegacy[0] -eq '8.0.x') "$($runtimesNone -join ',') | $($runtimesLegacy -join ',')"
    $install = @(pwsh -NoProfile -File build/Install-Dotnet.ps1 -InstallDir $dotnetRoot 2>&1)
    $installCode = $LASTEXITCODE
    $installAgain = @(pwsh -NoProfile -File build/Install-Dotnet.ps1 -InstallDir $dotnetRoot 2>&1)
    $installAgainCode = $LASTEXITCODE
    # Run in the project, the installation's dotnet picks the SDK global.json selects from what the script put there.
    $installedSdk = "$(& (Join-Path $dotnetRoot $(if ($IsWindows) { 'dotnet.exe' } else { 'dotnet' })) --version 2>&1)"
    $pinnedSdk = (Get-Content -Raw -LiteralPath global.json | ConvertFrom-Json).sdk.version
    Check 'dotnet: build/Install-Dotnet.ps1 -SkipSdk installs nothing without an older framework; build/Install-Dotnet.ps1 installs the SDK global.json selects, which dotnet runs from there, and the runtimes build/Get-TestRuntimes.ps1 names, and skips them once they are there' ($installNoneCode -eq 0 -and $installNone.Count -eq 0 -and -not $installNoneCreated -and $installCode -eq 0 -and $installedSdk -match '^\d+\.\d+\.\d+$' -and [version]$installedSdk -ge [version]$pinnedSdk -and ($install -join ' ').Contains("Installed .NET SDK $installedSdk in") -and (Test-Path (Join-Path $dotnetRoot 'shared/Microsoft.NETCore.App/8.0.*')) -and (Test-Path (Join-Path $dotnetRoot 'shared/Microsoft.AspNetCore.App/8.0.*')) -and $installAgainCode -eq 0 -and ($installAgain -join ' ').Contains(".NET SDK $installedSdk is already in") -and ($installAgain -join ' ').Contains('are already in')) "$installedSdk | $($installNone -join ',') | $($install -join ',') | $($installAgain -join ',')"

    # The support script reads the SDK and every target framework of the root solution, against an index that makes net8.0 past its end of support.
    $sdkChannel = ($pinnedSdk -split '\.')[0..1] -join '.'
    $index = Join-Path $Work 'support-index.json'
    [IO.File]::WriteAllText($index, (@{ 'releases-index' = @(
                @{ 'channel-version' = $sdkChannel; 'release-type' = 'lts'; 'support-phase' = 'active'; 'eol-date' = '2099-11-10' },
                @{ 'channel-version' = '8.0'; 'release-type' = 'lts'; 'support-phase' = 'eol'; 'eol-date' = '2026-11-10' }
            ) } | ConvertTo-Json -Depth 5))
    $previousActions = $env:GITHUB_ACTIONS
    $env:GITHUB_ACTIONS = ''
    try {
        $supportOutput = pwsh -NoProfile -File build/Test-DotnetSupport.ps1 -ReleasesIndex $index 2>&1 | Out-String
        $supportCode = $LASTEXITCODE
        $supportWarnOutput = pwsh -NoProfile -File build/Test-DotnetSupport.ps1 -ReleasesIndex $index -WarnOnly 2>&1 | Out-String
        $supportWarnCode = $LASTEXITCODE
    }
    finally { $env:GITHUB_ACTIONS = $previousActions }
    Check 'dotnet: build/Test-DotnetSupport.ps1 reads the SDK and every target framework of the root solution, fails on one past its end of support and only warns with -WarnOnly' ($supportCode -eq 1 -and $supportOutput.Contains('Error: .NET 8.0 (tests/Legacy.Tests/Legacy.Tests.csproj) reached its end of support on 2026-11-10') -and $supportOutput.Contains("$sdkChannel (global.json, ") -and $supportOutput.Contains('src/Demo/Demo.csproj') -and $supportWarnCode -eq 0 -and $supportWarnOutput.Contains('Warning: .NET 8.0 (tests/Legacy.Tests/Legacy.Tests.csproj)')) "$supportOutput | $supportWarnOutput"

    # A target framework on a Standard Term Support release fails the build, which ProjectTemplateLtsCheck set to false lets through.
    $stsFramework = "net$([int]($sdkChannel -split '\.')[0] - 1).0"
    New-Item -ItemType Directory -Force src/Sts | Out-Null
    [IO.File]::WriteAllText((Join-Path (Get-Location) 'src/Sts/Sts.csproj'), "<Project Sdk=""Microsoft.NET.Sdk"">`n  <PropertyGroup>`n    <TargetFramework>$stsFramework</TargetFramework>`n  </PropertyGroup>`n</Project>`n")
    # CheckEolTargetFramework=false keeps the SDK's own end-of-support warning, an error under TreatWarningsAsErrors, out of the way.
    $stsOutput = dotnet build src/Sts -p:CheckEolTargetFramework=false 2>&1 | Out-String
    $stsCode = $LASTEXITCODE
    $stsOffOutput = dotnet build src/Sts -p:CheckEolTargetFramework=false -p:ProjectTemplateLtsCheck=false 2>&1 | Out-String
    $stsOffCode = $LASTEXITCODE
    Check 'dotnet: a target framework on a Standard Term Support release fails the build with PT0155, and builds with ProjectTemplateLtsCheck set to false' ($stsCode -ne 0 -and $stsOutput -match "error PT0155: $([regex]::Escape($stsFramework)) is a Standard Term Support release" -and $stsOffCode -eq 0) ((($stsOutput -split "`n" | Select-String -Pattern ' error ' | Select-Object -First 3) -join ' | ') + ' || ' + (($stsOffOutput -split "`n" | Select-String -Pattern ' error ' | Select-Object -First 3) -join ' | '))

    # PT0155's target reads only the target framework: run it alone, without restore or build, so -windows and netcoreapp3.1 need no targeting pack.
    $ltsMajor = [int]($sdkChannel -split '\.')[0]
    $boundaries = [ordered]@{ "net$($ltsMajor - 1).0-windows" = $true; "net${ltsMajor}.0" = $false; "net${ltsMajor}.0-windows" = $false; 'netcoreapp3.1' = $false }
    $wrongBoundaries = @(foreach ($framework in $boundaries.Keys) {
            $boundaryOutput = dotnet msbuild src/Sts/Sts.csproj -t:ProjectTemplateLtsTargetFramework "-p:TargetFramework=$framework" 2>&1 | Out-String
            $boundaryFailed = $LASTEXITCODE -ne 0
            $reported = $boundaryOutput -match "error PT0155: $([regex]::Escape($framework)) is a Standard Term Support release"
            if ($boundaryFailed -ne $boundaries[$framework] -or $reported -ne $boundaries[$framework] -or (-not $boundaries[$framework] -and $boundaryOutput.Contains('PT0155'))) { "${framework}: exit $LASTEXITCODE $(($boundaryOutput -split "`n" | Select-String -Pattern ' error ' | Select-Object -First 2) -join ' ')" }
        })
    Check 'dotnet: PT0155 fails an odd major with a platform suffix, and leaves an even major, with or without one, and netcoreapp3.1 alone' (-not $wrongBoundaries) ($wrongBoundaries -join ' | ')
}
finally { Pop-Location }

# A library: its public API is recorded and checked, the Definition of Done packs it, and AssemblyVersion follows the major version.
$libraryDest = Join-Path $Work 'dotnet-library-apache'
if (Test-Path -LiteralPath $libraryDest) {
    Push-Location $libraryDest
    try {
        dotnet new classlib -o src/Greetings | Out-Null
        [IO.File]::WriteAllText((Join-Path (Get-Location) 'src/Greetings/Class1.cs'), "namespace Greetings;`n`n/// <summary>`n/// A greeter.`n/// </summary>`npublic sealed class Greeter`n{`n    /// <summary>`n    /// Greets someone.`n    /// </summary>`n    /// <param name=`"name`">Who to greet.</param>`n    /// <returns>The greeting.</returns>`n    public static string Greet(string name) => `$`"Hello, {name}!`";`n}`n")
        Add-FileHeader (Join-Path (Get-Location) 'src/Greetings/Class1.cs')
        dotnet new sln | Out-Null
        dotnet sln add src/Greetings | Out-Null
        $apiOutput = pwsh -NoProfile -File build/Update-PublicApi.ps1 2>&1 | Out-String
        $unshipped = Join-Path (Get-Location) 'src/Greetings/PublicAPI.Unshipped.txt'
        $apiText = if (Test-Path -LiteralPath $unshipped) { [IO.File]::ReadAllText($unshipped) } else { '' }
        Check 'dotnet-library-apache: Update-PublicApi.ps1 creates the files and records the public API' ($LASTEXITCODE -eq 0 -and $apiText.StartsWith("#nullable enable`n") -and $apiText.Contains('static Greetings.Greeter.Greet(string! name) -> string!') -and (Test-Path -LiteralPath (Join-Path (Get-Location) 'src/Greetings/PublicAPI.Shipped.txt'))) "$apiOutput | $apiText"
        # The scaffolded and test-written files are not yet formatted, and the Format stage would fail on them.
        dotnet tool restore | Out-Null
        dotnet csharpier format . | Out-Null
        $libDod = pwsh -NoProfile -File build/dod.ps1 2>&1 | Out-String
        $libDodExit = $LASTEXITCODE
        $packed = @(Get-ChildItem -LiteralPath (Join-Path (Get-Location) 'artifacts/packages') -Filter 'Greetings.*' -ErrorAction SilentlyContinue | ForEach-Object Name)
        Check 'dotnet-library-apache: build/dod.ps1 builds, tests and packs the library at version.json''s version with its symbols' ($LASTEXITCODE -eq 0 -and $libDod.Contains('== Pack') -and @($packed -match '^Greetings\.0\.1\.0(-g[0-9a-f]*)?\.nupkg$').Count -eq 1 -and @($packed -match '^Greetings\.0\.1\.0(-g[0-9a-f]*)?\.snupkg$').Count -eq 1) "$($packed -join ', ') | $libDod"
        Check 'dotnet-library-apache: build/dod.ps1 runs the Format stage and passes on formatted C#' ($libDodExit -eq 0 -and $libDod.Contains('== Format')) $libDod
        Check 'dotnet-library-apache: build/dod.ps1 skips the coverage stage without a test project' (-not $libDod.Contains('== Coverage')) $libDod
        [IO.File]::WriteAllText((Join-Path (Get-Location) 'src/Greetings/Extra.cs'), "namespace Greetings;`n`n/// <summary>`n/// Not recorded.`n/// </summary>`npublic sealed class Extra`n{`n}`n")
        Add-FileHeader (Join-Path (Get-Location) 'src/Greetings/Extra.cs')
        $unrecorded = dotnet build src/Greetings 2>&1 | Out-String
        [IO.File]::Delete((Join-Path (Get-Location) 'src/Greetings/Extra.cs'))
        Check 'dotnet-library-apache: a public type the API files do not record fails the build' ($unrecorded -match "error RS0016: Symbol 'Greetings\.Extra'") (($unrecorded -split "`n" | Select-String -Pattern ' error ' | Select-Object -First 3) -join ' | ')
        $messy = Join-Path (Get-Location) 'src/Greetings/Messy.cs'
        try {
            [IO.File]::WriteAllText($messy, 'namespace Greetings;internal static class Messy{}')
            $messyOutput = pwsh -NoProfile -File build/dod.ps1 -Fast 2>&1 | Out-String
            $messyExit = $LASTEXITCODE
        }
        finally { [IO.File]::Delete($messy) }
        Check 'dotnet-library-apache: an unformatted C# file fails build/dod.ps1 at the Format stage' ($messyExit -eq 1 -and $messyOutput -match 'Definition of Done: FAILED at Format' -and $messyOutput -match 'dotnet csharpier format \.') $messyOutput
        # Package validation compares a pack with a baseline package: making Greet internal removes a public member the baseline has.
        $baselinePackage = Get-ChildItem -LiteralPath (Join-Path (Get-Location) 'artifacts/packages') -Filter 'Greetings.*.nupkg' | Where-Object { $_.Name -notlike '*.snupkg' } | Select-Object -First 1
        $classPath = Join-Path (Get-Location) 'src/Greetings/Class1.cs'
        $classText = [IO.File]::ReadAllText($classPath)
        $unshippedText = [IO.File]::ReadAllText($unshipped)
        try {
            [IO.File]::WriteAllText($classPath, $classText.Replace('public static string Greet', 'internal static string Greet'))
            [IO.File]::WriteAllText($unshipped, (($unshippedText -split "`n" | Where-Object { $_ -notmatch 'Greeter\.Greet\(' }) -join "`n"))
            $validationOutput = dotnet pack src/Greetings --configuration Release "-p:PackageValidationBaselinePath=$($baselinePackage.FullName)" --output artifacts/validation 2>&1 | Out-String
        }
        finally {
            [IO.File]::WriteAllText($classPath, $classText)
            [IO.File]::WriteAllText($unshipped, $unshippedText)
        }
        Remove-Item -LiteralPath (Join-Path (Get-Location) 'src/Greetings/bin'), (Join-Path (Get-Location) 'src/Greetings/obj') -Recurse -Force -ErrorAction Ignore
        Check 'dotnet-library-apache: package validation fails a pack that removes a public member the baseline package has (CP0002)' ($validationOutput -match 'error CP0002') (($validationOutput -split "`n" | Select-String -Pattern ' error ' | Select-Object -First 3) -join ' | ')
        # (a) version.json's version, a prerelease here, packs as it is with PublicRelease, and the -p:Version publish.yml passes doesn't change it; AssemblyVersion moves only with the major version.
        $versionFile = Join-Path (Get-Location) 'version.json'
        $versionText = [IO.File]::ReadAllText($versionFile)
        $dll = Join-Path (Get-Location) 'src/Greetings/bin/Release/net10.0/Greetings.dll'
        try {
            [IO.File]::WriteAllText($versionFile, $versionText.Replace('"version": "0.1.0"', '"version": "2.5.0-rc.1"'))
            Remove-Item -LiteralPath (Join-Path (Get-Location) 'src/Greetings/bin'), (Join-Path (Get-Location) 'src/Greetings/obj') -Recurse -Force -ErrorAction Ignore
            dotnet pack src/Greetings --configuration Release -p:PublicRelease=true "-p:Version=9.9.9" --output artifacts/rc 2>&1 | Out-Null
        }
        finally { [IO.File]::WriteAllText($versionFile, $versionText) }
        $rcPacked = @(Get-ChildItem -LiteralPath (Join-Path (Get-Location) 'artifacts/rc') -Filter 'Greetings.*' -ErrorAction SilentlyContinue | ForEach-Object Name)
        $assemblyVersion = if (Test-Path -LiteralPath $dll) { "$([Reflection.AssemblyName]::GetAssemblyName($dll).Version)" } else { 'missing' }
        $fileVersion = if (Test-Path -LiteralPath $dll) { [Diagnostics.FileVersionInfo]::GetVersionInfo($dll).FileVersion } else { 'missing' }
        Check 'dotnet-library-apache: version.json''s version packs as is with PublicRelease, a prerelease included, -p:Version doesn''t change it, and AssemblyVersion moves only with the major version' ($rcPacked -contains 'Greetings.2.5.0-rc.1.nupkg' -and $assemblyVersion -eq '2.0.0.0' -and $fileVersion -match '^2\.5\.0(\.\d+)?$') "$($rcPacked -join ', ') | AssemblyVersion=$assemblyVersion FileVersion=$fileVersion"
        # (b) Without version.json, the tag-based versioning stays: -p:Version sets the exact version.
        $versionOff = Join-Path (Get-Location) 'version.json.off'
        try {
            [IO.File]::Move($versionFile, $versionOff)
            Remove-Item -LiteralPath (Join-Path (Get-Location) 'src/Greetings/bin'), (Join-Path (Get-Location) 'src/Greetings/obj') -Recurse -Force -ErrorAction Ignore
            dotnet build src/Greetings --configuration Release -p:Version=2.5.0-rc.1 2>&1 | Out-Null
        }
        finally {
            [IO.File]::Move($versionOff, $versionFile)
        }
        $assemblyVersion = if (Test-Path -LiteralPath $dll) { "$([Reflection.AssemblyName]::GetAssemblyName($dll).Version)" } else { 'missing' }
        $fileVersion = if (Test-Path -LiteralPath $dll) { [Diagnostics.FileVersionInfo]::GetVersionInfo($dll).FileVersion } else { 'missing' }
        Remove-Item -LiteralPath (Join-Path (Get-Location) 'src/Greetings/bin'), (Join-Path (Get-Location) 'src/Greetings/obj') -Recurse -Force -ErrorAction Ignore
        Check 'dotnet-library-apache: without version.json, AssemblyVersion moves only with the major version, FileVersion keeps the exact one' ($assemblyVersion -eq '2.0.0.0' -and $fileVersion -eq '2.5.0') "AssemblyVersion=$assemblyVersion FileVersion=$fileVersion"
        # IDE0073, raised to a warning for two probe files only, matches a file that starts with the header .editorconfig sets and fails one without it.
        $editorconfigPath = Join-Path (Get-Location) '.editorconfig'
        $editorconfigText = [IO.File]::ReadAllText($editorconfigPath)
        $headed = Join-Path (Get-Location) 'src/Greetings/Headed.cs'
        $bare = Join-Path (Get-Location) 'src/Greetings/HeadedBare.cs'
        try {
            [IO.File]::WriteAllText($editorconfigPath, $editorconfigText + "`n[Headed*.cs]`ndotnet_diagnostic.IDE0073.severity = warning`n")
            [IO.File]::WriteAllText($headed, "// Copyright $([char]0xA9) NCode Group`n// SPDX-License-Identifier: Apache-2.0`n`nnamespace Greetings;`n`ninternal static class Headed`n{`n}`n")
            [IO.File]::WriteAllText($bare, "namespace Greetings;`n`ninternal static class HeadedBare`n{`n}`n")
            $headerOutput = dotnet build src/Greetings 2>&1 | Out-String
        }
        finally {
            [IO.File]::WriteAllText($editorconfigPath, $editorconfigText)
            [IO.File]::Delete($headed)
            [IO.File]::Delete($bare)
        }
        Check 'dotnet-library-apache: IDE0073 matches a file that starts with the header .editorconfig sets and fails one without it' ($headerOutput -match 'HeadedBare\.cs\(1,1\): error IDE0073' -and $headerOutput -notmatch '[\\/]Headed\.cs\(\d+,\d+\): error IDE0073') (($headerOutput -split "`n" | Select-String -Pattern 'IDE0073' | Select-Object -First 3) -join ' | ')
        # The package's project page: the site docs/site/site.config.json names, else the repository, unless the project file sets one (ADR-0152).
        $linkArgs = @('src/Greetings', '-t:ProjectTemplateRepositoryLinks', '-getProperty:PackageProjectUrl', '-p:RepositoryUrl=https://github.com/example/Greetings.git', '-p:EnableSourceControlManagerQueries=false')
        $repositoryPage = "$(dotnet msbuild @linkArgs 2>&1)".Trim()
        $siteFolder = Join-Path (Get-Location) 'docs/site'
        $csprojPath = Join-Path (Get-Location) 'src/Greetings/Greetings.csproj'
        $csprojText = [IO.File]::ReadAllText($csprojPath)
        try {
            New-Item -ItemType Directory -Force $siteFolder | Out-Null
            [IO.File]::WriteAllText((Join-Path $siteFolder 'site.config.json'), "{`n  ""title"": ""Greetings"",`n  ""repository"": { ""url"": ""https://github.com/example/Greetings"" },`n  ""site"": {`n    ""url"": ""https://example.github.io/Greetings""`n  },`n  ""sidebar"": [{ ""label"": ""Start"", ""items"": [""index""] }]`n}`n")
            $sitePage = "$(dotnet msbuild @linkArgs 2>&1)".Trim()
            [IO.File]::WriteAllText((Join-Path $siteFolder 'site.config.json'), "{`n  ""title"": ""Greetings"",`n  ""site"": {`n    ""url"": ""https://example.github.io/Greetings/""`n  }`n}`n")
            $slashPage = "$(dotnet msbuild @linkArgs 2>&1)".Trim()
            [IO.File]::WriteAllText((Join-Path $siteFolder 'site.config.json'), "{`n  ""title"": ""Greetings"",`n  ""repository"": { ""url"": ""https://example.com/elsewhere"" }`n}`n")
            $noSitePage = "$(dotnet msbuild @linkArgs 2>&1)".Trim()
            [IO.File]::WriteAllText($csprojPath, $csprojText.Replace('</Project>', "  <PropertyGroup>`n    <PackageProjectUrl>https://example.com/greetings</PackageProjectUrl>`n  </PropertyGroup>`n</Project>"))
            $ownPage = "$(dotnet msbuild @linkArgs 2>&1)".Trim()
        }
        finally {
            [IO.File]::WriteAllText($csprojPath, $csprojText)
            Remove-Item -LiteralPath $siteFolder -Recurse -Force -ErrorAction Ignore
        }
        Check 'dotnet-library-apache: the package''s project page is the site docs/site/site.config.json names, with one trailing /, else the repository, also for a config without site.url, and the project file''s own wins' ($repositoryPage -eq 'https://github.com/example/Greetings' -and $sitePage -eq 'https://example.github.io/Greetings/' -and $slashPage -eq 'https://example.github.io/Greetings/' -and $noSitePage -eq 'https://github.com/example/Greetings' -and $ownPage -eq 'https://example.com/greetings') "repository: $repositoryPage | site: $sitePage | slash: $slashPage | no site.url: $noSitePage | own: $ownPage"
    }
    finally { Pop-Location }
}
''
if ($failures.Count) { "Kept the work folder: $Work"; "Template .NET tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Template .NET tests: PASSED'
exit 0
