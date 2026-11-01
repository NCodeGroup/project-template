<#
.SYNOPSIS
    Checks that docs/decisions/README.md indexes every decision record in docs/decisions/, and nothing else.

.DESCRIPTION
    From the project template; template updates replace this file. A decision record is a file named NNNN-<title>.md
    directly in docs/decisions/, other than 0000-template.md; the template's own records in docs/decisions/project-template/
    have an index of their own, which template updates keep. Fails, naming each one, on a record the README's index
    doesn't link and on a link in it to a record that doesn't exist. Passes when the repository has no docs/decisions/.

.PARAMETER Path
    The repository root. Defaults to the folder above this script's.

.EXAMPLE
    ./.template/Test-AdrIndex.ps1
#>
[CmdletBinding()]
param([string]$Path = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$folder = Join-Path $Path 'docs/decisions'
if (-not (Test-Path -LiteralPath $folder)) { 'Decision index: no docs/decisions/ folder.'; exit 0 }
$readme = Join-Path $folder 'README.md'
$index = if (Test-Path -LiteralPath $readme) { [IO.File]::ReadAllText($readme) } else { '' }

$records = @(Get-ChildItem -LiteralPath $folder -File -Filter '*.md' | Where-Object { $_.Name -match '^\d{4}-.+\.md$' -and $_.Name -ne '0000-template.md' } | ForEach-Object Name | Sort-Object)
$linked = @([regex]::Matches($index, '\]\((?:\./)?(\d{4}-[^)/#]+\.md)(?:#[^)]*)?\)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne '0000-template.md' } | Sort-Object -Unique)
$missing = @($records | Where-Object { $_ -notin $linked })
$dangling = @($linked | Where-Object { $_ -notin $records })

foreach ($name in $missing) { "Not in docs/decisions/README.md's index: $name" }
foreach ($name in $dangling) { "docs/decisions/README.md links a record that doesn't exist: $name" }
if ($missing -or $dangling) { "Decision index: FAILED ($($missing.Count + $dangling.Count))"; exit 1 }
"Decision index: $($records.Count) records, all indexed."
exit 0
