<#
.SYNOPSIS
    Legacy adapter for repositories that use the NCode.ProjectSettings.Scaffold NuGet package.

.DESCRIPTION
    Handles a repository whose MSBuild files reference NCode.ProjectSettings.Scaffold. The template's
    build/ProjectTemplate.props (nuget_package) replaces what that package provided, so the reference is removed.

    Contract: Adopt-Project.ps1 runs every script in adopt\legacy with -Phase Detect. For each that returns $true,
    it adds the -Phase Answers hashtable to the answers before Copier runs and runs -Phase Apply after, printing
    the lines Apply returns.

.EXAMPLE
    .\NCode.ProjectSettings.Scaffold.ps1 -Path C:\src\app -Phase Detect
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][ValidateSet('Detect', 'Answers', 'Apply')][string]$Phase
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\Adoption.psm1') -Force

$Path = (Resolve-Path -LiteralPath $Path).Path
$files = @(Get-MSBuildFile $Path | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw).Contains('NCode.ProjectSettings.Scaffold') })

switch ($Phase) {
    'Detect' { [bool]($files.Count -gt 0) }
    'Answers' {
        $answers = @{ nuget_package = $true; package_license = 'Apache-2.0'; author_name = 'NCode Group' }
        if (Test-Path -LiteralPath (Join-Path $Path 'NCodeGroup.png')) { $answers.package_icon = 'NCodeGroup.png' }
        $answers
    }
    'Apply' {
        $reference = '(?s)\r?\n[ \t]*<PackageReference\s+Include="NCode\.ProjectSettings\.Scaffold"[^>]*?(/>|>.*?</PackageReference>)'
        $version = '(?s)\r?\n[ \t]*<PackageVersion\s+Include="NCode\.ProjectSettings\.Scaffold"[^>]*/>'
        foreach ($file in $files) {
            $text = [IO.File]::ReadAllText($file.FullName)
            $new = $text -replace $reference, '' -replace $version, ''
            if ($new -ne $text) { [IO.File]::WriteAllText($file.FullName, $new, [Text.UTF8Encoding]::new($false)) }
            "Removed the NCode.ProjectSettings.Scaffold reference from $([IO.Path]::GetRelativePath($Path, $file.FullName).Replace([char]92, [char]47))"
        }
        'Its package settings now come from build/ProjectTemplate.props (nuget_package). Its GlobalAssemblyInfo.cs, its LICENSE.txt and COPYRIGHT.txt copies in each package, and its build-time release notes are gone.'
        foreach ($file in Get-MSBuildFile $Path) {
            if ([IO.File]::ReadAllText($file.FullName).Contains('$(NCode')) {
                "Uses a property the scaffold defined: $([IO.Path]::GetRelativePath($Path, $file.FullName).Replace([char]92, [char]47))"
            }
        }
    }
}
