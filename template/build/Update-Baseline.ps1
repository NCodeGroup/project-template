<#
.SYNOPSIS
    Raises PackageValidationBaselineVersion to a released version once nuget.org lists it, the template's ADR-0150.

.DESCRIPTION
    From the project template; template updates replace this file. Sets PackageValidationBaselineVersion in each
    Directory.Build.props and project file that already sets it, so package validation compares each package with the
    release just published. It never lowers the baseline: it changes nothing when no file sets the property, or when
    every file already holds the version or a later one. It prints the version it set, or nothing.

    A prerelease is never a baseline, so the version must be a stable one such as 1.4.0 or v1.4.0.

.PARAMETER Version
    The released version, such as 1.4.0 or v1.4.0.

.PARAMETER Root
    The repository root to search. Defaults to the folder above this script's.

.PARAMETER TimeoutMinutes
    How long to wait for nuget.org to list the version. Defaults to 30.

.PARAMETER SkipNugetCheck
    Raises the baseline without waiting for nuget.org.

.EXAMPLE
    ./build/Update-Baseline.ps1 -Version 1.4.0
#>
#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Version,

    [string]$Root = (Split-Path -Parent $PSScriptRoot),

    [int]$TimeoutMinutes = 30,

    [switch]$SkipNugetCheck
)

$ErrorActionPreference = 'Stop'

if ($Version -notmatch '^v?(\d+\.\d+\.\d+)$') {
    throw "'$Version' isn't a stable version such as 1.4.0 or v1.4.0: a prerelease is never a baseline."
}
$target = $Matches[1]
$targetVersion = [System.Management.Automation.SemanticVersion]$target

$candidates = @(
    Get-ChildItem -LiteralPath $Root -Recurse -File -Include Directory.Build.props, *.csproj |
        ForEach-Object {
            [pscustomobject]@{
                File     = $_
                Relative = [IO.Path]::GetRelativePath($Root, $_.FullName)
            }
        } |
        Where-Object { $_.Relative -notmatch '(^|[\\/])(bin|obj|node_modules|artifacts|\.git)[\\/]' } |
        Sort-Object -Property Relative
)

$pattern = '(<PackageValidationBaselineVersion>\s*)([^<]*?)(\s*</PackageValidationBaselineVersion>)'
$setters = 0
$changed = [ordered]@{}
foreach ($candidate in $candidates) {
    $path = $candidate.File.FullName
    $relative = $candidate.Relative
    $text = [IO.File]::ReadAllText($path)
    if ($text -notmatch $pattern) { continue }
    $setters++
    $newText = [regex]::Replace($text, $pattern, {
            param($m)
            $value = $m.Groups[2].Value
            $parsed = $null
            if (-not [System.Management.Automation.SemanticVersion]::TryParse($value, [ref]$parsed)) {
                Write-Warning "${relative}: PackageValidationBaselineVersion '$value' isn't a version; left as it is."
                return $m.Value
            }
            if ($parsed -ge $targetVersion) { return $m.Value }
            return $m.Groups[1].Value + $target + $m.Groups[3].Value
        })
    if ($newText -ceq $text) { continue }
    $bytes = [IO.File]::ReadAllBytes($path)
    $hadBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $changed[$path] = @{ Text = $newText; HadBom = $hadBom }
}

if ($setters -eq 0) {
    Write-Host 'No Directory.Build.props or project file sets PackageValidationBaselineVersion: set it once by hand, as the template''s ADR-0147 says, and this script raises it from then on.'
    return
}
if ($changed.Count -eq 0) {
    Write-Host "PackageValidationBaselineVersion is already $target or later."
    return
}

$null = $TimeoutMinutes, $SkipNugetCheck # The nuget.org wait replaces this line (step 3).

foreach ($path in $changed.Keys) {
    [IO.File]::WriteAllText($path, $changed[$path].Text, [Text.UTF8Encoding]::new($changed[$path].HadBom))
}

$changelog = 'CHANGELOG.md'
$agentsPath = Join-Path $Root 'AGENTS.md'
if (Test-Path -LiteralPath $agentsPath -PathType Leaf) {
    $agents = [IO.File]::ReadAllText($agentsPath)
    $landing = [regex]::Match($agents, '(?ms)^## Landing[ \t]*\r?$(.*?)(?=^## |\z)')
    if ($landing.Success) {
        $named = [regex]::Match($landing.Groups[1].Value, '(?m)^- changelog:[ \t]*(.+?)[ \t]*\r?$')
        if ($named.Success) { $changelog = $named.Groups[1].Value.Trim('`', '"', "'") }
    }
}
$changelogPath = Join-Path $Root $changelog
if (Test-Path -LiteralPath $changelogPath -PathType Leaf) {
    $original = [IO.File]::ReadAllText($changelogPath)
    $crlf = $original.Contains("`r`n")
    $text = $original.Replace("`r`n", "`n")
    if ($text -match '(?m)^## \[Unreleased\][ \t]*$' -and $text -match '(?m)^## \[\d+\.\d+\.\d+[^\]]*\] - ') {
        $entry = "- Package validation compares each package with the published $target package."
        $unreleased = [regex]::Match($text, '(?s)## \[Unreleased\]\n(.*?)(?=\n## \[|\n\[unreleased\]:)')
        if ($unreleased.Success) {
            $body = $unreleased.Groups[1].Value
            if ($body -match '(?m)^### Changed\n') {
                $newBody = [regex]::Replace($body, '(?m)^### Changed\n\n?', "### Changed`n`n$entry`n", 1)
            }
            elseif (($later = [regex]::Match($body, '(?m)^### (Deprecated|Removed|Fixed|Security)\n')).Success) {
                $newBody = $body.Insert($later.Index, "### Changed`n`n$entry`n`n")
            }
            else {
                $newBody = "`n" + ($body.Trim("`n") + "`n`n### Changed`n`n$entry").TrimStart("`n") + "`n"
            }
            $group = $unreleased.Groups[1]
            $newText = $text.Substring(0, $group.Index) + $newBody + $text.Substring($group.Index + $group.Length)
            if ($crlf) { $newText = $newText.Replace("`n", "`r`n") }
            $bytes = [IO.File]::ReadAllBytes($changelogPath)
            $hadBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
            [IO.File]::WriteAllText($changelogPath, $newText, [Text.UTF8Encoding]::new($hadBom))
        }
    }
    else {
        Write-Host "Left $changelog as it is: it has no [Unreleased] and release sections to add the entry to."
    }
}

$target
