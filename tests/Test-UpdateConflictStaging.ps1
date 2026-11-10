<#
.SYNOPSIS
    Test that an update that stops on a conflict leaves no file staged as an older version.

.DESCRIPTION
    Renders a project from v0.1.0 whose .gitignore ends with the block the adoption kept from the repository's own
    file, then updates it with -NoCommit to a v0.2.0 that changes .editorconfig, which the project changed too. The
    update must stop on the conflict in .editorconfig and leave it unmerged. The template also adds cafe.txt with an
    acute e (U+00E9), whose first line renders Copier's _folder_name, so the update conflicts on it too, and the
    project edits its second line, so the update's reset commit changes it: it must stay unmerged as well, which
    fails if the restage reads its unmerged list without core.quotePath=false. The .gitignore, which the update
    leaves as it was, must be neither listed nor staged, and must still end with the kept block. v0.2.0 also deletes
    removed-later.txt and changes changed-later.txt, which the project didn't edit: the update must stage both, the
    deletion included, and leave no change outside the conflicting files unstaged. Prints PASS or FAIL per check and
    exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-conflict-staging-test-<process ID>
    in the temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-UpdateConflictStaging.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-conflict-staging-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
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
# A template file with a non-ASCII name whose first line renders Copier's _folder_name: Copier renders an update's base in a temporary folder, so the update always conflicts on that line, and the reset restores the project's edit to its second line, so the reset commit changes it too.
$accented = "caf$([char]0xE9).txt"
$null = & (Join-Path $PSScriptRoot 'New-TemplateSnapshot.ps1') $tpl -BeforeCommit { [IO.File]::WriteAllText((Join-Path (Get-Location) "template/$accented.jinja"), "Rendered in {{ _folder_name }}`nA line the project edits`n"); [IO.File]::WriteAllText((Join-Path (Get-Location) 'template/removed-later.txt'), "removed by v0.2.0`n"); [IO.File]::WriteAllText((Join-Path (Get-Location) 'template/changed-later.txt'), "v0.1.0`n") }

Import-Module (Join-Path $repoRoot 'tools/adopt/Adoption.psm1') -Force
$marker = "# Kept from this repository's own .gitignore when it adopted the project template"
$kept = "# OpenTofu working directories and state`n.terraform/`n*.tfstate`n"

# Renders a project from v0.1.0 and replaces its .gitignore with the merge the adoption would have written.
$path = Join-Path $Work 'conflict-staging'
Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data 'project_name=ConflictStaging' --data stack=other --data git_host=github --data 'workflow_tools=[claude]' $tpl $path | Out-Null
$ignore = Join-Path $path '.gitignore'
[IO.File]::WriteAllText($ignore, (Merge-AdoptedFile '.gitignore' $kept ([IO.File]::ReadAllText($ignore))).Text)
Push-Location $path
try {
    Edit-File .editorconfig "indent_style = space`nindent_size = 4`n" "indent_style = space`nindent_size = 3`n"
    Edit-File $accented "A line the project edits`n" "A line the project edited`n"
    Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Adopt project-template v0.1.0'
}
finally { Pop-Location }

Push-Location (Join-Path $tpl 'template')
try { Edit-File .editorconfig.jinja "indent_style = space`nindent_size = 4`n" "indent_style = space`nindent_size = 8`n" }
finally { Pop-Location }
Push-Location $tpl
try { Invoke-Git rm -q template/removed-later.txt; [IO.File]::WriteAllText((Join-Path $tpl 'template/changed-later.txt'), "v0.2.0`n"); Invoke-Git commit -q -am 'Indent size 8'; Invoke-Git tag v0.2.0 }
finally { Pop-Location }

Push-Location $path
try {
    $before = [IO.File]::ReadAllText($ignore)
    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $path '.template\Update-Project.ps1') -NoCommit 2>&1 | ForEach-Object { $lines.Add("$_") }; $exitCode = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    $output = $lines -join "`n"
    $detail = "exit $exitCode`n$($output.Trim())`n$(git status --porcelain | Out-String)"
    Check 'conflict: the update stops on the conflict in .editorconfig' (($exitCode -eq 1) -and ($output -match '(?m)^  conflict  \.editorconfig\r?$')) $detail
    Check 'conflict: .editorconfig stays unmerged' ([bool](git ls-files -u -- .editorconfig)) $detail
    Check "conflict: $accented, which the reset changed, stays unmerged" ([bool](git ls-files -u -- $accented)) $detail
    Check 'kept: .gitignore, which the update left as it was, is neither listed nor staged' (($output -notmatch '(?m)^  \S+ +\.gitignore\r?$') -and -not (git status --porcelain -- .gitignore)) $detail
    Check 'staged: removed-later.txt, which v0.2.0 deletes, is staged as deleted' ((@(git diff --cached --name-only --diff-filter=D) -contains 'removed-later.txt') -and -not (git diff --name-only -- removed-later.txt)) $detail
    Check 'staged: changed-later.txt, which v0.2.0 changes, is staged as modified' ((@(git diff --cached --name-only --diff-filter=M) -contains 'changed-later.txt') -and -not (git diff --name-only -- changed-later.txt)) $detail
    $unmerged = @(git -c core.quotePath=false diff --name-only --diff-filter=U)
    $unstaged = @(git -c core.quotePath=false diff --name-only | Where-Object { $_ -notin $unmerged })
    Check 'staged: no change outside the conflicting files is left unstaged' ($unstaged.Count -eq 0) ($unstaged -join ', ')
    Check 'kept: .gitignore still ends with the kept block' (([IO.File]::ReadAllText($ignore) -eq $before) -and $before.EndsWith("$marker`n$kept")) $detail
}
finally { Pop-Location }
''
$env:COPIER_CACHE_DIR = $copierCache
if ($failures.Count) { "Kept the work folder: $Work"; "Update conflict staging tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Update conflict staging tests: PASSED'
exit 0
