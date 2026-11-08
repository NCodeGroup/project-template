<#
.SYNOPSIS
    Run /run-feedback end to end in headless Claude Code or the Copilot CLI (-Tool) on a fixture pull request with a local origin and a gh
    stand-in, and check what it pushed, commented and replied.

.DESCRIPTION
    Makes the fixture project with New-FixtureProject in Fixture.ps1, running NCode Review, with a local origin under a
    github.com folder and the gh stand-in, and opens a fixture pull request, #1 from add-farewell, that adds
    Get-Farewell. The pull request has one review thread, from a writer (COLLABORATOR), that asks for a real fix. The
    stand-in also holds NCode Review's review of the run's push, a nit, which it gives once a /review comment follows
    the push, and it completes NCode Review's Code review check run on the pushed commit.
    In -SetupOnly it checks the fixture: the project's state, the pull request, the installed commands and the
    stand-in's handling of the check-runs call, of the push review, of a comment read back, edited and deleted by its
    id, and of footer.txt.
    It runs /run-feedback #1 wait:0 in headless Claude Code or the Copilot CLI (-Tool), answers the run's one question by resuming the session, and
    checks that the writer's fix is pushed, never forced; that the writer's thread gets a reply that names the commit;
    that the run comments /review after its last push, asks for NCode Review's check run on the pushed commit and
    answers the bot's nit once; that it recommends the merge once, in a top-level comment after the /review; and that
    nothing is resolved, merged or edited, which the stand-in also refuses. It waits at least five minutes for the
    review, as the command does. With -Scenario session-footer the stand-in saves each comment and thread reply with a
    Claude Code cloud session's footer, so the run's /review comment starts no review: the test then checks that the
    run deletes it and posts no other, asks the maintainer in an Autopilot: comment to comment /review, and removes
    the footer from every top-level comment it leaves.
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
    Without -Scenario it checks the scenario the fixture was set up for: session-footer when the host folder has
    footer.txt, push-review otherwise.

.PARAMETER Scenario
    push-review, the default: the run's /review comment asks NCode Review for its review of the push. session-footer:
    the stand-in saves each comment and reply with the footer that footer.txt in its host folder holds, so the run
    must delete its /review comment and ask the maintainer for one, which the stand-in then takes as posted. Run both.

.PARAMETER Tool
    claude, the default, runs each prompt in headless Claude Code; copilot runs it in the Copilot CLI. The fixture
    project has both tools' commands, so the setup and the checks are the same for either tool, but for where a run
    works. Without -Tool, -CheckOnly checks the tool the fixture's run used, which tool.txt in the work folder names.

.PARAMETER Claude
    The Claude Code CLI. Defaults to claude.

.PARAMETER Copilot
    The Copilot CLI. Defaults to copilot.

.PARAMETER Model
    The model each prompt runs on, passed as --model. Empty, the default, keeps the tool's own default.

.PARAMETER MaxBudgetUsd
    The most each claude call, or each Copilot session, may spend: --max-budget-usd, or --max-ai-credits at 100 AI
    credits a dollar, 30 at least. 0 passes nothing. Defaults to 30.

.PARAMETER TimeoutMinutes
    The longest each claude or copilot call may run, in minutes: past it the test stops the CLI and its child processes,
    and that run fails its session check. 0 sets no limit. Defaults to 45.

.EXAMPLE
    .\tests\e2e\Test-RunFeedback.ps1

.EXAMPLE
    .\tests\e2e\Test-RunFeedback.ps1 -Scenario session-footer

.EXAMPLE
    .\tests\e2e\Test-RunFeedback.ps1 -SetupOnly

