<#
.SYNOPSIS
A stand-in for the GitHub CLI that the end-to-end tests put on PATH.

.DESCRIPTION
Run as `gh <args>`. It keeps its state in JSON files in the `host` folder beside it (`issues.json`, `prs.json`,
`comments.json`, optional `threads.json` with the pull requests' review threads, `reviews.json` with their review
summaries, and `origin.txt`), logs each call to `host/calls.log`, and fails on calls it doesn't support (logged as
UNSUPPORTED) or that the workflow must never make (logged as FORBIDDEN): merging a pull request, marking it ready,
closing it, and a GraphQL mutation that resolves a thread, dismisses a review, merges, or changes a pull request or
a branch. `pr view` of a branch with no pull request fails as gh does (logged as NOTFOUND). An optional `forbidden.txt` names more commands to refuse, one `<command> <subcommand>` per line, such as
`pr edit`. An optional `review-seed.json` holds the review threads, review summaries and top-level comments the first
pull request gets when it is opened. An optional `review-seed-push.json` holds the review a pull request gets on the first
GraphQL read after a /review comment posted once its branch on origin has moved past the head it was opened at, as NCode Review reviews a push only when a writer asks.
#>
$ErrorActionPreference = 'Stop'
$script:CallArgs = $args
$hostDir = Join-Path $PSScriptRoot 'host'
New-Item -ItemType Directory -Force $hostDir | Out-Null
$callsLog = Join-Path $hostDir 'calls.log'
[IO.File]::AppendAllText($callsLog, "CALL $($args -join ' ')`n")

function Read-Json([string]$Name, $Default) {
    $file = Join-Path $hostDir $Name
    if (-not (Test-Path -LiteralPath $file)) { return $Default }
    return ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($file)) -AsHashtable
}
function Write-Json([string]$Name, $Value) {
    $text = ConvertTo-Json -InputObject $Value -Depth 10
    [IO.File]::WriteAllText((Join-Path $hostDir $Name), $text.Replace("`r`n", "`n"))
}
function Get-Option([string[]]$Names) {
    $list = @($script:CallArgs)
    for ($i = 0; $i -lt $list.Count; $i++) {
        $arg = "$($list[$i])"
        if ($arg -in $Names) {
            if ($i + 1 -lt $list.Count) { return (@($list[$i + 1]) -join ',') }
            return $null
        }
        foreach ($name in $Names) {
            if ($arg.StartsWith("$name=")) { return $arg.Substring($name.Length + 1) }
        }
    }
    return $null
}
function Test-Flag([string[]]$Names) {
    foreach ($arg in $script:CallArgs) { if ("$arg" -in $Names) { return $true } }
    return $false
}
function Get-Field([string]$Key) {
    $list = @($script:CallArgs)
    for ($i = 0; $i -lt $list.Count - 1; $i++) {
        $flag = "$($list[$i])"
        if ($flag -in '-F', '-f', '--field', '--raw-field') {
            $pair = "$($list[$i + 1])"
            if ($pair.StartsWith("$Key=")) {
                $value = $pair.Substring($Key.Length + 1)
                # As gh does, a typed field (-F) whose value starts with @ is read from that file.
                if ($flag -in '-F', '--field' -and $value.StartsWith('@') -and $value.Length -gt 1) { return [IO.File]::ReadAllText($value.Substring(1)) }
                return $value
            }
        }
    }
    return $null
}
function Write-Result($Value) {
    $fields = Get-Option '--json'
    if ($fields) {
        $keys = $fields -split ','
        $pick = {
            param($item)
            $picked = @{}
            foreach ($key in $keys) { if ($item.ContainsKey($key)) { $picked[$key] = $item[$key] } }
            $picked
        }
        if ($Value -is [hashtable]) { $Value = & $pick $Value }
        elseif ($Value -is [array]) { $Value = @($Value | ForEach-Object { & $pick $_ }) }
    }
    $jq = Get-Option '--jq'
    if ($jq -and $jq -match '^(\.[A-Za-z_]\w*)+$') {
        $current = $Value
        foreach ($key in $jq.Substring(1) -split '\.') {
            if ($current -is [hashtable] -and $current.ContainsKey($key)) { $current = $current[$key] } else { $current = $null; break }
        }
        if ($current -is [string] -or $current -is [ValueType]) { "$current" }
        else { ConvertTo-Json -InputObject $current -Depth 10 }
        return
    }
    ConvertTo-Json -InputObject $Value -Depth 10
}
function Stop-Call([string]$Kind, [string]$Message, $CallArgs = $script:CallArgs) {
    [IO.File]::AppendAllText($callsLog, "$Kind $($CallArgs -join ' ')`n")
    [Console]::Error.WriteLine($Message)
    exit 1
}

