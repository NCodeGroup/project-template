<#
.SYNOPSIS
    Test that an adopted project's update keeps the lines it kept at adoption out of the template's merge.

.DESCRIPTION
    Renders three projects from v0.1.0 whose .gitignore ends with the block the adoption kept from the repository's own
    file, then updates them to a v0.2.0 that changes the secrets/ rule just above that block and adds a file,
    update-added.txt. The first project has no edit of its own and must update without a conflict. The second has a
    project edit next to the change and must stop on a conflict that leaves the kept block outside both sides and says
    to finish with git add -u. The update adds the file in the first project and stages it in the second. Both have a
    node_modules/ and a .turbo/ folder that only the kept lines ignore, which neither update may stage or commit, and
    the first must leave .git/info/exclude as it was. The third has a docs/secrets/ file that v0.1.0's secrets/ ignores
    and v0.2.0's /secrets/ doesn't: its update, with -NoCommit, must leave that file untracked. The fourth, adopted
    before Adopt-Project.ps1 left a catch-all text rule out, keeps * text=auto and * text eol=lf in its .gitattributes:
    its update, with -NoCommit, must leave both out of the kept lines, keep its other kept line, stage the change, say
    so, and leave an .ico file binary (git check-attr text answers unset). The fifth keeps a bare * text and a
    * text eol=crlf: its update leaves only the bare rule out. Prints PASS or FAIL per check and exits 1 on any
    failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-kept-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-UpdateKeptLines.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-kept-test-$PID"))
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
# v0.1.0 has the secrets rule the template had before v0.15.0, which v0.2.0 changes back.
$null = & (Join-Path $PSScriptRoot 'New-TemplateSnapshot.ps1') $tpl -BeforeCommit { Edit-File template/.gitignore.jinja "`n/secrets/`n" "`nsecrets/`n" }

Import-Module (Join-Path $repoRoot 'tools/adopt/Adoption.psm1') -Force
$marker = "# Kept from this repository's own .gitignore when it adopted the project template"
$kept = "# OpenTofu working directories and state`n.terraform/`n*.tfstate`n*.tfplan`nplan.txt`n# Frontend packages and build cache`nnode_modules/`n.turbo/`n"

# Renders a project from v0.1.0 and replaces its .gitignore with the merge the adoption would have written.
function New-AdoptedProject([string]$Name) {
    $path = Join-Path $Work $Name
    Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data "project_name=$Name" --data stack=other --data git_host=github --data 'workflow_tools=[claude]' $tpl $path | Out-Null
    $ignore = Join-Path $path '.gitignore'
    [IO.File]::WriteAllText($ignore, (Merge-AdoptedFile '.gitignore' $kept ([IO.File]::ReadAllText($ignore))).Text)
    Push-Location $path
    try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Adopt project-template v0.1.0' }
    finally { Pop-Location }
    $path
}
# Fills the folders that only the kept lines ignore, as an installed and built frontend does: an update must never stage them.
function Add-KeptIgnoredFile([string]$Path) {
    foreach ($i in 1..200) {
        $package = Join-Path $Path ('node_modules/package-{0:d3}' -f $i)
        [void][IO.Directory]::CreateDirectory($package)
        [IO.File]::WriteAllText((Join-Path $package 'index.js'), 'x')
    }
    [void][IO.Directory]::CreateDirectory((Join-Path $Path '.turbo'))
    [IO.File]::WriteAllText((Join-Path $Path '.turbo/cache.log'), 'x')
}
$a = New-AdoptedProject 'adopted'
$b = New-AdoptedProject 'adopted-edit'
Add-KeptIgnoredFile $a
Add-KeptIgnoredFile $b
$c = New-AdoptedProject 'adopted-unignored'
# v0.1.0's secrets/ ignores docs/secrets/ too, and v0.2.0's /secrets/ doesn't.
[void][IO.Directory]::CreateDirectory((Join-Path $c 'docs/secrets'))
[IO.File]::WriteAllText((Join-Path $c 'docs/secrets/token.txt'), 'x')

# The second project adds a line of its own right below secrets/, next to where v0.2.0 changes it.
Push-Location $b
try {
    Edit-File .gitignore "`nsecrets/`n`n$marker" "`nsecrets/`n/vault/`n`n$marker"
    Invoke-Git commit -q -am 'Ignore the vault folder'
}
finally { Pop-Location }

