<#
.SYNOPSIS
    Create a new repository from the project template: ask the template's questions, make the first commit, and
    optionally create the GitHub or GitLab repository and push it.

.DESCRIPTION
    Runs `copier copy` (Copier from PATH, or through uvx), which asks the template's questions in the terminal —
    project name, description, stack, git host (GitHub or GitLab), and build and test commands — and records the
    answers in .copier-answers.yml. -Data answers questions in advance so they aren't asked; -Defaults takes the
    default for every other question and asks nothing (project_name has no default, so pass it in -Data).

    Then initializes git on `main` and commits everything as the first commit. With -CreateRemote it reads the
    git_host answer from .copier-answers.yml and creates the repository there — `gh repo create` for github,
    `glab repo create` for gitlab — named after the destination folder, with the given -Visibility (public
    unless told otherwise), and pushes.

.EXAMPLE
    .\New-Project.ps1 -Path C:\src\qso-viewer                                              # local only
    .\New-Project.ps1 -Path C:\src\qso-viewer -CreateRemote                                # public, on the host you answer (GitHub by default)
    .\New-Project.ps1 -Path C:\src\qso-viewer -CreateRemote -Visibility private            # private, same host
    .\New-Project.ps1 -Path C:\src\qso-viewer -CreateRemote -Data @{ git_host = 'gitlab' } # GitLab, without asking the host question
    .\New-Project.ps1 -Path C:\src\qso-viewer -CreateRemote -Owner bixbots/tools           # under a GitLab group or GitHub org
    .\New-Project.ps1 -Path $env:TEMP\demo -Template . -Defaults -Data @{ project_name = 'Demo'; stack = 'python' }   # asks nothing
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [string]$Template = 'https://github.com/polewskm/project-template.git',
    [string]$Ref,
    [hashtable]$Data = @{},
    [switch]$Defaults,
    [switch]$CreateRemote,
    [string]$Owner,
    [ValidateSet('public', 'private', 'internal')][string]$Visibility = 'public'
)
$ErrorActionPreference = 'Stop'

function Invoke-Copier {
    if (Get-Command copier -ErrorAction SilentlyContinue) { & copier @args }
    elseif (Get-Command uvx -ErrorAction SilentlyContinue) { & uvx --from copier copier @args }
    else { throw 'Copier not found. Install it with: uv tool install copier' }
    if ($LASTEXITCODE) { throw "copier exited with code $LASTEXITCODE." }
}

function Get-Answer([string[]]$Lines, [string]$Key) {
    $match = $Lines | Select-String "^${Key}:\s*(\S+)" | Select-Object -First 1
    if ($match) { $match.Matches[0].Groups[1].Value }
}

if ((Test-Path $Path) -and (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)) { throw "$Path exists and is not empty." }
if ($Defaults -and -not $Data.project_name) { throw "-Defaults asks nothing, and project_name has no default. Add it: -Data @{ project_name = '<name>' }" }
foreach ($key in 'user.name', 'user.email') {
    if (-not (git config $key)) { throw "Git has no $key. Set it with: git config --global $key ""<value>""" }
}
if ($Template -eq '.') { $Template = $PSScriptRoot }

$copierArgs = @('copy')
if ($Ref) { $copierArgs += '--vcs-ref', $Ref }
if ($Defaults) { $copierArgs += '--defaults' }
foreach ($k in $Data.Keys) { $copierArgs += '--data', "$k=$($Data[$k])" }
$copierArgs += $Template, $Path
Invoke-Copier @copierArgs

Push-Location $Path
try {
    $answers = Get-Content -LiteralPath .copier-answers.yml
    $message = ('Create project from project-template ' + (Get-Answer $answers '_commit')).TrimEnd()
    git init -b main | Out-Null
    git add -A
    git commit -q -m $message
    if ($LASTEXITCODE) { throw 'The first commit failed.' }
    "Committed the new project in $((Get-Location).Path)."

    if ($CreateRemote) {
        $gitHost = Get-Answer $answers 'git_host'
        $name = Split-Path -Leaf (Get-Location)
        if ($gitHost -eq 'gitlab') {
            $glabArgs = @('repo', 'create', $name, "--$Visibility", '--defaultBranch', 'main')
            if ($Owner) { $glabArgs += '--group', $Owner }
            glab @glabArgs
            if ($LASTEXITCODE) { throw 'glab repo create failed.' }
            if (-not (git remote get-url origin 2>$null)) { throw 'glab created the project but added no origin remote. Add it with: git remote add origin <url>' }
            git push -u origin main
        }
        else {
            $fullName = if ($Owner) { "$Owner/$name" } else { $name }
            gh repo create $fullName "--$Visibility" --source . --remote origin --push
        }
        if ($LASTEXITCODE) { throw 'Creating or pushing the remote repository failed.' }
    }
}
finally { Pop-Location }
