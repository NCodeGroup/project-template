<#
.SYNOPSIS
    Test the Kanban board tool, tools/kanban-board.mjs.

.DESCRIPTION
    Runs tests/node/kanban-board.test.mjs with node --test, whose cases drive the tool's main with a stand-in for gh,
    so it needs no network and no token.
    Needs the Node.js release .node-version names on PATH, and no packages. Prints PASS or FAIL and exits 1 on
    failure.

.EXAMPLE
    .\tests\Test-KanbanBoard.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js not found: install the release .node-version names, see CONTRIBUTING.md.' }

$output = & node --test (Join-Path $repoRoot 'tests/node/kanban-board.test.mjs') 2>&1 | Out-String
if ($LASTEXITCODE) {
    "FAIL  tools/kanban-board.mjs: node --test exited $LASTEXITCODE"
    $output
    'Kanban board tests: FAILED (1)'
    exit 1
}
'PASS  tools/kanban-board.mjs: every node --test case passes'
'Kanban board tests: PASSED'
exit 0