Push-Location (Join-Path $tpl 'template')
try { Edit-File .gitignore.jinja "`nsecrets/`n" "`n/secrets/`n"; [IO.File]::WriteAllText((Join-Path (Get-Location) 'update-added.txt'), "added by v0.2.0`n") }
finally { Pop-Location }
Push-Location $tpl
try { Invoke-Git add -A; Invoke-Git commit -q -m 'Root secrets folder only'; Invoke-Git tag v0.2.0 }
finally { Pop-Location }

Push-Location $a
try {
    $text = [IO.File]::ReadAllText((Join-Path $a '.gitignore'))
    Check 'fixture: the adopted .gitignore ends with secrets/ and then the kept block' ($text.EndsWith("`nsecrets/`n`n$marker`n$kept")) $text
    $infoExclude = git rev-parse --path-format=absolute --git-path info/exclude
    New-Item -ItemType Directory -Force (Split-Path $infoExclude) | Out-Null
    [IO.File]::WriteAllText($infoExclude, "# kept by the project`n")

    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $a '.template\Update-Project.ps1') 2>&1 | ForEach-Object { $lines.Add("$_") }; $exitCode = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    $output = $lines -join "`n"
    Check 'update: the change to secrets/ next to the kept block merges without a conflict' (($exitCode -eq 0) -and $output.Contains('Committed "Update from project-template v0.2.0"') -and -not (git status --porcelain)) "exit $exitCode`n$($output.Trim())`n$(git status --porcelain | Out-String)"
    Check 'update: the file v0.2.0 adds is committed' ((@(git ls-files -- update-added.txt) -contains 'update-added.txt') -and (Test-Path -LiteralPath update-added.txt))
    $text = [IO.File]::ReadAllText((Join-Path $a '.gitignore'))
    Check 'update: .gitignore has /secrets/ and still ends with the kept block' ($text.Contains("`n/secrets/`n") -and -not $text.Contains("`nsecrets/`n") -and $text.EndsWith("`n/secrets/`n`n$marker`n$kept")) $text
    $tracked = @(git ls-files -- node_modules .turbo) + @(git log --format= --name-only -- node_modules .turbo)
    Check 'update: nothing that only the kept lines ignore is staged or committed' ($tracked.Count -eq 0) ($tracked | Select-Object -First 5 | Out-String)
    Check 'update: the folders that only the kept lines ignore stay in place' ((Test-Path -LiteralPath node_modules/package-001/index.js) -and (Test-Path -LiteralPath .turbo/cache.log))
    $excludeAfter = [IO.File]::ReadAllText($infoExclude)
    Check 'update: info/exclude ends as it was' ($excludeAfter -eq "# kept by the project`n") "after: '$excludeAfter'"

    $afterFirst = $text
    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $a '.template\Update-Project.ps1') 2>&1 | ForEach-Object { $lines.Add("$_") }; $exitCode = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    $output = $lines -join "`n"
    $text = [IO.File]::ReadAllText((Join-Path $a '.gitignore'))
    Check 'update: a second run has nothing to update and changes nothing' (($exitCode -eq 0) -and $output.Contains('Already up to date: template v0.2.0.') -and -not (git status --porcelain) -and ($text -eq $afterFirst)) "exit $exitCode`n$($output.Trim())`n$(git status --porcelain | Out-String)"
}
finally { Pop-Location }

Push-Location $b
try {
    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $b '.template\Update-Project.ps1') 2>&1 | ForEach-Object { $lines.Add("$_") }; $exitCode = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    $output = $lines -join "`n"
    Check 'conflict: a project edit next to the change stops the update on .gitignore' (($exitCode -eq 1) -and $output.Contains('conflict  .gitignore')) "exit $exitCode`n$($output.Trim())"
    $text = [IO.File]::ReadAllText((Join-Path $b '.gitignore'))
    Check 'conflict: the kept block stays after the conflict, out of both sides' (($text.IndexOf($marker) -gt $text.LastIndexOf('>>>>>>>')) -and ($text.LastIndexOf('>>>>>>>') -ge 0) -and $text.Contains('/vault/') -and $text.EndsWith("`n`n$marker`n$kept")) $text
    $staged = @(git ls-files -- node_modules .turbo)
    Check 'conflict: nothing that only the kept lines ignore is staged' ($staged.Count -eq 0) ($staged | Select-Object -First 5 | Out-String)
    $stagedFiles = @(git diff --cached --name-only)
    Check 'conflict: the file v0.2.0 adds is staged and .gitignore stays unmerged' (($stagedFiles -contains 'update-added.txt') -and (@(git diff --name-only --diff-filter=U) -contains '.gitignore')) ($stagedFiles -join ', ')
    Check 'conflict: the update says to stage the resolved files with git add -u, not git add -A' (($lines -contains '  git add -u') -and -not ($lines -contains '  git add -A')) $output.Trim()
}
finally { Pop-Location }

