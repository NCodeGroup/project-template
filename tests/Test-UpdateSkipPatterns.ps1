<#
.SYNOPSIS
    Test that an update brings a nested file up to date when a skip pattern without a / used to match it.

.DESCRIPTION
    Renders a project from a v0.1.0 whose copier.yml lists README.md under _skip_if_exists without a leading /, which
    Copier reads like a .gitignore pattern and so also matches docs/decisions/project-template/README.md, and whose
    decision index lacks the 0014 row. The project's copy of the index also lacks the 0013 row and has a line of its
    own. Updates it to a v0.2.0 with the repository's own copier.yml and index plus a change to the template's
    README.md. The update must commit without a conflict, bring the index up to the target version and list it as
    refreshed, saying its local edit is discarded, not as a discarded local edit, and leave the project's own
    README.md as it is while showing the template's change to it. Also checks that Test-CopierPattern reads file
    patterns as Copier does and that every _skip_if_exists entry in copier.yml starts with /. Prints PASS or FAIL per
    check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-skip-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-UpdateSkipPatterns.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-skip-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Invoke-Copier {
    if (Get-Command copier -ErrorAction SilentlyContinue) { & copier @args }
    elseif (Get-Command uvx -ErrorAction SilentlyContinue) { & uvx --from copier copier @args }
    else { throw 'Copier not found. Install it with: uv tool install copier' }
    if ($LASTEXITCODE) { throw "copier $($args[0]) exited with code $LASTEXITCODE." }
}
function Edit-File([string]$Path, [string]$Old, [string]$New) {
    $full = (Resolve-Path -LiteralPath $Path).Path
    $text = [IO.File]::ReadAllText($full)
    if (-not $text.Contains($Old)) { throw "'$Old' not found in $full." }
    [IO.File]::WriteAllText($full, $text.Replace($Old, $New))
}
function Invoke-Git {
    git -c user.name=template-test -c user.email=template-test@example.invalid @args
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed." }
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
# A direct run keeps its Copier mirror in its own work folder, not in the user's cache; under tests\Invoke-AllTests.ps1 it keeps the runner's folder.
$copierCache = $env:COPIER_CACHE_DIR
if (-not $copierCache) { $env:COPIER_CACHE_DIR = Join-Path $Work 'copier-cache' }
$tpl = Join-Path $Work 'template-repo'

$repoRoot = Split-Path -Parent $PSScriptRoot
$indexSource = 'template/docs/decisions/project-template/README.md.jinja'

$updateAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null)
$fn = $updateAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-CopierPattern' }, $true)
if ($fn) { . ([scriptblock]::Create($fn.Extent.Text)) }
Check 'unit: Test-CopierPattern reads file patterns as Copier does' ([bool](Get-Command Test-CopierPattern -CommandType Function -ErrorAction SilentlyContinue) -and
    (Test-CopierPattern 'docs/decisions/project-template/README.md' @('README.md')) -eq $true -and
    (Test-CopierPattern 'docs/decisions/project-template/README.md' @('/README.md')) -eq $false -and
    (Test-CopierPattern 'README.md' @('/README.md')) -eq $true -and
    (Test-CopierPattern 'docs/decisions/README.md' @('/docs/decisions/README.md')) -eq $true -and
    (Test-CopierPattern 'docs/decisions/README.md' @('docs/decisions/README.md')) -eq $true -and
    (Test-CopierPattern 'x/docs/decisions/README.md' @('docs/decisions/README.md')) -eq $false -and
    (Test-CopierPattern 'readme.md' @('/README.md')) -eq $false)

$skip = @(
    $inList = $false
    foreach ($line in Get-Content -LiteralPath (Join-Path $repoRoot 'copier.yml')) {
        if ($line -match '^_skip_if_exists:') { $inList = $true; continue }
        if ($inList -and $line -match '^\s+-\s+(.+?)\s*$') { $Matches[1].Trim("'", '"') }
        elseif ($inList -and $line -match '^\S') { break }
    }
)
Check 'repository: every _skip_if_exists entry in copier.yml starts with /' (($skip.Count -ge 15) -and -not @($skip | Where-Object { -not $_.StartsWith('/') -or $_ -match '[*?\[]' }).Count) ($skip -join ',')

