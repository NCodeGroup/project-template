<#
.SYNOPSIS
    The Definition of Done: the one gate a change passes before it counts as done, run the same way by people, agents
    and CI.

.DESCRIPTION
    From the project template; template updates replace this file. Runs these stages from the repository root and stops
    at the first that fails, with its name; prints "Definition of Done: PASSED" as its last line, and exits 0, when every
    stage passes. A script that runs it tests the exit code rather than that line, which build output can follow in a
    merged stream.

    1. Tools: dotnet tool restore, when .config/dotnet-tools.json exists.
    2. Decisions: .template/Test-AdrIndex.ps1 checks that docs/decisions/README.md indexes every decision record.
    3. Build: restore and build the solution at the repository root, in Release, with warnings as errors, the analyzers
       and the banned APIs that build/ProjectTemplate.props sets up, and for a library its public API checked.
    4. Test: every test project, without building again; -Filter narrows the run.
    5. Pack: for a library (the nuget_package answer), every packable project into artifacts/packages, with its symbols.

    -Fast is the local gate: Debug, no pack. CI runs the full gate.

.PARAMETER Fast
    Build in Debug and skip the pack stage.

.PARAMETER Filter
    A dotnet test filter expression, such as FullyQualifiedName~OrderStore, to run only the tests it matches.

.EXAMPLE
    ./build/dod.ps1

.EXAMPLE
    ./build/dod.ps1 -Fast -Filter 'FullyQualifiedName~OrderStore'
#>
[CmdletBinding()]
param(
    [switch]$Fast,
    [string]$Filter
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $configuration = if ($Fast) { 'Debug' } else { 'Release' }
    $answers = if (Test-Path -LiteralPath .copier-answers.yml) { [IO.File]::ReadAllText((Join-Path $root '.copier-answers.yml')) } else { '' }
    $library = $answers -match '(?m)^nuget_package:\s*true\s*$'

    function Invoke-Stage([string]$Name, [scriptblock]$Command) {
        "== $Name"
        & $Command
        if ($LASTEXITCODE) {
            ''
            "Definition of Done: FAILED at $Name"
            exit 1
        }
    }

    if (Test-Path -LiteralPath .config/dotnet-tools.json) { Invoke-Stage 'Tools' { dotnet tool restore } }
    Invoke-Stage 'Decisions' { pwsh -NoProfile -File .template/Test-AdrIndex.ps1 }
    if (-not (Get-ChildItem -LiteralPath $root -File | Where-Object Extension -In '.sln', '.slnx')) {
        "No solution at the repository root yet, so nothing to build: create it with dotnet new sln when adding the first project."
        ''
        'Definition of Done: PASSED'
        exit 0
    }
    Invoke-Stage 'Build' { dotnet build --configuration $configuration --nologo }
    $testArgs = @('--configuration', $configuration, '--no-build', '--nologo')
    if ($Filter) { $testArgs += '--filter', $Filter }
    Invoke-Stage 'Test' { dotnet test @testArgs }
    if ($library -and -not $Fast) { Invoke-Stage 'Pack' { dotnet pack --configuration $configuration --no-build --nologo --output artifacts/packages } }
    ''
    'Definition of Done: PASSED'
    exit 0
}
finally { Pop-Location }
