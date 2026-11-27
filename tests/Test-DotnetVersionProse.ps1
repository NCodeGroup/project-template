<#
.SYNOPSIS
    Check that no Markdown file or comment in the repository names a .NET version (the template's ADR-0155).

.DESCRIPTION
    Scans every Markdown file Git tracks, *.md and *.md.jinja, for a name that pins a .NET release: the product name followed by
    a number, a target framework moniker, a runtime channel such as a major version followed by .0.x, an SDK version, or a
    dotnet container image tag. The prose names the release by its role instead, so it does not go stale when a release ships.
    Skips everything under tests/, whose fixtures are data, and every CHANGELOG.md and CHANGELOG.md.jinja, which record what
    past releases did. First checks the pattern on names it must find and names it must leave alone. A failure names each
    offending line as <path>:<line>: <match>. Prints PASS or FAIL per check and exits 1 on any failure.

    It also reads the full-line comments of every script, workflow and project file Git tracks outside tests/: PowerShell # lines
    and block comments, YAML and shell # lines, and XML <!-- --> comments, in .ps1, .psm1, .psd1, .yml, .yaml, .sh, .props,
    .targets and .csproj files and their .jinja versions. Code lines and comments that trail code on the same line are not
    read: code may pin a version.

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

function Get-CommentLine([string]$Name, [string[]]$Lines) {
    $kind = $Name -replace '\.jinja$', ''
    $inBlock = $false
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        $text = $null
        if ($kind -match '\.(ps1|psm1|psd1)$') {
            if ($inBlock) { $text = $line; if ($line.Contains('#>')) { $inBlock = $false } }
            elseif ($line -match '^\s*<#') { $text = $line; if (-not $line.Contains('#>')) { $inBlock = $true } }
            elseif ($line -match '^\s*#') { $text = $line }
        }
        elseif ($kind -match '\.(props|targets|csproj)$') {
            if ($inBlock) {
                # in a block: text up to and including the first '-->', which ends the block, else the whole line
                $end = $line.IndexOf('-->')
                if ($end -ge 0) { $text = $line.Substring(0, $end + 3); $inBlock = $false }
                else { $text = $line }
            }
            else {
                # otherwise, when the line holds '<!--': text from it up to and including the next '-->', else to the end of the line, which starts a block
                $start = $line.IndexOf('<!--')
                if ($start -ge 0) {
                    $end = $line.IndexOf('-->', $start + 4)
                    if ($end -ge 0) { $text = $line.Substring($start, $end + 3 - $start) }
                    else { $text = $line.Substring($start); $inBlock = $true }
                }
            }
        }
        elseif ($kind -match '\.(yml|yaml|sh)$') { if ($line -match '^\s*#') { $text = $line } }
        if ($null -ne $text) { [pscustomobject]@{ Line = $i + 1; Text = $text } }
    }
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

$commentCases = @(
    @('a full-line PowerShell comment is read', 'a.ps1', @('# Needs .NET 10.', '$x = 1'), 1),
    @('a PowerShell code line is not read', 'a.ps1', @('$tfm = ''net8.0'''), 0),
    @('a line inside a PowerShell block comment is read', 'a.ps1', @('<#', '.SYNOPSIS', '    Installs 8.0.x.', '#>', '$c = ''8.0.x'''), 1),
    @('a YAML comment line is read, its code and a trailing comment are not', 'ci.yml.jinja', @('  # runs in mcr.microsoft.com/dotnet/sdk:10.0', '  image: mcr.microsoft.com/dotnet/sdk:10.0', '  - uses: a/b@0123 # net8.0'), 1),
    @('an XML comment over two lines is read, an element is not', 'ProjectTemplate.props.jinja', @('<!-- One line', '     targets net8.0. -->', '<TargetFramework>net10.0</TargetFramework>'), 1),
    @('an XML comment is read up to its end, not the element after it', 'a.props', @('<!-- shared --><TargetFramework>net8.0</TargetFramework>'), 0),
    @('a shell comment line is read, its code is not', 'a.sh', @('# needs .NET 10', 'echo net8.0'), 1)
)
foreach ($case in $commentCases) {
    $count = 0
    foreach ($comment in Get-CommentLine $case[1] $case[2]) { $count += [regex]::Matches($comment.Text, $pattern).Count }
    Check "comments: $($case[0])" ($count -eq $case[3])
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

$scriptPaths = @(git -C $repoRoot ls-files)
if ($LASTEXITCODE) { throw "git ls-files failed with exit code $LASTEXITCODE" }
$scriptPaths = @($scriptPaths | Where-Object { $_ -and -not $_.StartsWith('tests/') -and (($_ -replace '\.jinja$', '') -match '\.(ps1|psm1|psd1|yml|yaml|sh|props|targets|csproj)$') })

$commentHits = foreach ($path in $scriptPaths) {
    foreach ($comment in Get-CommentLine $path @(Get-Content -LiteralPath (Join-Path $repoRoot $path))) {
        foreach ($match in [regex]::Matches($comment.Text, $pattern)) { "${path}:$($comment.Line): $($match.Value)" }
    }
}
Check 'repository: no comment in a script, workflow or project file outside tests/ names a .NET version (name the release by its role, as ADR-0155 says)' (-not $commentHits) ($commentHits -join '; ')

''
if ($failures.Count) { ".NET version prose tests: FAILED ($($failures.Count))"; exit 1 }
'.NET version prose tests: PASSED'
exit 0
