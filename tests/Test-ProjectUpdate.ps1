<#
.SYNOPSIS
    Update a rendered project through two template versions with its own .template\Update-Project.ps1: the handover to the new version's script, the three kinds of file, a second run, and a conflict.

.DESCRIPTION
    Tests a committed, tagged (v0.1.0) snapshot of the current working tree in the work folder (-Work), so
    uncommitted template changes are tested too. Renders a python project and runs its .template\Update-Project.ps1
    to v0.2.0, which hands the update over to the new version's script, replaces template-owned files, merges merged
    files, leaves project-owned files alone and refuses to commit on the default branch. Then runs it again, which
    changes nothing, and to v0.3.0, which conflicts. Prints PASS or FAIL per check and exits 1 on any failure.

.EXAMPLE
    .\tests\Test-ProjectUpdate.ps1

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-project-update-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-project-update-test-$PID")
)
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
$tpl = Join-Path $Work 'template-repo'
$tplUrl = & (Join-Path $PSScriptRoot 'New-TemplateSnapshot.ps1') $tpl

Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data 'project_name=Test python' --data 'stack=python' --data 'git_host=github' --data 'workflow_tools=[claude, copilot, local]' $tplUrl (Join-Path $Work 'python')

$project = Join-Path $Work 'python'
# Each project runs its own copy of the update script.
$updateProject = Join-Path $project '.template\Update-Project.ps1'
$handoffMarker = 'Update-Project.ps1 from v0.2.0 is running.'
$rules = '.github/instructions/project-template.instructions.md'
$added = '.claude/commands/added-in-v0.2.0.md'
Push-Location $project
try {
    Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Create project'
    # The project edits its own and its merged files, as it should, and edits and deletes template-owned files, which it shouldn't.
    Edit-File AGENTS.md "- (Add the project's conventions here, and any template rule this project overrides.)" '- Local convention added in the project.'
    Edit-File README.md '## AI-Assisted Workflow' '## AI-Assisted Workflow in This Project'
    [IO.File]::AppendAllText((Resolve-Path -LiteralPath .gitignore).Path, "local-cache/`n")
    Edit-File CLAUDE.md '## Claude Code' '## Claude Code, Edited in the Project'
    Remove-Item -LiteralPath .claude/commands/plan-docs.md, .vscode/extensions.json
    Invoke-Git add -A; Invoke-Git commit -q -m 'Local edits'
    $projectOwnedHashes = (Get-FileHash -LiteralPath AGENTS.md, README.md).Hash -join ','
}
finally { Pop-Location }

# v0.2.0 changes the project-owned files, another part of .gitignore, CLAUDE.md and the rules, and removes and adds a template file.
Push-Location (Join-Path $tpl 'template')
try {
    Edit-File AGENTS.md.jinja 'Run from the repository root in PowerShell 7.' 'Run from the root of the {{ project_name }} repository in PowerShell 7.'
    Edit-File README.md.jinja '{{ project_description }}' '{{ project_description }} Updated.'
    Edit-File AGENTS.md.jinja "- (Add the project's conventions here, and any template rule this project overrides.)" '- Local convention added in the project.'
    Edit-File README.md.jinja '## AI-Assisted Workflow' '## AI-Assisted Workflow in This Project'
    Edit-File .gitignore.jinja 'Thumbs.db' "Thumbs.db`ndesktop.ini"
    Edit-File CLAUDE.md '## Claude Code' '## Claude Code, Updated'
    Edit-File "$rules.jinja" '## Conventions' '## Conventions, Updated'
    Edit-File .vscode/extensions.json.jinja '"editorconfig.editorconfig"' '"editorconfig.editorconfig", "example.added-in-v0-2-0"'
    Remove-Item -LiteralPath .claude/commands/analyze-decision.md
    Set-Content -LiteralPath $added 'Added in v0.2.0.' -NoNewline
    # A new version of the update script, which the project's v0.1.0 copy must hand the update over to.
    Edit-File .template/Update-Project.ps1 "`$ErrorActionPreference = 'Stop'`n" "`$ErrorActionPreference = 'Stop'`n'$handoffMarker'`n"
}
finally { Pop-Location }
Push-Location $tpl
try { Invoke-Git add -A; Invoke-Git commit -q -m 'Template change'; Invoke-Git tag v0.2.0 }
finally { Pop-Location }

