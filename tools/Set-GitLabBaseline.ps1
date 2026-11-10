<#
.SYNOPSIS
    Gives a GitLab project the baseline protection: changes reach the default branch only through a merge request, which
    merges only with every thread resolved and a passing pipeline, and never by squashing.

.DESCRIPTION
    For one GitLab project it makes four settings, each where it isn't so already:
      - "All threads must be resolved" (only_allow_merge_if_all_discussions_are_resolved), so a review finding from the
        bot or a person can't be merged past;
      - "Pipelines must succeed" (only_allow_merge_if_pipeline_succeeds), so a merge request whose pipeline failed can't
        merge. It also blocks a merge request that has no pipeline at all. The template's .gitlab-ci.yml runs a pipeline
        on every merge request, with the always-on "decision-index" job, so a project made from the template always
        has one; a project whose CI runs none can't merge until it does;
      - "Squash commits when merging" set to "Do not allow" (squash_option never), so a plan's step commits stay on the
        default branch, as a project's ADR-0013 records;
      - the default branch's "Allowed to push and merge" set to "No one", so a change reaches it only through a merge
        request, as ADR-0005 records, and Get-PlanState.ps1 reports protected: host. GitLab Free can't change a
        protected branch's access levels in place, so a protection made only of roles is removed (DELETE) and made
        again (POST) with no one allowed to push and its own merge, unprotect and force-push settings. If making it
        again fails, the earlier protection is restored, and the run fails, saying so, only when that fails too and
        the branch is left unprotected. A protection that names users, groups, deploy keys or code owners, which GitLab
        Premium allows, is reported and left as it is, to change by hand in the project's Settings > Repository >
        Protected branches. An unprotected default branch is protected, with Maintainers allowed to merge. A project
        with no default branch yet (nothing pushed) is reported, and its protection isn't read.

    These are the settings that play, on GitLab, the part the "Protect main" ruleset's pull request rule, merge
    methods, conversation resolution and required checks play on GitHub (see Set-RepositoryBaseline.ps1). All four are
    on GitLab Free.

    Each setting is read first, from the project, and printed as set, already set, would set (-WhatIf) or not available,
    with the reason, one line each: <project>: <setting>: <outcome>. A setting the API refuses to change is reported, and
    the run goes on with the next one. A project the script can't read (no response, not found, or an answer that isn't
    a project) fails the run with an error, and an archived project is skipped. A run also fails when it leaves the
    default branch unprotected.

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

# Sets one project setting to $Value (on by default) where the project's answer says otherwise, and prints the outcome on
# one line. A refusal is reported, not thrown: each setting stands on its own, so the next one is still tried.
function Set-ProjectSetting {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Label, [string]$Field, $Info, $Value = $true)
    if ($null -eq $Info.$Field) { Write-Host "${Project}: ${Label}: not available (couldn't read it: the project's answer doesn't include it)"; return }
    if ($Info.$Field -eq $Value) { Write-Host "${Project}: ${Label}: already set"; return }
    if (-not $PSCmdlet.ShouldProcess($Project, "set $Label")) { Write-Host "${Project}: ${Label}: would set"; return }
    $text = if ($Value -is [bool]) { "$Value".ToLowerInvariant() } else { "$Value" }
    $result = Invoke-Glab PUT $endpoint @("$Field=$text")
    if ($result.Status -ge 200 -and $result.Status -lt 300) { Write-Host "${Project}: ${Label}: set" }
    else { Write-Host "${Project}: ${Label}: not available ($(Get-FailureReason $result))" }
}

# The access level of a protected branch's list of access levels when the list holds exactly one entry and it is a role,
# not a user, a group, a deploy key or a custom role; otherwise $null.
function Get-RoleLevel($Levels) {
    $all = @($Levels | Where-Object { $null -ne $_ })
    if ($all.Count -ne 1) { return $null }
    $entry = $all[0]
    if ($null -eq $entry.access_level -or $entry.user_id -or $entry.group_id -or $entry.deploy_key_id -or $entry.member_role_id) { return $null }
    [int]$entry.access_level
}

