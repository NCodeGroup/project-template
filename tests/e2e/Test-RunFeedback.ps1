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

    # The installed commands name the queries the stand-in must answer.
    $commandText = if (Test-Path -LiteralPath $commandFile) { [IO.File]::ReadAllText($commandFile) } else { '' }
    $addressText = if (Test-Path -LiteralPath $addressFile) { [IO.File]::ReadAllText($addressFile) } else { '' }
    $checkPath = ''
    $checkJq = ''
    if ($commandText -match 'gh api "(repos/\{owner\}/\{repo\}/commits/<pushed>/check-runs\?[^"]+)" --jq ''([^'']+)''') { $checkPath = $Matches[1]; $checkJq = $Matches[2] }
    $readQuery = if ($addressText -match "gh api graphql -F owner='\{owner\}' -F name='\{repo\}' -F number=<number> -f query='(query[^']+)'") { $Matches[1] } else { '' }

    # The self-checks below call the stand-in, which changes its state: they run on a copy that is put back afterwards.
    $saved = @{}
    foreach ($file in Get-ChildItem -LiteralPath $hostDir -File) { $saved[$file.Name] = [IO.File]::ReadAllText($file.FullName) }
    Use-FixtureEnvironment $Work $bin {
        $st = Get-State $app $app
        $ok = $st['host'] -eq 'github' -and $st['default'] -eq 'main' -and $st['protected'] -eq 'hook' -and $st['landing'] -like '*integrate=pull-request*' -and $st['landing'] -like '*review-bots=ncode-review*' -and $st['next'] -eq 'none no plan in this folder'
        git --git-dir=$origin cat-file -e 'main:.github/workflows/code-review.yml' 2>$null
        $runsReview = $LASTEXITCODE -eq 0
        Check 'fixture: the state script sees a GitHub origin whose main takes only pull requests and runs NCode Review' ($ok -and $runsReview) "host='$($st['host'])' default='$($st['default'])' protected='$($st['protected'])' landing='$($st['landing'])' next='$($st['next'])' code-review.yml on origin main: $runsReview"

        $login = "$(gh api user --jq .login)".Trim()
        Check 'fixture: gh on PATH is the stand-in, signed in as fixture-owner' ($login -eq 'fixture-owner') "login='$login'"

        $view = gh pr view 1 --json number,url,title,state,isDraft,headRefName,headRefOid,isCrossRepository,baseRefName | Out-String | ConvertFrom-Json
        $ok = $view.state -eq 'OPEN' -and $view.headRefName -eq $head -and $view.headRefOid -eq $headOid -and $view.isCrossRepository -eq $false -and $view.baseRefName -eq 'main'
        Check 'fixture: pull request #1 is open, from add-farewell at its head on origin, not from a fork' $ok "state='$($view.state)' head='$($view.headRefName)' oid='$($view.headRefOid)' cross=$($view.isCrossRepository)"

        Check 'fixture: the installed commands ask for NCode Review''s check run, answer a nit as mandated and read the pull request with a query' ($checkPath -and $checkJq -and $commandText.Contains($nitReply) -and $readQuery) "check path: '$checkPath' jq: '$checkJq' command file: $commandFile read query: $([bool]$readQuery)"

        $data = $null
        if ($readQuery) { $data = (gh api graphql -F 'owner={owner}' -F 'name={repo}' -F number=1 -f "query=$readQuery" | Out-String | ConvertFrom-Json).data.repository.pullRequest }
        $ok = $data -and @($data.reviewThreads.nodes | Where-Object { -not $_.isResolved }).Count -eq 1 -and @($data.comments.nodes).Count -eq 0 -and @($data.reviews.nodes).Count -eq 0
        Check 'fixture: the command''s query reads one open thread, no comments and no reviews' ([bool]$ok) "threads=$(@($data.reviewThreads.nodes).Count) comments=$(@($data.comments.nodes).Count) reviews=$(@($data.reviews.nodes).Count)"

        $count = if ($checkPath) { "$(pwsh -NoProfile -File (Join-Path $bin 'gh.ps1') api ($checkPath.Replace('<pushed>', $headOid)) --jq $checkJq)".Trim() } else { '' }
        Check 'fixture: the stand-in reports no completed check run for the head before any review is asked for, and still holds the push review' ($count -eq '0' -and (Test-Path -LiteralPath (Join-Path $hostDir 'review-seed-push.json'))) "completed check runs: '$count'"
    }
    Remove-Item -LiteralPath $hostDir -Recurse -Force
    New-Item -ItemType Directory -Force $hostDir | Out-Null
    foreach ($name in $saved.Keys) { [IO.File]::WriteAllText((Join-Path $hostDir $name), $saved[$name]) }

    # The stand-in, in a folder of its own, completes NCode Review's check run on a pushed commit, and gives its review, only after a /review comment.
    $probe = Join-Path $Work 'gh-probe'
    New-Item -ItemType Directory -Force (Join-Path $probe 'host') | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'gh.ps1') -Destination (Join-Path $probe 'gh.ps1')
    Write-Text (Join-Path $probe 'host/issues.json') '{}'
    Write-Text (Join-Path $probe 'host/prs.json') '[]'
    Write-Text (Join-Path $probe 'host/comments.json') '[]'
    Copy-Item -LiteralPath (Join-Path $hostDir 'review-seed-push.json') -Destination (Join-Path $probe 'host/review-seed-push.json')
    [IO.File]::WriteAllText((Join-Path $probe 'host/origin.txt'), $origin)
    Invoke-Git --git-dir=$origin branch probe main
    $probeGh = Join-Path $probe 'gh.ps1'
    $null = pwsh -NoProfile -File $probeGh pr create --draft --base main --head probe --title Probe --body Probe
    $moved = "$(Invoke-Git --git-dir=$origin commit-tree 'main^{tree}' -p main -m 'Probe push')".Trim()
    Invoke-Git --git-dir=$origin update-ref refs/heads/probe $moved
    $probePath = $checkPath.Replace('<pushed>', $moved)
    $before = "$(pwsh -NoProfile -File $probeGh api $probePath --jq $checkJq)".Trim()
    Write-Text (Join-Path $probe 'review.md') "/review`n"
    $null = pwsh -NoProfile -File $probeGh pr comment 1 --body-file (Join-Path $probe 'review.md')
    $after = "$(pwsh -NoProfile -File $probeGh api $probePath --jq $checkJq)".Trim()
    $read = pwsh -NoProfile -File $probeGh api graphql -F owner=fixture -F name=app -F number=1 -f "query=$readQuery" | Out-String | ConvertFrom-Json
    $nodes = @($read.data.repository.pullRequest.reviewThreads.nodes)
    $nit = @($nodes | Where-Object { "$($_.comments.nodes[0].body)" -match 'severity=nit' })
    $calls = Join-Path $probe 'host/calls.log'
    $unsupported = @(if (Test-Path -LiteralPath $calls) { Get-Content -LiteralPath $calls | Where-Object { $_ -match 'UNSUPPORTED' } })
    $ok = $before -eq '0' -and $after -eq '1' -and $nodes.Count -eq 1 -and $nit.Count -eq 1 -and $nit[0].comments.nodes[0].author.login -eq 'ncode-review' -and
        -not (Test-Path -LiteralPath (Join-Path $probe 'host/review-seed-push.json')) -and $unsupported.Count -eq 0
    Check 'fixture: the stand-in completes NCode Review''s check run on a pushed commit, and gives its review, only after a /review comment that follows the push' $ok "before='$before' after='$after' threads=$($nodes.Count) nits=$($nit.Count) unsupported=$($unsupported.Count)"
    Invoke-Git --git-dir=$origin update-ref -d refs/heads/probe
    Remove-Item -LiteralPath $probe -Recurse -Force

    $clone = Join-Path $Work 'setup-check'
    Invoke-Git clone -q --branch $head $origin $clone
    $result = Get-FarewellResult $clone
    Check 'fixture: on the pull request''s branch the test passes and Get-Farewell says "Goodbye, !" without a name, as the writer says' ($result.Output -eq 'Goodbye, !|Goodbye, !|Goodbye, Ada!' -and $result.TestCode -eq 0) "output='$($result.Output)' test exit code $($result.TestCode)"
    Remove-Item -LiteralPath $clone -Recurse -Force
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
