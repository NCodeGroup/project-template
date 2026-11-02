<#
.SYNOPSIS
    Test that tools\Set-GitLabBaseline.ps1 turns on a GitLab project's merge protection settings and reports each one.

.DESCRIPTION
    Runs the script against a stand-in for glab that serves canned projects and records what it is asked to change.
    Checks, for a project named with -Project, that -WhatIf changes nothing and shows both settings as would set; that a
    project with both settings off gets one PUT for each, "All threads must be resolved" first, then "Pipelines must
    succeed", each with its own field; that a project with both on, or one of them, is reported as already set and only
    the one that is off is written; that a setting the API refuses is reported as not available with its answer, and
    the other one is still turned on, with the run succeeding; that an answer that leaves a setting out is reported and
    not written; that a project that can't be read, answers 200 with no project or with text that isn't JSON, or gives no
    response fails the run without a change, with glab's error for no response; and that an archived project is skipped.
    For the default branch, it checks that a protection made of roles is removed and made again with no one allowed to
    push and its other settings kept, that an unprotected branch is protected, that one naming a user, requiring
    code-owner approval or letting a user unprotect the branch is reported and left as it is, that an answer that isn't
    a protection is reported, that a refused read, removal or protection is reported, and that a branch left unprotected
    fails the run.
    It also checks that a project that allows squash commits gets one PUT that sets squash_option to never, and that a
    project with every setting made is reported as already set and nothing is written.
    Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-gitlab-baseline-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-GitLabBaseline.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-gitlab-baseline-test-$PID"))
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

# The stand-in for glab. It serves projects.json (host/project path -> the project's answer as info, and writeFails, the
# field -> status that refuses a change to it) and records every call in calls.log. A project with raw answers its GET
# with that body as it is, and one with offline prints that text to stderr and no status line, as glab does when it gets
# no response. A project's branch is the answer for its protected branch (404 without it); branchFails is the status that
# refuses reading it; deleteFails is the status that refuses removing it; and postFails lists the statuses that refuse
# the first, second, ... POST of the run.
Write-Text (Join-Path $bin 'glab.ps1') @'
# The script runs this in its own session, so a -WhatIf run would reach it as $WhatIfPreference, and its log would stay
# empty: it has to record the calls of a -WhatIf run too, to show that they change nothing.
$WhatIfPreference = $false
Add-Content -LiteralPath (Join-Path $PSScriptRoot 'calls.log') -Value ($args -join ' ')
$data = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'projects.json') | ConvertFrom-Json -AsHashtable
if ($args[0] -ne 'api') { exit 1 }
$hostname = ''; $method = 'GET'; $endpoint = ''; $fields = @()
for ($i = 1; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        '--hostname' { $i++; $hostname = $args[$i] }
        '--method' { $i++; $method = $args[$i] }
        '-F' { $i++; $fields += $args[$i] }
        '--include' { }
        default { $endpoint = $args[$i] }
    }
}
if ($endpoint -notmatch '^projects/(?<id>[^/]+)(?<rest>/.*)?$') { exit 1 }
$key = "$hostname/$([uri]::UnescapeDataString($Matches.id))"
$rest = "$($Matches.rest)"
# Answers with a status and a body, preceded by the status line and a header, as glab prints them with --include. A
# status of 300 or more exits 1, as glab does.
function Out-Answer([int]$Status, [string]$Body) {
    "HTTP/2.0 $Status Status"; 'Content-Type: application/json'; ''
    if ($Body) { $Body }
    if ($Status -ge 300) { exit 1 }
    exit 0
}
$project = $data[$key]
if (-not $project) { Out-Answer 404 '{"message":"404 Project Not Found"}' }
if ($project.offline) { Write-Error $project.offline -ErrorAction Continue; exit 1 }
if ($rest -like '/protected_branches/*') {
    if ($method -eq 'DELETE') {
        if ($project.deleteFails) { Out-Answer ([int]$project.deleteFails) '{"message":"Stand-in refused unprotect"}' }
        Out-Answer 204 ''
    }
    if ($project.branchFails) { Out-Answer ([int]$project.branchFails) '{"message":"Stand-in refused read"}' }
    if ($project.ContainsKey('branchRaw')) { Out-Answer 200 $project.branchRaw }
    if (-not $project.branch) { Out-Answer 404 '{"message":"404 Not found"}' }
    Out-Answer 200 (ConvertTo-Json -Compress -Depth 5 -InputObject $project.branch)
}
if ($rest -eq '/protected_branches') {
    $posts = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'calls.log') | Where-Object { $_ -like '*--method POST*' }).Count
    $postFails = @($project.postFails)
    if ($posts -le $postFails.Count -and $postFails[$posts - 1]) { Out-Answer ([int]$postFails[$posts - 1]) '{"message":"Stand-in refused protect"}' }
    Out-Answer 201 '{}'
}
if ($method -eq 'GET' -and $project.ContainsKey('raw')) { Out-Answer 200 $project.raw }
if ($method -eq 'GET') { Out-Answer 200 (ConvertTo-Json -Compress -Depth 5 -InputObject $project.info) }
$field = ("$($fields | Select-Object -First 1)" -split '=')[0]
$refused = if ($project.writeFails) { $project.writeFails[$field] }
if ($refused) { Out-Answer ([int]$refused) "{""message"":""Stand-in refused $field""}" }
Out-Answer 200 '{}'
'@

