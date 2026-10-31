<#
.SYNOPSIS
    Test that tools\Set-RepositoryBaseline.ps1 gives a repository the baseline ruleset and leaves protected ones alone.

.DESCRIPTION
    Runs the script against a stand-in for gh that serves canned repositories and rulesets and records what it is asked
    to change. Checks that -WhatIf changes nothing; that a repository with no ruleset gets "Protect main" on its default
    branch, with no deletion, no force push, a pull request with no approvals, merge-commit and rebase merges only and
    no bypass, and delete-branch-on-merge; that -RequireChecks adds required status checks; that a repository whose
    default branch already requires pull requests, or already has this ruleset, is left alone, and that -RequireChecks
    updates the ruleset the script made; that -All skips archived repositories and forks; and that bad parameters
    stop it. Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-baseline-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-RepositoryBaseline.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-baseline-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Write-Text([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n")) }

if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$bin = Join-Path $Work 'bin'
New-Item -ItemType Directory -Force $bin | Out-Null

# The stand-in for gh. It serves repos.json (repository name -> repository, rulesets and their full forms), records every
# call in calls.log, and keeps the body of the last create or update in posted.json.
Write-Text (Join-Path $bin 'gh.ps1') @'
$log = Join-Path $PSScriptRoot 'calls.log'
Add-Content -LiteralPath $log -Value ($args -join ' ')
$data = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'repos.json') | ConvertFrom-Json -AsHashtable
if ($args[0] -eq 'repo' -and $args[1] -eq 'list') { ConvertTo-Json -InputObject @($data.list) -Depth 5; exit 0 }
if ($args[0] -ne 'api') { exit 1 }
$method = 'GET'
$rest = @($args[1..($args.Count - 1)] | Where-Object { $_ -ne '--include' })
$include = $args -contains '--include'
if ($rest[0] -eq '-X') { $method = $rest[1]; $rest = @($rest[2..($rest.Count - 1)]) }
$path = $rest[0]
if ($rest -contains '--input') {
    $file = $rest[[array]::IndexOf($rest, '--input') + 1]
    Copy-Item -LiteralPath $file -Destination (Join-Path $PSScriptRoot 'posted.json') -Force
    Add-Content -LiteralPath $log -Value "BODY $method $path"
    '{}'; exit 0
}
if ($method -eq 'PATCH') { exit 0 }
if ($path -match '^repos/[^/]+/([^/]+)/code-scanning/default-setup$') {
    # codeql is a state, 404 for not found, fail:<code> for another status, fail:none for no response at all, or
    # raw:<text> for a body that isn't JSON. With --include, the answer starts with the status line and a header.
    $codeql = "$($data.repos[$Matches[1]].codeql)"
    $status = 200; $body = ConvertTo-Json -InputObject @{ state = $codeql }
    if ($codeql -eq 'fail:none') { exit 1 }
    if ($codeql -eq '404') { $status = 404; $body = '{"message":"Not Found"}' }
    elseif ($codeql.StartsWith('fail:')) { $status = [int]$codeql.Substring(5); $body = '{"message":"Error"}' }
    elseif ($codeql.StartsWith('raw:')) { $body = $codeql.Substring(4) }
    if ($include) { "HTTP/2.0 $status Status"; 'Content-Type: application/json'; '' }
    $body
    if ($status -ne 200) { exit 1 }
    exit 0
}
if ($path -match '^repos/[^/]+/([^/]+)/rulesets/(\d+)$') { ConvertTo-Json -InputObject $data.repos[$Matches[1]].full["$($Matches[2])"] -Depth 10; exit 0 }
if ($path -match '^repos/[^/]+/([^/]+)/rulesets$') { ConvertTo-Json -InputObject @($data.repos[$Matches[1]].rulesets) -Depth 5; exit 0 }
if ($path -match '^repos/[^/]+/([^/]+)$') { ConvertTo-Json -InputObject $data.repos[$Matches[1]].info -Depth 5; exit 0 }
exit 1
'@

function New-Ruleset([string]$Name, [string[]]$Types = @('deletion', 'non_fast_forward', 'pull_request'), [string]$Include = '~DEFAULT_BRANCH') {
    @{ name = $Name; target = 'branch'; enforcement = 'active'
        conditions = @{ ref_name = @{ include = @($Include); exclude = @() } }
        rules = @($Types | ForEach-Object { @{ type = $_ } }) }
}
function New-Repo([string]$Branch = 'main', [bool]$Archived = $false, [bool]$Fork = $false, $Rulesets = @(), [string]$CodeQL = 'configured') {
    $full = @{}
    $summaries = @()
    $id = 100
    foreach ($ruleset in $Rulesets) { $id++; $ruleset.id = $id; $full["$id"] = $ruleset; $summaries += @{ id = $id; name = $ruleset.name } }
    @{ info = @{ default_branch = $Branch; archived = $Archived; fork = $Fork }; rulesets = $summaries; full = $full; codeql = $CodeQL }
}
$repos = @{
    fresh = New-Repo
    noCodeQL = New-Repo -CodeQL 'not-configured'
    setupNotFound = New-Repo -CodeQL '404'
    setupFailed = New-Repo -CodeQL 'fail:403'
    setupNoResponse = New-Repo -CodeQL 'fail:none'
    setupUnreadable = New-Repo -CodeQL 'raw:<html>Bad Gateway</html>'
    oursCodeQL404 = New-Repo -CodeQL '404' -Rulesets @((New-Ruleset 'Protect main' @('deletion', 'non_fast_forward', 'pull_request', 'code_scanning')))
    oursWithoutCodeQL = New-Repo -CodeQL 'not-configured' -Rulesets @((New-Ruleset 'Protect main' @('deletion', 'non_fast_forward', 'pull_request', 'code_scanning')))
    legacy = New-Repo -Branch master
    owned = New-Repo -Rulesets @((New-Ruleset 'main'))
    ours = New-Repo -Rulesets @((New-Ruleset 'Protect main'))
    tags = New-Repo -Rulesets @((@{ name = 'release-tags'; target = 'tag'; enforcement = 'active'; conditions = @{ ref_name = @{ include = @('refs/tags/v*'); exclude = @() } }; rules = @(@{ type = 'deletion' }) }))
    noPullRequest = New-Repo -Rulesets @((New-Ruleset 'no force push' @('non_fast_forward')))
    old = New-Repo -Archived $true
    forked = New-Repo -Fork $true
}
Write-Text (Join-Path $bin 'repos.json') (ConvertTo-Json -Depth 12 -InputObject @{
    repos = $repos
    list = @(
        foreach ($name in 'fresh', 'old', 'forked', 'owned') {
            @{ name = $name; isArchived = $repos[$name].info.archived; isFork = $repos[$name].info.fork }
        })
})

$script = Join-Path $repoRoot 'tools/Set-RepositoryBaseline.ps1'
$calls = Join-Path $bin 'calls.log'
$posted = Join-Path $bin 'posted.json'
function Invoke-Baseline([string[]]$Arguments) {
    foreach ($file in $calls, $posted) { if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force } }
    $output = & pwsh -NoProfile -File $script @Arguments 2>&1 | Out-String
    $log = if (Test-Path -LiteralPath $calls) { Get-Content -LiteralPath $calls } else { @() }
    [pscustomobject]@{
        Output = $output
        ExitCode = $LASTEXITCODE
        Changes = @($log | Where-Object { $_ -like 'BODY *' -or $_ -like '*-X PATCH*' })
        Body = if (Test-Path -LiteralPath $posted) { Get-Content -Raw -LiteralPath $posted | ConvertFrom-Json } else { $null }
    }
}