Push-Location $c
try {
    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $c '.template\Update-Project.ps1') -NoCommit 2>&1 | ForEach-Object { $lines.Add("$_") }; $exitCode = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    $output = $lines -join "`n"
    Check 'unignored: the update stages without a conflict' (($exitCode -eq 0) -and $output.Contains('Staged for review')) "exit $exitCode`n$($output.Trim())"
    $staged = @(git ls-files -- docs/secrets)
    Check 'unignored: a file the project ignored before the update is not staged' ($staged.Count -eq 0) ($staged | Out-String)
    Check 'unignored: fixture: the updated .gitignore does not ignore it, so it is left untracked' ([bool](git ls-files --others --exclude-standard -- docs/secrets)) (git status --porcelain | Out-String)
}
finally { Pop-Location }

# A project adopted before Adopt-Project.ps1 left a catch-all text rule out of the lines it keeps (v0.41.1), whose .gitattributes still holds the rule.
$d = New-AdoptedProject 'adopted-attributes'
$attributesMarker = "# Kept from this repository's own .gitattributes when it adopted the project template"
Push-Location $d
try {
    $attributes = Join-Path $d '.gitattributes'
    [IO.File]::WriteAllText($attributes, [IO.File]::ReadAllText($attributes).TrimEnd("`n") + "`n`n$attributesMarker`n* text=auto`n* text eol=lf`n*.cs text diff=csharp`n")
    Invoke-Git commit -q -am 'Keep the catch-all text rules'
    Check 'attributes: fixture: the kept catch-all rule makes an icon text' ((git check-attr text -- x.ico) -eq 'x.ico: text: set') (git check-attr text -- x.ico | Out-String)
    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $d '.template\Update-Project.ps1') -NoCommit 2>&1 | ForEach-Object { $lines.Add("$_") }; $exitCode = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    $output = $lines -join "`n"
    $text = [IO.File]::ReadAllText($attributes)
    Check 'attributes: the update leaves the catch-all text rules out of the kept lines and keeps the others' (($exitCode -eq 0) -and $text.EndsWith("`n$attributesMarker`n*.cs text diff=csharp`n")) "exit $exitCode`n$text"
    Check 'attributes: an icon is no longer text' ((git check-attr text -- x.ico) -eq 'x.ico: text: unset') (git check-attr text -- x.ico | Out-String)
    Check 'attributes: the change to .gitattributes is staged' ((@(git diff --cached --name-only) -contains '.gitattributes') -and -not (git diff --name-only -- .gitattributes)) (git status --porcelain | Out-String)
    Check 'attributes: the update says which rules it left out' ($output.Contains('catch-all text rule (* text=auto; * text eol=lf)')) $output.Trim()
}
finally { Pop-Location }

# The catch-all pattern is narrow on purpose: a bare "* text" is one, while "* text eol=crlf" is not and stays among the kept lines.
$e = New-AdoptedProject 'adopted-attributes-variants'
Push-Location $e
try {
    $attributes = Join-Path $e '.gitattributes'
    [IO.File]::WriteAllText($attributes, [IO.File]::ReadAllText($attributes).TrimEnd("`n") + "`n`n$attributesMarker`n* text`n* text eol=crlf`n*.cs text diff=csharp`n")
    Invoke-Git commit -q -am 'Keep a bare catch-all text rule and a CRLF one'
    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $e '.template\Update-Project.ps1') -NoCommit 2>&1 | ForEach-Object { $lines.Add("$_") }; $exitCode = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    $output = $lines -join "`n"
    $text = [IO.File]::ReadAllText($attributes)
    Check 'attributes: a bare catch-all text rule is left out and the near-miss with eol=crlf stays' (($exitCode -eq 0) -and $text.EndsWith("`n$attributesMarker`n* text eol=crlf`n*.cs text diff=csharp`n")) "exit $exitCode`n$text"
    Check 'attributes: the update names the bare rule it left out' ($output.Contains('catch-all text rule (* text)')) $output.Trim()
}
finally { Pop-Location }
''
$env:COPIER_CACHE_DIR = $copierCache
if ($failures.Count) { "Kept the work folder: $Work"; "Update kept-lines tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Update kept-lines tests: PASSED'
exit 0
