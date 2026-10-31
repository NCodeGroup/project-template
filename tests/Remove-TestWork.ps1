<#
.SYNOPSIS
    Deletes a test run's own work folder, on a best-effort basis.

.DESCRIPTION
    The tests/Test-*.ps1 suites and tests/Invoke-AllTests.ps1 call it when a run that made its own work folder (no
    -Work) passes. Deletes the folder and, when it can't, for example because a file in it is still open, prints
    "Couldn't delete the work folder: <path>" and leaves the run passing.

.PARAMETER Path
    The work folder.

.EXAMPLE
    & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path)
Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $Path) { "Couldn't delete the work folder: $Path" }