.EXAMPLE
    .\tests\e2e\Test-RunFeedback.ps1 -Tool copilot
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) 'project-template-run-feedback-e2e'),
    [switch]$SetupOnly,
    [switch]$CheckOnly,
    [ValidateSet('push-review', 'session-footer')][string]$Scenario = 'push-review',
    [ValidateSet('claude', 'copilot')][string]$Tool = 'claude',
    [string]$Claude = 'claude',
    [string]$Copilot = 'copilot',
    [string]$Model = '',
    [double]$MaxBudgetUsd = 30,
    [double]$TimeoutMinutes = 45
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
# Without -Tool, -CheckOnly checks the run of the tool the fixture ran, which New-Agent writes to tool.txt.
if ($CheckOnly -and -not $PSBoundParameters.ContainsKey('Tool')) { $Tool = Get-RunTool $Work $Tool }
# Without -Scenario, -CheckOnly checks the scenario the fixture was set up for: footer.txt in the host folder marks session-footer.
if ($CheckOnly -and -not $PSBoundParameters.ContainsKey('Scenario') -and (Test-Path -LiteralPath (Join-Path $hostDir 'footer.txt'))) { $Scenario = 'session-footer' }
$head = 'add-farewell'
$prUrl = 'https://github.com/fixture/app/pull/1'
$commandFile = Get-CommandFile $app $Tool 'run-feedback'
$addressFile = Get-CommandFile $app $Tool 'address-feedback'
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
        Test-InstalledCommand $app 'run-feedback' 'the check-runs call and the nit reply the checks match' @("gh api ""$checkPath"" --jq '$checkJq'", $nitReply)
        Test-InstalledCommand $app 'address-feedback' 'the read query' @($readQuery)

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
    Copy-StandIn gh $probe
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

    # The stand-in, in a folder of its own, reads a comment back by its id, edits it with -X PATCH and deletes it with
    # -X DELETE, refuses an id it doesn't hold and any other method, and with footer.txt saves each comment with that footer.
    $probe = Join-Path $Work 'gh-comment-probe'
    New-Item -ItemType Directory -Force (Join-Path $probe 'host') | Out-Null
    Copy-StandIn gh $probe
    Write-Text (Join-Path $probe 'host/issues.json') '{}'
    Write-Text (Join-Path $probe 'host/prs.json') '[]'
    Write-Text (Join-Path $probe 'host/comments.json') '[]'
    [IO.File]::WriteAllText((Join-Path $probe 'host/origin.txt'), $origin)
    Invoke-Git --git-dir=$origin branch probe main
    $probeGh = Join-Path $probe 'gh.ps1'
    $null = pwsh -NoProfile -File $probeGh pr create --draft --base main --head probe --title Probe --body Probe
    $moved = "$(Invoke-Git --git-dir=$origin commit-tree 'main^{tree}' -p main -m 'Probe push')".Trim()
    Invoke-Git --git-dir=$origin update-ref refs/heads/probe $moved
    $bodyFile = Join-Path $probe 'body.md'
    Write-Text $bodyFile "Probe comment`n"
    $id = ("$(pwsh -NoProfile -File $probeGh pr comment 1 --body-file $bodyFile)".Trim() -split '#issuecomment-')[-1]
    $readBack = "$(pwsh -NoProfile -File $probeGh api "repos/fixture/app/issues/comments/$id" --jq .body)".Trim()
    $null = pwsh -NoProfile -File $probeGh api repos/fixture/app/issues/comments/999999 --jq .body 2>$null; $unknownCode = $LASTEXITCODE
    $null = pwsh -NoProfile -File $probeGh api -X POST "repos/fixture/app/issues/comments/$id" 2>$null; $postCode = $LASTEXITCODE
    Write-Text $bodyFile "Edited comment`n"
    $null = pwsh -NoProfile -File $probeGh api -X PATCH "repos/fixture/app/issues/comments/$id" -F "body=@$bodyFile"
    $edited = "$(pwsh -NoProfile -File $probeGh api "repos/fixture/app/issues/comments/$id" --jq .body)".Trim()
    $null = pwsh -NoProfile -File $probeGh api -X DELETE "repos/fixture/app/issues/comments/$id"; $deleteCode = $LASTEXITCODE
    $null = pwsh -NoProfile -File $probeGh api "repos/fixture/app/issues/comments/$id" 2>$null; $goneCode = $LASTEXITCODE
    $unsupported = @(Get-Content -LiteralPath (Join-Path $probe 'host/calls.log') | Where-Object { $_ -match '^UNSUPPORTED' })
    Check 'fixture: the stand-in reads a comment back by its id, edits it with -X PATCH, deletes it with -X DELETE, and refuses an id it doesn''t hold and any other method' ($readBack -eq 'Probe comment' -and $unknownCode -ne 0 -and $postCode -ne 0 -and $edited -eq 'Edited comment' -and $deleteCode -eq 0 -and $goneCode -ne 0 -and $unsupported.Count -eq 3) "read back: '$readBack'; unknown id: exit $unknownCode; POST: exit $postCode; edited: '$edited'; DELETE: exit $deleteCode; read after it: exit $goneCode; unsupported: $($unsupported.Count)"
    # gh also takes a method attached to -X, as in -XPATCH, and sends a POST when a call has fields and no method.
    Write-Text $bodyFile "Probe comment`n"
    $attachedId = ("$(pwsh -NoProfile -File $probeGh pr comment 1 --body-file $bodyFile)".Trim() -split '#issuecomment-')[-1]
    Write-Text $bodyFile "Edited with -XPATCH`n"
    $null = pwsh -NoProfile -File $probeGh api -XPATCH "repos/fixture/app/issues/comments/$attachedId" -F "body=@$bodyFile"
    $attachedEdit = "$(pwsh -NoProfile -File $probeGh api "repos/fixture/app/issues/comments/$attachedId" --jq .body)".Trim()
    $null = pwsh -NoProfile -File $probeGh api "repos/fixture/app/issues/comments/$attachedId" -f 'body=Posted' 2>$null; $impliedPostCode = $LASTEXITCODE
    $impliedBody = "$(pwsh -NoProfile -File $probeGh api "repos/fixture/app/issues/comments/$attachedId" --jq .body)".Trim()
    $unsupportedNow = @(Get-Content -LiteralPath (Join-Path $probe 'host/calls.log') | Where-Object { $_ -match '^UNSUPPORTED' })
    Check 'fixture: the stand-in edits a comment with -XPATCH, and refuses a call with fields and no method, which gh sends as a POST' ($attachedEdit -eq 'Edited with -XPATCH' -and $impliedPostCode -ne 0 -and $impliedBody -eq 'Edited with -XPATCH' -and $unsupportedNow.Count -eq 4) "after -XPATCH: '$attachedEdit'; fields and no method: exit $impliedPostCode, body '$impliedBody'; unsupported: $($unsupportedNow.Count)"
    # The state script reads the pull request list by head branch and the release by tag through gh api REST paths.
    $pulls = "$(pwsh -NoProfile -File $probeGh api 'repos/{owner}/{repo}/pulls?head={owner}%3Aprobe&state=all&per_page=100')" | ConvertFrom-Json
    $none = "$(pwsh -NoProfile -File $probeGh api 'repos/{owner}/{repo}/pulls?head={owner}%3Ano-such-branch&state=all&per_page=100')" | ConvertFrom-Json
    $null = pwsh -NoProfile -File $probeGh api 'repos/{owner}/{repo}/releases/tags/v9.9.9' 2>$null; $releaseCode = $LASTEXITCODE
    Check 'fixture: the stand-in answers the state script''s REST pull request list by head branch, and finds no release' (@($pulls).Count -eq 1 -and @($pulls)[0].number -eq 1 -and @($pulls)[0].state -eq 'open' -and @($pulls)[0].head.ref -eq 'probe' -and @($none).Count -eq 0 -and $releaseCode -ne 0) "pulls: $(@($pulls).Count); none: $(@($none).Count); release: exit $releaseCode"

    $footer = '_Generated by [Claude Code](https://claude.ai/code/session_01AbCdEf)_'
    Write-Text (Join-Path $probe 'host/footer.txt') "$footer`n"
    Write-Text $bodyFile "/review`n"
    $footerId = ("$(pwsh -NoProfile -File $probeGh pr comment 1 --body-file $bodyFile)".Trim() -split '#issuecomment-')[-1]
    $saved = (pwsh -NoProfile -File $probeGh api "repos/fixture/app/issues/comments/$footerId" --jq .body | Out-String).Replace("`r`n", "`n").TrimEnd()
    $unasked = "$(@(Get-Content -Raw -LiteralPath (Join-Path $probe 'host/prs.json') | ConvertFrom-Json)[0].reviewRequestedOid)"
    Write-Text $bodyFile "Autopilot: please comment ``/review`` on this pull request, so NCode Review reviews the commits just pushed.`n"
    $null = pwsh -NoProfile -File $probeGh pr comment 1 --body-file $bodyFile
    $asked = "$(@(Get-Content -Raw -LiteralPath (Join-Path $probe 'host/prs.json') | ConvertFrom-Json)[0].reviewRequestedOid)"
    Check 'fixture: with footer.txt the stand-in saves each comment with the footer under a new id, so a /review comment asks for no review, and an Autopilot: comment that names /review stands for the maintainer''s' ([long]$footerId -gt [long]$id -and $saved -eq "/review`n`n---`n$footer" -and -not $unasked -and $asked -eq $moved) "id $footerId after the deleted $id; saved: '$saved'; review asked for at '$unasked' before the Autopilot: comment and at '$asked' after it; the push is '$moved'"
    Invoke-Git --git-dir=$origin update-ref -d refs/heads/probe
    Remove-Item -LiteralPath $probe -Recurse -Force

    $clone = Join-Path $Work 'setup-check'
    Invoke-Git clone -q --branch $head $origin $clone
    $result = Get-FarewellResult $clone
    Check 'fixture: on the pull request''s branch the test passes and Get-Farewell says "Goodbye, !" without a name, as the writer says' ($result.Output -eq 'Goodbye, !|Goodbye, !|Goodbye, Ada!' -and $result.TestCode -eq 0) "output='$($result.Output)' test exit code $($result.TestCode)"
    Remove-Item -LiteralPath $clone -Recurse -Force

    # In the session-footer scenario the stand-in saves each comment and reply the run posts with a cloud session's footer.
    if ($Scenario -eq 'session-footer') { Write-Text (Join-Path $hostDir 'footer.txt') "_Generated by [Claude Code](https://claude.ai/code/session_01AbCdEf)_`n" }
    Check "fixture: the stand-in saves what the run posts with a session footer only in the session-footer scenario ($Scenario)" ((Test-Path -LiteralPath (Join-Path $hostDir 'footer.txt')) -eq ($Scenario -eq 'session-footer')) "footer.txt in the host folder: $(Test-Path -LiteralPath (Join-Path $hostDir 'footer.txt'))"
}

