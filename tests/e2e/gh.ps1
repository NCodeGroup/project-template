<#
.SYNOPSIS
A stand-in for the GitHub CLI that the run-issues end-to-end test puts on PATH.

.DESCRIPTION
Run as `gh <args>`. It keeps its state in JSON files in the `host` folder beside it (`issues.json`, `prs.json`,
`comments.json`, `threads.json`, `reviews.json`, optional `origin.txt`), logs each call to `host/calls.log`, and fails
on calls it doesn't support or that /run-issues must never make. An optional `review-seed.json` holds the review
threads, review summaries and top-level comments the first pull request gets when it is opened.
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
        if ("$($list[$i])" -in '-F', '-f', '--field', '--raw-field') {
            $pair = "$($list[$i + 1])"
            if ($pair.StartsWith("$Key=")) { return $pair.Substring($Key.Length + 1) }
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
    $comments += @{ kind = $Kind; number = $Number; body = (Get-Body); url = $url; author = @{ login = 'fixture-owner' } }
    Write-Json 'comments.json' $comments
    return $url
}
# Gives the first pull request opened the review in host/review-seed.json, then deletes the seed: threads, with the
# earlier replies a seed thread lists, go to threads.json, review summaries to reviews.json and top-level comments to comments.json.
function Add-ReviewSeed([int]$Number, [string]$PrUrl) {
    $seedFile = Join-Path $hostDir 'review-seed.json'
    if (-not (Test-Path -LiteralPath $seedFile)) { return }
    $seed = Read-Json 'review-seed.json' @{}
    $threads = @(Read-Json 'threads.json' @())
    foreach ($t in @($seed.threads)) {
        $id = 2000 + $threads.Count + 1
        $threadComments = @(@{ author = $t.author; body = $t.body; url = "$PrUrl#discussion_r$id" })
        foreach ($reply in $t.replies) { $threadComments += @{ author = $reply.author; body = $reply.body; url = "$PrUrl#discussion_r$id-$($threadComments.Count)" } }
        $threads += @{
            id = "PRRT_$id"; key = $t.key; number = $Number; isResolved = $false; isOutdated = $false; path = $t.path; line = $t.line
            comments = $threadComments
        }
    }
    Write-Json 'threads.json' $threads
    $reviews = @(Read-Json 'reviews.json' @())
    foreach ($r in @($seed.reviews)) {
        $reviews += @{ number = $Number; author = $r.author; body = $r.body; url = "$PrUrl#pullrequestreview-$(3000 + $reviews.Count + 1)" }
    }
    Write-Json 'reviews.json' $reviews
    $comments = @(Read-Json 'comments.json' @())
    foreach ($c in @($seed.comments)) {
        $comments += @{ kind = 'pr'; key = $c.key; number = $Number; body = $c.body; url = "$PrUrl#issuecomment-$(1000 + $comments.Count + 1)"; author = $c.author }
    }
    Write-Json 'comments.json' $comments
    Remove-Item -LiteralPath $seedFile
}

if ("$($args[0])" -eq '--version') { 'gh version 2.99.0 (stand-in)'; exit 0 }

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
            $oid = git -C $originPath rev-parse --verify -q "refs/heads/$head"
            if ($LASTEXITCODE -ne 0) { Stop-Call UNSUPPORTED "head branch $head is not on origin" }
        }
        $number = Get-NextNumber
        $url = "https://github.com/fixture/app/pull/$number"
        $prs = @(Read-Json 'prs.json' @())
        $prs += @{
            number = $number; title = (Get-Option '--title', '-t'); body = (Get-Body); state = 'OPEN'
            isDraft = (Test-Flag '--draft', '-d'); headRefName = $head; baseRefName = $base
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
        if (-not $pr) { Stop-Call UNSUPPORTED "gh stand-in: unsupported call: $($args -join ' ')" }
        $pr.comments = @(@(Read-Json 'comments.json' @()) | Where-Object { $_.kind -eq 'pr' -and "$($_.number)" -eq "$($pr.number)" } |
            ForEach-Object { @{ author = $_.author; body = $_.body; url = $_.url } })
        $pr.reviews = @()
        $pr.reviewDecision = ''
        Write-Result $pr
        exit 0
    }
    'pr comment' {
        $number = [int]"$($args[2])".TrimStart('#')
        Add-Comment 'pr' $number 'pull'
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
        $query = Get-Field 'query'
        $number = Get-Field 'number'
        $pr = @(Read-Json 'prs.json' @()) | Where-Object { "$($_.number)" -eq "$number" } | Select-Object -First 1
        if ($query -and $query.Contains('addPullRequestReviewThreadReply')) {
            $threadId = Get-Field 'threadId'
            $threads = @(Read-Json 'threads.json' @())
            $thread = $threads | Where-Object { $_.id -eq $threadId } | Select-Object -First 1
            if (-not $thread) { Stop-Call UNSUPPORTED "gh stand-in: no review thread $threadId" }
            $body = Get-Field 'body'
            if ("$body".StartsWith('@')) { $body = [IO.File]::ReadAllText($body.Substring(1)) }
            $prUrl = @(Read-Json 'prs.json' @()) | Where-Object { "$($_.number)" -eq "$($thread.number)" } | ForEach-Object { $_.url } | Select-Object -First 1
            $replyUrl = "$prUrl#discussion_r$(4000 + @($threads | ForEach-Object { @($_.comments).Count } | Measure-Object -Sum).Sum)"
            $thread.comments = @($thread.comments) + @(@{ author = @{ __typename = 'User'; login = 'fixture-owner' }; body = "$body"; url = $replyUrl })
            Write-Json 'threads.json' $threads
            Write-Result @{ data = @{ addPullRequestReviewThreadReply = @{ comment = @{ url = $replyUrl } } } }
            exit 0
        }
        if (-not $pr) { Stop-Call UNSUPPORTED "gh stand-in: unsupported call: $($args -join ' ')" }
        $nodes = @(@(Read-Json 'comments.json' @()) | Where-Object { $_.kind -eq 'pr' -and "$($_.number)" -eq "$($pr.number)" } |
            ForEach-Object { @{ author = $_.author; body = $_.body; url = $_.url } })
        $reviewNodes = @(@(Read-Json 'reviews.json' @()) | Where-Object { "$($_.number)" -eq "$($pr.number)" } |
            ForEach-Object { @{ author = $_.author; body = $_.body; url = $_.url } })
        $threadNodes = @(@(Read-Json 'threads.json' @()) | Where-Object { "$($_.number)" -eq "$($pr.number)" } |
            ForEach-Object { @{ id = $_.id; isResolved = $_.isResolved; isOutdated = $_.isOutdated; path = $_.path; line = $_.line; comments = @{ nodes = @($_.comments) } } })
        Write-Result @{ data = @{ repository = @{ pullRequest = @{
            state = $pr.state; isDraft = $pr.isDraft
            comments = @{ nodes = $nodes }; reviews = @{ nodes = $reviewNodes }; reviewThreads = @{ nodes = $threadNodes }
        } } } }
        exit 0
    }
    'pr merge' { Stop-Call FORBIDDEN 'pr merge is not allowed in /run-issues' }
    'pr ready' { Stop-Call FORBIDDEN 'pr ready is not allowed in /run-issues' }
    default { Stop-Call UNSUPPORTED "gh stand-in: unsupported call: $($args -join ' ')" }
}
