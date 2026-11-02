<#
.SYNOPSIS
    Run /run-feedback end to end in headless Claude Code on a fixture pull request with a local origin and a gh
    stand-in, and check what it pushed, commented and replied.

.DESCRIPTION
    Makes the fixture project with New-FixtureProject in Fixture.ps1, running NCode Review, with a local origin under a
    github.com folder and the gh stand-in, and opens a fixture pull request, #1 from add-farewell, that adds
    Get-Farewell. The pull request has one review thread, from a writer (COLLABORATOR), that asks for a real fix. The
    stand-in also holds NCode Review's review of the run's push, a nit, which it gives once a /review comment follows
    the push, and it completes NCode Review's Code review check run on the pushed commit.
    In -SetupOnly it checks the fixture: the project's state, the pull request, the installed commands and the
    stand-in's handling of the check-runs call and of the push review.
    It runs /run-feedback #1 wait:0 in headless Claude Code, answers the run's one question by resuming the session, and
    checks that the writer's fix is pushed, never forced; that the writer's thread gets a reply that names the commit;
    that the run comments /review after its last push, asks for NCode Review's check run on the pushed commit and
    answers the bot's nit once; that it recommends the merge once, in a top-level comment after the /review; and that
    nothing is resolved, merged or edited, which the stand-in also refuses. It waits at least five minutes for the
    review, as the command does.
    It costs model usage, so Invoke-AllTests.ps1 doesn't run it; run it by hand. CI runs only its fixture setup
    (-SetupOnly), so a template change that breaks the fixture still fails CI. Prints PASS or FAIL per check and exits
    1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated unless -CheckOnly. Defaults to project-template-run-feedback-e2e in the
    temp folder.

.PARAMETER SetupOnly
    Build the fixture and check it, without calling a model.

.PARAMETER CheckOnly
    Check the fixture of an earlier run again, without building it or calling a model.

.PARAMETER Claude
    The Claude Code CLI. Defaults to claude.

.PARAMETER MaxBudgetUsd
    The most each claude call may spend, passed as --max-budget-usd. 0 passes nothing. Defaults to 30.

.EXAMPLE
    .\tests\e2e\Test-RunFeedback.ps1

.EXAMPLE
    .\tests\e2e\Test-RunFeedback.ps1 -SetupOnly
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) 'project-template-run-feedback-e2e'),
    [switch]$SetupOnly,
    [switch]$CheckOnly,
    [string]$Claude = 'claude',
    [double]$MaxBudgetUsd = 30
)
$ErrorActionPreference = 'Stop'
if ($SetupOnly -and $CheckOnly) { throw '-SetupOnly and -CheckOnly can''t be used together.' }
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [Collections.Generic.List[string]]::new()
. (Join-Path $PSScriptRoot 'Fixture.ps1')

$app = Join-Path $Work 'app'
$origin = Join-Path $Work 'github.com/fixture/app.git'
$bin = Join-Path $Work 'bin'
$hostDir = Join-Path $bin 'host'
$head = 'add-farewell'
$prUrl = 'https://github.com/fixture/app/pull/1'
$commandFile = Join-Path $app '.claude/commands/run-feedback.md'
$addressFile = Join-Path $app '.claude/commands/address-feedback.md'
$nitReply = 'Autopilot: not changed: a nit, left for the maintainer to judge.'

function Read-Threads {
    @(Read-HostJson $hostDir 'threads.json' | Where-Object { $_ })
}
function Get-Thread([object[]]$Threads, [string]$Id) {
    $Threads | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}
function Test-Autopilot($Body) {
    "$Body".TrimStart() -match '^Autopilot:'
}
function Get-FarewellResult([string]$Folder) {
    Push-Location $Folder
    try {
        $out = "$(pwsh -NoProfile -Command '. ./src/Farewell.ps1; (Get-Farewell), (Get-Farewell -Name ''''), (Get-Farewell -Name Ada) -join ''|''')".Trim()
        $null = pwsh -NoProfile -File tests/Test-Greeting.ps1
        @{ Output = $out; TestCode = $LASTEXITCODE }
    }
    finally { Pop-Location }
}