# v0.1.0 lists the skip entries without a leading / and has no 0014 row in the decision index.
$null = & (Join-Path $PSScriptRoot 'New-TemplateSnapshot.ps1') $tpl -BeforeCommit {
    $yml = Join-Path (Get-Location) 'copier.yml'
    [IO.File]::WriteAllText($yml, ([IO.File]::ReadAllText($yml) -replace '(?m)^  - /', '  - '))
    $idx = Join-Path (Get-Location) $indexSource
    [IO.File]::WriteAllText($idx, ([IO.File]::ReadAllText($idx) -replace '(?m)^\| \[0014\]\(.*\r?\n', ''))
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'copier.yml') -Destination (Join-Path $tpl 'copier.yml') -Force
Copy-Item -LiteralPath (Join-Path $repoRoot $indexSource) -Destination (Join-Path $tpl $indexSource) -Force
Push-Location (Join-Path $tpl 'template')
try { Edit-File README.md.jinja "`n## Development`n" "`n## Development and Tests`n" }
finally { Pop-Location }
Push-Location $tpl
try { Invoke-Git add -A; Invoke-Git commit -q -m 'Anchor skip patterns, add the 0014 row, change README.md'; Invoke-Git tag v0.2.0 }
finally { Pop-Location }

$path = Join-Path $Work 'skip'
Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data 'project_name=Skip' --data stack=python --data git_host=github --data 'workflow_tools=[claude]' $tpl $path | Out-Null
$nested = Join-Path $path 'docs/decisions/project-template/README.md'
# An earlier version wrote the index without the 0013 row.
[IO.File]::WriteAllText($nested, ([IO.File]::ReadAllText($nested) -replace '(?m)^\| \[0013\]\(.*\r?\n', ''))
# The project also added a line of its own to the index, which the refresh discards.
[IO.File]::AppendAllText($nested, "Local note the refresh discards.`n")
Push-Location $path
try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Render project-template v0.1.0' }
finally { Pop-Location }
$readmeHash = (Get-FileHash -LiteralPath (Join-Path $path 'README.md')).Hash

function Invoke-Update([hashtable]$Data) {
    $lines = [Collections.Generic.List[string]]::new()
    $exitCode = 0
    try {
        if ($Data) { & (Join-Path $path '.template\Update-Project.ps1') -Data $Data 2>&1 | ForEach-Object { $lines.Add("$_") } }
        else { & (Join-Path $path '.template\Update-Project.ps1') 2>&1 | ForEach-Object { $lines.Add("$_") } }
        $exitCode = $LASTEXITCODE
    }
    catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    [pscustomobject]@{ ExitCode = $exitCode; Output = ($lines -join "`n") }
}

Push-Location $path
try {
    $r = Invoke-Update $null
    $status = git status --porcelain
    $index = [IO.File]::ReadAllText($nested)
    $detail = "exit $($r.ExitCode)`n$($r.Output.Trim())"
    Check 'update: commits without a conflict' (($r.ExitCode -eq 0) -and $r.Output.Contains('Committed "Update from project-template v0.2.0"') -and -not $status) $detail
    Check 'update: brings docs/decisions/project-template/README.md up to the target version' ($index.Contains('| [0013](0013-') -and $index.Contains('| [0014](0014-')) $detail
    Check 'update: lists the decision index as refreshed, not as a discarded local edit' (($r.Output -match '(?m)^Refreshed — .*\r?\n  docs/decisions/project-template/README\.md\r?$') -and -not $r.Output.Contains('Local edits discarded')) $detail
    Check 'update: says that refreshing the decision index discards its local edit' ((-not $index.Contains('Local note the refresh discards.')) -and $r.Output.Contains('a local edit to one is discarded, so make the change in a project file instead:')) $detail
    Check "update: leaves the project's own README.md untouched and shows the template's change to it" (((Get-FileHash -LiteralPath (Join-Path $path 'README.md')).Hash -eq $readmeHash) -and ($r.Output -match '(?m)^  README\.md:\r?$') -and $r.Output.Contains('+## Development and Tests')) $detail
}
finally { Pop-Location }
''
$env:COPIER_CACHE_DIR = $copierCache
if ($failures.Count) { "Kept the work folder: $Work"; "Update skip-pattern tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Update skip-pattern tests: PASSED'
exit 0