$threads = 'only_allow_merge_if_all_discussions_are_resolved'
$pipelines = 'only_allow_merge_if_pipeline_succeeds'
# A project with every merge setting made, GitLab's default protection of main, made of roles with Maintainers allowed
# to push, and a protection that also lets a user push. Two more need code-owner approval, or let a user unprotect the
# branch.
$merged = @{ archived = $false; $threads = $true; $pipelines = $true; squash_option = 'never'; default_branch = 'main' }
$openBranch = @{
    name = 'main'; allow_force_push = $false; code_owner_approval_required = $false
    push_access_levels = @(@{ id = 1; access_level = 40; user_id = $null; group_id = $null })
    merge_access_levels = @(@{ id = 2; access_level = 40 })
    unprotect_access_levels = @(@{ id = 3; access_level = 40 })
}
$granularBranch = @{
    name = 'main'; allow_force_push = $false
    push_access_levels = @(@{ id = 1; access_level = 40 }, @{ id = 4; access_level = 40; user_id = 5 })
    merge_access_levels = @(@{ id = 2; access_level = 40 })
}
$codeOwnerBranch = $openBranch.Clone(); $codeOwnerBranch.code_owner_approval_required = $true
$unprotectUserBranch = $openBranch.Clone(); $unprotectUserBranch.unprotect_access_levels = @(@{ id = 6; access_level = $null; user_id = 7 })
Write-Text (Join-Path $bin 'projects.json') (ConvertTo-Json -Depth 6 -InputObject @{
    'gitlab.com/grp/fresh' = @{ info = @{ archived = $false; $threads = $false; $pipelines = $false } }
    'gitlab.com/grp/complete' = @{ info = @{ archived = $false; $threads = $true; $pipelines = $true; squash_option = 'never'; default_branch = 'main' }; branch = @{ name = 'main'; push_access_levels = @(@{ access_level = 0 }); merge_access_levels = @(@{ access_level = 40 }) } }
    'gitlab.com/grp/squash' = @{ info = @{ archived = $false; $threads = $true; $pipelines = $true; squash_option = 'default_off' } }
    'gitlab.com/grp/open' = @{ info = $merged; branch = $openBranch }
    'gitlab.com/grp/unprotected' = @{ info = $merged }
    'gitlab.com/grp/granular' = @{ info = $merged; branch = $granularBranch }
    'gitlab.com/grp/codeowner' = @{ info = $merged; branch = $codeOwnerBranch }
    'gitlab.com/grp/unprotectuser' = @{ info = $merged; branch = $unprotectUserBranch }
    'gitlab.com/grp/oddbranch' = @{ info = $merged; branchRaw = '{}' }
    'gitlab.com/grp/branchfail' = @{ info = $merged; branchFails = 500 }
    'gitlab.com/grp/nodelete' = @{ info = $merged; branch = $openBranch; deleteFails = 403 }
    'gitlab.com/grp/restored' = @{ info = $merged; branch = $openBranch; postFails = @(422) }
    'gitlab.com/grp/lost' = @{ info = $merged; branch = $openBranch; postFails = @(422, 500) }
    'gitlab.com/grp/partial' = @{ info = @{ archived = $false; $threads = $false; $pipelines = $true } }
    'gitlab.com/grp/refused' = @{
        info = @{ archived = $false; $threads = $false; $pipelines = $false }
        writeFails = @{ $threads = 403 }
    }
    'gitlab.com/grp/unread' = @{ info = @{ archived = $false; $threads = $false } }
    'gitlab.com/grp/old' = @{ info = @{ archived = $true; $threads = $false; $pipelines = $false } }
    'gitlab.com/grp/empty' = @{ raw = '' }
    'gitlab.com/grp/text' = @{ raw = 'not json' }
    'gitlab.com/grp/offline' = @{ offline = 'glab: could not reach gitlab.com' }
    'gitlab.example.com/grp/sub/fresh' = @{ info = @{ archived = $false; $threads = $false; $pipelines = $false } }
})