# Sets the default branch's "Allowed to push and merge" to No one. GitLab Free can't change a protected branch's access
# levels in place (the PATCH that does is Premium), so this removes a protection made only of roles and makes it again
# with the same merge, unprotect and force-push settings. It reports a protection that names users, groups, deploy keys
# or code owners and leaves it as it is, and it protects an unprotected default branch.
function Set-DefaultBranchPush {
    [CmdletBinding(SupportsShouldProcess)]
    param($Info)
    $branch = "$($Info.default_branch)"
    $label = "No one allowed to push to $branch"
    $protected = "$endpoint/protected_branches"
    $branchEndpoint = "$protected/$([uri]::EscapeDataString($branch))"
    if (-not $branch) { Write-Host "${Project}: No one allowed to push to the default branch: not available (the project has no default branch yet)"; return }
    $read = Invoke-Glab GET $branchEndpoint
    if ($read.Status -eq 404) {
        if (-not $PSCmdlet.ShouldProcess($Project, "protect $branch with $label")) { Write-Host "${Project}: ${label}: would set"; return }
        $result = Invoke-Glab POST $protected @("name=$branch", 'push_access_level=0', 'merge_access_level=40')
        if ($result.Status -ge 200 -and $result.Status -lt 300) { Write-Host "${Project}: ${label}: set" }
        else { Write-Host "${Project}: ${label}: not available ($(Get-FailureReason $result))" }
        return
    }
    if ($read.Status -ne 200) { Write-Host "${Project}: ${label}: not available ($(Get-FailureReason $read))"; return }
    $protection = try { $read.Body | ConvertFrom-Json -ErrorAction Stop } catch { $null }
    if ($protection -isnot [Management.Automation.PSCustomObject] -or $null -eq $protection.push_access_levels) {
        Write-Host "${Project}: ${label}: not available (couldn't read it: the answer is not a protected branch)"
        return
    }
    if (@($protection.push_access_levels | Where-Object { $_.access_level -ne 0 }).Count -eq 0) { Write-Host "${Project}: ${label}: already set"; return }
    $push = Get-RoleLevel $protection.push_access_levels
    $merge = Get-RoleLevel $protection.merge_access_levels
    $unprotect = Get-RoleLevel $protection.unprotect_access_levels
    $unprotectCount = @($protection.unprotect_access_levels | Where-Object { $null -ne $_ }).Count
    if ($null -eq $push -or $null -eq $merge -or ($unprotectCount -and $null -eq $unprotect) -or $protection.code_owner_approval_required -eq $true) {
        Write-Host "${Project}: ${label}: not available (its protection names users, groups, deploy keys or code owners, which this script doesn't make again: set Allowed to push and merge to No one in Settings > Repository > Protected branches)"
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Project, "protect $branch again with $label")) { Write-Host "${Project}: ${label}: would set"; return }
    $kept = @("merge_access_level=$merge")
    if ($null -ne $unprotect) { $kept += "unprotect_access_level=$unprotect" }
    if ($null -ne $protection.allow_force_push) { $kept += "allow_force_push=$("$($protection.allow_force_push)".ToLowerInvariant())" }
    $removed = Invoke-Glab DELETE $branchEndpoint
    if (-not ($removed.Status -ge 200 -and $removed.Status -lt 300)) { Write-Host "${Project}: ${label}: not available ($(Get-FailureReason $removed))"; return }
    $result = Invoke-Glab POST $protected (@("name=$branch", 'push_access_level=0') + $kept)
    if ($result.Status -ge 200 -and $result.Status -lt 300) { Write-Host "${Project}: ${label}: set"; return }
    $restored = Invoke-Glab POST $protected (@("name=$branch", "push_access_level=$push") + $kept)
    if ($restored.Status -ge 200 -and $restored.Status -lt 300) {
        Write-Host "${Project}: ${label}: not available ($(Get-FailureReason $result); its earlier protection was made again)"
        return
    }
    throw "$branch of GitLab project $Project is no longer protected: removing its protection worked, but protecting it again failed ($(Get-FailureReason $result)), and so did restoring it ($(Get-FailureReason $restored)). Protect it in the project's Settings > Repository > Protected branches."
}

Set-ProjectSetting 'All threads must be resolved' 'only_allow_merge_if_all_discussions_are_resolved' $info
Set-ProjectSetting 'Pipelines must succeed' 'only_allow_merge_if_pipeline_succeeds' $info
Set-ProjectSetting 'Do not allow squash commits' 'squash_option' $info 'never'
Set-DefaultBranchPush $info
