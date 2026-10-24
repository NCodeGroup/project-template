<#
.SYNOPSIS
    Update this project to the newest version of the project template it was created from, and commit it.

.DESCRIPTION
    Every project carries this script as .template\Update-Project.ps1. The template owns it, so an update replaces
    it like the template's other files. It updates the project it sits in, or -Path.

    It clones the template from the address in .copier-answers.yml, so no template clone is needed. When the
    target version's copy of this script differs from this one, it hands the update over to that copy: the
    newest update logic always does the update, including replacing this file.

    Every file in the project has one of three owners (copier.yml, and the template README's "What a Project Gets"):

      Template-owned  Replaced by the new version. A local edit to one is discarded and a deleted one is
                      restored; the script lists both.
      Merged          Files whose tools can't include a second file (copier.yml's _merged_files). The template's
                      changes are merged with the project's edits, like a Git merge; the same lines changed on
                      both sides conflict.
      Project-owned   Written once, never touched again (copier.yml's _skip_if_exists). When the template changed
                      one since the project's version, the script shows the template's change.

    The update runs `copier recopy` at the project's current template version, which resets the template-owned
    files and shows any local edits, then `copier update --defaults` to the newest version (or -Ref), which merges
    the merged files and adds and deletes template files as the template did. Copier runs from PATH or through uvx.

    Without conflicts the result is one commit, "Update from project-template <version>"; -NoCommit stages it
    instead. With a conflict it commits nothing, says how to finish or abandon the update, and exits 1. On any
    other failure the project is reset to where it was.

    Every version of this script accepts -Path, -Ref, -Data, -NoCommit, -TemplateClone and -HandedOff, so any
    version can hand over to any later one.

.EXAMPLE
    .\.template\Update-Project.ps1
    .\.template\Update-Project.ps1 -NoCommit
    .\.template\Update-Project.ps1 -Ref v0.3.0
#>
[CmdletBinding()]
param(
    [string]$Path = (Split-Path $PSScriptRoot),
    [string]$Ref,
    [hashtable]$Data = @{},
    [switch]$NoCommit,
    # Set by the version that hands the update over; not for direct use.
    [string]$TemplateClone,
    [switch]$HandedOff
)
$ErrorActionPreference = 'Stop'

function Invoke-Copier {
    if (Get-Command copier -ErrorAction SilentlyContinue) { & copier @args }
    elseif (Get-Command uvx -ErrorAction SilentlyContinue) { & uvx --from copier copier @args }
    else { throw 'Copier not found. Install it with: uv tool install copier' }
    if ($LASTEXITCODE) { throw "copier $($args[0]) exited with code $LASTEXITCODE." }
}

function Get-Answer([string]$Key) {
    $match = Select-String -LiteralPath .copier-answers.yml -Pattern "^${Key}:\s*(.+?)\s*$" | Select-Object -First 1
    if ($match) { $match.Matches[0].Groups[1].Value.Trim("'", '"') }
}

# A file list from the template's copier.yml at a version, or at the clone's HEAD when that version isn't in it.
function Get-TemplateList([string]$Repo, [string]$Version, [string]$Key) {
    $yaml = git -C $Repo show "${Version}:copier.yml" 2>$null
    if ($LASTEXITCODE) { $yaml = git -C $Repo show HEAD:copier.yml }
    $inList = $false
    foreach ($line in $yaml) {
        if ($line -match "^${Key}:") { $inList = $true; continue }
        if ($inList -and $line -match '^\s+-\s+(.+?)\s*$') { $Matches[1].Trim("'", '"') }
        elseif ($inList -and $line -match '^\S') { break }
    }
}

# The newest version tag, as Copier picks it: v1.2.3 or 1.2.3, prereleases ignored.
function Get-NewestTag([string]$Repo) {
    git -C $Repo tag --list | Where-Object { $_ -match '^v?\d+(\.\d+){0,3}$' } |
        Sort-Object { $v = $_ -replace '^v'; if ($v -notmatch '\.') { $v += '.0' }; [version]$v } | Select-Object -Last 1
}

function Get-Change {
    foreach ($line in git status --porcelain --untracked-files=all) {
        $code = $line.Substring(0, 2)
        $file = $line.Substring(3)
        if ($file -eq '.copier-answers.yml') { continue }
        $kind = if ($code -match 'U' -or $code -in 'AA', 'DD') { 'conflict' }
        elseif ($code -eq '??' -or $code[0] -eq 'A') { 'added' }
        elseif ($code -match 'D') { 'deleted' }
        elseif ($code -match 'R') { 'renamed' }
        else { 'modified' }
        [pscustomobject]@{ Kind = $kind; File = $file }
    }
}

$project = (Resolve-Path -LiteralPath $Path).Path
$ownClone = -not $TemplateClone
$outputEncoding = [Console]::OutputEncoding
Push-Location -LiteralPath $project
try {
    # Read Git's output as UTF-8, so file contents and diffs keep their characters.
    try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch { }
    if (-not (Test-Path -LiteralPath .copier-answers.yml)) { throw "$project has no .copier-answers.yml, so it wasn't created from the template." }
    if (git status --porcelain) { throw "$project has uncommitted changes. Commit or stash them first." }
    $head = git rev-parse HEAD
    $from = Get-Answer '_commit'
    $src = Get-Answer '_src_path'

    if ($ownClone) {
        $TemplateClone = Join-Path ([IO.Path]::GetTempPath()) "project-template-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        git clone --quiet --no-checkout --filter=blob:none -- $src $TemplateClone 2>$null
        if ($LASTEXITCODE) { throw "Can't read the project template at $src. Updating needs read access to it; for its owner, Git's credentials (gh auth setup-git). Without access the project still works as it is: only template updates are unavailable." }
    }
    $to = if ($Ref) { $Ref } else { Get-NewestTag $TemplateClone }
    if (-not $to) { throw "The template at $src has no version tags." }

    # Hand over to the target version's copy of this script when it differs, so the newest update logic runs.
    if (-not $HandedOff) {
        git -C $TemplateClone checkout --quiet $to -- template/.template/Update-Project.ps1 2>$null
        $next = Join-Path $TemplateClone 'template\.template\Update-Project.ps1'
        if (-not $LASTEXITCODE -and (Test-Path -LiteralPath $next) -and
            [IO.File]::ReadAllText($next).Replace("`r`n", "`n") -ne [IO.File]::ReadAllText($PSCommandPath).Replace("`r`n", "`n")) {
            "Handing the update over to the $to version of Update-Project.ps1."
            & $next -Path $project -Ref $to -Data $Data -NoCommit:$NoCommit -TemplateClone $TemplateClone -HandedOff
            exit $LASTEXITCODE
        }
    }

    $projectOwned = @(Get-TemplateList $TemplateClone $from '_skip_if_exists')
    $merged = @(Get-TemplateList $TemplateClone $from '_merged_files')
    try {
        # Reset the template-owned files to the project's current version; what changes was edited or deleted here.
        $exclude = foreach ($file in $projectOwned + $merged) { '--exclude', $file }
        Invoke-Copier recopy --force --quiet --vcs-ref :current: @exclude
        $reset = @(Get-Change)
        $resetCommitted = [bool](git status --porcelain)
        if ($resetCommitted) { git add -A; git commit -q --no-verify -m 'Reset template-owned files'; if ($LASTEXITCODE) { throw 'Committing the reset failed.' } }

        $copierArgs = @('update', '--defaults', '--quiet', '--vcs-ref', $to)
        foreach ($k in $Data.Keys) { $copierArgs += '--data', "$k=$($Data[$k])" }
        # A project-owned file the project deleted stays deleted; Copier would otherwise create it again.
        $deleted = $projectOwned | Where-Object { -not (Test-Path -LiteralPath $_) -and (git log --diff-filter=D --format=%h -1 -- $_) }
        foreach ($file in $deleted) { $copierArgs += '--exclude', $file }
        Invoke-Copier @copierArgs

        # Drop the reset commit but keep its changes, and any conflict, in the index and the working tree.
        if ($resetCommitted) { git update-ref HEAD $head; if ($LASTEXITCODE) { throw 'Removing the reset commit failed.' } }
    }
    catch {
        git reset -q --hard $head; git clean -fdq
        throw
    }

    $conflicts = @(git diff --name-only --diff-filter=U)
    if (-not $conflicts) { git add -A }
    $changes = @(Get-Change)
    $jinjaTag = '\{' + '%.*?%' + '\}'
    $projectOwnedChanged = @(if ($from -ne $to) {
            $owned = @(Get-TemplateList $TemplateClone $to '_skip_if_exists')
            foreach ($source in git -C $TemplateClone diff --name-only $from $to -- template/ 2>$null) {
                $file = $source -replace '^template/' -replace $jinjaTag -replace '\.jinja$'
                if ($file -in $owned -and (Test-Path -LiteralPath $file)) { [pscustomobject]@{ File = $file; Source = $source } }
            }
        })

    if (-not (git status --porcelain)) { "Already up to date: template $to."; return }
    "Template $from -> ${to}:"
    $changes | Sort-Object Kind, File | ForEach-Object { '  {0,-9} {1}' -f $_.Kind, $_.File }
    $edited = @($reset | Where-Object Kind -NE 'added' | ForEach-Object File)
    $restored = @($reset | Where-Object Kind -EQ 'added' | ForEach-Object File)
    if ($edited) { ''; 'Local edits discarded — these files are the template''s; make the change in a project file instead:'; $edited | ForEach-Object { "  $_" } }
    if ($restored) { ''; 'Restored — these files are the template''s, so the project can''t delete them:'; $restored | ForEach-Object { "  $_" } }
    if ($projectOwnedChanged) {
        ''
        "The template changed these project-owned files since ${from}. They weren't touched; copy over what you want:"
        foreach ($changed in $projectOwnedChanged) {
            ''
            "  $($changed.File), from $($changed.Source):"
            $inHunk = $false
            foreach ($line in git -C $TemplateClone diff --no-color --unified=1 $from $to -- $changed.Source) {
                if ($line.StartsWith('@@')) { $inHunk = $true }
                if ($inHunk) { "    $line" }
            }
        }
    }

    $message = "Update from project-template $to"
    if ($conflicts) {
        ''
        "$($conflicts.Count) file(s) conflict: the template and this project changed the same lines. In each, keep the right lines and delete the <<<<<<<, ======= and >>>>>>> marker lines. Then:"
        '  git add -A'
        '  git diff --cached --check     # prints any marker you missed'
        "  git commit -m `"$message`""
        'To abandon the update instead: git reset --hard; git clean -fd'
        exit 1
    }
    if ($NoCommit) { ''; "Staged for review: git diff --cached, then git commit -m `"$message`""; return }
    git commit -q -m $message
    if ($LASTEXITCODE) { throw 'The commit failed.' }
    ''
    "Committed `"$message`". Review it with: git show --stat"
}
finally {
    Pop-Location
    try { [Console]::OutputEncoding = $outputEncoding } catch { }
    if ($ownClone -and $TemplateClone -and (Test-Path -LiteralPath $TemplateClone)) { Remove-Item -LiteralPath $TemplateClone -Recurse -Force -ErrorAction SilentlyContinue }
}