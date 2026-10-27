<#
.SYNOPSIS
    Test the commit attribution check every project gets as .template\Test-CommitAttribution.ps1.

.DESCRIPTION
    Builds one fixture repository with commits by people and by AI agent accounts, runs the check on them and compares
    the exit code and the output. Prints PASS or FAIL per check and exits 1 on any failure. The check takes seconds.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to %TEMP%\project-template-attribution-test.

.EXAMPLE
    .\tests\Test-CommitAttribution.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path $env:TEMP 'project-template-attribution-test')
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Write-FixtureFile([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function Invoke-Git([string[]]$Arguments) {
    & git -C $repository @Arguments
    if ($LASTEXITCODE) { throw "git $($Arguments -join ' ') failed." }
}
# Commits a new file on the current branch; the message goes through a file so it keeps its line breaks.
function Add-CaseCommit([string]$Message, [string]$Author = '', [string]$CommitterName = '', [string]$CommitterEmail = '') {
    $script:caseCount++
    Write-FixtureFile (Join-Path $repository "case-$script:caseCount.txt") "case $script:caseCount`n"
    Invoke-Git @('add', '-A') | Out-Null
    Write-FixtureFile $messageFile $Message
    $arguments = @('commit', '-q', '-F', $messageFile)
    if ($Author) { $arguments += @('--author', $Author) }
    try {
        if ($CommitterName) { $env:GIT_COMMITTER_NAME = $CommitterName }
        if ($CommitterEmail) { $env:GIT_COMMITTER_EMAIL = $CommitterEmail }
        Invoke-Git $arguments | Out-Null
    }
    finally {
        Remove-Item Env:GIT_COMMITTER_NAME -ErrorAction SilentlyContinue
        Remove-Item Env:GIT_COMMITTER_EMAIL -ErrorAction SilentlyContinue
    }
}
# Starts a branch at the base commit with one commit and returns the branch name.
function New-CaseBranch([string]$Branch, [string]$Message, [string]$Author = '', [string]$CommitterName = '', [string]$CommitterEmail = '') {
    Invoke-Git @('switch', '-q', '-c', $Branch, $baseCommit) | Out-Null
    Add-CaseCommit $Message $Author $CommitterName $CommitterEmail
    $Branch
}
function Assert-Attribution([string]$Name, [string]$Base, [string]$Head, [int]$ExitCode, [string[]]$Contains = @(), [string[]]$NotContains = @()) {
    $output = & pwsh -NoProfile -File $checker -Root $repository -Base $Base -Head $Head 2>&1 | Out-String
    $code = $LASTEXITCODE
    $missing = @($Contains | Where-Object { -not $output.Contains($_) })
    $unwanted = @($NotContains | Where-Object { $output.Contains($_) })
    Check $Name (($code -eq $ExitCode) -and -not $missing -and -not $unwanted) "exit $code, expected $ExitCode; missing: $($missing -join ' | '); unexpected: $($unwanted -join ' | '); output: $output"
}

$checker = Join-Path $repoRoot 'template\.template\Test-CommitAttribution.ps1'
$repository = Join-Path $Work 'repository'
$hooks = Join-Path $Work 'hooks'
$messageFile = Join-Path $Work 'message.txt'
$caseCount = 0
$agent = 'copilot-swe-agent[bot] <198982749+Copilot@users.noreply.github.com>'

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $hooks, $repository | Out-Null
try {
    Invoke-Git @('init', '-q') | Out-Null
    Invoke-Git @('config', 'user.name', 'Commit Attribution') | Out-Null
    Invoke-Git @('config', 'user.email', 'commit-attribution@example.invalid') | Out-Null
    Invoke-Git @('config', 'commit.gpgsign', 'false') | Out-Null
    Invoke-Git @('config', 'core.autocrlf', 'false') | Out-Null
    Invoke-Git @('config', 'core.hooksPath', $hooks) | Out-Null
    Write-FixtureFile (Join-Path $repository 'base.txt') "base`n"
    Invoke-Git @('add', '-A') | Out-Null
    Invoke-Git @('commit', '-q', '-m', 'base') | Out-Null
    $baseCommit = (Invoke-Git @('rev-parse', 'HEAD') | Out-String).Trim()

    $head = New-CaseBranch 'human' "Add a feature`n`nA plain message.`n"
    Assert-Attribution 'a human commit passes' $baseCommit $head 0 @('1 commit(s) checked')

    $head = New-CaseBranch 'agent-author' "Add a feature`n" $agent
    Assert-Attribution 'an agent-authored commit fails' $baseCommit $head 1 @('is an AI agent account', '--reset-author')

    $head = New-CaseBranch 'claude-trailer' "Add a feature`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`n"
    Assert-Attribution 'a Claude co-author trailer fails' $baseCommit $head 1 @('message has agent attribution')

    $head = New-CaseBranch 'copilot-trailer' "Add a feature`n`nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`n"
    Assert-Attribution 'a Copilot co-author trailer fails' $baseCommit $head 1 @('message has agent attribution')

    $head = New-CaseBranch 'session-trailer' "Add a feature`n`nClaude-Session: 0f8fad5b-d9cb-469f-a165-70867728950e`n"
    Assert-Attribution 'a Claude-Session trailer fails' $baseCommit $head 1 @('message has agent attribution')

    $head = New-CaseBranch 'person-trailer' "Add a feature`n`nCo-authored-by: Jane Doe <jane@example.com>`n"
    Assert-Attribution 'a co-author trailer naming a person passes' $baseCommit $head 0 @('1 commit(s) checked')

    $head = New-CaseBranch 'dependabot' "Bump a package`n" 'dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>'
    Assert-Attribution 'a Dependabot commit passes' $baseCommit $head 0 @('1 commit(s) checked')

    $head = New-CaseBranch 'unknown-base' "Add a feature`n"
    Assert-Attribution 'an unknown base checks only the head' '0000000000000000000000000000000000000000' $head 0 @('checking')

    $head = New-CaseBranch 'agent-committer' "Add a feature`n" -CommitterName 'Copilot' -CommitterEmail '223556219+Copilot@users.noreply.github.com'
    Assert-Attribution 'an agent committer fails' $baseCommit $head 1 @('committer Copilot', 'is an AI agent account')

    $head = New-CaseBranch 'range' "First commit`n"
    Add-CaseCommit "Middle commit`n" $agent
    Add-CaseCommit "Last commit`n"
    Assert-Attribution 'a range finds an agent commit in the middle' $baseCommit $head 1 @('Middle commit') @('First commit', 'Last commit')

    $head = New-CaseBranch 'github-copilot-trailer' "Add a feature`n`nCo-authored-by: GitHub Copilot <noreply@github.com>`n"
    Assert-Attribution 'a GitHub Copilot trailer fails' $baseCommit $head 1 @('message has agent attribution')

    $robot = [char]::ConvertFromUtf32(0x1F916)
    $head = New-CaseBranch 'generated-with' "Add a feature`n`n$robot Generated with [Claude Code](https://claude.com/claude-code)`n"
    Assert-Attribution 'a Generated with Claude Code line fails' $baseCommit $head 1 @('message has agent attribution')

    $head = New-CaseBranch 'prose' "Add a feature`n`nThe hook strips the Generated with Claude Code line.`n"
    Assert-Attribution 'a prose line that mentions the advertising phrase passes' $baseCommit $head 0 @('1 commit(s) checked')

    $head = New-CaseBranch 'empty-base' "Add a feature`n"
    Assert-Attribution 'an empty base checks only the head' '' $head 0 @('checking')
}
finally {
    if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
}

if ($failures.Count) { "Commit attribution tests: FAILED ($($failures.Count))"; exit 1 }
'Commit attribution tests: PASSED'
exit 0
