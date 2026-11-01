<#
.SYNOPSIS
    Build a tagged snapshot of the working tree for the template tests and print the URL to clone it from.

.DESCRIPTION
    Copies the repository the script sits in, without .git and Claude Code's worktrees, into -Path, commits it there
    and tags the commit v0.1.0, so uncommitted template changes are tested too. Allows blob-filtered clones of it and
    prints its file:/// URL, so a clone works as one from a host does.

.PARAMETER Path
    The folder to build the snapshot in.

.EXAMPLE
    $tplUrl = & (Join-Path $PSScriptRoot 'New-TemplateSnapshot.ps1') (Join-Path $Work 'template-repo')
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-Git {
    git -c user.name=template-test -c user.email=template-test@example.invalid @args
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed." }
}

New-Item -ItemType Directory -Force $Path | Out-Null
Get-ChildItem -LiteralPath $repoRoot -Force | Where-Object Name -NotIn '.git', '.claude' | Copy-Item -Destination $Path -Recurse -Force
# Claude Code's plan worktrees are other checkouts, not part of the snapshot.
$claudeCopy = New-Item -ItemType Directory -Force (Join-Path $Path '.claude')
Get-ChildItem -LiteralPath (Join-Path $repoRoot '.claude') -Force | Where-Object Name -NE 'worktrees' | Copy-Item -Destination $claudeCopy.FullName -Recurse -Force
Push-Location $Path
try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Snapshot'; Invoke-Git tag v0.1.0 }
finally { Pop-Location }
# Serve the snapshot as a host does: over a URL with partial clones allowed, so a --filter=blob:none clone really is blob-filtered; Git ignores the filter for a plain path.
Invoke-Git -C $Path config uploadpack.allowFilter true
Invoke-Git -C $Path config uploadpack.allowAnySHA1InWant true
'file:///' + ($Path -replace '\\', '/') + '/.git'
