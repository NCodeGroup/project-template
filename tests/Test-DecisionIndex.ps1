<#
.SYNOPSIS
    Test the decision index check every project gets as .template\Test-AdrIndex.ps1.

.DESCRIPTION
    Builds one small fixture project per case, runs the check on it and compares the exit code and the output. Also
    checks that every decision record the template ships in docs/decisions/project-template/ is numbered 0001-0999 and
    linked from the template's index. Prints PASS or FAIL per check and exits 1 on any failure. The checks take seconds.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-decision-index-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-DecisionIndex.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-decision-index-test-$PID")
)
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
# Creates the fixture project $Work\<Name> and writes each file, keyed by its path relative to that root.
function New-Fixture([string]$Name, [hashtable]$Files) {
    $root = Join-Path $Work $Name
    New-Item -ItemType Directory -Force $root | Out-Null
    foreach ($relative in $Files.Keys) {
        $path = Join-Path $root $relative
        New-Item -ItemType Directory -Force (Split-Path -Parent $path) | Out-Null
        [IO.File]::WriteAllText($path, $Files[$relative], [Text.UTF8Encoding]::new($false))
    }
    $root
}
function Invoke-AdrIndex([string]$Root) {
    $output = & $adrIndex -Path $Root 2>&1 | Out-String
    [pscustomobject]@{ Exit = $LASTEXITCODE; Output = $output }
}
function Get-Readme([string[]]$Rows) {
    (@('| ADR | Decision | Status |', '| --- | --- | --- |') + $Rows) -join "`n"
}
# The decision records in a template folder; most names start with Jinja, so the pattern is not anchored.
function Get-TemplateRecord([string]$Folder) { @(Get-ChildItem -LiteralPath $Folder -File | ForEach-Object { if ($_.Name -match '(\d{4})-[^{}%]+?\.md') { [pscustomobject]@{ Number = [int]$Matches[1]; Record = $Matches[0] } } }) }
function Get-OutOfRange([object[]]$Records) { @($Records | Where-Object { $_.Number -lt 1 -or $_.Number -gt 999 } | ForEach-Object Record) }
function Get-SharedNumber([object[]]$Records) { @($Records | Group-Object Number | Where-Object Count -GT 1 | ForEach-Object { '{0:D4}: {1}' -f [int]$_.Name, (($_.Group.Record | Sort-Object) -join ', ') }) }

$adrIndex = Join-Path $repoRoot 'template\.template\Test-AdrIndex.ps1'
$record = '# x'
$rowA = '| [0001](0001-a.md) | A | Accepted |'
$rowB = '| [0002](0002-b.md) | B | Accepted |'
$row1000 = '| [1000](1000-a.md) | A | Accepted |'
$row1001 = '| [1001](1001-b.md) | B | Accepted |'
$allIndexed = 'Decision index: 2 records, all indexed.'

