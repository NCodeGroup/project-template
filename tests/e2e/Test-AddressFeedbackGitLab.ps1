<#
.SYNOPSIS
    Run /address-feedback end to end in headless Claude Code on a fixture GitLab merge request with a local origin and a
    glab stand-in, and check what it pushed and replied, and that its read-backs see the notes without the session footer.

.DESCRIPTION
    Makes the fixture project with New-FixtureProject in Fixture.ps1, with git_host gitlab, a local origin under a
    gitlab.com folder and the glab stand-in (glab.ps1), and opens a fixture merge request, !1 from add-farewell, that adds
    Get-Farewell. The merge request has a discussion from a developer that asks for a real fix, and an individual note
    from a reporter that asks a question. The stand-in appends a Claude Code cloud session's footer to every note it
    saves (footer.txt), so the checks show that the run reads each note back, edits out the footer with PUT, and replies
    in the discussion without it. It costs model usage, so Invoke-AllTests.ps1 doesn't run it; run it by hand. CI runs
    only its fixture setup (-SetupOnly), so a template change that breaks the fixture still fails CI. Prints PASS or FAIL
    per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated unless -CheckOnly. Defaults to project-template-address-feedback-gitlab-e2e
    in the temp folder.

.PARAMETER SetupOnly
    Build the fixture and check it, without calling a model.

.PARAMETER CheckOnly
    Check the fixture of an earlier run again, without building it or calling a model.

.PARAMETER Claude
    The Claude Code CLI. Defaults to claude.

.PARAMETER MaxBudgetUsd
    The most each claude call may spend, passed as --max-budget-usd. 0 passes nothing. Defaults to 30.

.EXAMPLE
    .\tests\e2e\Test-AddressFeedbackGitLab.ps1

.EXAMPLE
    .\tests\e2e\Test-AddressFeedbackGitLab.ps1 -SetupOnly
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) 'project-template-address-feedback-gitlab-e2e'),
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
$origin = Join-Path $Work 'gitlab.com/fixture/app.git'
$bin = Join-Path $Work 'bin'
$hostDir = Join-Path $bin 'host'
$head = 'add-farewell'
$mrUrl = 'https://gitlab.com/fixture/app/-/merge_requests/1'
$commandFile = Join-Path $app '.claude/commands/address-feedback.md'