if (-not $CheckOnly) {
    New-FixtureProject -RepoRoot $repoRoot -Work $Work -App $app -Origin $origin -Bin $bin -Data @{ code_review = $true }

    Invoke-Git -C $app switch -q -c $head
    Write-Text (Join-Path $app 'src/Farewell.ps1') @'
function Get-Farewell {
    param([string]$Name)
    "Goodbye, $Name!"
}
'@
    Invoke-Git -C $app add src/Farewell.ps1
    Invoke-Git -C $app commit -q -m 'Add Get-Farewell'
    Write-Text (Join-Path $app 'tests/Test-Greeting.ps1') @'
. "$PSScriptRoot/../src/Greeting.ps1"
. "$PSScriptRoot/../src/Farewell.ps1"
if ((Get-Greeting -Name Ada) -ne 'Hello, Ada!') { 'FAIL  Get-Greeting -Name Ada'; exit 1 }
'PASS  Get-Greeting -Name Ada'
if ((Get-Farewell -Name Ada) -ne 'Goodbye, Ada!') { 'FAIL  Get-Farewell -Name Ada'; exit 1 }
'PASS  Get-Farewell -Name Ada'
exit 0
'@
    Invoke-Git -C $app add tests/Test-Greeting.ps1
    Invoke-Git -C $app commit -q -m 'Check Get-Farewell -Name Ada'
    $checkCommit = "$(git -C $app rev-parse --short HEAD)".Trim()
    # The pull request's branch reaches origin as main did, and the main checkout is back on main, as a person's would be.
    Invoke-Git --git-dir=$origin fetch -q $app "${head}:$head"
    Invoke-Git -C $app switch -q main
    Invoke-Git -C $app branch -q -D $head
    Invoke-Git -C $app fetch -q origin
    $headOid = "$(git --git-dir=$origin rev-parse $head)".Trim()

    $prs = @(
        @{
            number = 1; title = 'Add Get-Farewell'; state = 'OPEN'; isDraft = $false; url = $prUrl
            body = "Adds ``Get-Farewell``, which says goodbye by name, and checks it in ``tests/Test-Greeting.ps1``.`n"
            headRefName = $head; baseRefName = 'main'; headRefOid = $headOid; isCrossRepository = $false; mergeCommit = $null
        }
    )
    $threads = @(
        @{
            id = 'PRRT_writer'; number = 1; isResolved = $false; isOutdated = $false; path = 'src/Farewell.ps1'; line = 3
            comments = @(@{
                    author = @{ login = 'ada-writer' }; authorAssociation = 'COLLABORATOR'; url = "$prUrl#discussion_r2001"
                    body = 'With no name, or an empty one, this says `Goodbye, !`. Please make it say `Goodbye, world!` in both cases, and check both in `tests/Test-Greeting.ps1`.'
                })
        }
    )
    Write-Text (Join-Path $hostDir 'issues.json') '{}'
    Write-Text (Join-Path $hostDir 'prs.json') (ConvertTo-Json -InputObject $prs -Depth 10)
    Write-Text (Join-Path $hostDir 'comments.json') '[]'
    Write-Text (Join-Path $hostDir 'threads.json') (ConvertTo-Json -InputObject $threads -Depth 10)
    Write-Text (Join-Path $hostDir 'reviews.json') '[]'
    Write-Text (Join-Path $hostDir 'forbidden.txt') "pr edit`nissue close`n"
    [IO.File]::WriteAllText((Join-Path $hostDir 'head.txt'), $headOid)

    # NCode Review's review of the run's push: one nit, no blocker or should-fix, so /run-feedback fixes nothing more and never waits for a second review.
    $ncode = @{ __typename = 'Bot'; login = 'ncode-review' }
    $pushSeed = @{
        threads  = @(
            @{ key = 'nit'; path = 'src/Farewell.ps1'; line = 1; author = $ncode; authorAssociation = 'NONE'; body = "<!-- ncode-review:finding id=F1 fp=7c3e91a2 severity=nit -->`n**Nit:** give ``Get-Farewell`` a comment-based help block." }
        )
        reviews  = @(@{ author = $ncode; authorAssociation = 'NONE'; body = 'NCode Review: 1 finding (1 nit).' })
        comments = @()
    }
    Write-Text (Join-Path $hostDir 'review-seed-push.json') (ConvertTo-Json -InputObject $pushSeed -Depth 10)
}

if ($SetupOnly) {
    ''
    if ($failures.Count) { "Run-feedback end-to-end setup: FAILED ($($failures.Count))"; exit 1 }
    'Run-feedback end-to-end setup: PASSED'
    exit 0
}

''
if ($failures.Count) { "Run-feedback end-to-end: FAILED ($($failures.Count))"; exit 1 }
'Run-feedback end-to-end: PASSED'
exit 0
