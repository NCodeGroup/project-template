<#
.SYNOPSIS
    Check the OpenSSF Best Practices criteria map against the badge's own list of criteria.

.DESCRIPTION
    Runs Get-UpstreamCriteria on a small criteria.yml fixture and Compare-Criteria on small page fixtures,
    then reads criteria/criteria.yml from ossf/best-practices-badge and compares each level's criterion
    IDs, requirement levels (MUST, SHOULD or SUGGESTED), N/A flags and URL flags with the rows of
    template/docs/best-practices-criteria.md.jinja. A criterion without a row, a row without a criterion, a
    criterion listed twice and a row whose requirement, N/A or URL flag differs from the badge's all fail,
    so CI fails when the badge adds, renames or retires a criterion. It needs network access unless
    -Source names a file. Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Source
    The address or path of criteria.yml. Defaults to the file on the main branch of ossf/best-practices-badge.

.PARAMETER Page
    The path of the criteria page's Jinja source.

.EXAMPLE
    .\tests\Test-BestPracticesCriteria.ps1
#>
[CmdletBinding()]
param(
    [string]$Source = 'https://raw.githubusercontent.com/ossf/best-practices-badge/main/criteria/criteria.yml',
    [string]$Page = (Join-Path (Split-Path -Parent $PSScriptRoot) 'template/docs/best-practices-criteria.md.jinja')
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}

$levels = @('passing', 'silver', 'gold')

# criteria.yml has a fixed layout: a level is "- '0':" at column 0, a criterion "      - <id>:" at column 6
# (which can end with a comment) and its keys sit at column 10. PowerShell has no YAML parser.
function Get-UpstreamCriteria([string]$Text) {
    $names = @{ '0' = 'passing'; '1' = 'silver'; '2' = 'gold' }
    $found = [Collections.Generic.List[object]]::new()
    $level = $null
    $current = $null
    foreach ($line in $Text -split '\r?\n') {
        if ($line -match "^- '([012])':") {
            $level = $names[$Matches[1]]
            $current = $null
        }
        elseif ($line -match "^- '") {
            $level = $null
            $current = $null
        }
        elseif ($level -and $line -match '^      - ([A-Za-z0-9_]+):\s*(#.*)?$') {
            $current = [pscustomobject]@{ Level = $level; Id = $Matches[1]; Req = ''; NA = 'no'; Url = 'no' }
            $found.Add($current)
        }
        elseif ($current) {
            if ($line -match '^          category:\s*(MUST|SHOULD|SUGGESTED)') { $current.Req = $Matches[1] }
            elseif ($line -match '^          na_allowed:\s*true') { $current.NA = 'yes' }
            elseif ($line -match '^          met_url_required:\s*true') { $current.Url = 'yes' }
            elseif ($line -match '^          obsolete:\s*true') {
                [void]$found.Remove($current)
                $current = $null
            }
        }
    }
    $found.ToArray()
}

function Get-PageCriteria([string]$Text) {
    foreach ($section in [regex]::Matches($Text, '(?ms)^## (Passing|Silver|Gold)\r?$(.*?)(?=^## |\z)')) {
        $level = $section.Groups[1].Value.ToLowerInvariant()
        foreach ($row in [regex]::Matches($section.Groups[2].Value, '(?m)^\| `([A-Za-z0-9_]+)` \| (MUST|SHOULD|SUGGESTED) \| (yes|no) \| (yes|no) \| ')) {
            [pscustomobject]@{
                Level = $level
                Id    = $row.Groups[1].Value
                Req   = $row.Groups[2].Value
                NA    = $row.Groups[3].Value
                Url   = $row.Groups[4].Value
            }
        }
    }
}

function Compare-Criteria([object[]]$Upstream, [object[]]$Page) {
    foreach ($level in $levels) {
        $want = @($Upstream | Where-Object Level -EQ $level)
        $have = @($Page | Where-Object Level -EQ $level)
        foreach ($c in $want) {
            if (-not ($have | Where-Object Id -EQ $c.Id)) { "${level}: $($c.Id) is missing" }
        }
        foreach ($id in @($have | ForEach-Object Id | Select-Object -Unique)) {
            if (-not ($want | Where-Object Id -EQ $id)) { "${level}: $id is not a criterion at this level" }
        }
        foreach ($id in @($have | ForEach-Object Id | Select-Object -Unique)) {
            $rows = @($have | Where-Object Id -EQ $id)
            if ($rows.Count -gt 1) { "${level}: $id is listed $($rows.Count) times" }
        }
        foreach ($row in $have) {
            $c = $want | Where-Object Id -EQ $row.Id | Select-Object -First 1
            if (-not $c) { continue }
            if ($row -ne ($have | Where-Object Id -EQ $row.Id | Select-Object -First 1)) { continue }
            if ($row.Req -ne $c.Req) { "${level}: $($row.Id) has Req $($row.Req), the badge says $($c.Req)" }
            if ($row.NA -ne $c.NA) { "${level}: $($row.Id) has N/A $($row.NA), the badge says $($c.NA)" }
            if ($row.Url -ne $c.Url) { "${level}: $($row.Id) has URL $($row.Url), the badge says $($c.Url)" }
        }
    }
}

