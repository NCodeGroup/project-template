<#
.SYNOPSIS
    Dismisses, as won't fix with a standard comment, the open Scorecard code-scanning alerts that one person with write
    access can't clear in an NCodeGroup repository.

.DESCRIPTION
    Scorecard's Branch-Protection, CII-Best-Practices and Contributors checks score below 10 for a project one person
    maintains: where one person has write access, the ruleset can require no approval but the one NCode Review's
    approver gives, of the last push, where it is set up, while tier 4 of Branch-Protection needs two, silver and gold
    Best Practices badges need a second person, and Contributors needs recent contributors from at least 3 companies.
    The script reads the repository's open Scorecard alerts (repos/<owner>/<name>/code-scanning/alerts) and dismisses
    the alerts of those three checks as won't fix, each with the standard comment that says why and names the
    template's decision records (ADR-0034 and ADR-0036 for Branch-Protection, ADR-0035 for the other two). An alert
    of any other check is left open, as the project can clear it: Code-Review and Maintained reach 10 with one person.

    It counts who has write access first, as the users the collaborators list
    (repos/<owner>/<name>/collaborators?affiliation=all&permission=push) gives. With two or more it dismisses nothing,
    since a second person can clear these checks, and exits 0. A list it can't read, or open alerts it can't read, make
    it say so, with gh's reason, and exit 1 with nothing dismissed. It lists every alert and what it would do before it
    dismisses any, and -WhatIf stops there. A dismissal that gh refuses is named and counted, the others still go
    ahead, and the exit code is 1.

    A dismissed alert is an accepted one, not a fixed one: /best-practices reports it as accepted. The script needs an
    account with the security_events scope and write access to the repository. Run it from a project-template clone,
    where the baseline script is.

.EXAMPLE
    .\tools\Dismiss-ScorecardAlerts.ps1 -Repo NCodeGroup/PropertyBag -WhatIf     # lists what it would dismiss
    .\tools\Dismiss-ScorecardAlerts.ps1 -Repo NCodeGroup/PropertyBag
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # The repository, as <owner>/<repository>.
    [Parameter(Mandatory)][string]$Repo
)
$ErrorActionPreference = 'Stop'
if ($Repo -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$') {
    throw '-Repo takes <owner>/<repository>, such as NCodeGroup/PropertyBag.'
}

$reasons = [ordered]@{
    'Branch-Protection'  = "One person has write access, and GitHub counts no approval from the author, so the ruleset can require only the one approval, of the last push, that NCode Review's approver gives where it is set up, and none elsewhere (project-template ADR-0034 and ADR-0036)."
    'CII-Best-Practices' = "One person maintains the project. Silver needs a second owner, and gold needs two-person review and a bus factor of 2, so one person reaches passing at most and the check stays below 10 (project-template ADR-0035)."
    'Contributors'       = "One person maintains the project. The check scores 10 only with recent contributors from at least 3 companies, each with 5 of the last 30 commits, which one person can't meet (project-template ADR-0035)."
}

# Reads every page of a gh api list. Reason holds gh's error text, or its exit code, when the read fails.
function Read-GhPages([string]$Path) {
    $ErrorActionPreference = 'Continue'
    $errors = [Collections.Generic.List[string]]::new()
    $out = & gh api --paginate --slurp $Path 2>&1 | ForEach-Object {
        if ($_ -is [Management.Automation.ErrorRecord]) { $errors.Add("$_".Trim()) } else { $_ }
    }
    $code = $LASTEXITCODE
    $failed = [bool]$code
    $items = @()
    if (-not $failed) {
        $items = @(($out | Out-String | ConvertFrom-Json) | ForEach-Object { $_ } | Where-Object { $_ })
    }
    $reason = if (-not $failed) { $null }
    elseif (@($errors | Where-Object { $_ }).Count) { (@($errors | Where-Object { $_ }) -join ' ') }
    else { "gh exited $code" }
    [pscustomobject]@{ Failed = $failed; Items = $items; Reason = $reason }
}

$writers = Read-GhPages "repos/$Repo/collaborators?affiliation=all&permission=push&per_page=100"
if ($writers.Failed) {
    Write-Host "${Repo}: couldn't read who has write access ($($writers.Reason)), so nothing is dismissed"
    exit 1
}
$count = @($writers.Items | Where-Object { $_.type -eq 'User' }).Count
if ($count -ge 2) {
    Write-Host "${Repo}: $count people have write access, so a second person can clear these checks (the template's ADR-0035): nothing to dismiss"
    exit 0
}

$alerts = Read-GhPages "repos/$Repo/code-scanning/alerts?tool_name=Scorecard&state=open&per_page=100"
if ($alerts.Failed) {
    Write-Host "${Repo}: couldn't read its open Scorecard alerts ($($alerts.Reason)), so nothing is dismissed"
    exit 1
}
if (-not $alerts.Items.Count) {
    Write-Host "${Repo}: no open Scorecard alert"
    exit 0
}

$sorted = @($alerts.Items | Sort-Object { [int]$_.number })
$toDismiss = @()
foreach ($alert in $sorted) {
    $check = "$($alert.rule.name)"
    if ($reasons.Contains($check)) {
        Write-Host "${Repo}: alert #$($alert.number) ($check): dismiss as won't fix: $($reasons[$check])"
        $toDismiss += $alert
    }
    else {
        Write-Host "${Repo}: alert #$($alert.number) ($check): left open, since the project can clear it"
    }
}

$failures = 0
foreach ($alert in $toDismiss) {
    $number = $alert.number
    $check = "$($alert.rule.name)"
    if (-not $PSCmdlet.ShouldProcess("$Repo alert #$number", "dismiss $check as won't fix")) {
        Write-Host "${Repo}: alert #$number ($check): would dismiss"
        continue
    }
    & gh api -X PATCH "repos/$Repo/code-scanning/alerts/$number" -f state=dismissed -f "dismissed_reason=won't fix" -f "dismissed_comment=$($reasons[$check])" | Out-Null
    if ($LASTEXITCODE) {
        Write-Host "${Repo}: alert #$number ($check): not dismissed (gh api failed)"
        $failures++
    }
    else {
        Write-Host "${Repo}: alert #$number ($check): dismissed"
    }
}
if ($failures) { exit 1 }
exit 0
