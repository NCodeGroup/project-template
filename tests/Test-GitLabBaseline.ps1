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
# no response.
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
$key = "$hostname/$([uri]::UnescapeDataString(($endpoint -replace '^projects/', '')))"
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
if ($method -eq 'GET' -and $project.ContainsKey('raw')) { Out-Answer 200 $project.raw }
if ($method -eq 'GET') { Out-Answer 200 (ConvertTo-Json -Compress -Depth 5 -InputObject $project.info) }
$field = ("$($fields | Select-Object -First 1)" -split '=')[0]
$refused = if ($project.writeFails) { $project.writeFails[$field] }
if ($refused) { Out-Answer ([int]$refused) "{""message"":""Stand-in refused $field""}" }
Out-Answer 200 '{}'
'@

$threads = 'only_allow_merge_if_all_discussions_are_resolved'
$pipelines = 'only_allow_merge_if_pipeline_succeeds'
Write-Text (Join-Path $bin 'projects.json') (ConvertTo-Json -Depth 6 -InputObject @{
    'gitlab.com/grp/fresh' = @{ info = @{ archived = $false; $threads = $false; $pipelines = $false } }
    'gitlab.com/grp/complete' = @{ info = @{ archived = $false; $threads = $true; $pipelines = $true } }
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

    # 8. A project named by a clone's origin remote.
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

    # 9. -Project with -Hostname, and the arguments that can't be used.
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