# On the default branch the update refuses before it changes anything.
Push-Location $project
try {
    Invoke-Git update-ref refs/remotes/origin/main HEAD
    Invoke-Git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
    $before = git rev-parse HEAD
    $refusal = try { & $updateProject | Out-Null; 'no refusal' } catch { $_.Exception.Message }
    Check 'update: refuses to commit on the default branch' ($refusal.Contains('git switch -c build/project-template-v0.2.0') -and (git rev-parse HEAD) -eq $before -and -not (git status --porcelain)) $refusal
    Invoke-Git symbolic-ref --delete refs/remotes/origin/HEAD
    Invoke-Git update-ref -d refs/remotes/origin/main
}
finally { Pop-Location }

$output = & $updateProject | Out-String
Push-Location $project
try {
    Check 'update: hands over to the v0.2.0 script through a blob-filtered clone' ($output.Contains('Handing the update over to the v0.2.0 version') -and $output.Contains($handoffMarker) -and (Select-String -LiteralPath .template/Update-Project.ps1 -SimpleMatch $handoffMarker -Quiet)) $output.Trim()
    Check 'update: one commit, nothing left over' (((git log -1 --format=%s) -eq 'Update from project-template v0.2.0') -and ((git rev-list --count HEAD) -eq 3) -and -not (git status --porcelain)) $output.Trim()
    $gitVersion = [version]((git version) -replace '^git version (\d+\.\d+\.\d+).*$', '$1')
    Check 'update: replaces the false Git version warning from Copier' (-not $output.Contains('installed to improve updates') -and ($gitVersion -lt [version]'2.55' -or $output.Contains('copier-org/copier#2759'))) $output.Trim()
    Check 'update: project-owned files untouched' (((Get-FileHash -LiteralPath AGENTS.md, README.md).Hash -join ',') -eq $projectOwnedHashes)
    $owned = if ($output -match '(?s)The template changed these project-owned files.*?(?=\r?\n\r?\nCommitted)') { $Matches[0] } else { '' }
    Check 'update: shows project-owned changes rendered with the project answers' ($owned -match '(?m)^  AGENTS\.md:\r?$' -and $owned.Contains('+Run from the root of the Test python repository in PowerShell 7.') -and $owned -notmatch '\{%|\{\{' -and $owned -notmatch '(?m)^  README\.md') $output.Trim()
    Check 'update: leaves out project-owned changes the project already has' ($owned -match '(?m)^  AGENTS\.md:\r?$' -and -not $owned.Contains('+- Local convention added in the project.') -and $owned -notmatch '(?m)^  README\.md') $output.Trim()
    $gitignore = Get-Content -LiteralPath .gitignore -Raw
    Check 'update: merged file keeps the project''s edit and gains the template''s' ($gitignore.Contains('local-cache/') -and $gitignore.Contains('desktop.ini'))
    Check 'update: deleted merged file stays deleted' (-not (Test-Path -LiteralPath .vscode/extensions.json))
    Check 'update: template-owned files replaced' ((Select-String -LiteralPath $rules -Pattern '## Conventions, Updated' -Quiet) -and (Select-String -LiteralPath CLAUDE.md -Pattern '## Claude Code, Updated' -Quiet))
    Check 'update: edit to a template-owned file discarded and reported' ((-not (Select-String -LiteralPath CLAUDE.md -Pattern 'Edited in the Project' -Quiet)) -and $output -match '(?s)Local edits discarded.*\n  CLAUDE\.md')
    Check 'update: deleted template-owned file restored and reported' ((Test-Path -LiteralPath .claude/commands/plan-docs.md) -and $output -match '(?s)Restored.*\n  \.claude/commands/plan-docs\.md')
    Check 'update: file removed from the template deleted' (-not (Test-Path -LiteralPath .claude/commands/analyze-decision.md))
    Check 'update: file added to the template created' ([bool](git ls-files -- $added))
    Check 'update: no conflict markers or .rej files' (-not (git grep -lE '^(<<<<<<<|>>>>>>>) ') -and -not (Get-ChildItem -Recurse -Filter '*.rej' -File))
    Check 'update: answers record v0.2.0' ((Get-Content -LiteralPath .copier-answers.yml -Raw) -match '(?m)^_commit: v0\.2\.0$')
    Check 'update: .template-version records v0.2.0' ((Get-Content -LiteralPath .template-version -Raw) -eq "v0.2.0`n")
    Check 'update: enables the hooks in the clone' (((git config core.hooksPath) -join '') -eq '.githooks')
    $head = git rev-parse HEAD
}
finally { Pop-Location }

