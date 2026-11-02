<#
.SYNOPSIS
    Gives a GitLab project the baseline merge protection: no merge request merges past an unresolved thread or without a
    passing pipeline.

.DESCRIPTION
    For one GitLab project it turns on two settings, each where it is off:
      - "All threads must be resolved" (only_allow_merge_if_all_discussions_are_resolved), so a review finding from the
        bot or a person can't be merged past;
      - "Pipelines must succeed" (only_allow_merge_if_pipeline_succeeds), so a merge request whose pipeline failed can't
        merge. It also blocks a merge request that has no pipeline at all. The template's .gitlab-ci.yml runs a pipeline
        on every merge request, with the always-on "Commit attribution" job, so a project made from the template always
        has one; a project whose CI runs none can't merge until it does.

    These are the settings that play, on GitLab, the part the "Protect main" ruleset's conversation resolution and
    required checks play on GitHub (see Set-RepositoryBaseline.ps1). Both are on GitLab Free. Protecting the default
    branch's push access and forbidding squash merges are not done here.

    Each setting is read first, from the project, and printed as set, already set, would set (-WhatIf) or not available,
    with the reason, one line each: <project>: <setting>: <outcome>. A setting the API refuses to change is reported, and
    the run goes on with the next one. A project the script can't read (no response, not found, or an answer that isn't
    a project) fails the run with an error, and an archived project is skipped.

    Name the project with -Project <group/subgroup/name>, and -Hostname for a GitLab other than gitlab.com, or point
    -Path at a clone (the current folder by default), whose origin remote gives both. It needs glab, signed in to the
    GitLab, and a token that can edit the project. New-Project.ps1 runs it for a GitLab project it creates;
    Adopt-Project.ps1 prints the command to run.

.EXAMPLE
    .\tools\Set-GitLabBaseline.ps1 -Project bixbots/qso-viewer -WhatIf     # shows each setting's state
    .\tools\Set-GitLabBaseline.ps1 -Project tools/qso-viewer -Hostname gitlab.example.com
    .\tools\Set-GitLabBaseline.ps1 -Path C:\src\qso-viewer
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # The project's full path on the GitLab: group/name, or group/subgroup/name.
    [string]$Project,
    # The GitLab's host name. With -Path, the origin remote's host unless this is given; otherwise gitlab.com.
    [string]$Hostname,
    # A clone of the project, whose origin remote names the project and the host. Not with -Project.
    [string]$Path = '.'
)
$ErrorActionPreference = 'Stop'
if ($Project -and $PSBoundParameters.ContainsKey('Path')) { throw 'Pass -Project or -Path, not both.' }
if (-not $Project) {
    $origin = "$(git -C $Path remote get-url origin 2>$null)"
    if ($origin -notmatch '^(?:(?:https?|ssh)://)?(?:[^@/]+@)?(?<host>[\w.-]+\.[\w-]+)(?::\d+)?[:/](?<path>[\w.-]+(?:/[\w.-]+?)+?)(?:\.git)?/?$') {
        throw "Couldn't tell the GitLab project from the origin remote of ${Path}: pass -Project <group/name>, and -Hostname for a GitLab other than gitlab.com."
    }
    $Project = $Matches.path
    if (-not $Hostname) { $Hostname = $Matches.host }
}
if (-not $Hostname) { $Hostname = 'gitlab.com' }
$endpoint = "projects/$([uri]::EscapeDataString($Project))"

# Calls the GitLab's API through glab and returns the HTTP status and the body. The status comes from the response's own
# status line (--include), never from the CLI's wording, and stderr stays out of the body, so a warning can't spoil the
# JSON; its first line is kept as the reason for a call with no status. A call that got no response at all (no network, no login) has no status. Every call names the host, so it never
# depends on the folder glab runs in.
function Invoke-Glab([string]$Method, [string]$Endpoint, [string[]]$Fields = @()) {
    $fieldArgs = @(foreach ($f in $Fields) { '-F'; $f })
    $all = @(& glab api --hostname $Hostname --method $Method --include $Endpoint @fieldArgs 2>&1)
    $lines = @($all | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    $errorLine = @($all | Where-Object { $_ -is [Management.Automation.ErrorRecord] } | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) | Select-Object -First 1
    $status = $null
    if ($lines.Count -and $lines[0] -match '^HTTP/\S+\s+(\d{3})\b') { $status = [int]$Matches[1] }
    $blank = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if (-not $lines[$i].Trim()) { $blank = $i; break } }
    $body = if ($blank -ge 0 -and $blank -lt $lines.Count - 1) { $lines[($blank + 1)..($lines.Count - 1)] -join "`n" } else { '' }
    [pscustomobject]@{ Status = $status; Body = $body; Error = "$errorLine" }
}

# Why a call failed, for the line that reports it: the status and, when the answer has one, the API's message.
function Get-FailureReason($Response) {
    if ($null -eq $Response.Status) { return $(if ($Response.Error) { "no response: $($Response.Error)" } else { 'no response' }) }
    $message = try { "$(($Response.Body | ConvertFrom-Json -ErrorAction Stop).message)" } catch { '' }
    "HTTP $($Response.Status)$(if ($message) { ": $message" })"
}

$read = Invoke-Glab GET $endpoint
$info = $null
$why = ''
if ($read.Status -eq 200) {
    try { $info = $read.Body | ConvertFrom-Json -ErrorAction Stop } catch { $why = 'an answer that is not JSON' }
    if (-not $why -and $info -isnot [Management.Automation.PSCustomObject]) { $why = 'an answer that is not a project' }
}
else { $why = Get-FailureReason $read }
if ($why) { throw "Couldn't read GitLab project $Project on ${Hostname}: $why." }
if ($info.archived) { Write-Host "${Project}: skipped (archived)"; exit 0 }

# Turns one project setting on where the project's answer says it is off, and prints the outcome on one line. A refusal
# is reported, not thrown: each setting stands on its own, so the next one is still tried.
function Set-ProjectSetting {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Label, [string]$Field, $Info)
    if ($null -eq $Info.$Field) { Write-Host "${Project}: ${Label}: not available (couldn't read it: the project's answer doesn't include it)"; return }
    if ($Info.$Field -eq $true) { Write-Host "${Project}: ${Label}: already set"; return }
    if (-not $PSCmdlet.ShouldProcess($Project, "turn on $Label")) { Write-Host "${Project}: ${Label}: would set"; return }
    $result = Invoke-Glab PUT $endpoint @("$Field=true")
    if ($result.Status -ge 200 -and $result.Status -lt 300) { Write-Host "${Project}: ${Label}: set" }
    else { Write-Host "${Project}: ${Label}: not available ($(Get-FailureReason $result))" }
}

Set-ProjectSetting 'All threads must be resolved' 'only_allow_merge_if_all_discussions_are_resolved' $info
Set-ProjectSetting 'Pipelines must succeed' 'only_allow_merge_if_pipeline_succeeds' $info
