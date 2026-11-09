<#
.SYNOPSIS
    Check that Windows can check out every path in the repository.

.DESCRIPTION
    Runs Get-WindowsNameProblem on names Windows refuses and accepts, then lists every path with
    git ls-files -z --cached --others --exclude-standard and fails each one with a part Windows
    refuses (a control character, one of <>:"|?*\, a reserved name such as CON, NUL, COM1 or LPT1
    with or without an extension, or a name ending in a dot or a space), because Copier checks out
    the whole template repository at a tag and Git for Windows refuses such a path. Prints PASS or
    FAIL per check and exits 1 on any failure.

.EXAMPLE
    .\tests\Test-WindowsFileNames.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}

function Get-WindowsNameProblem([string]$Name) {
    if ($Name -match '[\x00-\x1F]') { return 'has a control character' }
    if ($Name -match '[<>:"|?*\\]') { return "has '$($Matches[0])', a character Windows forbids in file names" }
    if ($Name -match '^(?i:CON|PRN|AUX|NUL|COM[0-9\xB9\xB2\xB3]|LPT[0-9\xB9\xB2\xB3]|CONIN\$|CONOUT\$)(\..*)?$') { return 'is a name Windows reserves' }
    if ($Name -match '[. ]$') { return 'ends in a dot or a space' }
    ''
}

function Get-WindowsPathProblem([string[]]$Path) {
    foreach ($p in $Path) {
        foreach ($part in $p -split '/') {
            $why = Get-WindowsNameProblem $part
            if ($why) { "$p ($why)"; break }
        }
    }
}

$refused = [ordered]@{
    'a|b'                = "has '|', a character Windows forbids in file names"
    'a<b'                = "has '<', a character Windows forbids in file names"
    'a>b'                = "has '>', a character Windows forbids in file names"
    'a:b'                = "has ':', a character Windows forbids in file names"
    'a"b'                = "has '`"', a character Windows forbids in file names"
    'a?b'                = "has '?', a character Windows forbids in file names"
    'a*b'                = "has '*', a character Windows forbids in file names"
    'a\b'                = "has '\', a character Windows forbids in file names"
    'CON'                = 'is a name Windows reserves'
    'con.txt'            = 'is a name Windows reserves'
    'Nul'                = 'is a name Windows reserves'
    'PRN.md'             = 'is a name Windows reserves'
    'AUX'                = 'is a name Windows reserves'
    'COM1'               = 'is a name Windows reserves'
    'lpt9.log'           = 'is a name Windows reserves'
    'CONIN$'             = 'is a name Windows reserves'
    'name.'              = 'ends in a dot or a space'
    'name '              = 'ends in a dot or a space'
}
foreach ($name in $refused.Keys) {
    $result = Get-WindowsNameProblem $name
    Check "unit: refuses $name" ($result -eq $refused[$name]) "got '$result'"
}
$tab = "a$([char]9)b"
$result = Get-WindowsNameProblem $tab
Check 'unit: refuses a tab' ($result -eq 'has a control character') "got '$result'"

$accepted = @(
    "{% if stack == 'dotnet' %}global.json{% endif %}"
    "{% if (uses_node is defined and uses_node) or (uses_node is not defined and stack == 'node') %}.node-version{% endif %}"
    '.node-version'
    'CONTRIBUTING.md'
    'console.md'
    'COM10'
    'LPT'
    'README.md.jinja'
)
foreach ($name in $accepted) {
    $result = Get-WindowsNameProblem $name
    Check "unit: accepts $name" ($result -eq '') "got '$result'"
}

$listing = (git -C $repoRoot ls-files -z --cached --others --exclude-standard) -join "`n"
if ($LASTEXITCODE) { throw "git ls-files exited with code $LASTEXITCODE." }
$paths = @($listing -split "`0" | Where-Object { $_ })
Check 'repository: git lists the repository''s files' ($paths.Count -gt 100) "$($paths.Count) paths"
$bad = @(Get-WindowsPathProblem $paths)
Check 'repository: Windows can check out every path (write a file name''s condition with is defined, never a | filter)' (-not $bad) ($bad -join '; ')

''
if ($failures.Count) { "Windows file name tests: FAILED ($($failures.Count))"; exit 1 }
'Windows file name tests: PASSED'
exit 0
