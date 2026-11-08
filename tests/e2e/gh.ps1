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
read of its threads, comments or reviews, GraphQL or REST, after a /review comment posted once its branch on origin has moved past the head it was opened at, as NCode Review reviews a push only when a writer asks.
`api repos/<owner>/<repo>/commits/<sha>/check-runs` answers one completed `Code review` check run of the app `ncode-review` for a commit whose push review it has given, giving it first when a /review comment asked for it, and evaluates only simple `--jq` paths and the count of completed check runs of one app.
`api repos/<owner>/<repo>/issues/comments/<id>` answers a comment it holds by its id, as the commands read a post back
after making it; with `-X PATCH` it saves the `body` field as given, and with `-X DELETE` it deletes the comment, whose
id `last-comment-id.txt` keeps it from giving again. An optional `footer.txt` holds a footer it appends, after a blank
line and a `---` line, to each top-level comment and thread reply it saves, as a Claude Code cloud session's tooling
does: a `/review` comment saved with it asks for no review, and an `Autopilot:` comment that names `/review` then
stands for the `/review` the maintainer posts after it. An optional delete-fails.txt makes a comment's delete fail (logged as REFUSED), so the comment stays.
An optional footer-pr-only.txt keeps the footer off issue comments, such as a plan snapshot, so the first post that comes back with it is one on the pull request.
On that route it reads the method as gh does, from `-X PATCH`, `-XPATCH`, `-X=PATCH` or `--method=PATCH`, and takes a
call with `-f`, `-F`, `--field`, `--raw-field` or `--input` and no method as the POST gh sends, which it refuses.
`api repos/<owner>/<repo>/pulls?head=<owner>:<branch>&state=all`, `api repos/<owner>/<repo>/issues/<number>` and `api repos/<owner>/<repo>/releases/tags/<tag>` answer the state script's REST calls from `prs.json` and `issues.json`, a release always not found (logged as NOTFOUND).
An optional graphql-refused.txt makes it refuse gh api graphql and the pr, issue, release and repo commands as a Claude Code cloud session's proxy does (logged as GRAPHQL), so a command must use the REST routes below.
api repos/<owner>/<repo>/pulls/<number>, its /ccr/review_threads, /comments and /reviews (the last two paged by per_page and page) answer the pull request and its review threads, comments and reviews from prs.json, threads.json and reviews.json.
api repos/<owner>/<repo>/issues/<number>/comments (GET paged, POST a body), pulls/<number>/comments/<id>/replies (POST, to a thread's first comment) save and answer comments and thread replies as the pr comment command and the GraphQL reply do; /ccr resolve, auto-merge and draft routes, and a PATCH of pulls/<number> under forbidden.txt's pr edit, are refused (FORBIDDEN).
#>
$ErrorActionPreference = 'Stop'
$script:CallArgs = $args
$hostDir = Join-Path $PSScriptRoot 'host'
New-Item -ItemType Directory -Force $hostDir | Out-Null
$callsLog = Join-Path $hostDir 'calls.log'
. (Join-Path $PSScriptRoot 'StandInLog.ps1')
Add-StandInLog $callsLog "CALL $($args -join ' ')"

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
    Add-StandInLog $callsLog "$Kind $($CallArgs -join ' ')"
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
# The body a comment or a thread reply is saved with: with host/footer.txt, the body sent, a blank line, a --- line and
# that footer, as a Claude Code cloud session's tooling appends one to what it posts.
function Get-SavedBody([string]$Body) {
    $footerFile = Join-Path $hostDir 'footer.txt'
    if (-not (Test-Path -LiteralPath $footerFile)) { return $Body }
    return $Body.TrimEnd() + "`n`n---`n" + ([IO.File]::ReadAllText($footerFile)).Trim()
}
# The id a new top-level comment gets: one more than any id given so far, which host/last-comment-id.txt keeps, so a
# deleted comment's id is never given again.
function Get-NextCommentId($Comments) {
    $idFile = Join-Path $hostDir 'last-comment-id.txt'
    $id = 1000
    if (Test-Path -LiteralPath $idFile) { $id = [long]([IO.File]::ReadAllText($idFile)).Trim() }
    foreach ($c in @($Comments)) { if ("$($c.url)" -match '#issuecomment-(\d+)$' -and [long]$Matches[1] -gt $id) { $id = [long]$Matches[1] } }
    $id++
    [IO.File]::WriteAllText($idFile, "$id")
    return $id
}
# The id a new review comment gets: one more than the largest #discussion_r number in threads.json and the one
# host/last-review-comment-id.txt keeps, so ids never collide and a given id is never given again.
function Get-NextReviewCommentId {
    $idFile = Join-Path $hostDir 'last-review-comment-id.txt'
    $id = 2000
    if (Test-Path -LiteralPath $idFile) { $id = [long]([IO.File]::ReadAllText($idFile)).Trim() }
    foreach ($t in @(Read-Json 'threads.json' @())) {
        foreach ($c in @($t.comments)) { if ("$($c.url)" -match '#discussion_r(\d+)$' -and [long]$Matches[1] -gt $id) { $id = [long]$Matches[1] } }
    }
    $id++
    [IO.File]::WriteAllText($idFile, "$id")
    return $id
}
function Get-NextNumber {
    $max = 0
    foreach ($key in (Read-Json 'issues.json' @{}).Keys) { if ([int]$key -gt $max) { $max = [int]$key } }
    foreach ($pr in @(Read-Json 'prs.json' @())) { if ([int]$pr.number -gt $max) { $max = [int]$pr.number } }
    return $max + 1
}
function Add-Comment([string]$Kind, [int]$Number, [string]$Path, [string]$Body) {
    $comments = @(Read-Json 'comments.json' @())
    $id = Get-NextCommentId $comments
    $url = "https://github.com/fixture/app/$Path/$Number#issuecomment-$id"
    $body = $Body
    if (-not ($Kind -eq 'issue' -and (Test-Path -LiteralPath (Join-Path $hostDir 'footer-pr-only.txt')))) { $body = Get-SavedBody $body }
    $comments += @{ kind = $Kind; number = $Number; body = $body; url = $url; author = @{ login = 'fixture-owner' }; authorAssociation = 'OWNER' }
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
        $id = Get-NextReviewCommentId
        $threadComments = @(@{ author = $t.author; authorAssociation = $t.authorAssociation; body = $t.body; url = "$PrUrl#discussion_r$id" })
        foreach ($reply in $t.replies) { $threadComments += @{ author = $reply.author; authorAssociation = $reply.authorAssociation; body = $reply.body; url = "$PrUrl#discussion_r$id$($threadComments.Count)" } }
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
        $comments += @{ kind = 'pr'; key = $c.key; number = $Number; body = $c.body; url = "$PrUrl#issuecomment-$(Get-NextCommentId $comments)"; author = $c.author; authorAssociation = $c.authorAssociation }
    }
    Write-Json 'comments.json' $comments
    Remove-Item -LiteralPath $seedFile
}
# Gives a pull request the review in host/review-seed-push.json, as NCode Review reviews a push when a writer asks: on the first read
# after a /review comment posted once its branch on origin has moved past the head it was opened at. Then deletes that seed
# and records the commit it reviewed as the pull request's reviewedOid.
function Add-PushReview($Pr) {
    $originFile = Join-Path $hostDir 'origin.txt'
    if (-not (Test-Path -LiteralPath (Join-Path $hostDir 'review-seed-push.json')) -or -not (Test-Path -LiteralPath $originFile)) { return }
    $oid = git --git-dir=$(([IO.File]::ReadAllText($originFile)).Trim()) rev-parse --verify -q "refs/heads/$($Pr.headRefName)"
    if ($LASTEXITCODE -ne 0 -or "$oid" -eq "$($Pr.headRefOid)") { return }
    if ("$($Pr.reviewRequestedOid)" -ne "$oid") { return }
    Add-ReviewSeed ([int]$Pr.number) "$($Pr.url)" 'review-seed-push.json'
    $prs = @(Read-Json 'prs.json' @())
    $current = $prs | Where-Object { "$($_.number)" -eq "$($Pr.number)" } | Select-Object -First 1
    if ($current) {
        $current.reviewedOid = "$oid"
        Write-Json 'prs.json' $prs
    }
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

function Get-RestId([string]$Url) {
    if ($Url -match '#(?:discussion_r|issuecomment-|pullrequestreview-)(\d+)$') { return [long]$Matches[1] }
    return 0
}

function Get-RestUser($Author) {
    $login = "$($Author.login)"
    $isBot = "$($Author.__typename)" -eq 'Bot' -or $login.EndsWith('[bot]')
    if ($isBot -and -not $login.EndsWith('[bot]')) { $login = "${login}[bot]" }
    return @{ login = $login; type = $(if ($isBot) { 'Bot' } else { 'User' }) }
}

# The stored pull request with this number, or nothing.
function Get-PullRequestRecord($Number) {
    return @(Read-Json 'prs.json' @()) | Where-Object { "$($_.number)" -eq "$Number" } | Select-Object -First 1
}

# The repos/ path of an api call as gh takes it: the first argument after api that names a repository's resource, with a leading /
# removed, wherever -X, --method or -H put it; $null when there is none.
function Get-ApiPath {
    $found = @($script:CallArgs | Select-Object -Skip 1 | Where-Object { "$_" -match '^/?repos/[^/]+/[^/]+/' }) | Select-Object -First 1
    if ($null -eq $found) { return $null }
    return "$found".TrimStart('/')
}

# One page of a REST list, from the per_page (30 when absent) and page (1 when absent) of the call's path query, else of its
# -f/-F fields, which gh sends as query parameters on a GET. page is at least 1 and per_page 1 to 100, as GitHub clamps them.
function Get-Page($Items) {
    $perPage = $null
    $page = $null
    if ("$(Get-ApiPath)" -match '\?(.*)$') {
        foreach ($pair in "$($Matches[1])" -split '&') {
            if ($pair -match '^per_page=(\d+)$') { $perPage = [long]$Matches[1] }
            elseif ($pair -match '^page=(\d+)$') { $page = [long]$Matches[1] }
        }
    }
    if ($null -eq $perPage -and "$(Get-Field 'per_page')" -match '^\d+$') { $perPage = [long]"$(Get-Field 'per_page')" }
    if ($null -eq $page -and "$(Get-Field 'page')" -match '^\d+$') { $page = [long]"$(Get-Field 'page')" }
    if ($null -eq $perPage) { $perPage = 30 }
    if ($null -eq $page) { $page = 1 }
    $page = [Math]::Max($page, 1)
    $perPage = [Math]::Min([Math]::Max($perPage, 1), 100)
    $all = @($Items)
    if (($page - 1) -ge $all.Count) { return @() }
    $skip = [int](($page - 1) * $perPage)
    if ($skip -ge $all.Count) { return @() }
    return @($all | Select-Object -Skip $skip -First ([int]$perPage))
}

# The method an api call uses, as gh reads it: -X or --method (also as -X=PATCH), a method attached to -X as in -XPATCH, or POST
# when fields or --input are given without one, else GET.
function Get-ApiMethod {
    $method = "$(Get-Option '-X', '--method')".ToUpperInvariant()
    $attachedMethod = @($script:CallArgs | Where-Object { "$_" -cmatch '^-X[A-Za-z]+$' }) | Select-Object -First 1
    if (-not $method -and $attachedMethod) { $method = "$attachedMethod".Substring(2).ToUpperInvariant() }
    if (-not $method -and @($script:CallArgs | Where-Object { "$_" -in '-f', '-F', '--field', '--raw-field', '--input' -or "$_" -match '^--(field|raw-field|input)=' }).Count) { $method = 'POST' }
    if (-not $method) { $method = 'GET' }
    return $method
}

if ("$($args[0])" -eq '--version') { 'gh version 2.99.0 (stand-in)'; exit 0 }

$forbiddenFile = Join-Path $hostDir 'forbidden.txt'
if (Test-Path -LiteralPath $forbiddenFile) {
    foreach ($line in [IO.File]::ReadAllLines($forbiddenFile)) {
        if ($line.Trim() -and "$($args[0]) $($args[1])" -eq $line.Trim()) { Stop-Call FORBIDDEN "gh stand-in: $($line.Trim()) is not allowed in this test" }
    }
}

if ("$($args[0]) $($args[1])" -in 'pr merge', 'pr ready', 'pr close') { Stop-Call FORBIDDEN "gh stand-in: $($args[0]) $($args[1]) is not allowed" }

if ((Test-Path -LiteralPath (Join-Path $hostDir 'graphql-refused.txt')) -and ("$($args[0])" -in 'pr', 'issue', 'release', 'repo' -or ("$($args[0])" -eq 'api' -and @($args | Select-Object -Skip 1 | Where-Object { "$_" -in 'graphql', '/graphql' }).Count))) {
    Stop-Call GRAPHQL 'HTTP 403: GitHub GraphQL is not available from Claude Code sessions; use the REST API (gh api repos/{owner}/{repo}/...). For review threads, auto-merge, and draft/ready-for-review use the CCR routes on api.github.com: GET /repos/{owner}/{repo}/pulls/{n}/ccr/review_threads, POST /repos/{owner}/{repo}/pulls/{n}/ccr/comments/{comment_id}/resolve (or /unresolve), PUT or DELETE /repos/{owner}/{repo}/pulls/{n}/ccr/auto_merge, POST /repos/{owner}/{repo}/pulls/{n}/ccr/ready_for_review, POST /repos/{owner}/{repo}/pulls/{n}/ccr/convert_to_draft. (https://api.github.com/graphql)'
}

if ("$($args[0])" -eq 'api' -and "$($args[1])" -match '^repos/[^/]+/[^/]+/commits/([0-9a-fA-F]{7,40})/check-runs(?:\?(.*))?$') {
    $sha = $Matches[1]
    $query = "$($Matches[2])"
    foreach ($pr in @(Read-Json 'prs.json' @())) {
        if ("$($pr.reviewRequestedOid)".StartsWith($sha)) { Add-PushReview $pr }
    }
    $runs = @()
    $reviewed = @(Read-Json 'prs.json' @()) | Where-Object { "$($_.reviewedOid)" -and "$($_.reviewedOid)".StartsWith($sha) } | Select-Object -First 1
    if ($reviewed) {
        $runs = @(@{ id = 4001; name = 'Code review'; head_sha = "$($reviewed.reviewedOid)"; status = 'completed'; conclusion = 'success'; app = @{ slug = 'ncode-review' } })
    }
    if ($query -match '(?:^|&)check_name=([^&]*)') {
        $checkName = [uri]::UnescapeDataString($Matches[1])
        $runs = @($runs | Where-Object { $_.name -eq $checkName })
    }
    $jq = Get-Option '--jq'
    if (-not $jq -or $jq -match '^(\.[A-Za-z_]\w*)+$') {
        Write-Result @{ total_count = $runs.Count; check_runs = $runs }
        exit 0
    }
    if ($jq -match '^\[\.check_runs\[\] \| select\(\.app\.slug == "([^"]+)" and \.status == "completed"\)\] \| length$') {
        $slug = $Matches[1]
        "$(@($runs | Where-Object { $_.app.slug -eq $slug -and $_.status -eq 'completed' }).Count)"
        exit 0
    }
    Stop-Call UNSUPPORTED "gh stand-in: unsupported --jq for check runs: $jq"
}

# The REST reads: a GET (no method option, or -X GET) of a repository path.
$apiPath = Get-ApiPath
$restGet = "$($args[0])" -eq 'api' -and $apiPath -and (Get-ApiMethod) -eq 'GET'
if ($restGet -and $apiPath -match '^repos/[^/]+/[^/]+/pulls/(\d+)$') {
    $number = $Matches[1]
    $pr = Get-PullRequestRecord $number
    if (-not $pr) { Stop-Call NOTFOUND "gh stand-in: no pull request $number" }
    Write-Result @{
        number = $pr.number; title = $pr.title; body = $pr.body; html_url = $pr.url
        state = $(if ($pr.state -eq 'OPEN') { 'open' } else { 'closed' })
        merged = ($pr.state -eq 'MERGED'); draft = [bool]$pr.isDraft
        head = @{ ref = $pr.headRefName; sha = $pr.headRefOid; repo = @{ full_name = $(if ($pr.isCrossRepository) { 'someone/app' } else { 'fixture/app' }) } }
        base = @{ ref = $pr.baseRefName; repo = @{ full_name = 'fixture/app' } }
    }
    exit 0
}
if ($restGet -and $apiPath -match '^repos/[^/]+/[^/]+/pulls/(\d+)/ccr/review_threads$') {
    $number = $Matches[1]
    $pr = Get-PullRequestRecord $number
    if (-not $pr) { Stop-Call NOTFOUND "gh stand-in: no pull request $number" }
    Add-PushReview $pr
    $threads = @(@(Read-Json 'threads.json' @()) | Where-Object { "$($_.number)" -eq $number } | ForEach-Object {
        @{ resolved = [bool]$_.isResolved; outdated = [bool]$_.isOutdated; path = $_.path; line = $_.line; comment_ids = @(@($_.comments) | ForEach-Object { Get-RestId $_.url }) }
    })
    Write-Result $threads
    exit 0
}
if ($restGet -and $apiPath -match '^repos/[^/]+/[^/]+/pulls/(\d+)/comments(\?.*)?$') {
    $number = $Matches[1]
    $pr = Get-PullRequestRecord $number
    if (-not $pr) { Stop-Call NOTFOUND "gh stand-in: no pull request $number" }
    Add-PushReview $pr
    $all = @()
    foreach ($thread in @(Read-Json 'threads.json' @()) | Where-Object { "$($_.number)" -eq $number }) {
        $firstId = $null
        foreach ($c in @($thread.comments)) {
            $id = Get-RestId $c.url
            $all += @{
                id = $id; in_reply_to_id = $firstId; path = $thread.path; line = $thread.line
                user = (Get-RestUser $c.author); author_association = $c.authorAssociation; body = $c.body; html_url = $c.url
            }
            if ($null -eq $firstId) { $firstId = $id }
        }
    }
    Write-Result @(Get-Page $all)
    exit 0
}
if ($restGet -and $apiPath -match '^repos/[^/]+/[^/]+/pulls/(\d+)/reviews(\?.*)?$') {
    $number = $Matches[1]
    $pr = Get-PullRequestRecord $number
    if (-not $pr) { Stop-Call NOTFOUND "gh stand-in: no pull request $number" }
    Add-PushReview $pr
    $reviews = @(@(Read-Json 'reviews.json' @()) | Where-Object { "$($_.number)" -eq $number } | ForEach-Object {
        @{ id = (Get-RestId $_.url); user = (Get-RestUser $_.author); author_association = $_.authorAssociation; body = $_.body; html_url = $_.url; state = 'COMMENTED' }
    })
    Write-Result @(Get-Page $reviews)
    exit 0
}
if ($restGet -and $apiPath -match '^repos/[^/]+/[^/]+/pulls\?(.*)$') {
    $head = $null
    $state = 'all'
    foreach ($pair in "$($Matches[1])" -split '&') {
        if ($pair -match '^head=(.*)$') { $head = [uri]::UnescapeDataString($Matches[1]); $head = $head.Substring($head.IndexOf(':') + 1) }
        elseif ($pair -match '^state=(.+)$') { $state = [uri]::UnescapeDataString($Matches[1]) }
    }
    $found = @(@(Read-Json 'prs.json' @()) | Where-Object {
        (-not $head -or $_.headRefName -eq $head) -and
        ($state -eq 'all' -or ($state -eq 'open' -and $_.state -eq 'OPEN') -or ($state -eq 'closed' -and $_.state -in 'CLOSED', 'MERGED'))
    } | Sort-Object { [int]$_.number } -Descending | ForEach-Object {
        @{
            number = $_.number; title = $_.title; body = $_.body
            state = $(if ($_.state -eq 'OPEN') { 'open' } else { 'closed' })
            merged_at = $(if ($_.state -eq 'MERGED') { '2026-01-01T00:00:00Z' } else { $null })
            merge_commit_sha = $(if ($_.mergeCommit) { "$($_.mergeCommit.oid)" } else { $null })
            draft = [bool]$_.isDraft; html_url = $_.url
            head = @{ ref = $_.headRefName; sha = $_.headRefOid }; base = @{ ref = $_.baseRefName }
        }
    })
    Write-Result $found
    exit 0
}
if ($restGet -and $apiPath -match '^repos/[^/]+/[^/]+/issues/(\d+)$') {
    $number = $Matches[1]
    $issues = Read-Json 'issues.json' @{}
    if (-not $issues.ContainsKey($number)) { Stop-Call NOTFOUND "gh stand-in: no issue $number" }
    $issue = $issues[$number]
    Write-Result @{ number = [int]$number; title = $issue.title; body = $issue.body; state = "$($issue.state)".ToLowerInvariant(); labels = $issue.labels }
    exit 0
}
if ($restGet -and $apiPath -match '^repos/[^/]+/[^/]+/releases/tags/[^/]+$') {
    Stop-Call NOTFOUND 'gh stand-in: no release'
}

# The REST routes for top-level comments, thread replies and refusals.
if ("$($args[0])" -eq 'api' -and $apiPath -match '^repos/[^/]+/[^/]+/issues/(\d+)/comments(\?.*)?$') {
    $number = $Matches[1]
    $method = Get-ApiMethod
    if ($method -eq 'GET') {
        $listedPr = Get-PullRequestRecord $number
        if ($listedPr) { Add-PushReview $listedPr }
        $list = @(@(Read-Json 'comments.json' @()) | Where-Object { "$($_.number)" -eq $number } | ForEach-Object {
            @{ id = (Get-RestId $_.url); user = (Get-RestUser $_.author); author_association = $_.authorAssociation; body = $_.body; html_url = $_.url }
        })
        Write-Result @(Get-Page $list)
        exit 0
    }
    $sent = Get-Field 'body'
    if ($method -ne 'POST' -or $null -eq $sent) { Stop-Call UNSUPPORTED "gh stand-in: unsupported call: $($args -join ' ')" }
    $isPr = [bool](Get-PullRequestRecord $number)
    $kind = $(if ($isPr) { 'pr' } else { 'issue' })
    $url = Add-Comment $kind ([int]$number) $(if ($isPr) { 'pull' } else { 'issues' }) $sent
    $saved = @(Read-Json 'comments.json' @()) | Where-Object { $_.url -eq $url } | Select-Object -First 1
    if ($isPr) {
        # As the pr comment route does: only a comment exactly /review as saved asks for a review, and with footer.txt an Autopilot: comment naming /review stands for it.
        if ("$($saved.body)".Trim() -eq '/review') { Set-ReviewRequest ([int]$number) }
        elseif ((Test-Path -LiteralPath (Join-Path $hostDir 'footer.txt')) -and $sent -match '^\s*Autopilot:' -and $sent.Contains('/review')) { Set-ReviewRequest ([int]$number) }
    }
    Write-Result @{ id = (Get-RestId $url); html_url = $url; body = $saved.body; user = @{ login = 'fixture-owner'; type = 'User' } }
    exit 0
}
if ("$($args[0])" -eq 'api' -and $apiPath -match '^repos/[^/]+/[^/]+/pulls/(\d+)/comments/(\d+)/replies$') {
    $number = $Matches[1]
    $replyTo = [long]$Matches[2]
    if ((Get-ApiMethod) -ne 'POST') { Stop-Call UNSUPPORTED "gh stand-in: unsupported call: $($args -join ' ')" }
    $threads = @(Read-Json 'threads.json' @())
    $thread = $threads | Where-Object { "$($_.number)" -eq $number -and @($_.comments).Count -and (Get-RestId @($_.comments)[0].url) -eq $replyTo } | Select-Object -First 1
    if (-not $thread) { Stop-Call NOTFOUND "gh stand-in: no review comment $replyTo to reply to" }
    $sentBody = Get-Field 'body'
    if ($null -eq $sentBody) { Stop-Call UNSUPPORTED 'gh stand-in: a reply needs a body field' }
    $url = "https://github.com/fixture/app/pull/$($thread.number)#discussion_r$(Get-NextReviewCommentId)"
    $savedBody = Get-SavedBody "$sentBody"
    $thread.comments = @($thread.comments) + @(@{ author = @{ __typename = 'User'; login = 'fixture-owner' }; authorAssociation = 'OWNER'; body = $savedBody; url = $url })
    Write-Json 'threads.json' $threads
    Write-Result @{ id = (Get-RestId $url); html_url = $url; body = $savedBody; in_reply_to_id = $replyTo }
    exit 0
}
if ("$($args[0])" -eq 'api' -and $apiPath -match '^repos/[^/]+/[^/]+/pulls/(\d+)/ccr/(comments/\d+/(resolve|unresolve)|auto_merge|ready_for_review|convert_to_draft)$') {
    Stop-Call FORBIDDEN 'gh stand-in: resolving, auto-merge and draft changes are not allowed'
}
if ("$($args[0])" -eq 'api' -and $apiPath -match '^repos/[^/]+/[^/]+/pulls/(\d+)$' -and (Get-ApiMethod) -eq 'PATCH') {
    $forbiddenEdit = (Test-Path -LiteralPath $forbiddenFile) -and @([IO.File]::ReadAllLines($forbiddenFile) | Where-Object { $_.Trim() -eq 'pr edit' }).Count
    if ($forbiddenEdit) { Stop-Call FORBIDDEN 'gh stand-in: pr edit is not allowed in this test' }
    Stop-Call UNSUPPORTED "gh stand-in: unsupported call: $($args -join ' ')"
}

# A comment read back, edited or deleted by its id, as the commands do after posting one: a GET answers it, -X PATCH saves
# its body field as given, with no footer, and -X DELETE deletes it. Any other method, or an id it doesn't hold, is unsupported.
$commentPath = @($args | Select-Object -Skip 1 | Where-Object { "$_" -match '^/?repos/[^/]+/[^/]+/issues/comments/\d+$' }) | Select-Object -First 1
if ("$($args[0])" -eq 'api' -and $commentPath) {
    $commentId = "$commentPath".Split('/')[-1]
    $method = Get-ApiMethod
    $comments =@(Read-Json 'comments.json' @())
    $comment = $comments | Where-Object { "$($_.url)".EndsWith("#issuecomment-$commentId") } | Select-Object -First 1
    $newBody = Get-Field 'body'
    if (-not $comment -or $method -notin 'GET', 'PATCH', 'DELETE' -or ($method -eq 'PATCH' -and $null -eq $newBody)) { Stop-Call UNSUPPORTED "gh stand-in: unsupported call: $($args -join ' ')" }
    if ($method -eq 'DELETE') {
        if (Test-Path -LiteralPath (Join-Path $hostDir 'delete-fails.txt')) { Stop-Call REFUSED "gh stand-in: the delete of comment $commentId failed" }
        Write-Json 'comments.json' @($comments | Where-Object { -not "$($_.url)".EndsWith("#issuecomment-$commentId") })
        exit 0
    }
    if ($method -eq 'PATCH') {
        $comment.body = $newBody
        Write-Json 'comments.json' $comments
    }
    Write-Result @{ id = [long]$commentId; body = $comment.body; html_url = $comment.url; user = $comment.author }
    exit 0
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
        Add-Comment 'issue' $number 'issues' (Get-Body)
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
        Add-Comment 'pr' $number 'pull' (Get-Body)
        # NCode Review acts only on a comment that is exactly /review as it is saved, so one saved with a footer asks for no review.
        if ((Get-SavedBody (Get-Body)) -match '^\s*/review\s*\z') { Set-ReviewRequest $number }
        # With host/footer.txt, an Autopilot: comment that names /review stands for the /review the maintainer posts after it.
        elseif ((Test-Path -LiteralPath (Join-Path $hostDir 'footer.txt')) -and (Get-Body) -match '^\s*Autopilot:' -and (Get-Body).Contains('/review')) { Set-ReviewRequest $number }
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
            $url = "https://github.com/fixture/app/pull/$($thread.number)#discussion_r$(Get-NextReviewCommentId)"
            $thread.comments = @($thread.comments) + @(@{ author = @{ __typename = 'User'; login = 'fixture-owner' }; authorAssociation = 'OWNER'; body = (Get-SavedBody "$(Get-Field 'body')"); url = $url })
            Write-Json 'threads.json' $threads
            Write-Result @{ data = @{ addPullRequestReviewThreadReply = @{ comment = @{ url = $url } } } }
            exit 0
        }
        $number = Get-Field 'number'
        $pr = Get-PullRequestRecord $number
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
    default { Stop-Call UNSUPPORTED "gh stand-in: unsupported call: $($args -join ' ')" }
}
