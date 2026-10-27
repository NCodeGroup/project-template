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
                      both sides conflict. An adopted project's own lines at the end of .gitignore,
                      .gitattributes and .editorconfig are set aside while Copier merges, so they never
                      conflict.
      Project-owned   Written once, never touched again (copier.yml's _skip_if_exists). When the template changed
                      one since the project's version, the script shows the template's change, rendered with
                      the project's answers, leaving out what the project's file already has.
                      A merged file that the project's project_owned_files answer names
                      is project-owned too; a project that replaced one sets it with -Data @{ project_owned_files
                      = '.github/workflows/ci.yml' }, and only merged files can be named.

    The update runs `copier recopy` at the project's current template version, which resets the template-owned
    files and shows any local edits, then `copier update --defaults` to the newest version (or -Ref), which merges
    the merged files and adds and deletes template files as the template did. Copier runs from PATH or through uvx.

    Without conflicts the result is one commit, "Update from project-template <version>"; -NoCommit stages it
    instead. Either way it exits 0, as it does when there is nothing to update. With a conflict it commits nothing,
    says how to finish or abandon the update, and exits 1. On any other failure the project is reset to where it
    was.

    On the default branch (the branch origin/HEAD names) it refuses to run unless -NoCommit is given, because it
    commits. It enables the template's hooks (core.hooksPath .githooks) unless the clone already has a hooks path,
    hooks in .git/hooks, or uses pre-commit; then it says how to run them, or nothing once .pre-commit-config.yaml
    runs .githooks/commit-msg.

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

# Copier says "Make sure Git >= 2.24 is installed" whenever Git rejects `diff-tree --inter-hunk-context=-1`,
# which Git 2.55 and later always do (copier-org/copier#2759), so the filter swaps in an accurate note.
function Invoke-Copier {
    $gitNote = 'Copier''s "Make sure Git >= 2.24 is installed" is a false alarm: Git 2.55 and later reject an option its update uses, so Copier falls back, and nearby changes to a merged file may conflict as one block (copier-org/copier#2759).'
    $ErrorActionPreference = 'Continue'   # Copier's stderr lines arrive as error records through 2>&1
    $prefix = @()
    $command = if (Get-Command copier -ErrorAction SilentlyContinue) { 'copier' }
    elseif (Get-Command uvx -ErrorAction SilentlyContinue) { $prefix = '--from', 'copier', 'copier'; 'uvx' }
    else { throw 'Copier not found. Install it with: uv tool install copier' }
    & $command @prefix @args 2>&1 | ForEach-Object { if ("$_" -match 'Make sure Git >= 2\.24 is installed') { $gitNote } else { "$_" } }
    if ($LASTEXITCODE) { throw "copier $($args[0]) exited with code $LASTEXITCODE." }
}

# Copier reads --data values as YAML, so a list answer goes as a flow sequence: [claude, copilot].
function ConvertTo-CopierValue($Value) {
    if ($Value -is [Collections.IList]) { '[' + ($Value -join ', ') + ']' } else { "$Value" }
}

# Render the template at a version into a folder with the project's answers; false when Copier can't.
function Invoke-TemplateRender([string]$Version, [string]$Folder) {
    $renderArgs = @('copy', '--defaults', '--quiet', '--vcs-ref', $Version, '--data-file', (Join-Path $project '.copier-answers.yml'))
    foreach ($k in $Data.Keys) { $renderArgs += '--data', "$k=$(ConvertTo-CopierValue $Data[$k])" }
    try { Invoke-Copier @renderArgs $TemplateClone $Folder | Out-Null; $true } catch { $false }
}

function Get-Answer([string]$Key) {
    $match = Select-String -LiteralPath .copier-answers.yml -Pattern "^${Key}:\s*(.+?)\s*$" | Select-Object -First 1
    if ($match) { $match.Matches[0].Groups[1].Value.Trim("'", '"') }
}

# A list answer from .copier-answers.yml, which Copier writes as "key:" and then one "- item" line each.
function Get-AnswerList([string]$Key) {
    $inList = $false
    foreach ($line in Get-Content -LiteralPath .copier-answers.yml) {
        if ($line -match "^${Key}:\s*$") { $inList = $true; continue }
        if ($inList -and $line -match '^\s*-\s+(.+?)\s*$') { $Matches[1].Trim("'", '"') }
        elseif ($inList) { break }
    }
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

# True when the project's file already has a hunk of the template's change: the hunk applies to it in reverse.
function Test-HunkApplied([string]$File, [string[]]$Hunk, [string]$Folder) {
    $patch = Join-Path $Folder 'hunk.patch'
    [IO.File]::WriteAllText($patch, ((@("--- a/$File", "+++ b/$File") + $Hunk) -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
    git apply --check --reverse -- $patch 2>$null
    -not $LASTEXITCODE
}

# How to run the template's .githooks in this clone: HooksPath when core.hooksPath can point at it, otherwise the
# Note to print. A hooks path turns off the hooks in .git/hooks, and pre-commit won't install while one is set, so
# a clone that uses pre-commit gets a local pre-commit hook to add instead, and no note once its config runs it.
function Get-GitHooksSetup {
    $config = '.pre-commit-config.yaml'
    $ownHooks = @(Get-ChildItem -LiteralPath (git rev-parse --path-format=absolute --git-path hooks) -File -ErrorAction SilentlyContinue | Where-Object Extension -NE '.sample')
    $preCommit = (Test-Path -LiteralPath $config) -or [bool]($ownHooks | Select-String -SimpleMatch 'File generated by pre-commit' -List)
    $note = if ($preCommit -and (Test-Path -LiteralPath $config) -and (Select-String -LiteralPath $config -SimpleMatch '.githooks/commit-msg' -Quiet)) { $null }
    elseif ($preCommit) {
        @('Git hooks: .githooks not enabled. This clone uses pre-commit, which won''t install its hooks while core.hooksPath is set. To run .githooks/commit-msg through pre-commit, add this hook to the repos list in .pre-commit-config.yaml, then run: pre-commit install --hook-type commit-msg',
            '  - repo: local', '    hooks:', '      - id: strip-agent-attribution', '        name: strip agent attribution', '        entry: .githooks/commit-msg', '        language: script', '        stages: [commit-msg]') -join "`n"
    }
    elseif ($ownHooks) { "Git hooks: .githooks not enabled. This clone has hooks of its own in .git/hooks ($(($ownHooks | ForEach-Object Name) -join ', ')), and core.hooksPath would turn them off. To run both, call .githooks/commit-msg from your commit-msg hook, or move your hooks into .githooks and run: git config core.hooksPath .githooks" }
    [pscustomobject]@{ HooksPath = -not $preCommit -and -not $ownHooks; Note = $note }
}

$project = (Resolve-Path -LiteralPath $Path).Path
$ownClone = -not $TemplateClone
$scratch = Join-Path ([IO.Path]::GetTempPath()) "project-template-update-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
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
        # A full clone: Copier renders versions from it and can't clone a blob-filtered clone; the template is small.
        git clone --quiet --no-checkout -- $src $TemplateClone 2>$null
        if ($LASTEXITCODE) { throw "Can't read the project template at $src. Updating needs read access to it; for its owner, Git's credentials (gh auth setup-git). Without access the project still works as it is: only template updates are unavailable." }
    }
    $to = if ($Ref) { $Ref } else { Get-NewestTag $TemplateClone }
    if (-not $to) { throw "The template at $src has no version tags." }

    # The update commits, and the default branch may accept changes only through pull requests.
    $branch = git branch --show-current
    $defaultRef = git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null
    $default = if ($defaultRef) { $defaultRef -replace '^origin/' } elseif ($branch -in 'main', 'master' -and (git rev-parse --quiet --verify "refs/remotes/origin/$branch" 2>$null)) { $branch }
    if ($branch -and $branch -eq $default -and -not $NoCommit) { throw "$project is on $branch, its default branch, and the update commits. Update on a branch of its own: git switch -c build/project-template-$to — or stage the update here with -NoCommit." }

    # Hand over to the target version's copy of this script when it differs, so the newest update logic runs.
    # git show, not git checkout: checkout doesn't fetch the file in a blob-filtered clone, but show does.
    if (-not $HandedOff) {
        $nextText = (git -C $TemplateClone show "${to}:template/.template/Update-Project.ps1" 2>$null) -join "`n"
        if (-not $LASTEXITCODE -and $nextText -and $nextText.TrimEnd() -ne [IO.File]::ReadAllText($PSCommandPath).Replace("`r`n", "`n").TrimEnd()) {
            New-Item -ItemType Directory -Force $scratch | Out-Null
            $next = Join-Path $scratch 'Update-Project.ps1'
            [IO.File]::WriteAllText($next, "$nextText`n", [Text.UTF8Encoding]::new($false))
            "Handing the update over to the $to version of Update-Project.ps1."
            & $next -Path $project -Ref $to -Data $Data -NoCommit:$NoCommit -TemplateClone $TemplateClone -HandedOff
            exit $LASTEXITCODE
        }
    }

    $projectOwned = @(Get-TemplateList $TemplateClone $from '_skip_if_exists')
    $merged = @(Get-TemplateList $TemplateClone $from '_merged_files')
    # Merged files the project owns (its project_owned_files answer): updates leave them alone and show the template's change, as for project-owned files.
    # -Data wins, because this update records it, and a single file becomes the list the answer must be.
    if ($Data.ContainsKey('project_owned_files')) { $Data['project_owned_files'] = @($Data['project_owned_files'] | Where-Object { $_ }) }
    $ownedMerged = @(if ($Data.ContainsKey('project_owned_files')) { $Data['project_owned_files'] } else { Get-AnswerList 'project_owned_files' })
    $notMerged = @($ownedMerged | Where-Object { $_ -notin $merged })
    if ($notMerged) { throw "project_owned_files names $($notMerged -join ', '), which isn't a merged file. It can name only these: $($merged -join ', ')." }
    try {
        # Reset the template-owned files to the project's current version; what changes was edited or deleted here.
        $exclude = foreach ($file in $projectOwned + $merged) { '--exclude', $file }
        Invoke-Copier recopy --force --quiet --vcs-ref :current: @exclude
        $reset = @(Get-Change)
        # Adopt-Project.ps1 ends these files with the repository's own lines under a "# Kept from …" comment. Set them aside while
        # Copier merges, so a template change to the file's last lines can't conflict with them or take them into its conflict.
        $keptLines = @{}
        foreach ($file in '.gitignore', '.gitattributes', '.editorconfig') {
            if ($file -notin $merged -or $file -in $ownedMerged -or -not (Test-Path -LiteralPath $file)) { continue }
            $text = [IO.File]::ReadAllText((Join-Path $project $file))
            $match = [regex]::Match($text, "(?m)^# Kept from this repository's own \S+ when it adopted the project template\r?$")
            if (-not $match.Success) { continue }
            $templatePart = $text.Substring(0, $match.Index).TrimEnd("`r", "`n")
            $keptLines[$file] = $text.Substring($templatePart.Length)
            [IO.File]::WriteAllText((Join-Path $project $file), "$templatePart`n")
        }
        $resetCommitted = [bool](git status --porcelain)
        if ($resetCommitted) { git add -A; git commit -q --no-verify -m 'Reset template-owned files'; if ($LASTEXITCODE) { throw 'Committing the reset failed.' } }

        $copierArgs = @('update', '--defaults', '--quiet', '--vcs-ref', $to)
        foreach ($k in $Data.Keys) { $copierArgs += '--data', "$k=$(ConvertTo-CopierValue $Data[$k])" }
        # A project-owned file the project deleted stays deleted; Copier would otherwise create it again.
        $deleted = $projectOwned | Where-Object { -not (Test-Path -LiteralPath $_) -and (git log --diff-filter=D --format=%h -1 -- $_) }
        foreach ($file in $deleted) { $copierArgs += '--exclude', $file }
        # A merged file the project owns stays as it is; its template change is shown below.
        foreach ($file in $ownedMerged) { $copierArgs += '--exclude', $file }
        # Copier writes the template's .gitignore over the project's before merging the project's edits back, then passes
        # every path Git reports as ignored to one `git apply` command. Keep the project's rules in force meanwhile, or a
        # folder only they ignore, such as node_modules/, is listed file by file and overflows Windows' command line.
        # The copy sits between marker lines, so a run that was killed before restoring info/exclude is cleaned up here.
        $infoExclude = git rev-parse --path-format=absolute --git-path info/exclude
        $beginCopy = '# Update-Project.ps1: the project''s .gitignore, in force while Copier updates'
        $endCopy = '# Update-Project.ps1: end of the .gitignore copy'
        $excludeBefore = if (Test-Path -LiteralPath $infoExclude) {
            [regex]::Replace([IO.File]::ReadAllText($infoExclude), "(?s)\n$([regex]::Escape($beginCopy))\n.*?\n$([regex]::Escape($endCopy))\n", '')
        }
        $projectIgnore = Join-Path $project '.gitignore'
        try {
            if (Test-Path -LiteralPath $projectIgnore) {
                New-Item -ItemType Directory -Force (Split-Path $infoExclude) | Out-Null
                [IO.File]::WriteAllText($infoExclude, "$excludeBefore`n$beginCopy`n$([IO.File]::ReadAllText($projectIgnore))$($keptLines['.gitignore'])`n$endCopy`n")
            }
            Invoke-Copier @copierArgs
        }
        finally {
            if ($null -eq $excludeBefore) { Remove-Item -LiteralPath $infoExclude -Force -ErrorAction SilentlyContinue }
            else { [IO.File]::WriteAllText($infoExclude, $excludeBefore) }
        }

        # Put the kept lines back at the end, after any conflict.
        foreach ($file in $keptLines.Keys) {
            $full = Join-Path $project $file
            if (Test-Path -LiteralPath $full) { [IO.File]::WriteAllText($full, [IO.File]::ReadAllText($full).TrimEnd("`r", "`n") + $keptLines[$file]) }
        }

        # Drop the reset commit but keep its changes, and any conflict, in the index and the working tree.
        if ($resetCommitted) { git update-ref HEAD $head; if ($LASTEXITCODE) { throw 'Removing the reset commit failed.' } }
    }
    catch {
        git reset -q --hard $head; git clean -fdq
        throw
    }

    $conflicts = @(git diff --name-only --diff-filter=U)
    if (-not $conflicts) {
        git add -A
        # Executable on Linux and macOS; Windows doesn't record the bit on its own.
        if (Test-Path -LiteralPath .githooks/commit-msg) { git update-index --chmod=+x .githooks/commit-msg }
        if (Test-Path -LiteralPath .githooks/pre-push) { git update-index --chmod=+x .githooks/pre-push }
    }
    # Enable the template's versioned hooks in this clone, unless it already runs hooks another way (Get-GitHooksSetup).
    if ((Test-Path -LiteralPath .githooks) -and -not (git config --get core.hooksPath)) {
        $hooksSetup = Get-GitHooksSetup
        if ($hooksSetup.HooksPath) { git config core.hooksPath .githooks }
        elseif ($hooksSetup.Note) { $hooksSetup.Note; '' }
    }
    $changes = @(Get-Change)
    $jinjaTag = '\{' + '%.*?%' + '\}'
    $projectOwnedChanged = @(if ($from -ne $to) {
            $owned = @(Get-TemplateList $TemplateClone $to '_skip_if_exists') + $ownedMerged
            foreach ($source in git -C $TemplateClone diff --name-only $from $to -- template/ 2>$null) {
                $file = $source -replace '^template/' -replace $jinjaTag -replace '\.jinja$'
                if ($file -in $owned -and (Test-Path -LiteralPath $file)) { [pscustomobject]@{ File = $file; Source = $source } }
            }
        })

    # A success ends with exit 0, not return, which would hand a caller that runs this with & the exit code of the last git command, such as git apply --check's 1 for a hunk the project lacks.
    if (-not (git status --porcelain)) { "Already up to date: template $to."; exit 0 }
    "Template $from -> ${to}:"
    $changes | Sort-Object Kind, File | ForEach-Object { '  {0,-9} {1}' -f $_.Kind, $_.File }
    $edited = @($reset | Where-Object Kind -NE 'added' | ForEach-Object File)
    $restored = @($reset | Where-Object Kind -EQ 'added' | ForEach-Object File)
    if ($edited) { ''; 'Local edits discarded — these files are the template''s; make the change in a project file instead:'; $edited | ForEach-Object { "  $_" } }
    if ($restored) { ''; 'Restored — these files are the template''s, so the project can''t delete them:'; $restored | ForEach-Object { "  $_" } }
    if ($projectOwnedChanged) {
        # Render both versions with the project's answers, so the diffs show what the project would get, not Jinja.
        New-Item -ItemType Directory -Force $scratch | Out-Null
        $renderedFrom = Join-Path $scratch 'rendered\from'
        $renderedTo = Join-Path $scratch 'rendered\to'
        $rendered = (Invoke-TemplateRender $from $renderedFrom) -and (Invoke-TemplateRender $to $renderedTo)
        $empty = Join-Path $scratch 'empty'
        [IO.File]::WriteAllText($empty, '')
        $shown = foreach ($changed in $projectOwnedChanged) {
            if ($rendered) {
                $old = Join-Path $renderedFrom $changed.File
                $new = Join-Path $renderedTo $changed.File
                $diff = git diff --no-index --no-color --unified=1 -- $(if (Test-Path -LiteralPath $old) { $old } else { $empty }) $(if (Test-Path -LiteralPath $new) { $new } else { $empty })
                $title = "  $($changed.File):"
            }
            else {
                $diff = git -C $TemplateClone diff --no-color --unified=1 $from $to -- $changed.Source
                $title = "  $($changed.File), from the template source $($changed.Source), which Copier couldn't render with this project's answers:"
            }
            # Leave out a hunk the project's file already has; a file left with none isn't shown.
            $hunk = @(
                $current = @()
                foreach ($line in @($diff | Where-Object { $_ -is [string] }) + '@@') {
                    if ($line.StartsWith('@@')) {
                        if ($current -and -not ($rendered -and (Test-HunkApplied $changed.File $current $scratch))) { $current | ForEach-Object { "    $_" } }
                        $current = @()
                    }
                    if ($current -or $line.StartsWith('@@')) { $current += $line }
                }
            )
            if ($hunk) { [pscustomobject]@{ Title = $title; Lines = $hunk } }
        }
        if ($shown) {
            ''
            "The template changed these project-owned files since ${from}. They weren't touched; copy over what you want:"
            foreach ($file in $shown) { ''; $file.Title; $file.Lines }
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
    if ($NoCommit) { ''; "Staged for review: git diff --cached, then git commit -m `"$message`""; exit 0 }
    git commit -q -m $message
    if ($LASTEXITCODE) { throw 'The commit failed.' }
    ''
    "Committed `"$message`". Review it with: git show --stat"
    exit 0
}
finally {
    Pop-Location
    try { [Console]::OutputEncoding = $outputEncoding } catch { }
    if ($ownClone -and $TemplateClone -and (Test-Path -LiteralPath $TemplateClone)) { Remove-Item -LiteralPath $TemplateClone -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