if (-not $CheckOnly) {
    New-FixtureProject -RepoRoot $repoRoot -Work $Work -App $app -Origin $origin -Bin $bin -Data @{ git_host = 'gitlab' }

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
    # The merge request's branch reaches origin as main did, and the main checkout is back on main, as a person's would be.
    Invoke-Git --git-dir=$origin fetch -q $app "${head}:$head"
    Invoke-Git -C $app switch -q main
    Invoke-Git -C $app branch -q -D $head
    Invoke-Git -C $app fetch -q origin
    $headOid = "$(git --git-dir=$origin rev-parse $head)".Trim()

    $mrs = @(
        @{
            iid = 1; title = 'Add Get-Farewell'; state = 'opened'; draft = $false; web_url = $mrUrl
            description = "Adds ``Get-Farewell``.`n"
            source_branch = $head; target_branch = 'main'; sha = $headOid; source_project_id = 1; target_project_id = 1
        }
    )
    $discussions = @(
        @{
            id = 'd-writer'; mr = 1; individual_note = $false
            notes = @(@{
                    id = 4001; author = @{ id = 2; username = 'ada-writer' }; system = $false; resolvable = $true; resolved = $false
                    body = 'With no name, or an empty one, this says `Goodbye, !`. Please make it say `Goodbye, world!` in both cases, and check both in `tests/Test-Greeting.ps1`.'
                })
        },
        @{
            id = 'd-question'; mr = 1; individual_note = $true
            notes = @(@{
                    id = 4002; author = @{ id = 3; username = 'grace-reader' }; system = $false; resolvable = $false; resolved = $false
                    body = 'Question: is `Get-Farewell` called anywhere yet, apart from the test?'
                })
        }
    )
    $members = @{
        '1' = @{ id = 1; username = 'fixture-owner'; access_level = 50 }
        '2' = @{ id = 2; username = 'ada-writer'; access_level = 30 }
        '3' = @{ id = 3; username = 'grace-reader'; access_level = 10 }
    }
    Write-Text (Join-Path $hostDir 'mrs.json') (ConvertTo-Json -InputObject $mrs -Depth 10)
    Write-Text (Join-Path $hostDir 'discussions.json') (ConvertTo-Json -InputObject $discussions -Depth 10)
    Write-Text (Join-Path $hostDir 'members.json') (ConvertTo-Json -InputObject $members -Depth 10)
    Write-Text (Join-Path $hostDir 'footer.txt') '_Generated by [Claude Code](https://claude.ai/code/session_01AbCdEf)_'

    # The self-checks below call the stand-in, which changes its state: they run on a copy that is put back afterwards.
    $saved = @{}
    foreach ($file in Get-ChildItem -LiteralPath $hostDir -File) { $saved[$file.Name] = [IO.File]::ReadAllText($file.FullName) }
    Use-FixtureEnvironment $Work $bin {
        $st = Get-State $app $app
        $ok = $st['host'] -eq 'gitlab' -and $st['default'] -eq 'main' -and $st['protected'] -eq 'hook' -and $st['landing'] -like '*integrate=pull-request*' -and $st['next'] -eq 'none no plan in this folder'
        Check 'fixture: the state script sees a GitLab origin whose main takes only merge requests' $ok "host='$($st['host'])' default='$($st['default'])' protected='$($st['protected'])' landing='$($st['landing'])' next='$($st['next'])'"

        $user = (glab api user | Out-String | ConvertFrom-Json).username
        Check 'fixture: glab on PATH is the stand-in, signed in as fixture-owner' ($user -eq 'fixture-owner') "username='$user'"

        $view = glab mr view 1 --output json | Out-String | ConvertFrom-Json
        $ok = $view.state -eq 'opened' -and $view.source_branch -eq $head -and $view.sha -eq $headOid -and $view.source_project_id -eq $view.target_project_id
        Check 'fixture: merge request !1 is open, from add-farewell at its head on origin, in the same project' $ok "state='$($view.state)' head='$($view.source_branch)' sha='$($view.sha)' source=$($view.source_project_id) target=$($view.target_project_id)"

        $found = @(glab api --paginate 'projects/:id/merge_requests/1/discussions?per_page=100' | Out-String | ConvertFrom-Json)
        $writer = @($found | Where-Object { -not $_.individual_note } | ForEach-Object { $_.notes } | Where-Object { $_.author.username -eq 'ada-writer' -and $_.resolvable -and -not $_.resolved })
        $reader = @($found | Where-Object { $_.individual_note } | ForEach-Object { $_.notes } | Where-Object { $_.author.username -eq 'grace-reader' })
        Check 'fixture: the discussions read gives the writer''s unresolved thread and the reader''s question' ($found.Count -eq 2 -and $writer.Count -eq 1 -and $reader.Count -eq 1) "discussions=$($found.Count) writer notes=$($writer.Count) reader notes=$($reader.Count)"

        $commandText = if (Test-Path -LiteralPath $commandFile) { [IO.File]::ReadAllText($commandFile) } else { '' }
        $routes = @('glab api "projects/:id/merge_requests/<number>/notes/<id>"', 'glab api --method PUT "projects/:id/merge_requests/<number>/notes/<id>" -F body=@<file>', 'discussions/<discussion id>/notes/<id>')
        $missing = @($routes | Where-Object { -not $commandText.Contains($_) })
        Check 'fixture: the installed /address-feedback has the GitLab read-back and edit routes' ($commandText -and $missing.Count -eq 0) "missing: $($missing -join '; ')"

        $callsLog = Join-Path $hostDir 'calls.log'
        $footer = ([IO.File]::ReadAllText((Join-Path $hostDir 'footer.txt'))).Trim()
        $bodyFile = Join-Path $Work 'note.md'
        Write-Text $bodyFile 'Autopilot: a note from the setup check.'
        $top = glab api --method POST 'projects/:id/merge_requests/1/notes' -F "body=@$bodyFile" | Out-String | ConvertFrom-Json
        $reply = glab api --method POST 'projects/:id/merge_requests/1/discussions/d-writer/notes' -F "body=@$bodyFile" | Out-String | ConvertFrom-Json
        $withFooter = "$($top.body)".EndsWith($footer) -and "$($reply.body)".EndsWith($footer)
        $null = glab api --method PUT "projects/:id/merge_requests/1/notes/$($top.id)" -F "body=@$bodyFile"
        $putCode = $LASTEXITCODE
        $backTop = glab api "projects/:id/merge_requests/1/notes/$($top.id)" | Out-String | ConvertFrom-Json
        $backReply = glab api "projects/:id/merge_requests/1/discussions/d-writer/notes/$($reply.id)" | Out-String | ConvertFrom-Json
        $edited = $putCode -eq 0 -and "$($backTop.body)".Trim() -eq 'Autopilot: a note from the setup check.' -and "$($backTop.body)" -notmatch 'Generated by'
        $replyKept = "$($backReply.body)".EndsWith($footer)
        $null = glab api --method DELETE "projects/:id/merge_requests/1/notes/$($top.id)"
        $deleteCode = $LASTEXITCODE
        $null = glab api "projects/:id/merge_requests/1/notes/$($top.id)" 2>$null
        $goneCode = $LASTEXITCODE
        $before = @(Get-Content -LiteralPath $callsLog).Count
        $null = glab api --method PUT 'projects/:id/merge_requests/1/discussions/d-writer' -F resolved=true 2>$null
        $resolveCode = $LASTEXITCODE
        $forbidden = @(Get-Content -LiteralPath $callsLog | Select-Object -Skip $before | Where-Object { $_ -like 'FORBIDDEN api*' }).Count
        Remove-Item -LiteralPath $bodyFile
        $ok = $top.id -and $reply.id -and $withFooter -and $edited -and $replyKept -and $deleteCode -eq 0 -and $goneCode -ne 0 -and $resolveCode -ne 0 -and $forbidden -eq 1
        Check 'fixture: with footer.txt the stand-in saves each new note and discussion reply with the footer, edits it with PUT, deletes it, and refuses resolving' ([bool]$ok) "footer: $withFooter edited: $edited reply kept footer: $replyKept delete exit $deleteCode, read after delete exit $goneCode, resolve exit $resolveCode, new FORBIDDEN lines $forbidden"

        $refused = [Collections.Generic.List[string]]::new()
        foreach ($command in 'merge', 'approve', 'close') {
            $before = @(Get-Content -LiteralPath $callsLog).Count
            $null = glab mr $command 1 2>$null
            $code = $LASTEXITCODE
            $logged = @(Get-Content -LiteralPath $callsLog | Select-Object -Skip $before | Where-Object { $_ -like "FORBIDDEN mr $command*" }).Count
            if ($code -eq 0 -or $logged -ne 1) { $refused.Add("mr $command (exit code $code, new FORBIDDEN lines $logged)") }
        }
        Check 'fixture: the stand-in refuses merging, approving and closing' ($refused.Count -eq 0) "not refused: $($refused -join '; ')"
    }
    Remove-Item -LiteralPath $hostDir -Recurse -Force
    New-Item -ItemType Directory -Force $hostDir | Out-Null
    foreach ($name in $saved.Keys) { [IO.File]::WriteAllText((Join-Path $hostDir $name), $saved[$name]) }
}

