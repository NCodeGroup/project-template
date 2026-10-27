<#
.SYNOPSIS
    Test that an adopted project's update keeps the lines it kept at adoption out of the template's merge.

.DESCRIPTION
    Renders two projects from v0.1.0 whose .gitignore ends with the block the adoption kept from the repository's own
    file, then updates them to a v0.2.0 that changes the secrets/ rule just above that block. The first project has no
    edit of its own and must update without a conflict. The second has a project edit next to the change and must stop
    on a conflict that leaves the kept block outside both sides. Prints PASS or FAIL per check and exits 1 on any
    failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to %TEMP%\project-template-update-kept-test.

.EXAMPLE
    .\tests\Test-UpdateKeptLines.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path $env:TEMP 'project-template-update-kept-test'))
$ErrorActionPreference = 'Stop'
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
$tpl = Join-Path $Work 'template-repo'
New-Item -ItemType Directory -Force $tpl | Out-Null
Get-ChildItem -LiteralPath $repoRoot -Force | Where-Object Name -NotIn '.git', '.claude' | Copy-Item -Destination $tpl -Recurse -Force
# Claude Code's plan worktrees are other checkouts, not part of the snapshot.
$claudeCopy = New-Item -ItemType Directory -Force (Join-Path $tpl '.claude')
Get-ChildItem -LiteralPath (Join-Path $repoRoot '.claude') -Force | Where-Object Name -NE 'worktrees' | Copy-Item -Destination $claudeCopy.FullName -Recurse -Force
Push-Location $tpl
try {
    # v0.1.0 has the secrets rule the template had before v0.15.0, which v0.2.0 changes back.
    Edit-File template/.gitignore.jinja "`n/secrets/`n" "`nsecrets/`n"
    Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Snapshot'; Invoke-Git tag v0.1.0
}
finally { Pop-Location }

Import-Module (Join-Path $repoRoot 'adopt/Adoption.psm1') -Force
$marker = "# Kept from this repository's own .gitignore when it adopted the project template"
$kept = "# OpenTofu working directories and state`n.terraform/`n*.tfstate`n*.tfplan`nplan.txt`n"

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
$a = New-AdoptedProject 'adopted'
$b = New-AdoptedProject 'adopted-edit'

# The second project adds a line of its own right below secrets/, next to where v0.2.0 changes it.
Push-Location $b
try {
    Edit-File .gitignore "`nsecrets/`n`n$marker" "`nsecrets/`n/vault/`n`n$marker"
    Invoke-Git commit -q -am 'Ignore the vault folder'
}
finally { Pop-Location }

Push-Location (Join-Path $tpl 'template')
try { Edit-File .gitignore.jinja "`nsecrets/`n" "`n/secrets/`n" }
finally { Pop-Location }
Push-Location $tpl
try { Invoke-Git commit -q -am 'Root secrets folder only'; Invoke-Git tag v0.2.0 }
finally { Pop-Location }

Push-Location $a
try {
    $text = [IO.File]::ReadAllText((Join-Path $a '.gitignore'))
    Check 'fixture: the adopted .gitignore ends with secrets/ and then the kept block' ($text.EndsWith("`nsecrets/`n`n$marker`n$kept")) $text

    $lines = [Collections.Generic.List[string]]::new()
    try { & (Join-Path $a '.template\Update-Project.ps1') 2>&1 | ForEach-Object { $lines.Add("$_") }; $exitCode = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
    $output = $lines -join "`n"
    Check 'update: the change to secrets/ next to the kept block merges without a conflict' (($exitCode -eq 0) -and $output.Contains('Committed "Update from project-template v0.2.0"') -and -not (git status --porcelain)) "exit $exitCode`n$($output.Trim())`n$(git status --porcelain | Out-String)"
    $text = [IO.File]::ReadAllText((Join-Path $a '.gitignore'))
    Check 'update: .gitignore has /secrets/ and still ends with the kept block' ($text.Contains("`n/secrets/`n") -and -not $text.Contains("`nsecrets/`n") -and $text.EndsWith("`n/secrets/`n`n$marker`n$kept")) $text

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
}
finally { Pop-Location }
''
if ($failures.Count) { "Update kept-lines tests: FAILED ($($failures.Count))"; exit 1 }
'Update kept-lines tests: PASSED'
exit 0
