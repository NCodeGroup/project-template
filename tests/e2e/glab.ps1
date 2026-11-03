<#
.SYNOPSIS
A stand-in for the GitLab CLI that the end-to-end tests put on PATH.

.DESCRIPTION
Run as `glab <args>`. It keeps its state in JSON files in the `host` folder beside it (`mrs.json` with the merge
requests, by `iid`; `discussions.json` with their discussions, each with an `id`, the `mr` it belongs to, `individual_note`
and its `notes`; `members.json` with the project members by user id; and an optional `footer.txt`), logs each call to
`host/calls.log`, and fails on calls it doesn't support (logged as UNSUPPORTED), that the workflow must never make (logged
as FORBIDDEN: merging, approving or closing a merge request, and resolving a discussion) or that name something it can't
find (logged as NOTFOUND). An optional `footer.txt` holds a footer it appends, after a blank line and a `---` line, to
each note it saves, as a Claude Code cloud session's tooling does.
`api projects/<project>/merge_requests/<n>/discussions` answers the discussions of a merge request, as one JSON array.
`api --method POST projects/<project>/merge_requests/<n>/notes` saves the `body` field as a new note in a new individual discussion and prints the note.
`api --method POST projects/<project>/merge_requests/<n>/discussions/<id>/notes` saves the `body` field as a reply in that discussion and prints the note.
`api projects/<project>/merge_requests/<n>/notes/<id>` (or `.../discussions/<id>/notes/<id>`) answers a note by its id, as the commands read a post back after making it.
With `--method PUT` it saves the `body` field as given, with no footer, and with `--method DELETE` it deletes the note, and its discussion when no note is left; the id of a note it has given is never given again (`last-note-id.txt`).
`api projects/<project>/members/all/<id>` answers a project member of `members.json` by user id.
Any `resolved` field, or a PUT to a discussion, is refused as FORBIDDEN, and any other route under `projects/` as UNSUPPORTED.
It reads the method as glab does, from --method POST, --method=POST, -X POST or -XPOST, and takes a call with -f, -F, --field, --raw-field or --input and no method as a POST.
`--paginate`, a `?query` on the path and the other flags of `glab api` are ignored.
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
function Stop-Call([string]$Kind, [string]$Message, $CallArgs = $script:CallArgs) {
    [IO.File]::AppendAllText($callsLog, "$Kind $($CallArgs -join ' ')`n")
    [Console]::Error.WriteLine($Message)
    exit 1
}
# The body a comment or a thread reply is saved with: with host/footer.txt, the body sent, a blank line, a --- line and
# that footer, as a Claude Code cloud session's tooling appends one to what it posts.
function Get-SavedBody([string]$Body) {
    $footerFile = Join-Path $hostDir 'footer.txt'
    if (-not (Test-Path -LiteralPath $footerFile)) { return $Body }
    return $Body.TrimEnd() + "`n`n---`n" + ([IO.File]::ReadAllText($footerFile)).Trim()
}

if ("$($args[0])" -eq '--version') { 'glab 1.99.0 (stand-in)'; exit 0 }

# The merge request a command names by its number, as `!1` or `1`; none is a NOTFOUND.
function Get-MergeRequest($Mrs, [string]$Number) {
    $mr = @($Mrs) | Where-Object { "$($_.iid)" -eq $Number } | Select-Object -First 1
    if (-not $mr) { Stop-Call NOTFOUND "glab stand-in: no merge request $Number" }
    return $mr
}

# The id a new note gets: one more than any id given so far, which host/last-note-id.txt keeps, so a deleted note's id is
# never given again. The first is 5000.
function Get-NextNoteId($Discussions) {
    $idFile = Join-Path $hostDir 'last-note-id.txt'
    $id = 4999
    if (Test-Path -LiteralPath $idFile) { $id = [long]([IO.File]::ReadAllText($idFile)).Trim() }
    foreach ($d in @($Discussions)) { foreach ($n in @($d.notes)) { if ([long]$n.id -gt $id -and [long]$n.id -ge 5000) { $id = [long]$n.id } } }
    $id++
    [IO.File]::WriteAllText($idFile, "$id")
    return $id
}
# A new note by the fixture owner with the body the call sent, saved with the footer if there is one.
function New-Note([long]$Id, [bool]$Resolvable) {
    $body = Get-Field 'body'
    if ($null -eq $body) { Stop-Call UNSUPPORTED 'glab stand-in: a note needs a body field' }
    return @{ id = $Id; body = (Get-SavedBody $body); author = @{ id = 1; username = 'fixture-owner' }; system = $false; resolvable = $Resolvable; resolved = $false }
}

