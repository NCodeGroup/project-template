<#
.SYNOPSIS
    Test that tools\Dismiss-ScorecardAlerts.ps1 dismisses the Scorecard alerts one person can't clear, and only those.

.DESCRIPTION
    Runs the script against a stand-in for gh that serves canned repositories (who has write access, and their open
    Scorecard alerts) and records every call. Checks that, for a repository with one person with write access (and a
    bot, which isn't counted), -WhatIf makes no PATCH, lists every alert, and says would dismiss for the
    Branch-Protection, CII-Best-Practices and Contributors alerts only; that a run makes exactly three PATCH calls, for
    those alerts in order, each with the state, the won't fix reason and its check's comment of at most 280
    characters, after listing every alert; that a repository with two people with write access is left alone; that a
    list of writers or of alerts that can't be read exits 1 without a PATCH, giving gh's reason; that a repository with
    no open alert says so; that an alert gh refuses to dismiss is named and counted while the others are still
    dismissed; and that a -Repo that isn't <owner>/<repository> fails without a call.
    Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-scorecard-alerts-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-ScorecardAlerts.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-scorecard-alerts-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Write-Text([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n")) }

if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$bin = Join-Path $Work 'bin'
New-Item -ItemType Directory -Force $bin | Out-Null

# The stand-in for gh. It serves data.json (repos.<name>.writers: the logins with write access, bot:<login> for a Bot,
# or fail:<status>;
# .alerts: the open alerts, or fail:<status>; .patchFails: the alert numbers whose dismissal it refuses) and records
# every call in calls.log.
Write-Text (Join-Path $bin 'gh.ps1') @'
# The script runs this in its own session, so a -WhatIf run would reach it as $WhatIfPreference, and its log would stay
# empty: it has to record the calls of a -WhatIf run too, to show that they change nothing.
$WhatIfPreference = $false
Add-Content -LiteralPath (Join-Path $PSScriptRoot 'calls.log') -Value ($args -join ' ')
$data = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'data.json') | ConvertFrom-Json -AsHashtable
if ($args[0] -ne 'api') { exit 1 }
$path = @($args | Where-Object { $_ -is [string] -and $_ -match '^repos/' })[0]
if ($args -contains 'PATCH') {
    if ($path -notmatch '^repos/[^/]+/(?<name>[^/]+)/code-scanning/alerts/(?<number>\d+)$') { exit 1 }
    $repo = $data.repos[$Matches.name]
    if ($repo -and @($repo.patchFails) -contains [int]$Matches.number) { exit 1 }
    '{}'
    exit 0
}
if ($args -contains '--paginate' -and $path -match '^repos/[^/]+/(?<name>[^/]+)/(?<what>collaborators|code-scanning/alerts)\?') {
    $repo = $data.repos[$Matches.name]
    if (-not $repo) { exit 1 }
    $items = if ($Matches.what -eq 'collaborators') { $repo.writers } else { $repo.alerts }
    if ($items -is [string] -and $items.StartsWith('fail:')) { Write-Error -Message "gh: Stand-in refused (HTTP $($items.Substring(5)))" -ErrorAction Continue; exit 1 }
    if ($Matches.what -eq 'collaborators') { $items = @($items | ForEach-Object { if ($_.StartsWith('bot:')) { @{ login = $_.Substring(4); type = 'Bot' } } else { @{ login = $_; type = 'User' } } }) }
    ConvertTo-Json -Compress -Depth 6 -InputObject @(, @($items))
    exit 0
}
exit 1
'@

$alerts = @(
    @{ number = 8; rule = @{ name = 'Branch-Protection' } }
    @{ number = 11; rule = @{ name = 'Pinned-Dependencies' } }
    @{ number = 13; rule = @{ name = 'Code-Review' } }
    @{ number = 14; rule = @{ name = 'CII-Best-Practices' } }
    @{ number = 15; rule = @{ name = 'Contributors' } }
    @{ number = 16; rule = @{ name = 'Maintained' } }
)
Write-Text (Join-Path $bin 'data.json') (ConvertTo-Json -Depth 6 -InputObject @{
    repos = @{
        sole = @{ writers = @('maintainer', 'bot:release-app'); alerts = $alerts }
        two = @{ writers = @('maintainer', 'colleague'); alerts = $alerts }
        writersUnreadable = @{ writers = 'fail:403'; alerts = $alerts }
        alertsUnreadable = @{ writers = @('maintainer'); alerts = 'fail:404' }
        none = @{ writers = @('maintainer'); alerts = @() }
        refused = @{ writers = @('maintainer'); alerts = $alerts; patchFails = @(14) }
    }
})

# The comments the script gives each check, from the decision records (each under GitHub's 280 characters).
$comments = @{
    'Branch-Protection' = 'One person has write access, and GitHub counts no approval from the author, so the ruleset ' +
        'can require only the one approval, of the last push, that NCode Review''s approver gives where it is set up, ' +
        'and none elsewhere (project-template ADR-0034 and ADR-0036).'
    'CII-Best-Practices' = 'One person maintains the project. Silver needs a second owner, and gold needs two-person ' +
        'review and a bus factor of 2, so one person reaches passing at most and the check stays below 10 ' +
        '(project-template ADR-0035).'
    'Contributors' = 'One person maintains the project. The check scores 10 only with recent contributors from at ' +
        'least 3 companies, each with 5 of the last 30 commits, which one person can''t meet (project-template ADR-0035).'
}

$script = Join-Path $repoRoot 'tools/Dismiss-ScorecardAlerts.ps1'
$calls = Join-Path $bin 'calls.log'
# A run: its output lines and exit code, every call the stand-in got, and the PATCH calls, in order.
function Invoke-Dismiss([string[]]$Arguments) {
    if (Test-Path -LiteralPath $calls) { Remove-Item -LiteralPath $calls -Force }
    Push-Location $Work
    try {
        $output = & pwsh -NoProfile -File $script @Arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    }
    finally { Pop-Location }
    $log = if (Test-Path -LiteralPath $calls) { @(Get-Content -LiteralPath $calls) } else { @() }
    [pscustomobject]@{
        Output = $output
        Lines = @($output -split '\r?\n' | Where-Object { $_ })
        ExitCode = $exitCode
        Log = $log
        Patches = @($log | Where-Object { $_ -like '*-X PATCH*' })
    }
}
function Test-Line([object]$Run, [string]$Pattern) { [bool]($Run.Output -match $Pattern) }

$savedPath = $env:PATH
$env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
try {
    # 1. One writer, -WhatIf.
    $r = Invoke-Dismiss @('-Repo', 'NCodeGroup/sole', '-WhatIf')
    Check 'whatif: makes no PATCH and exits 0' ($r.ExitCode -eq 0 -and $r.Patches.Count -eq 0) "patches=$($r.Patches -join '|') exit=$($r.ExitCode) output=$($r.Output)"
    Check 'whatif: lists what it would dismiss and what it leaves open' ((Test-Line $r ([regex]::Escape('#8 (Branch-Protection): dismiss as won''t fix'))) -and (Test-Line $r ([regex]::Escape('#11 (Pinned-Dependencies): left open')))) $r.Output
    Check 'whatif: says would dismiss for 8, 14 and 15 only' ((Test-Line $r '#8 \(Branch-Protection\): would dismiss') -and (Test-Line $r '#14 \(CII-Best-Practices\): would dismiss') -and (Test-Line $r '#15 \(Contributors\): would dismiss') -and @($r.Lines | Where-Object { $_ -match 'would dismiss' }).Count -eq 3) $r.Output

    # 2. One writer.
    $r = Invoke-Dismiss @('-Repo', 'NCodeGroup/sole')
    $numbers = @($r.Patches | ForEach-Object { if ($_ -match 'alerts/(\d+) ') { [int]$Matches[1] } })
    Check 'dismiss: three PATCH calls, for 8, 14 and 15 in that order' ($r.ExitCode -eq 0 -and $numbers.Count -eq 3 -and ($numbers -join ',') -eq '8,14,15') "exit=$($r.ExitCode) patches=$($r.Patches -join '|')"
    $checks = @{ 8 = 'Branch-Protection'; 14 = 'CII-Best-Practices'; 15 = 'Contributors' }
    $fieldsOk = $r.Patches.Count -eq 3
    $lengthsOk = $true
    foreach ($patch in $r.Patches) {
        if ($patch -notmatch 'alerts/(?<n>\d+) ') { $fieldsOk = $false; continue }
        $comment = $comments[$checks[[int]$Matches.n]]
        if (-not ($patch -like '* -f state=dismissed *' -and $patch -like '* -f dismissed_reason=won''t fix *' -and $patch.EndsWith(" -f dismissed_comment=$comment"))) { $fieldsOk = $false }
        if ($comment.Length -gt 280) { $lengthsOk = $false }
    }
    Check 'dismiss: each PATCH sets state, reason and its check''s comment' $fieldsOk ($r.Patches -join '|')
    Check 'dismiss: every comment is at most 280 characters' ($lengthsOk -and $comments.Count -eq 3) ''
    $lastListing = -1; $firstDismissed = -1
    for ($i = 0; $i -lt $r.Lines.Count; $i++) {
        if ($r.Lines[$i] -match "dismiss as won't fix|left open") { $lastListing = $i }
        if ($firstDismissed -lt 0 -and $r.Lines[$i] -match '\): dismissed\s*$') { $firstDismissed = $i }
    }
    Check 'dismiss: every alert is listed before the first is dismissed' ($lastListing -ge 0 -and $firstDismissed -gt $lastListing -and @($r.Lines | Where-Object { $_ -match '\): dismissed\s*$' }).Count -eq 3) $r.Output
    Check 'dismiss: a bot with write access is not counted, so one person and a bot are one writer' ($r.Patches.Count -eq 3 -and -not (Test-Line $r 'people have write access')) $r.Output

    # 3. Two writers.
    $r = Invoke-Dismiss @('-Repo', 'NCodeGroup/two')
    Check 'two writers: nothing is dismissed and the run says so' ($r.ExitCode -eq 0 -and $r.Patches.Count -eq 0 -and (Test-Line $r ([regex]::Escape('2 people have write access')))) "exit=$($r.ExitCode) output=$($r.Output)"

    # 4. A list that can't be read.
    $r = Invoke-Dismiss @('-Repo', 'NCodeGroup/writersUnreadable')
    Check 'writers unreadable: exits 1 without a PATCH, and says why' ($r.ExitCode -eq 1 -and $r.Patches.Count -eq 0 -and (Test-Line $r ([regex]::Escape('(gh: Stand-in refused (HTTP 403))')))) "exit=$($r.ExitCode) output=$($r.Output)"
    $r = Invoke-Dismiss @('-Repo', 'NCodeGroup/alertsUnreadable')
    Check 'alerts unreadable: exits 1 without a PATCH, and says why' ($r.ExitCode -eq 1 -and $r.Patches.Count -eq 0 -and (Test-Line $r ([regex]::Escape('(gh: Stand-in refused (HTTP 404))')))) "exit=$($r.ExitCode) output=$($r.Output)"

    # 5. No open alert.
    $r = Invoke-Dismiss @('-Repo', 'NCodeGroup/none')
    Check 'none: exits 0 and says there is no open Scorecard alert' ($r.ExitCode -eq 0 -and $r.Patches.Count -eq 0 -and (Test-Line $r ([regex]::Escape('no open Scorecard alert')))) "exit=$($r.ExitCode) output=$($r.Output)"

    # 6. A dismissal gh refuses.
    $r = Invoke-Dismiss @('-Repo', 'NCodeGroup/refused')
    $numbers = @($r.Patches | ForEach-Object { if ($_ -match 'alerts/(\d+) ') { [int]$Matches[1] } })
    Check 'refused: exits 1 and names the alert that was not dismissed' ($r.ExitCode -eq 1 -and (Test-Line $r ([regex]::Escape('#14 (CII-Best-Practices): not dismissed')))) "exit=$($r.ExitCode) output=$($r.Output)"
    Check 'refused: still dismisses 8 and 15' (($numbers -join ',') -eq '8,14,15' -and (Test-Line $r '#8 \(Branch-Protection\): dismissed') -and (Test-Line $r '#15 \(Contributors\): dismissed')) $r.Output

    # 7. A -Repo that isn't <owner>/<repository>.
    $r = Invoke-Dismiss @('-Repo', 'PropertyBag')
    Check 'repo: a name without an owner fails without a call' ($r.ExitCode -ne 0 -and $r.Log.Count -eq 0 -and (Test-Line $r ([regex]::Escape('-Repo takes <owner>/<repository>')))) "exit=$($r.ExitCode) calls=$($r.Log -join '|') output=$($r.Output)"
}
finally { $env:PATH = $savedPath }

''
if ($failures.Count) { "Kept the work folder: $Work"; "Scorecard alert helper tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Scorecard alert helper tests: PASSED'
exit 0