if ($SetupOnly) {
    ''
    if ($failures.Count) { "Address-feedback GitLab end-to-end setup: FAILED ($($failures.Count))"; exit 1 }
    'Address-feedback GitLab end-to-end setup: PASSED'
    exit 0
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
    if (-not (Get-Command $Claude -ErrorAction SilentlyContinue)) { throw 'Claude Code CLI not found: install it, or pass -Claude <path>' }

    $claudeArgs = @{ Claude = $Claude; MaxBudgetUsd = $MaxBudgetUsd; App = $app; Work = $Work }
    $script:cost = 0.0
    $script:sessionId = ''
    Use-FixtureEnvironment $Work $bin {
        $first = Invoke-Claude @claudeArgs -Prompt '/address-feedback #1' -Index 1
        Check 'Claude Code run 1 returned a session' ($first -and $first.session_id) 'no session_id in the output'
        if ($first -and $first.total_cost_usd) { $script:cost += [double]$first.total_cost_usd }
        $script:sessionId = if ($first) { "$($first.session_id)" } else { '' }
        $pushed = "$(git --git-dir=$origin rev-parse $head 2>$null)".Trim() -ne $headOid
        if (-not $pushed -and $first -and $first.session_id) {
            $second = Invoke-Claude @claudeArgs -Prompt 'Yes, go ahead with the run you summarized.' -SessionId $first.session_id -Index 2
            Check 'Claude Code run 2 returned a session' ($second -and $second.session_id) 'no session_id in the output'
            if ($second -and $second.total_cost_usd) { $script:cost += [double]$second.total_cost_usd }
        }
    }
    "Cost: $script:cost USD"
    "Fixture: $app"
    "Continue the session from $app with: claude --resume $script:sessionId"
}

