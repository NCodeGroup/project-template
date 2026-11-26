<#
.SYNOPSIS
    Check that no Markdown file in the repository names a .NET version (the template's ADR-0155).

.DESCRIPTION
    Scans every Markdown file Git tracks, *.md and *.md.jinja, for a name that pins a .NET release: the product name followed by
    a number, a target framework moniker, a runtime channel such as a major version followed by .0.x, an SDK version, or a
    dotnet container image tag. The prose names the release by its role instead, so it does not go stale when a release ships.
    Skips everything under tests/, whose fixtures are data, and every CHANGELOG.md and CHANGELOG.md.jinja, which record what
    past releases did. First checks the pattern on names it must find and names it must leave alone. A failure names each
    offending line as <path>:<line>: <match>. Prints PASS or FAIL per check and exits 1 on any failure.

.EXAMPLE
    .\tests\Test-DotnetVersionProse.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}

$pattern = '\.NET (?:Core )?\d+|\bnet(?:coreapp)?\d+\.\d+|\b\d+\.0\.x\b|\b\d{1,2}\.0\.\d{3}\b|dotnet/[a-z-]+:\d+'

$found = '.NET 10', 'ASP.NET Core 10.0', '.NET Core 3.1', 'net8.0', 'net10.0-windows', 'netcoreapp3.1', '8.0.x', '10.0.402', 'mcr.microsoft.com/dotnet/sdk:10.0', 'mcr.microsoft.com/dotnet/aspnet:10.0'
foreach ($text in $found) {
    Check "pattern: finds $text" ([regex]::Matches($text, $pattern).Count -gt 0)
}

$left = 'netstandard2.0', '.NET Framework 4.8', 'net48', 'netN.0', 'N.0.x', '.NET N', 'sdk:N.0', 'xunit.runner.visualstudio 4.0 or later', 'Microsoft.NET.Test.Sdk', 'mcr.microsoft.com/dotnet/sdk', 'v0.114.0'
foreach ($text in $left) {
    Check "pattern: leaves $text" ([regex]::Matches($text, $pattern).Count -eq 0)
}

$paths = @(git -C $repoRoot ls-files -- '*.md' '*.md.jinja')
if ($LASTEXITCODE) { throw "git ls-files failed with exit code $LASTEXITCODE" }
$paths = @($paths | Where-Object { $_ -and -not $_.StartsWith('tests/') -and (($_ -split '/')[-1] -notin 'CHANGELOG.md', 'CHANGELOG.md.jinja') })

$hits = foreach ($path in $paths) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath (Join-Path $repoRoot $path)) {
        $lineNumber++
        foreach ($match in [regex]::Matches($line, $pattern)) { "${path}:${lineNumber}: $($match.Value)" }
    }
}
Check 'repository: no Markdown file outside tests/ and the changelogs names a .NET version (name the release by its role, as ADR-0155 says)' (-not $hits) ($hits -join '; ')

''
if ($failures.Count) { ".NET version prose tests: FAILED ($($failures.Count))"; exit 1 }
'.NET version prose tests: PASSED'
exit 0