$script = Join-Path $repoRoot 'tools/Set-GitLabBaseline.ps1'
$calls = Join-Path $bin 'calls.log'
# A run in the folder $In: its output and exit code, and its changes, the calls that PUT, in order.
function Invoke-GitLabBaseline([string[]]$Arguments, [string]$In = $Work) {
    if (Test-Path -LiteralPath $calls) { Remove-Item -LiteralPath $calls -Force }
    Push-Location $In
    try {
        $output = & pwsh -NoProfile -File $script @Arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    }
    finally { Pop-Location }
    $log = if (Test-Path -LiteralPath $calls) { Get-Content -LiteralPath $calls } else { @() }
    [pscustomobject]@{
        Output = $output
        ExitCode = $exitCode
        Puts = @($log | Where-Object { $_ -like '*--method PUT*' })
        Writes = @($log | Where-Object { $_ -match '--method (PUT|POST|DELETE) ' })
    }
}

$savedPath = $env:PATH
$env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
try {
    # 1. -WhatIf.
    $r = Invoke-GitLabBaseline @('-Project', 'grp/fresh', '-WhatIf')
    Check 'whatif: changes nothing and shows both settings as would set' ($r.ExitCode -eq 0 -and $r.Puts.Count -eq 0 -and $r.Output -match [regex]::Escape('grp/fresh: All threads must be resolved: would set') -and $r.Output -match [regex]::Escape('grp/fresh: Pipelines must succeed: would set')) "puts=$($r.Puts -join '|') output=$($r.Output)"

    # 2. A project with both settings off.
    $r = Invoke-GitLabBaseline @('-Project', 'grp/fresh')
    $putThreads = '*--hostname gitlab.com --method PUT --include projects/grp%2Ffresh -F only_allow_merge_if_all_discussions_are_resolved=true'
    $putPipelines = '*--hostname gitlab.com --method PUT --include projects/grp%2Ffresh -F only_allow_merge_if_pipeline_succeeds=true'
    Check 'create: two PUTs, the threads setting first, then the pipelines setting, each with its own field' ($r.Puts.Count -eq 2 -and $r.Puts[0] -like $putThreads -and $r.Puts[1] -like $putPipelines) ($r.Puts -join '|')
    Check 'create: both are reported as set' ($r.ExitCode -eq 0 -and $r.Output -match [regex]::Escape('grp/fresh: All threads must be resolved: set') -and $r.Output -match [regex]::Escape('grp/fresh: Pipelines must succeed: set')) $r.Output

    # 3. A project with both settings on.
    $r = Invoke-GitLabBaseline @('-Project', 'grp/complete')
    Check 'already: a project with both settings on is reported and not written' ($r.ExitCode -eq 0 -and $r.Puts.Count -eq 0 -and $r.Output -match [regex]::Escape('grp/complete: All threads must be resolved: already set') -and $r.Output -match [regex]::Escape('grp/complete: Pipelines must succeed: already set')) "puts=$($r.Puts -join '|') output=$($r.Output)"

    # 4. A project with one of them on.
    $r = Invoke-GitLabBaseline @('-Project', 'grp/partial')
    Check 'partial: only the setting that is off is written' ($r.ExitCode -eq 0 -and $r.Puts.Count -eq 1 -and $r.Puts[0] -like '*projects/grp%2Fpartial -F only_allow_merge_if_all_discussions_are_resolved=true' -and $r.Output -match [regex]::Escape('grp/partial: Pipelines must succeed: already set')) "puts=$($r.Puts -join '|') output=$($r.Output)"

    # 5. A setting the API refuses.
    $r = Invoke-GitLabBaseline @('-Project', 'grp/refused')
    Check 'refused: a change the API refuses is reported as not available, with its answer, and the other setting is still set' ($r.ExitCode -eq 0 -and $r.Output -match [regex]::Escape('grp/refused: All threads must be resolved: not available (HTTP 403: Stand-in refused only_allow_merge_if_all_discussions_are_resolved)') -and $r.Output -match [regex]::Escape('grp/refused: Pipelines must succeed: set')) $r.Output

    # 6. An answer that leaves a setting out.
    $r = Invoke-GitLabBaseline @('-Project', 'grp/unread')
    Check 'unread: an answer that leaves a setting out is reported and only the other setting is written' ($r.ExitCode -eq 0 -and $r.Puts.Count -eq 1 -and $r.Puts[0] -like '*projects/grp%2Funread -F only_allow_merge_if_all_discussions_are_resolved=true' -and $r.Output -match [regex]::Escape("grp/unread: Pipelines must succeed: not available (couldn't read it: the project's answer doesn't include it)")) "puts=$($r.Puts -join '|') output=$($r.Output)"

    # 7. A project that can't be read, and an archived one.
    $r = Invoke-GitLabBaseline @('-Project', 'grp/missing')
    Check 'missing: a project that can''t be read fails the run, with the reason, and changes nothing' ($r.ExitCode -ne 0 -and $r.Puts.Count -eq 0 -and ($r.Output -replace '[\s|]', '').Contains(("Couldn't read GitLab project grp/missing on gitlab.com: HTTP 404: 404 Project Not Found" -replace '\s', ''))) "puts=$($r.Puts -join '|') output=$($r.Output)"
    $r = Invoke-GitLabBaseline @('-Project', 'grp/old')
    Check 'archived: an archived project is skipped and changes nothing' ($r.ExitCode -eq 0 -and $r.Puts.Count -eq 0 -and $r.Output -match [regex]::Escape('grp/old: skipped (archived)')) "puts=$($r.Puts -join '|') output=$($r.Output)"
    $r = Invoke-GitLabBaseline @('-Project', 'grp/empty')
    Check 'empty: a read that answers 200 with no project fails the run and changes nothing' ($r.ExitCode -ne 0 -and $r.Puts.Count -eq 0 -and ($r.Output -replace '[\s|]', '').Contains(("Couldn't read GitLab project grp/empty on gitlab.com: an answer that is not a project." -replace '\s', ''))) "puts=$($r.Puts -join '|') output=$($r.Output)"
    $r = Invoke-GitLabBaseline @('-Project', 'grp/text')
    Check 'text: a read that answers 200 with text that is not JSON fails the run and changes nothing' ($r.ExitCode -ne 0 -and $r.Puts.Count -eq 0 -and ($r.Output -replace '[\s|]', '').Contains(("Couldn't read GitLab project grp/text on gitlab.com: an answer that is not JSON." -replace '\s', ''))) "puts=$($r.Puts -join '|') output=$($r.Output)"
    $r = Invoke-GitLabBaseline @('-Project', 'grp/offline')
    Check 'offline: a call with no response fails the run with glab''s error and changes nothing' ($r.ExitCode -ne 0 -and $r.Puts.Count -eq 0 -and ($r.Output -replace '[\s|]+', ' ') -match [regex]::Escape("Couldn't read GitLab project grp/offline on gitlab.com: no response: glab: could not reach gitlab.com.")) "puts=$($r.Puts -join '|') output=$($r.Output)"

    # 8. The default branch's push access.
    $delete = '*--hostname gitlab.com --method DELETE --include projects/grp%2F{0}/protected_branches/main'
    $protect = '*--hostname gitlab.com --method POST --include projects/grp%2F{0}/protected_branches -F name=main -F push_access_level={1} -F merge_access_level=40 -F unprotect_access_level=40 -F allow_force_push=false'

    $r = Invoke-GitLabBaseline @('-Project', 'grp/open', '-WhatIf')
    Check 'push whatif: an open default branch is shown as would set and nothing is written' ($r.ExitCode -eq 0 -and $r.Writes.Count -eq 0 -and $r.Output -match [regex]::Escape('grp/open: No one allowed to push to main: would set')) "writes=$($r.Writes -join '|') output=$($r.Output)"

    $r = Invoke-GitLabBaseline @('-Project', 'grp/open')
    Check 'push: a protection of roles is removed and made again with no one allowed to push and its merge, unprotect and force-push settings' ($r.ExitCode -eq 0 -and $r.Writes.Count -eq 2 -and $r.Writes[0] -like ($delete -f 'open') -and $r.Writes[1] -like ($protect -f 'open', 0) -and $r.Output -match [regex]::Escape('grp/open: No one allowed to push to main: set')) "writes=$($r.Writes -join '|') output=$($r.Output)"

    $r = Invoke-GitLabBaseline @('-Project', 'grp/unprotected')
    Check 'push unprotected: an unprotected default branch is protected with no one allowed to push and Maintainers allowed to merge' ($r.ExitCode -eq 0 -and $r.Writes.Count -eq 1 -and $r.Writes[0] -like '*--hostname gitlab.com --method POST --include projects/grp%2Funprotected/protected_branches -F name=main -F push_access_level=0 -F merge_access_level=40' -and $r.Output -match [regex]::Escape('grp/unprotected: No one allowed to push to main: set')) "writes=$($r.Writes -join '|') output=$($r.Output)"

    $r = Invoke-GitLabBaseline @('-Project', 'grp/granular')
    Check 'push granular: a protection that names a user is reported and left as it is' ($r.ExitCode -eq 0 -and $r.Writes.Count -eq 0 -and $r.Output -match [regex]::Escape('grp/granular: No one allowed to push to main: not available (its protection names users, groups, deploy keys or code owners')) "writes=$($r.Writes -join '|') output=$($r.Output)"

    $r = Invoke-GitLabBaseline @('-Project', 'grp/codeowner')
    Check 'push code owners: a protection that requires code-owner approval is reported and left as it is' ($r.ExitCode -eq 0 -and $r.Writes.Count -eq 0 -and $r.Output -match [regex]::Escape('grp/codeowner: No one allowed to push to main: not available (its protection names users, groups, deploy keys or code owners')) "writes=$($r.Writes -join '|') output=$($r.Output)"
    $r = Invoke-GitLabBaseline @('-Project', 'grp/unprotectuser')
    Check 'push unprotect user: a protection that lets a user unprotect the branch is reported and left as it is' ($r.ExitCode -eq 0 -and $r.Writes.Count -eq 0 -and $r.Output -match [regex]::Escape('grp/unprotectuser: No one allowed to push to main: not available (its protection names users, groups, deploy keys or code owners')) "writes=$($r.Writes -join '|') output=$($r.Output)"
    $r = Invoke-GitLabBaseline @('-Project', 'grp/oddbranch')
    Check 'push odd answer: a branch answer that isn''t a protection is reported and nothing is written' ($r.ExitCode -eq 0 -and $r.Writes.Count -eq 0 -and $r.Output -match [regex]::Escape('grp/oddbranch: No one allowed to push to main: not available (couldn''t read it: the answer is not a protected branch)')) "writes=$($r.Writes -join '|') output=$($r.Output)"

    $r = Invoke-GitLabBaseline @('-Project', 'grp/branchfail')
    Check 'push unread: a protection that can''t be read is reported with its answer and nothing is written' ($r.ExitCode -eq 0 -and $r.Writes.Count -eq 0 -and $r.Output -match [regex]::Escape('grp/branchfail: No one allowed to push to main: not available (HTTP 500: Stand-in refused read)')) "writes=$($r.Writes -join '|') output=$($r.Output)"

    $r = Invoke-GitLabBaseline @('-Project', 'grp/nodelete')
    Check 'push no delete: a refused removal is reported and nothing is protected again' ($r.ExitCode -eq 0 -and $r.Writes.Count -eq 1 -and $r.Writes[0] -like ($delete -f 'nodelete') -and $r.Output -match [regex]::Escape('grp/nodelete: No one allowed to push to main: not available (HTTP 403: Stand-in refused unprotect)')) "writes=$($r.Writes -join '|') output=$($r.Output)"

    $r = Invoke-GitLabBaseline @('-Project', 'grp/restored')
    Check 'push restored: a refused protection is reported and the earlier protection is made again' ($r.ExitCode -eq 0 -and $r.Writes.Count -eq 3 -and $r.Writes[1] -like ($protect -f 'restored', 0) -and $r.Writes[2] -like ($protect -f 'restored', 40) -and $r.Output -match [regex]::Escape('grp/restored: No one allowed to push to main: not available (HTTP 422: Stand-in refused protect; its earlier protection was made again)')) "writes=$($r.Writes -join '|') output=$($r.Output)"

    $r = Invoke-GitLabBaseline @('-Project', 'grp/lost')
    Check 'push lost: a branch left unprotected fails the run and says so' ($r.ExitCode -ne 0 -and $r.Writes.Count -eq 3 -and ($r.Output -replace '[\s|]', '').Contains(('main of GitLab project grp/lost is no longer protected' -replace '\s', ''))) "writes=$($r.Writes -join '|') output=$($r.Output)"

    $r = Invoke-GitLabBaseline @('-Project', 'grp/fresh')
    Check 'push no branch: a project with no default branch is reported and its protection isn''t read' ($r.Output -match [regex]::Escape('grp/fresh: No one allowed to push to the default branch: not available (the project has no default branch yet)') -and -not ((Get-Content -LiteralPath $calls) -like '*protected_branches*')) "output=$($r.Output)"

    # 9. Squash commits, and a project with every setting made.
    $r = Invoke-GitLabBaseline @('-Project', 'grp/squash')
    Check 'squash: a project that allows squash commits gets one PUT that sets squash_option to never' ($r.ExitCode -eq 0 -and $r.Puts.Count -eq 1 -and $r.Puts[0] -like '*--hostname gitlab.com --method PUT --include projects/grp%2Fsquash -F squash_option=never' -and $r.Output -match [regex]::Escape('grp/squash: Do not allow squash commits: set')) "puts=$($r.Puts -join '|') output=$($r.Output)"

    $r = Invoke-GitLabBaseline @('-Project', 'grp/complete')
    Check 'complete: squash commits already not allowed and no one allowed to push to main are reported and nothing is written' ($r.ExitCode -eq 0 -and $r.Writes.Count -eq 0 -and $r.Output -match [regex]::Escape('grp/complete: Do not allow squash commits: already set') -and $r.Output -match [regex]::Escape('grp/complete: No one allowed to push to main: already set')) "writes=$($r.Writes -join '|') output=$($r.Output)"

    # 10. A project named by a clone's origin remote.
    $httpsClone = Join-Path $Work 'clone-https'
    & git init -q $httpsClone
    & git -C $httpsClone remote add origin 'https://gitlab.example.com/grp/sub/fresh.git'
    $sshClone = Join-Path $Work 'clone-ssh'
    & git init -q $sshClone
    & git -C $sshClone remote add origin 'git@gitlab.com:grp/fresh.git'
    $bareClone = Join-Path $Work 'clone-no-origin'
    & git init -q $bareClone

    $r = Invoke-GitLabBaseline @('-Path', $httpsClone)
    Check 'path: the origin remote of a clone gives the host and the project' ($r.ExitCode -eq 0 -and $r.Puts.Count -eq 2 -and @($r.Puts | Where-Object { $_ -like '*--hostname gitlab.example.com*projects/grp%2Fsub%2Ffresh *' }).Count -eq 2 -and $r.Output -match [regex]::Escape('grp/sub/fresh: All threads must be resolved: set')) "puts=$($r.Puts -join '|') output=$($r.Output)"
    $r = Invoke-GitLabBaseline @() $httpsClone
    Check 'current folder: with no arguments, the clone the run starts in is used' ($r.ExitCode -eq 0 -and $r.Puts.Count -eq 2 -and @($r.Puts | Where-Object { $_ -like '*--hostname gitlab.example.com*projects/grp%2Fsub%2Ffresh *' }).Count -eq 2) "puts=$($r.Puts -join '|') output=$($r.Output)"
    $r = Invoke-GitLabBaseline @('-Path', $sshClone)
    Check 'ssh: an scp-style origin remote gives the host and the project' ($r.ExitCode -eq 0 -and $r.Puts.Count -eq 2 -and @($r.Puts | Where-Object { $_ -like '*--hostname gitlab.com*projects/grp%2Ffresh *' }).Count -eq 2) "puts=$($r.Puts -join '|') output=$($r.Output)"

    # 11. -Project with -Hostname, and the arguments that can't be used.
    $r = Invoke-GitLabBaseline @('-Project', 'grp/sub/fresh', '-Hostname', 'gitlab.example.com')
    Check 'hostname: a project on another GitLab is written there' ($r.ExitCode -eq 0 -and $r.Puts.Count -eq 2 -and @($r.Puts | Where-Object { $_ -like '*--hostname gitlab.example.com --method PUT --include projects/grp%2Fsub%2Ffresh -F *' }).Count -eq 2) "puts=$($r.Puts -join '|') output=$($r.Output)"
    $r = Invoke-GitLabBaseline @('-Project', 'grp/fresh', '-Path', $httpsClone)
    Check 'both: -Project with -Path fails before any call' ($r.ExitCode -ne 0 -and -not (Test-Path -LiteralPath $calls) -and $r.Output -match [regex]::Escape('Pass -Project or -Path, not both.')) "output=$($r.Output)"
    $r = Invoke-GitLabBaseline @('-Path', $bareClone)
    Check 'no origin: a clone with no origin remote fails and changes nothing' ($r.ExitCode -ne 0 -and $r.Puts.Count -eq 0 -and ($r.Output -replace '[\s|]+', ' ') -match [regex]::Escape('pass -Project <group/name>')) "puts=$($r.Puts -join '|') output=$($r.Output)"
}
finally { $env:PATH = $savedPath }

''
if ($failures.Count) { "Kept the work folder: $Work"; "GitLab baseline tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'GitLab baseline tests: PASSED'
exit 0