Use-FixtureEnvironment $Work $bin {
    Invoke-Git -C $app fetch -q origin
    $mainBefore = ([IO.File]::ReadAllText((Join-Path $hostDir 'main.txt'))).Trim()
    # The merge request's head before the run is the sha in mrs.json, which the stand-in never changes.
    $headBefore = "$(@(Read-HostJson $hostDir 'mrs.json' | Where-Object { $_ })[0].sha)".Trim()
    $callsPath = Join-Path $hostDir 'calls.log'
    $calls = if (Test-Path -LiteralPath $callsPath) { @(Get-Content -LiteralPath $callsPath) } else { @() }

    $refused = @($calls | Where-Object { $_ -match '^(UNSUPPORTED|FORBIDDEN)' })
    Check 'the stand-in saw only supported glab calls, and none it refuses' ($refused.Count -eq 0) ($refused -join '; ')

    $mainNow = "$(git --git-dir=$origin rev-parse main 2>$null)".Trim()
    $headNow = "$(git --git-dir=$origin rev-parse $head 2>$null)".Trim()
    $null = git --git-dir=$origin merge-base --is-ancestor $headBefore $head 2>$null
    $forward = $LASTEXITCODE -eq 0
    Check 'origin main is unchanged, and add-farewell moved forward, never forced' ($mainNow -and $mainNow -eq $mainBefore -and $headNow -and $headNow -ne $headBefore -and $forward) "main is '$mainNow', expected '$mainBefore'; add-farewell is '$headNow', before '$headBefore', contains the old head: $forward"

    $clone = Join-Path $Work 'check'
    if (Test-Path -LiteralPath $clone) { Remove-Item -LiteralPath $clone -Recurse -Force }
    Invoke-Git clone -q --branch $head $origin $clone
    $result = Get-FarewellResult $clone
    Check 'the writer''s fix is on add-farewell: Get-Farewell says "Goodbye, world!" without a name, and its test passes' ($result.Output -eq 'Goodbye, world!|Goodbye, world!|Goodbye, Ada!' -and $result.TestCode -eq 0) "output='$($result.Output)' test exit code $($result.TestCode)"

    $discussions = @(Read-HostJson $hostDir 'discussions.json' | Where-Object { $_ })
    $noFooter = { param($Text) "$Text" -notmatch 'Generated by' -and "$Text" -notmatch '(?m)^---\s*$' }

    $writerNotes = @(@($discussions | Where-Object { $_.id -eq 'd-writer' } | ForEach-Object { $_.notes }) | Select-Object -Skip 1)
    $writerBody = if ($writerNotes.Count) { "$($writerNotes[0].body)" } else { '' }
    $ok = $writerNotes.Count -eq 1 -and $writerBody.TrimStart().StartsWith('Autopilot:') -and $writerBody -match '\b[0-9a-f]{7,40}\b' -and (& $noFooter $writerBody)
    Check 'the writer''s thread got one Autopilot: reply naming the commit, with no footer' ([bool]$ok) "notes after the first: $($writerNotes.Count); last: '$writerBody'"

    $topNotes = @($discussions | Where-Object { $_.individual_note -and @($_.notes).Count -eq 1 } | ForEach-Object { $_.notes } | Where-Object { "$($_.body)".TrimStart().StartsWith('Autopilot:') })
    $questionUrl = "$($mrUrl)#note_4002"
    $answer = @($topNotes | Where-Object {
            $body = "$($_.body)"
            $text = $body.Replace($questionUrl, '') -replace '^\s*Autopilot:', ''
            $body.Contains($questionUrl) -and $text -match 'Test-Greeting\.ps1' -and $text -match "(?i)\b(no|not|only|nowhere|none)\b|n't\b" -and $text -notmatch '(?i)\byes\b' -and (& $noFooter $body)
        })
    Check 'the question got a top-level Autopilot: note naming it, with no footer' ($answer.Count -ge 1) "top-level Autopilot: notes: $($topNotes.Count); naming the question and Test-Greeting.ps1 without a footer: $($answer.Count)"

    $puts = @($calls | Where-Object { $_ -match '^CALL api\b.*(--method[ =]|-X\s*)PUT\b.*/notes/' })
    Check 'the run read each note back and edited out the footer with PUT' ($puts.Count -ge 1) "PUT calls on notes: $($puts.Count)"

    $resolvedNotes = @($discussions | ForEach-Object { $_.notes } | Where-Object { $_.resolved -eq $true })
    Check 'no discussion was resolved' ($resolvedNotes.Count -eq 0) "resolved notes: $($resolvedNotes.Count)"
}

''
if ($failures.Count) { "Address-feedback GitLab end-to-end: FAILED ($($failures.Count))"; exit 1 }
'Address-feedback GitLab end-to-end: PASSED'
exit 0
