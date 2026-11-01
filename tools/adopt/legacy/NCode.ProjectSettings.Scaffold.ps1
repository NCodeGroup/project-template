<#
.SYNOPSIS
    Legacy adapter for repositories that use the NCode.ProjectSettings.Scaffold NuGet package.

.DESCRIPTION
    Handles a repository whose MSBuild files reference NCode.ProjectSettings.Scaffold. The template's
    build/ProjectTemplate.props (nuget_package), .editorconfig, license files, icon and publish.yml replace what that
    package provided, so the reference is removed and the leftovers it no longer reads are reported.

    Contract: Adopt-Project.ps1 runs every script in tools\adopt\legacy with -Phase Detect. For each that returns $true,
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
        $answers = @{ nuget_package = $true; license = 'Apache-2.0'; package_license = 'Apache-2.0'; author_name = 'NCode Group' }
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
        'Its package settings now come from build/ProjectTemplate.props (nuget_package), its file header from .editorconfig, its LICENSE.txt, COPYRIGHT.txt and NCodeGroup.png from the template, and its publishing from .github/workflows/publish.yml. Its GlobalAssemblyInfo.cs, its license copies in each package and its build-time release notes are gone.'
        $relative = { param($full) [IO.Path]::GetRelativePath($Path, $full).Replace([char]92, [char]47) }
        foreach ($file in Get-MSBuildFile $Path) {
            $text = [IO.File]::ReadAllText($file.FullName)
            if ($text.Contains('$(NCode')) { "Uses a property the scaffold defined: $(& $relative $file.FullName)" }
            if ($text.Contains('Microsoft.SourceLink.GitHub')) { "References Microsoft.SourceLink.GitHub, which the .NET SDK builds in: remove it from $(& $relative $file.FullName)" }
            if ($text -match '<DocumentationFile>') { "Sets DocumentationFile, the scaffold's path for XML documentation; the template generates it: remove it from $(& $relative $file.FullName)" }
        }
        # The scaffold imported the nearest project.props into each project; nothing does now.
        foreach ($props in Get-ChildItem -LiteralPath $Path -Recurse -File -Filter project.props | Where-Object { $_.FullName -notmatch '[\\/](bin|obj|\.git)[\\/]' }) {
            "Nothing imports $(& $relative $props.FullName) now: move its settings, such as Description and PackageTags, into the project file beside it and delete it"
        }
        foreach ($settings in Get-ChildItem -LiteralPath $Path -File -Filter '*.sln.DotSettings') {
            "$($settings.Name) holds the scaffold's ReSharper file header and cleanup profile; .editorconfig's file_header_template now sets the header: delete it unless it holds settings of the project's own"
        }
        $workflows = Join-Path $Path '.github/workflows'
        if (Test-Path -LiteralPath $workflows) {
            foreach ($workflow in Get-ChildItem -LiteralPath $workflows -File | Where-Object { $_.Name -ne 'publish.yml' -and $_.Extension -in '.yml', '.yaml' }) {
                if ([IO.File]::ReadAllText($workflow.FullName).Contains('dotnet nuget push')) {
                    "$(& $relative $workflow.FullName) pushes packages to NuGet too: keep one publisher, either it or .github/workflows/publish.yml, which uses trusted publishing instead of an API key"
                }
            }
        }
    }
}