$fixture = @(
    '--- !!omap'
    "- '0': !!omap"
    '  - Basics: !!omap'
    '    - Group: !!omap'
    '      - alpha:'
    '          category: MUST'
    '          na_allowed: true'
    '      - beta: # a comment, as hardened_site has'
    '          category: SHOULD'
    '          met_url_required: true'
    '      - gone:'
    '          category: MUST'
    '          obsolete: true'
    "- '1': !!omap"
    '  - Basics: !!omap'
    '    - Group: !!omap'
    '      - alpha:'
    '          category: SUGGESTED'
) -join "`n"
$parsed = @(Get-UpstreamCriteria $fixture)
$flat = @($parsed | ForEach-Object { "$($_.Level)/$($_.Id)/$($_.Req)/$($_.NA)/$($_.Url)" })
$expected = @('passing/alpha/MUST/yes/no', 'passing/beta/SHOULD/no/yes', 'silver/alpha/SUGGESTED/no/no')
Check 'unit: Get-UpstreamCriteria reads a level, a trailing comment, N/A, URL and a retired criterion' ($flat.Count -eq 3 -and -not (Compare-Object $flat $expected)) "got $($flat -join ', ')"

$matching = @(
    '## Passing'
    ''
    '| `alpha` | MUST | yes | no | x |'
    '| `beta` | SHOULD | no | yes | x |'
    ''
    '## Silver'
    ''
    '| `alpha` | SUGGESTED | no | no | x |'
    ''
    '## Checks'
    ''
    '| `zeta` | MUST | no | no | x |'
) -join "`n"
$problems = @(Compare-Criteria $parsed @(Get-PageCriteria $matching))
Check 'unit: Compare-Criteria finds nothing wrong with a matching page' ($problems.Count -eq 0) ($problems -join '; ')

$wrong = @(
    '## Passing'
    ''
    '| `alpha` | MUST | yes | no | x |'
    '| `zeta` | MUST | no | no | x |'
    ''
    '## Silver'
    ''
    '| `alpha` | MUST | no | no | x |'
    '| `alpha` | MUST | no | no | x |'
) -join "`n"
$problems = @(Compare-Criteria $parsed @(Get-PageCriteria $wrong))
$expected = @(
    'passing: beta is missing'
    'passing: zeta is not a criterion at this level'
    'silver: alpha is listed 2 times'
    'silver: alpha has Req MUST, the badge says SUGGESTED'
)
Check 'unit: Compare-Criteria names a missing, an extra, a repeated and a mismatched row' ($problems.Count -eq 4 -and -not (Compare-Object $problems $expected)) "got $($problems -join '; ')"

if (Test-Path -LiteralPath $Source -PathType Leaf) {
    $yaml = Get-Content -Raw -LiteralPath $Source
}
else {
    $yaml = (Invoke-WebRequest -Uri $Source -TimeoutSec 60 -MaximumRetryCount 2 -RetryIntervalSec 5).Content
}
$upstream = @(Get-UpstreamCriteria $yaml)
$counts = @($levels | ForEach-Object { $level = $_; "$level $(@($upstream | Where-Object Level -EQ $level).Count)" })
$allLevels = -not @($levels | Where-Object { $level = $_; -not ($upstream | Where-Object Level -EQ $level) })
Check 'upstream: criteria.yml lists criteria at all three levels' $allLevels ($counts -join ', ')

if (-not [IO.Path]::IsPathRooted($Page)) { $Page = Join-Path $repoRoot $Page }
$pageRows = @(Get-PageCriteria (Get-Content -Raw -LiteralPath $Page))
$problems = @(Compare-Criteria $upstream $pageRows)
Check 'repository: the criteria map lists every criterion of criteria.yml at its level, with its Req, N/A and URL' ($problems.Count -eq 0) ($problems -join '; ')

''
if ($failures.Count) { "Best Practices criteria tests: FAILED ($($failures.Count))"; exit 1 }
'Best Practices criteria tests: PASSED'
exit 0