if ($SetupOnly) {
    ''
    if ($failures.Count) { "Run-feedback end-to-end setup: FAILED ($($failures.Count))"; exit 1 }
    'Run-feedback end-to-end setup: PASSED'
    exit 0
}

if (-not $CheckOnly) {
    # New-Agent reads Copilot's token before Use-FixtureEnvironment puts the gh stand-in first on PATH.
    $agent = New-Agent -Tool $Tool -Claude $Claude -Copilot $Copilot -Model $Model -MaxBudgetUsd $MaxBudgetUsd -TimeoutMinutes $TimeoutMinutes -App $app -Work $Work
    Use-FixtureEnvironment $Work $bin {
        Invoke-Agent $agent -Prompt '/run-feedback #1 wait:0' -Index 1
        $callsPath = Join-Path $hostDir 'calls.log'
        $replied = (Test-Path -LiteralPath $callsPath) -and @(Get-Content -LiteralPath $callsPath | Where-Object { $_ -match '^CALL (pr comment|api graphql .*addPullRequestReviewThreadReply)' }).Count
        if (-not $replied -and $agent.SessionId) {
            Invoke-Agent $agent -Prompt 'Yes, go ahead with the run you summarized.' -SessionId $agent.SessionId -Index 2
        }
    }
    Write-AgentSummary $agent
}