$output = & $updateProject | Out-String
Check 'update: second run changes nothing' ($output.Contains('Already up to date') -and -not $output.Contains('Handing the update over') -and ((git -C $project rev-parse HEAD) -eq $head) -and -not (git -C $project status --porcelain)) $output.Trim()

# v0.3.0 changes the .gitignore line the project changed too, and CLAUDE.md, which the project edited again: one conflict.
Push-Location $project
try {
    Edit-File .gitignore 'Thumbs.db' 'Thumbs.db # project'
    Edit-File CLAUDE.md '## Claude Code, Updated' '## Claude Code, Edited Again'
    Invoke-Git commit -q -am 'More local edits'
    $head = git rev-parse HEAD
}
finally { Pop-Location }
Push-Location (Join-Path $tpl 'template')
try { Edit-File .gitignore.jinja 'Thumbs.db' 'Thumbs.db # template'; Edit-File CLAUDE.md '## Claude Code, Updated' '## Claude Code, Updated Again' }
finally { Pop-Location }
Push-Location $tpl
try { Invoke-Git commit -q -am 'Conflicting template change'; Invoke-Git tag v0.3.0 }
finally { Pop-Location }

$output = & $updateProject | Out-String
$exitCode = $LASTEXITCODE
Push-Location $project
try {
    Check 'update: a conflict exits 1 and commits nothing' (($exitCode -eq 1) -and ((git rev-parse HEAD) -eq $head)) $output.Trim()
    Check 'update: the conflict is inline, unmerged in git, and reported' (((Get-Content -LiteralPath .gitignore -Raw) -match '(?s)<<<<<<< before updating\nThumbs\.db # project\n=======\nThumbs\.db # template\n>>>>>>> after updating') -and ((git status --porcelain -- .gitignore) -match '^UU ') -and $output.Contains('conflict  .gitignore'))
    Check 'update: only merged files conflict; template-owned ones are still replaced' ((@(git diff --name-only --diff-filter=U) -join ',') -eq '.gitignore' -and (Select-String -LiteralPath CLAUDE.md -Pattern '## Claude Code, Updated Again' -Quiet))
    Edit-File .gitignore "<<<<<<< before updating`nThumbs.db # project`n=======`nThumbs.db # template`n>>>>>>> after updating" 'Thumbs.db # project'
    Invoke-Git add -A
    Check 'update: resolving and committing completes it' (-not (git diff --cached --check) -and $LASTEXITCODE -eq 0)
    Invoke-Git commit -q -m 'Update from project-template v0.3.0'
    Check 'update: answers record v0.3.0' ((Get-Content -LiteralPath .copier-answers.yml -Raw) -match '(?m)^_commit: v0\.3\.0$' -and -not (git status --porcelain))
}
finally { Pop-Location }

if ($failures.Count) { "Kept the work folder: $Work"; "Project update tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Project update tests: PASSED'
exit 0
