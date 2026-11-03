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

# The api routes follow.
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