$savedPath = $env:PATH
$env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
try {
    # 1. -WhatIf.
    $r = Invoke-Baseline @('-Repo', 'fresh', '-WhatIf')
    Check 'whatif: changes nothing' ($r.Changes.Count -eq 0 -and $r.Output -match "would: fresh \(main\): create 'Protect main'") "changes=$($r.Changes -join '|') output=$($r.Output)"

    # 2. A repository with no ruleset.
    $r = Invoke-Baseline @('-Repo', 'fresh')
    $types = @($r.Body.rules.type)
    Check 'create: posts one ruleset and turns on delete-branch-on-merge' (($r.Changes -join '|') -eq 'BODY POST repos/NCodeGroup/fresh/rulesets|api -X PATCH repos/NCodeGroup/fresh -F delete_branch_on_merge=true') ($r.Changes -join '|')
    Check 'create: protects the default branch and cannot be bypassed' (($r.Body.name -eq 'Protect main') -and ($r.Body.target -eq 'branch') -and ($r.Body.enforcement -eq 'active') -and ($r.Body.conditions.ref_name.include -contains '~DEFAULT_BRANCH') -and ($r.Body.bypass_actors.Count -eq 0))
    Check 'create: no deletion, no force push, a pull request, a code-scanning rule, and nothing more' (($types -join ',') -eq 'deletion,non_fast_forward,pull_request,code_scanning') ($types -join ',')
    $scan = @(($r.Body.rules | Where-Object type -eq 'code_scanning').parameters.code_scanning_tools)
    Check 'create: the code-scanning rule blocks CodeQL alerts at error level and security alerts of medium severity or higher' (($scan.Count -eq 1) -and ($scan[0].tool -eq 'CodeQL') -and ($scan[0].alerts_threshold -eq 'errors') -and ($scan[0].security_alerts_threshold -eq 'medium_or_higher')) ($scan | ConvertTo-Json -Compress)
    $pr = $r.Body.rules | Where-Object type -eq 'pull_request'
    Check 'create: no approvals, and merge-commit or rebase merges only, never squash' (($pr.parameters.required_approving_review_count -eq 0) -and ((@($pr.parameters.allowed_merge_methods) -join ',') -eq 'merge,rebase')) ($pr.parameters | ConvertTo-Json -Compress)

    # 3. Required checks, as one comma-separated string, which is how pwsh -File passes a list.
    $r = Invoke-Baseline @('-Repo', 'fresh', '-RequireChecks', 'build-and-test,Commit attribution')
    $checks = $r.Body.rules | Where-Object type -eq 'required_status_checks'
    Check 'checks: names the jobs, reported by GitHub Actions' ((@($checks.parameters.required_status_checks.context) -join ',') -eq 'build-and-test,Commit attribution' -and (@($checks.parameters.required_status_checks.integration_id | Select-Object -Unique) -join ',') -eq '15368') ($checks | ConvertTo-Json -Depth 6 -Compress)

    # 3b. A repository where CodeQL's default setup isn't configured gets no code-scanning rule, which would wait forever.
    $r = Invoke-Baseline @('-Repo', 'noCodeQL')
    Check 'create: no code-scanning rule where CodeQL is not configured, and says so' (((@($r.Body.rules.type)) -join ',') -eq 'deletion,non_fast_forward,pull_request' -and $r.Output -match [regex]::Escape("no code-scanning rule (CodeQL's default setup is not configured)")) "$(@($r.Body.rules.type) -join ',') $($r.Output)"

    $r = Invoke-Baseline @('-Repo', 'setupNotFound')
    Check 'create: CodeQL setup not found (404) gets no code-scanning rule' (((@($r.Body.rules.type)) -join ',') -eq 'deletion,non_fast_forward,pull_request') "$(@($r.Body.rules.type) -join ',') $($r.Output)"
    foreach ($name in 'setupFailed', 'setupNoResponse', 'setupUnreadable') {
        $r = Invoke-Baseline @('-Repo', $name)
        Check "skip: a CodeQL setup lookup that fails or can't be read changes nothing ($name)" ($r.Changes.Count -eq 0 -and $r.Output -match "${name}: skipped \(couldn't read CodeQL's default setup") "$($r.Changes -join '|') $($r.Output)"
    }

    # 3c. Invoke-HostApi is copied from workflow/Get-PlanState.ps1, which projects get on its own; the copies must match.
    $bodies = foreach ($file in (Join-Path $repoRoot 'tools/Set-RepositoryBaseline.ps1'), (Join-Path $repoRoot 'workflow/Get-PlanState.ps1')) {
        $ast = [Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)
        $fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-HostApi' }, $true)
        if ($fn) { $fn.Extent.Text -replace '\r\n', "`n" } else { '' }
    }
    Check 'copies: Invoke-HostApi is the same in Set-RepositoryBaseline.ps1 and Get-PlanState.ps1' ($bodies[0] -and $bodies[0] -eq $bodies[1]) 'the two functions differ, or one is missing'

    # 4. A branch other than main.
    $r = Invoke-Baseline @('-Repo', 'legacy')
    Check 'create: works for a default branch that is not main' (($r.Changes -join '|') -like 'BODY POST repos/NCodeGroup/legacy/rulesets*') ($r.Changes -join '|')

    # 5. Repositories left alone.
    $r = Invoke-Baseline @('-Repo', 'owned')
    Check 'alone: a default branch that already requires pull requests' ($r.Changes.Count -eq 0 -and $r.Output -match "owned: left alone \('main' already requires pull requests\)") $r.Output
    $r = Invoke-Baseline @('-Repo', 'ours')
    Check 'alone: a repository that already has Protect main' ($r.Changes.Count -eq 0 -and $r.Output -match "ours: left alone \(already has 'Protect main'\)") $r.Output
    $r = Invoke-Baseline @('-Repo', 'tags')
    Check 'create: a tag ruleset does not count as protecting the default branch' (($r.Changes -join '|') -like 'BODY POST repos/NCodeGroup/tags/rulesets*') ($r.Changes -join '|')
    $r = Invoke-Baseline @('-Repo', 'noPullRequest')
    Check 'create: a ruleset without a pull request rule does not count' (($r.Changes -join '|') -like 'BODY POST repos/NCodeGroup/noPullRequest/rulesets*') ($r.Changes -join '|')

    # 6. -RequireChecks updates the ruleset the script made.
    $r = Invoke-Baseline @('-Repo', 'ours', '-RequireChecks', 'test')
    Check 'update: -RequireChecks changes the ruleset it made, in place' (($r.Changes -join '|') -like 'BODY PUT repos/NCodeGroup/ours/rulesets/101*') ($r.Changes -join '|')
    $scan = @(($r.Body.rules | Where-Object type -eq 'code_scanning').parameters.code_scanning_tools)
    $r2 = Invoke-Baseline @('-Repo', 'oursWithoutCodeQL', '-RequireChecks', 'test')
    Check 'update: a ruleset with a code-scanning rule keeps it, whatever the default setup says (advanced setup runs CodeQL too)' ((@($r2.Body.rules.type) -contains 'code_scanning') -and $r2.Output -match 'keeps its code-scanning rule') "$(@($r2.Body.rules.type) -join ',') $($r2.Output)"
    $r3 = Invoke-Baseline @('-Repo', 'oursCodeQL404', '-RequireChecks', 'test')
    Check 'update: a 404 from the CodeQL setup doesn''t touch the rule a ruleset has' ((@($r3.Body.rules.type) -contains 'code_scanning') -and $r3.Output -match 'keeps its code-scanning rule') "$(@($r3.Body.rules.type) -join ',') $($r3.Output)"
    Check 'update: the ruleset keeps its code-scanning rule, with the same thresholds' (($scan.Count -eq 1) -and ($scan[0].alerts_threshold -eq 'errors') -and ($scan[0].security_alerts_threshold -eq 'medium_or_higher')) (@($r.Body.rules.type) -join ',')

    # 7. -All.
    $r = Invoke-Baseline @('-All')
    Check 'all: skips archived repositories and forks' (($r.Output -notmatch 'old') -and ($r.Output -notmatch 'forked') -and ($r.Output -match 'done: fresh') -and ($r.Output -match 'owned: left alone')) $r.Output

    # 8. Bad parameters.
    $r = Invoke-Baseline @()
    Check 'params: needs -Repo or -All' ($r.ExitCode -ne 0 -and $r.Output -match 'Pass -Repo <name> or -All') $r.Output
    $r = Invoke-Baseline @('-All', '-RequireChecks', 'test')
    Check 'params: -RequireChecks needs -Repo' ($r.ExitCode -ne 0 -and $r.Changes.Count -eq 0 -and $r.Output -match '-RequireChecks needs -Repo') $r.Output
    $r = Invoke-Baseline @('-Repo', 'fresh', '-Owner', 'someone')
    Check 'params: -Owner picks the owner of the repository' (($r.Changes -join '|') -like 'BODY POST repos/someone/fresh/rulesets*') ($r.Changes -join '|')
}
finally { $env:PATH = $savedPath }

''
if ($failures.Count) { "Kept the work folder: $Work"; "Repository baseline tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) {
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Work) { "Couldn't delete the work folder: $Work" }
}
'Repository baseline tests: PASSED'
exit 0