# The api routes: a merge request's discussions, notes (a note read back, edited or deleted by its id, as the commands do
# after posting one) and the project members. Resolving, in any form, is refused; `api user` is left to the switch below.
$path = @($args | Select-Object -Skip 1 | Where-Object { "$_" -match '^(projects/|user$)' }) | Select-Object -First 1
if ("$($args[0])" -eq 'api' -and $path -and "$path" -ne 'user') {
    $route = "$path".Split('?')[0]
    $method = "$(Get-Option '--method', '-X')".ToUpperInvariant()
    # As glab does, a method can be attached to -X, as in -XPOST, and a call with fields or --input and no method is a POST.
    $attachedMethod = @($args | Where-Object { "$_" -cmatch '^-X[A-Za-z]+$' }) | Select-Object -First 1
    if (-not $method -and $attachedMethod) { $method = "$attachedMethod".Substring(2).ToUpperInvariant() }
    if (-not $method -and @($args | Where-Object { "$_" -in '-f', '-F', '--field', '--raw-field', '--input' -or "$_" -match '^--(field|raw-field|input)=' }).Count) { $method = 'POST' }
    if (-not $method) { $method = 'GET' }
    if ($null -ne (Get-Field 'resolved')) { Stop-Call FORBIDDEN 'glab stand-in: resolving is not allowed' }
    if ($route -match '^projects/[^/]+/merge_requests/(\d+)/discussions$' -and $method -eq 'GET') {
        $number = $Matches[1]
        $found = @(@(Read-Json 'discussions.json' @()) | Where-Object { "$($_.mr)" -eq $number } | ForEach-Object {
            $copy = @{} + $_
            $copy.Remove('mr')
            $copy
        })
        ConvertTo-Json -InputObject $found -Depth 10
        exit 0
    }
    if ($route -match '^projects/[^/]+/merge_requests/(\d+)/notes$' -and $method -eq 'POST') {
        $number = $Matches[1]
        $discussions = @(Read-Json 'discussions.json' @())
        $note = New-Note (Get-NextNoteId $discussions) $false
        $discussions += @{ id = "d$($note.id)"; mr = [int]$number; individual_note = $true; notes = @($note) }
        Write-Json 'discussions.json' $discussions
        ConvertTo-Json -InputObject $note -Depth 10
        exit 0
    }
    if ($route -match '^projects/[^/]+/merge_requests/(\d+)/discussions/([^/]+)/notes$' -and $method -eq 'POST') {
        $number = $Matches[1]
        $discussionId = $Matches[2]
        $discussions = @(Read-Json 'discussions.json' @())
        $discussion = $discussions | Where-Object { "$($_.mr)" -eq $number -and "$($_.id)" -eq $discussionId } | Select-Object -First 1
        if (-not $discussion) { Stop-Call NOTFOUND "glab stand-in: no discussion $discussionId on merge request $number" }
        $note = New-Note (Get-NextNoteId $discussions) $true
        $discussion.notes = @($discussion.notes) + $note
        Write-Json 'discussions.json' $discussions
        ConvertTo-Json -InputObject $note -Depth 10
        exit 0
    }
    if ($route -match '^projects/[^/]+/merge_requests/(\d+)/(?:discussions/([^/]+)/)?notes/(\d+)$') {
        $number = $Matches[1]
        $discussionId = $Matches[2]
        $noteId = $Matches[3]
        $discussions = @(Read-Json 'discussions.json' @())
        $discussion = $discussions | Where-Object { "$($_.mr)" -eq $number -and (-not $discussionId -or "$($_.id)" -eq $discussionId) -and @($_.notes | Where-Object { "$($_.id)" -eq $noteId }).Count } | Select-Object -First 1
        if (-not $discussion) { Stop-Call NOTFOUND "glab stand-in: no note $noteId on merge request $number" }
        $note = @($discussion.notes) | Where-Object { "$($_.id)" -eq $noteId } | Select-Object -First 1
        if ($method -eq 'GET') {
            ConvertTo-Json -InputObject $note -Depth 10
            exit 0
        }
        if ($method -eq 'PUT') {
            $newBody = Get-Field 'body'
            if ($null -eq $newBody) { Stop-Call UNSUPPORTED "glab stand-in: unsupported call: $($args -join ' ')" }
            $note.body = $newBody
            Write-Json 'discussions.json' $discussions
            ConvertTo-Json -InputObject $note -Depth 10
            exit 0
        }
        if ($method -eq 'DELETE') {
            $discussion.notes = @(@($discussion.notes) | Where-Object { "$($_.id)" -ne $noteId })
            if (-not @($discussion.notes).Count) { $discussions = @($discussions | Where-Object { "$($_.id)" -ne "$($discussion.id)" -or "$($_.mr)" -ne $number }) }
            Write-Json 'discussions.json' $discussions
            exit 0
        }
        Stop-Call UNSUPPORTED "glab stand-in: unsupported call: $($args -join ' ')"
    }
    if ($route -match '^projects/[^/]+/merge_requests/(\d+)/discussions/([^/]+)$' -and $method -eq 'PUT') { Stop-Call FORBIDDEN 'glab stand-in: resolving is not allowed' }
    if ($route -match '^projects/[^/]+/members/all/(\d+)$' -and $method -eq 'GET') {
        $member = (Read-Json 'members.json' @{})
        $entry = $null
        if ($member -is [hashtable]) { if ($member.ContainsKey($Matches[1])) { $entry = $member[$Matches[1]] } }
        else { $entry = @($member) | Where-Object { "$($_.id)" -eq $Matches[1] } | Select-Object -First 1 }
        if (-not $entry) { Stop-Call NOTFOUND "glab stand-in: no member $($Matches[1])" }
        ConvertTo-Json -InputObject $entry -Depth 10
        exit 0
    }
    Stop-Call UNSUPPORTED "glab stand-in: unsupported call: $($args -join ' ')"
}
switch ("$($args[0]) $($args[1])") {
    'auth status' { 'Logged in to gitlab.com as fixture-owner (stand-in)'; exit 0 }
    'api user' { ConvertTo-Json @{ id = 1; username = 'fixture-owner' }; exit 0 }
    'mr view' {
        $number = "$($args[2])".TrimStart('!')
        $mr = Get-MergeRequest @(Read-Json 'mrs.json' @()) $number
        ConvertTo-Json -InputObject $mr -Depth 10
        exit 0
    }
    'mr list' {
        $branch = Get-Option '--source-branch'
        $found = @(@(Read-Json 'mrs.json' @()) | Where-Object { -not $branch -or $_.source_branch -eq $branch })
        ConvertTo-Json -InputObject $found -Depth 10
        exit 0
    }
    'mr update' {
        $number = "$($args[2])".TrimStart('!')
        # Only the description is editable; any other flag, such as --ready, --draft or --squash-before-merge, is refused.
        $list = @($args)
        for ($i = 3; $i -lt $list.Count; $i++) {
            $arg = "$($list[$i])"
            if ($arg -in '--description', '-d') { $i++; continue }
            if ($arg.StartsWith('--description=')) { continue }
            if ($arg.StartsWith('-')) { Stop-Call FORBIDDEN "glab stand-in: mr update $arg is not allowed" }
        }
        $mrs = @(Read-Json 'mrs.json' @())
        $mr = Get-MergeRequest $mrs $number
        $description = Get-Option '--description', '-d'
        if ($null -ne $description) {
            $mr.description = $description
            Write-Json 'mrs.json' $mrs
        }
        "$($mr.web_url)"
        exit 0
    }
    'mr merge' { Stop-Call FORBIDDEN "glab stand-in: mr $($args[1]) is not allowed" }
    'mr approve' { Stop-Call FORBIDDEN "glab stand-in: mr $($args[1]) is not allowed" }
    'mr close' { Stop-Call FORBIDDEN "glab stand-in: mr $($args[1]) is not allowed" }
    default { Stop-Call UNSUPPORTED "glab stand-in: unsupported call: $($args -join ' ')" }
}
