<#
.SYNOPSIS
A stand-in for the GitHub CLI that the run-issues end-to-end test puts on PATH.

.DESCRIPTION
Run as `gh <args>`. It keeps its state in JSON files in the `host` folder beside it (`issues.json`, `prs.json`,
`comments.json`, optional `origin.txt`), logs each call to `host/calls.log`, and fails on calls it doesn't support
or that /run-issues must never make.
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
    'pr merge' { Stop-Call FORBIDDEN 'pr merge is not allowed in /run-issues' }
    'pr ready' { Stop-Call FORBIDDEN 'pr ready is not allowed in /run-issues' }
    default { Stop-Call UNSUPPORTED "gh stand-in: unsupported call: $($args -join ' ')" }
}