# Each case: a name, the files of the fixture project, the expected exit code and the text the output must contain.
$cases = @(
    @{ Name = 'no docs/decisions folder passes'; Files = @{}; Exit = 0; Text = 'Decision index: no docs/decisions/ folder.' }
    @{
        Name  = 'records from 0001 pass'
        Files = @{
            'docs/decisions/0000-template.md' = $record
            'docs/decisions/0001-a.md'        = $record
            'docs/decisions/0002-b.md'        = $record
            'docs/decisions/README.md'        = Get-Readme @($rowA, $rowB)
        }
        Exit  = 0
        Text  = $allIndexed
    }
    @{
        Name  = 'records from 1000 pass'
        Files = @{
            'docs/decisions/1000-a.md' = $record
            'docs/decisions/1001-b.md' = $record
            'docs/decisions/README.md' = Get-Readme @($row1000, $row1001)
        }
        Exit  = 0
        Text  = $allIndexed
    }
    @{
        Name  = 'records below and from 1000 together pass'
        Files = @{
            'docs/decisions/0003-a.md' = $record
            'docs/decisions/1000-b.md' = $record
            'docs/decisions/README.md' = Get-Readme @('| [0003](0003-a.md) | A | Accepted |', '| [1000](1000-b.md) | B | Accepted |')
        }
        Exit  = 0
        Text  = $allIndexed
    }
    @{
        Name  = "the template's records are not counted"
        Files = @{
            'docs/decisions/project-template/0001-a.md' = $record
            'docs/decisions/project-template/README.md' = Get-Readme @($rowA)
            'docs/decisions/1000-b.md'                  = $record
            'docs/decisions/README.md'                  = Get-Readme @('| [1000](1000-b.md) | B | Accepted |')
        }
        Exit  = 0
        Text  = 'Decision index: 1 records, all indexed.'
    }
    @{
        Name  = 'an unindexed record fails'
        Files = @{
            'docs/decisions/1000-a.md' = $record
            'docs/decisions/README.md' = Get-Readme @()
        }
        Exit  = 1
        Text  = "Not in docs/decisions/README.md's index: 1000-a.md"
    }
    @{
        Name  = 'a link to a missing record fails'
        Files = @{
            'docs/decisions/1000-a.md' = $record
            'docs/decisions/README.md' = Get-Readme @($row1000, '| [1001](1001-gone.md) | Gone | Accepted |')
        }
        Exit  = 1
        Text  = "links a record that doesn't exist: 1001-gone.md"
    }
    @{
        Name  = 'two records with one number fail'
        Files = @{
            'docs/decisions/1000-a.md' = $record
            'docs/decisions/1000-b.md' = $record
            'docs/decisions/README.md' = Get-Readme @($row1000, '| [1000](1000-b.md) | B | Accepted |')
        }
        Exit  = 1
        Text  = 'Two records share the number 1000'
    }
    @{
        Name  = 'a row showing another number fails'
        Files = @{
            'docs/decisions/1000-a.md' = $record
            'docs/decisions/README.md' = Get-Readme @('| [1001](1000-a.md) | A | Accepted |')
        }
        Exit  = 1
        Text  = "shows another number than its record's"
    }
)

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null
$caseNumber = 0
foreach ($case in $cases) {
    $caseNumber++
    $root = New-Fixture "case-$caseNumber" $case.Files
    $result = Invoke-AdrIndex $root
    $ok = ($result.Exit -eq $case.Exit) -and $result.Output.Contains($case.Text)
    Check "index: $($case.Name)" $ok "exit $($result.Exit), expected $($case.Exit); expected output to contain: $($case.Text); output: $($result.Output)"
}

# A fixture folder of template records shows each repository check's building blocks working, and failing.
$fixtureRoot = New-Fixture 'template-records' @{
    '0001-a.md'                                     = $record
    "{% if stack == 'dotnet' %}0100-b.md{% endif %}" = $record
    '0100-c.md'                                     = $record
    '1000-D.md'                                     = $record
    'README.md.jinja'                               = $record
}
$fixtureRecords = Get-TemplateRecord $fixtureRoot
$found = ($fixtureRecords.Record | Sort-Object) -join ','
Check 'template records: the pattern finds plain, Jinja-named and capitalised names' ($found -eq '0001-a.md,0100-b.md,0100-c.md,1000-D.md') "found: $found"
$fixtureOutside = (Get-OutOfRange $fixtureRecords) -join ','
Check 'template records: a record numbered 1000 is out of range' ($fixtureOutside -eq '1000-D.md') "out of range: $fixtureOutside"
$fixtureShared = (Get-SharedNumber $fixtureRecords) -join ';'
Check 'template records: two records with one number are named' ($fixtureShared -eq '0100: 0100-b.md, 0100-c.md') "shared: $fixtureShared"

# The template's own records, in the folder every template update replaces.
$templateFolder = Join-Path $repoRoot 'template\docs\decisions\project-template'
$templateRecords = Get-TemplateRecord $templateFolder
$outside = Get-OutOfRange $templateRecords
Check 'repository: every template decision record is numbered 0001-0999' (($templateRecords.Count -gt 0) -and -not $outside) "records: $($templateRecords.Count); outside 0001-0999: $($outside -join ', ')"

$templateIndex = [IO.File]::ReadAllText((Join-Path $templateFolder 'README.md.jinja'))
$unlinked = @($templateRecords | Where-Object { -not $templateIndex.Contains("($($_.Record))") } | ForEach-Object Record)
Check "repository: the template's decision index links every template record" (($templateRecords.Count -gt 0) -and -not $unlinked) "records: $($templateRecords.Count); not linked: $($unlinked -join ', ')"

$shared = Get-SharedNumber $templateRecords
Check 'repository: no two template decision records share a number' (($templateRecords.Count -gt 0) -and -not $shared) "records: $($templateRecords.Count); sharing a number: $($shared -join '; ')"

if ($failures.Count) { "Kept the work folder: $Work"; "Decision index tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Decision index tests: PASSED'
exit 0
