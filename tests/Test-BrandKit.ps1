<#
.SYNOPSIS
    Test the logo kit generator, brand/build.mjs.

.DESCRIPTION
    Checks that `node brand/build.mjs --check` passes on the committed kit, so every file in brand/ and
    template/NCodeGroup.png holds what the script draws. Then builds the kit into an empty folder with --output and
    checks that it writes every file the committed kit has and that its own --check passes there, and that the
    check fails, naming the file, once one file is removed or holds something else. Prints PASS or FAIL per check
    and exits 1 on any failure.
    Needs the Node.js release .node-version names on PATH, and no packages. The checks take about half a minute.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-brand-test-<process ID> in the temp
    folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-BrandKit.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-brand-test-$PID")
)
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
# Runs brand/build.mjs with the arguments, and returns its exit code and output.
function Invoke-Build([string[]]$Arguments) {
    $output = & node (Join-Path $repoRoot 'brand/build.mjs') @Arguments 2>&1 | Out-String
    [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output }
}
# The files a run's report lists: one line per file, its name and its size, before the "N files, M bytes" total.
function Get-ReportedFile([string]$Output) {
    @([regex]::Matches($Output, '(?m)^(\S+)\s+\d+\b') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notmatch '^\d+$' })
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js not found: install the release .node-version names, see CONTRIBUTING.md.' }
if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

$committed = Invoke-Build @('--check')
Check 'brand/build.mjs --check passes on the committed kit (run node brand/build.mjs and commit what it writes)' ($committed.Code -eq 0 -and $committed.Output.Contains('No file would change.')) $committed.Output.Trim()
$kitFiles = @(Get-ReportedFile $committed.Output | Where-Object { $_ -ne 'template/NCodeGroup.png' })
Check 'the committed kit lists its files' ($kitFiles.Count -gt 50) "files: $($kitFiles.Count)"

$out = Join-Path $Work 'kit'
$built = Invoke-Build @('--output', $out)
$missing = @($kitFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $out $_)) })
Check 'a build into an empty folder writes every file the kit has' ($built.Code -eq 0 -and -not $missing) "exit $($built.Code); missing: $($missing -join ', ')"
Check 'a build into an empty folder leaves template/NCodeGroup.png alone' (-not (Get-ReportedFile $built.Output).Contains('template/NCodeGroup.png')) $built.Output.Trim()
$rebuilt = Invoke-Build @('--output', $out, '--check')
Check 'the check passes on the kit it just wrote' ($rebuilt.Code -eq 0) $rebuilt.Output.Trim()

$removed = 'tile/ncode-tile-dark-256.png'
Remove-Item -LiteralPath (Join-Path $out $removed)
$broken = Invoke-Build @('--output', $out, '--check')
Check 'the check fails, naming the file, once one is removed' ($broken.Code -eq 1 -and $broken.Output -match "(?m)^$([regex]::Escape($removed))\s.*missing") $broken.Output.Trim()
Check 'the check writes nothing' (-not (Test-Path -LiteralPath (Join-Path $out $removed)))

$changed = 'mark/ncode-mark-blue.svg'
$changedPath = Join-Path $out $changed
$drifted = [IO.File]::ReadAllText($changedPath).Replace('#0033CC', '#0033CD')
[IO.File]::WriteAllText($changedPath, $drifted)
$drift = Invoke-Build @('--output', $out, '--check')
Check 'the check fails, naming the file, once a file holds something else' ($drift.Code -eq 1 -and $drift.Output -match "(?m)^$([regex]::Escape($changed))\s.*would change") $drift.Output.Trim()
Check 'the check leaves a file that holds something else as it is' ([IO.File]::ReadAllText($changedPath) -eq $drifted)

if ($failures.Count) { "Kept the work folder: $Work"; "Brand kit tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Brand kit tests: PASSED'
exit 0