function Get-Body {
    $file = Get-Option '--body-file', '-F'
    if ($file) { return [IO.File]::ReadAllText($file) }
    $body = Get-Option '--body', '-b'
    if ($null -ne $body) { return $body }
    return ''
}
function Get-NextNumber {
    $max = 0
    foreach ($key in (Read-Json 'issues.json' @{}).Keys) { if ([int]$key -gt $max) { $max = [int]$key } }
    foreach ($pr in @(Read-Json 'prs.json' @())) { if ([int]$pr.number -gt $max) { $max = [int]$pr.number } }
    return $max + 1
}
function Add-Comment([string]$Kind, [int]$Number, [string]$Path) {
    $comments = @(Read-Json 'comments.json' @())
    $id = 1000 + $comments.Count + 1
    $url = "https://github.com/fixture/app/$Path/$Number#issuecomment-$id"
    $comments += @{ kind = $Kind; number = $Number; body = (Get-Body); url = $url; author = @{ login = 'fixture-owner' }; authorAssociation = 'OWNER' }
    Write-Json 'comments.json' $comments
    return $url
}
# Gives the first pull request opened the review in host/review-seed.json, then deletes the seed: threads, with the
# earlier replies a seed thread lists, go to threads.json, review summaries to reviews.json and top-level comments to comments.json.
# Each keeps the authorAssociation the seed gives it, and has none when the seed gives none.
function Add-ReviewSeed([int]$Number, [string]$PrUrl, [string]$SeedName = 'review-seed.json') {
    $seedFile = Join-Path $hostDir $SeedName
    if (-not (Test-Path -LiteralPath $seedFile)) { return }
    $seed = Read-Json $SeedName @{}
    $threads = @(Read-Json 'threads.json' @())
    foreach ($t in @($seed.threads | Where-Object { $_ })) {
        $id = 2000 + $threads.Count + 1
        $threadComments = @(@{ author = $t.author; authorAssociation = $t.authorAssociation; body = $t.body; url = "$PrUrl#discussion_r$id" })
        foreach ($reply in $t.replies) { $threadComments += @{ author = $reply.author; authorAssociation = $reply.authorAssociation; body = $reply.body; url = "$PrUrl#discussion_r$id-$($threadComments.Count)" } }
        $threads += @{
            id = "PRRT_$id"; key = $t.key; number = $Number; isResolved = $false; isOutdated = $false; path = $t.path; line = $t.line
            comments = $threadComments
        }
    }
    Write-Json 'threads.json' $threads
    $reviews = @(Read-Json 'reviews.json' @())
    foreach ($r in @($seed.reviews | Where-Object { $_ })) {
        $reviews += @{ number = $Number; author = $r.author; authorAssociation = $r.authorAssociation; body = $r.body; url = "$PrUrl#pullrequestreview-$(3000 + $reviews.Count + 1)" }
    }
    Write-Json 'reviews.json' $reviews
    $comments = @(Read-Json 'comments.json' @())
    foreach ($c in @($seed.comments | Where-Object { $_ })) {
        $comments += @{ kind = 'pr'; key = $c.key; number = $Number; body = $c.body; url = "$PrUrl#issuecomment-$(1000 + $comments.Count + 1)"; author = $c.author; authorAssociation = $c.authorAssociation }
    }
    Write-Json 'comments.json' $comments
    Remove-Item -LiteralPath $seedFile
}
# Gives a pull request the review in host/review-seed-push.json, as NCode Review reviews a push when a writer asks: on the first read
# after a /review comment posted once its branch on origin has moved past the head it was opened at. Then deletes that seed.
function Add-PushReview($Pr) {
    $originFile = Join-Path $hostDir 'origin.txt'
    if (-not (Test-Path -LiteralPath (Join-Path $hostDir 'review-seed-push.json')) -or -not (Test-Path -LiteralPath $originFile)) { return }
    $oid = git --git-dir=$(([IO.File]::ReadAllText($originFile)).Trim()) rev-parse --verify -q "refs/heads/$($Pr.headRefName)"
    if ($LASTEXITCODE -ne 0 -or "$oid" -eq "$($Pr.headRefOid)") { return }
    if ("$($Pr.reviewRequestedOid)" -ne "$oid") { return }
    Add-ReviewSeed ([int]$Pr.number) "$($Pr.url)" 'review-seed-push.json'
}
# Records the head a /review comment asks a review of: the pull request's branch on origin as it is now.
function Set-ReviewRequest([int]$Number) {
    $originFile = Join-Path $hostDir 'origin.txt'
    if (-not (Test-Path -LiteralPath $originFile)) { return }
    $prs = @(Read-Json 'prs.json' @())
    $pr = $prs | Where-Object { "$($_.number)" -eq "$Number" } | Select-Object -First 1
    if (-not $pr) { return }
    $oid = git --git-dir=$(([IO.File]::ReadAllText($originFile)).Trim()) rev-parse --verify -q "refs/heads/$($pr.headRefName)"
    if ($LASTEXITCODE -ne 0) { return }
    $pr.reviewRequestedOid = "$oid"
    Write-Json 'prs.json' $prs
}
# A comment without an authorAssociation is served without one, never as the owner's.
function Get-CommentNode($Comment) {
    return @{ author = $Comment.author; authorAssociation = $Comment.authorAssociation; body = $Comment.body; url = $Comment.url }
}

