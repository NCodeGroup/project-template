<#
.SYNOPSIS
    Checks that docs/decisions/README.md indexes every decision record in docs/decisions/, and nothing else.

.DESCRIPTION
    From the project template; template updates replace this file. A decision record is a file named NNNN-<title>.md
    directly in docs/decisions/, other than 0000-template.md; the template's own records in docs/decisions/project-template/
    have an index of their own, which template updates keep. Fails, naming each one, on a record the README's index
    doesn't link, on a link in it to a record that doesn't exist, on two records that share a number (as when two
    branches each took the next free one), and on an index row whose link text shows another number than its record's.
    Passes when the repository has no docs/decisions/.

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
# Two branches or worktrees can each take the next free number; both records then pass every other check.
$duplicates = @($records | Group-Object { $_.Substring(0, 4) } | Where-Object Count -GT 1 | ForEach-Object { "$($_.Name): $($_.Group -join ', ')" })
# An index row shows a number as its link text; it must be its record's.
$mismatched = @([regex]::Matches($index, '\[(?:ADR-)?(\d{4})\]\((?:\./)?(\d{4})-[^)/#]+\.md') | Where-Object { $_.Groups[1].Value -ne $_.Groups[2].Value } | ForEach-Object { $_.Value })

foreach ($name in $missing) { "Not in docs/decisions/README.md's index: $name" }
foreach ($name in $dangling) { "docs/decisions/README.md links a record that doesn't exist: $name" }
foreach ($entry in $duplicates) { "Two records share the number $entry; renumber the later one" }
foreach ($link in $mismatched) { "docs/decisions/README.md shows another number than its record's: $link" }
$problems = $missing.Count + $dangling.Count + $duplicates.Count + $mismatched.Count
if ($problems) { "Decision index: FAILED ($problems)"; exit 1 }
"Decision index: $($records.Count) records, all indexed."
exit 0