Use-FixtureEnvironment $Work $bin {
    Invoke-Git -C $app fetch -q origin
    $mainBefore = ([IO.File]::ReadAllText((Join-Path $hostDir 'main.txt'))).Trim()
    $headBefore = ([IO.File]::ReadAllText((Join-Path $hostDir 'head.txt'))).Trim()
    $callsPath = Join-Path $hostDir 'calls.log'
    $calls = if (Test-Path -LiteralPath $callsPath) { @(Get-Content -LiteralPath $callsPath) } else { @() }

    $unsupported = @($calls | Where-Object { $_ -match '^UNSUPPORTED' })
    Check 'the stand-in saw only supported gh calls' ($unsupported.Count -eq 0) ($unsupported -join '; ')
    $forbidden = @($calls | Where-Object { $_ -match '^FORBIDDEN' })
    Check 'no gh call resolved a thread, merged, readied, closed or edited the pull request' ($forbidden.Count -eq 0) ($forbidden -join '; ')

    $prs = @(Read-HostJson $hostDir 'prs.json' | Where-Object { $_ })
    $pr1 = @($prs | Where-Object { "$($_.number)" -eq '1' })
    $prOk = $prs.Count -eq 1 -and $pr1.Count -eq 1 -and $pr1[0].state -eq 'OPEN' -and $pr1[0].isDraft -eq $false -and $pr1[0].headRefName -eq $head
    Check 'pull request #1 is still open and not a draft, and no other was opened' $prOk "pull requests: $($prs.Count)$(if ($pr1.Count) { "; state=$($pr1[0].state) isDraft=$($pr1[0].isDraft)" })"

    $mainNow = "$(git --git-dir=$origin rev-parse main 2>$null)".Trim()
    Check 'origin main is unchanged' ($mainNow -and $mainNow -eq $mainBefore) "main is '$mainNow', expected '$mainBefore'"

    $headNow = "$(git --git-dir=$origin rev-parse $head 2>$null)".Trim()
    $null = git --git-dir=$origin merge-base --is-ancestor $headBefore $head 2>$null
    Check 'add-farewell on origin only moved forward: nothing was force-pushed' ($headNow -and $LASTEXITCODE -eq 0) "add-farewell is '$headNow', which doesn't contain '$headBefore'"

    $files = @(git --git-dir=$origin diff --name-only $headBefore $head 2>$null | Where-Object { $_ })
    $outside = @($files | Where-Object { $_ -notmatch '^(src|tests)/' })
    Check 'only the writer''s fix is pushed: new commits change src/ and tests/ and nothing else, such as ci.yml' ($headNow -ne $headBefore -and $files.Count -gt 0 -and $outside.Count -eq 0) "changed files: $($files -join ', ')"

    $null = pwsh -NoProfile -File (Join-Path $app '.template/Test-CommitAttribution.ps1') -Root $app -Base $headBefore -Head "origin/$head" 2>&1
    Check 'the pushed commits carry no AI attribution' ($LASTEXITCODE -eq 0) "exit code $LASTEXITCODE"

    $clone = Join-Path $Work 'check'
    if (Test-Path -LiteralPath $clone) { Remove-Item -LiteralPath $clone -Recurse -Force }
    Invoke-Git clone -q --branch $head $origin $clone
    $result = Get-FarewellResult $clone
    Check 'Get-Farewell says "Goodbye, world!" without a name on the pushed branch, and its test passes' ($result.Output -eq 'Goodbye, world!|Goodbye, world!|Goodbye, Ada!' -and $result.TestCode -eq 0) "output='$($result.Output)' test exit code $($result.TestCode)"

    $threads = Read-Threads
    $comments = @(Read-HostJson $hostDir 'comments.json' | Where-Object { $_ })

    $writer = @((Get-Thread $threads 'PRRT_writer').comments)
    $writerReply = if ($writer.Count -gt 1) { "$($writer[-1].body)".TrimStart() } else { '' }
    Check 'the writer''s thread gets "Autopilot: fixed in <commit>"' ($writerReply -match '^Autopilot: fixed in [0-9a-f]{7,}') "comments: $($writer.Count); last: '$writerReply'"

    $prComments = @($comments | Where-Object { $_.kind -eq 'pr' })
    $slash = @($prComments | Where-Object { "$($_.body)".Trim() -eq '/review' })
    $pr = $pr1 | Select-Object -First 1
    if ($Scenario -eq 'session-footer') {
        $leftSlash = @($prComments | Where-Object { "$($_.body)".TrimStart() -match '^/review\b' })
        $deletes = @($calls | Where-Object { $_ -match '^CALL api ' -and $_ -match '(^| )(-X|--method)[ =]?DELETE( |$)' -and $_ -match 'issues/comments/\d+' })
        Check 'no /review comment is left on the pull request: the run deleted the one that came back with the footer, and posted no other' ($leftSlash.Count -eq 0 -and $deletes.Count -eq 1) "/review comments left: $($leftSlash.Count); comments deleted: $($deletes.Count)"
        $asks = @(for ($i = 0; $i -lt $comments.Count; $i++) { if ($comments[$i].kind -eq 'pr' -and (Test-Autopilot $comments[$i].body) -and "$($comments[$i].body)".Contains('/review')) { $i } })
        Check 'an Autopilot: comment after the last push asks the maintainer to comment /review' ($asks.Count -ge 1 -and $pr -and $headNow -and "$($pr.reviewRequestedOid)" -eq $headNow) "comments that ask: $($asks.Count); reviewRequestedOid='$(if ($pr) { $pr.reviewRequestedOid })', branch head '$headNow'"
        $footed = @($comments | Where-Object { "$($_.body)".Contains('claude.ai/code/session_') })
        Check 'the run removed the footer from every top-level comment it left' ($prComments.Count -ge 1 -and $footed.Count -eq 0) "comments with the footer: $($footed.Count)"
    }
    else {
        Check 'the run commented /review after its last push' ($slash.Count -ge 1 -and $pr -and $headNow -and "$($pr.reviewRequestedOid)" -eq $headNow) "/review comments: $($slash.Count); reviewRequestedOid='$(if ($pr) { $pr.reviewRequestedOid })', branch head '$headNow'"
    }

    $checked = @($calls | Where-Object { $_ -match '^CALL api repos/\S+/commits/([0-9a-f]{7,40})/check-runs' -and $headNow.StartsWith($Matches[1]) })
    Check 'the run asked for NCode Review''s check run on the pushed commit, and the review arrived' ($checked.Count -ge 1 -and -not (Test-Path -LiteralPath (Join-Path $hostDir 'review-seed-push.json'))) "check-runs calls for the pushed commit: $($checked.Count); review-seed-push.json is still in the host folder: $(Test-Path -LiteralPath (Join-Path $hostDir 'review-seed-push.json'))"

    $nitThread = $threads | Where-Object { $_.key -eq 'nit' } | Select-Object -First 1
    $nitComments = @($nitThread.comments)
    $nitReplies = @($nitComments | Select-Object -Skip 1)
    Check 'NCode Review''s nit on the push got one reply, "Autopilot: not changed: a nit"' ($nitThread -and $nitReplies.Count -eq 1 -and "$($nitReplies[0].body)".TrimStart().StartsWith('Autopilot: not changed: a nit')) "comments on the nit: $($nitComments.Count); last: '$(if ($nitComments.Count -gt 1) { $nitComments[-1].body })'"

    $resolved = @($threads | Where-Object { $_.isResolved })
    Check 'no thread is resolved' ($threads.Count -eq 2 -and $resolved.Count -eq 0) "threads: $($threads.Count); resolved: $($resolved.Count)"

    $lastSlash = -1
    for ($i = 0; $i -lt $comments.Count; $i++) { if ($comments[$i].kind -eq 'pr' -and "$($comments[$i].body)".Trim() -eq '/review') { $lastSlash = $i } }
    # In the session-footer scenario no /review comment is left, so the recommendation comes after the comment that asks for one.
    if ($Scenario -eq 'session-footer') { $lastSlash = if ($asks.Count) { $asks[0] } else { -1 } }
    $merge = @(for ($i = 0; $i -lt $comments.Count; $i++) {
            if ($i -ne $lastSlash -and $comments[$i].kind -eq 'pr' -and "$($comments[$i].body)".TrimStart().StartsWith('Autopilot:') -and "$($comments[$i].body)" -match '(?i)\bmerg') { $i }
        })
    Check 'the run recommended the merge once, in a top-level Autopilot: comment after its /review, or after its request for one' ($merge.Count -eq 1 -and $lastSlash -ge 0 -and $merge[0] -gt $lastSlash) "merge recommendations: $($merge.Count); at index $($merge -join ','), last /review at index $lastSlash"

    $written = @($comments | Where-Object { "$($_.body)".Trim() -ne '/review' }) + @($threads | ForEach-Object { @($_.comments) | Select-Object -Skip 1 })
    $unmarked = @($written | Where-Object { -not (Test-Autopilot $_.body) })
    Check 'every comment and reply the run wrote, but /review, starts with Autopilot:' ($written.Count -ge 1 -and $unmarked.Count -eq 0) "written: $($written.Count); without the prefix: $($unmarked.Count)"
}

''
if ($failures.Count) { "Run-feedback end-to-end: FAILED ($($failures.Count))"; exit 1 }
'Run-feedback end-to-end: PASSED'
exit 0