if ("$($args[0])" -eq '--version') { 'gh version 2.99.0 (stand-in)'; exit 0 }

$forbiddenFile = Join-Path $hostDir 'forbidden.txt'
if (Test-Path -LiteralPath $forbiddenFile) {
    foreach ($line in [IO.File]::ReadAllLines($forbiddenFile)) {
        if ($line.Trim() -and "$($args[0]) $($args[1])" -eq $line.Trim()) { Stop-Call FORBIDDEN "gh stand-in: $($line.Trim()) is not allowed in this test" }
    }
}

switch ("$($args[0]) $($args[1])") {
    'auth status' { 'Logged in to github.com account fixture-owner (stand-in)'; exit 0 }
    'api user' { Write-Result @{ login = 'fixture-owner' }; exit 0 }
    'repo view' {
        Write-Result @{ name = 'app'; nameWithOwner = 'fixture/app'; owner = @{ login = 'fixture' }; url = 'https://github.com/fixture/app'; defaultBranchRef = @{ name = 'main' } }
        exit 0
    }
    'issue view' {
        $number = "$($args[2])".TrimStart('#')
        $issues = Read-Json 'issues.json' @{}
        if (-not $issues.ContainsKey($number)) { Stop-Call UNSUPPORTED "gh stand-in: unsupported call: $($args -join ' ')" }
        $issue = $issues[$number]
        $issue.comments = @(@(Read-Json 'comments.json' @()) | Where-Object { $_.kind -eq 'issue' -and "$($_.number)" -eq $number } |
            ForEach-Object { @{ author = $_.author; body = $_.body; url = $_.url } })
        if ((Get-Option '--json') -or (Get-Option '--jq')) { Write-Result $issue }
        else {
            "title:`t$($issue.title)"
            "state:`t$($issue.state)"
            "labels:`t$((@($issue.labels) | ForEach-Object { $_.name }) -join ', ')"
            ''
            $issue.body
        }
        exit 0
    }
    'issue list' {
        if (Get-Option '--json') { Write-Result @() }
        exit 0
    }
    'issue comment' {
        $number = [int]"$($args[2])".TrimStart('#')
        Add-Comment 'issue' $number 'issues'
        exit 0
    }
    'issue create' {
        $number = Get-NextNumber
        $url = "https://github.com/fixture/app/issues/$number"
        $labels = @()
        $label = Get-Option '--label', '-l'
        if ($label) { $labels = @($label -split ',' | ForEach-Object { @{ name = $_ } }) }
        $issues = Read-Json 'issues.json' @{}
        $issues["$number"] = @{
            number = $number; title = (Get-Option '--title', '-t'); body = (Get-Body); state = 'OPEN'; url = $url
            labels = $labels; assignees = @(); author = @{ login = 'fixture-owner' }
        }
        Write-Json 'issues.json' $issues
        $url
        exit 0
    }
    'issue close' {
        $number = "$($args[2])".TrimStart('#')
        $issues = Read-Json 'issues.json' @{}
        if (-not $issues.ContainsKey($number)) { Stop-Call UNSUPPORTED "gh stand-in: unsupported call: $($args -join ' ')" }
        $issues[$number].state = 'CLOSED'
        Write-Json 'issues.json' $issues
        exit 0
    }
    'label create' { exit 0 }
    'pr create' {
        $head = Get-Option '--head'
        if (-not $head) { $head = (git branch --show-current) }
        $base = Get-Option '--base'
        if (-not $base) { $base = 'main' }
        $oid = ''
        $originFile = Join-Path $hostDir 'origin.txt'
        if (Test-Path -LiteralPath $originFile) {
            $originPath = ([IO.File]::ReadAllText($originFile)).Trim()
            $oid = git --git-dir=$originPath rev-parse --verify -q "refs/heads/$head"
            if ($LASTEXITCODE -ne 0) { Stop-Call UNSUPPORTED "head branch $head is not on origin" }
        }
        $number = Get-NextNumber
        $url = "https://github.com/fixture/app/pull/$number"
        $prs = @(Read-Json 'prs.json' @())
        $prs += @{
            number = $number; title = (Get-Option '--title', '-t'); body = (Get-Body); state = 'OPEN'
            isDraft = (Test-Flag '--draft', '-d'); headRefName = $head; baseRefName = $base; isCrossRepository = $false
            headRefOid = "$oid"; mergeCommit = $null; url = $url
        }
        Write-Json 'prs.json' $prs
        Add-ReviewSeed $number $url
        $url
        exit 0
    }
    'pr list' {
        $state = Get-Option '--state'
        $head = Get-Option '--head'
        $found = @(@(Read-Json 'prs.json' @()) | Where-Object {
            (-not $state -or $state -eq 'all' -or $_.state -eq $state.ToUpper()) -and (-not $head -or $_.headRefName -eq $head)
        })
        if (Get-Option '--json') { Write-Result $found }
        else { foreach ($pr in $found) { "$($pr.number)`t$($pr.title)`t$($pr.headRefName)`t$(if ($pr.isDraft) { 'DRAFT' } else { 'OPEN' })" } }
        exit 0
    }
    'pr view' {
        $which = "$($args[2])".TrimStart('#')
        if (-not $which -or $which.StartsWith('-')) { $which = (git branch --show-current) }
        $pr = @(Read-Json 'prs.json' @()) | Where-Object { "$($_.number)" -eq $which -or $_.headRefName -eq $which } | Select-Object -First 1
        # A branch without a pull request fails as gh fails it. Claude Code itself looks up the current branch's pull
        # request this way, so it is not the workflow's call to refuse.
        if (-not $pr -and $which -notmatch '^\d+$') { Stop-Call NOTFOUND "no pull requests found for branch ""$which""" }
        if (-not $pr) { Stop-Call UNSUPPORTED "gh stand-in: unsupported call: $($args -join ' ')" }
        $pr.comments = @(@(Read-Json 'comments.json' @()) | Where-Object { $_.kind -eq 'pr' -and "$($_.number)" -eq "$($pr.number)" } |
            ForEach-Object { Get-CommentNode $_ })
        $pr.reviews = @()
        $pr.reviewDecision = ''
        Write-Result $pr
        exit 0
    }
    'pr comment' {
        $number = [int]"$($args[2])".TrimStart('#')
        Add-Comment 'pr' $number 'pull'
        if ((Get-Body) -match '^\s*/review\s*\z') { Set-ReviewRequest $number }
        exit 0
    }
    'pr edit' {
        $number = "$($args[2])".TrimStart('#')
        $prs = @(Read-Json 'prs.json' @())
        $pr = $prs | Where-Object { "$($_.number)" -eq $number } | Select-Object -First 1
        if (-not $pr) { Stop-Call UNSUPPORTED "gh stand-in: unsupported call: $($args -join ' ')" }
        $pr.body = Get-Body
        Write-Json 'prs.json' $prs
        $pr.url
        exit 0
    }
    'api graphql' {
        $query = "$(Get-Field 'query')"
        if ($query -match '^\s*mutation\b') {
            $refused = 'resolveReviewThread', 'dismissPullRequestReview', 'mergePullRequest', 'markPullRequestReadyForReview',
                'convertPullRequestToDraft', 'enablePullRequestAutoMerge', 'closePullRequest', 'updatePullRequest',
                'minimizeComment', 'updateRef', 'deleteRef'
            foreach ($name in $refused) { if ($query -match "\b$name\b") { Stop-Call FORBIDDEN "gh stand-in: the mutation $name is not allowed" } }
            if (-not $query.Contains('addPullRequestReviewThreadReply')) { Stop-Call UNSUPPORTED "gh stand-in: unsupported mutation: $query" }
            $threadId = Get-Field 'threadId'
            $threads = @(Read-Json 'threads.json' @())
            $thread = $threads | Where-Object { "$($_.id)" -eq "$threadId" } | Select-Object -First 1
            if (-not $thread) { Stop-Call UNSUPPORTED "gh stand-in: no review thread $threadId" }
            $count = 0
            foreach ($t in $threads) { $count += @($t.comments).Count }
            $url = "https://github.com/fixture/app/pull/$($thread.number)#discussion_r$(2000 + $count + 1)"
            $thread.comments = @($thread.comments) + @(@{ author = @{ __typename = 'User'; login = 'fixture-owner' }; authorAssociation = 'OWNER'; body = "$(Get-Field 'body')"; url = $url })
            Write-Json 'threads.json' $threads
            Write-Result @{ data = @{ addPullRequestReviewThreadReply = @{ comment = @{ url = $url } } } }
            exit 0
        }
        $number = Get-Field 'number'
        $pr = @(Read-Json 'prs.json' @()) | Where-Object { "$($_.number)" -eq "$number" } | Select-Object -First 1
        if (-not $pr) { Stop-Call UNSUPPORTED "gh stand-in: unsupported call: $($args -join ' ')" }
        Add-PushReview $pr
        $none = @{ hasNextPage = $false }
        $nodes = @(@(Read-Json 'comments.json' @()) | Where-Object { $_.kind -eq 'pr' -and "$($_.number)" -eq "$($pr.number)" } |
            ForEach-Object { Get-CommentNode $_ })
        $reviews = @(@(Read-Json 'reviews.json' @()) | Where-Object { "$($_.number)" -eq "$($pr.number)" } | ForEach-Object { Get-CommentNode $_ })
        $threads = @(@(Read-Json 'threads.json' @()) | Where-Object { "$($_.number)" -eq "$($pr.number)" } | ForEach-Object {
            @{
                id = $_.id; isResolved = [bool]$_.isResolved; isOutdated = [bool]$_.isOutdated; path = $_.path; line = $_.line
                comments = @{ nodes = @(@($_.comments) | ForEach-Object { Get-CommentNode $_ }) }
            }
        })
        Write-Result @{ data = @{ repository = @{ pullRequest = @{
            state = $pr.state; isDraft = $pr.isDraft
            comments = @{ pageInfo = $none; nodes = $nodes }; reviews = @{ pageInfo = $none; nodes = $reviews }
            reviewThreads = @{ pageInfo = $none; nodes = $threads }
        } } } }
        exit 0
    }
    'pr merge' { Stop-Call FORBIDDEN 'gh stand-in: pr merge is not allowed' }
    'pr ready' { Stop-Call FORBIDDEN 'gh stand-in: pr ready is not allowed' }
    'pr close' { Stop-Call FORBIDDEN 'gh stand-in: pr close is not allowed' }
    default { Stop-Call UNSUPPORTED "gh stand-in: unsupported call: $($args -join ' ')" }
}
