<#
.SYNOPSIS
    Test that tools\Get-AdoptionChecklist.ps1 reports every row of docs/adopt.md's Checklist, and changes nothing.

.DESCRIPTION
    Runs the script against small git repositories, one adopted on GitHub, one private on GitHub and one on GitLab,
    with stand-ins for gh, glab, copier, gitsign, node and the three sibling scripts it runs with -WhatIf. A stand-in
    answers by the exact command line (its base name, then its arguments joined by single spaces) from a JSON file the
    suite writes per run, and records every command line in a log. Checks the frame: that the rows match the
    Checklist table of docs/adopt.md, which rows apply to each repository, the summary line and the exit code, and that
    a folder that isn't adopted fails. Each row's check has its own checks below the frame.
    Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-adoption-checklist-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-AdoptionChecklist.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-adoption-checklist-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
$Work = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Work)
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Write-Text([string]$Path, [string]$Text) {
    $folder = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Force $folder | Out-Null }
    [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n"))
}

if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$bin = Join-Path $Work 'bin'
$tools = Join-Path $Work 'tools'
New-Item -ItemType Directory -Force $bin, $tools | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'tools/Get-AdoptionChecklist.ps1') -Destination $tools

# The stand-in for gh, glab, copier, gitsign, node and the three sibling scripts. It answers by its command line (its
# base name, then its arguments joined by single spaces) from the JSON at ADOPTION_CHECKLIST_DATA (each key: out, the
# lines it prints; err, what it writes to the error stream; exit, its exit code), and appends the line to the log at
# ADOPTION_CHECKLIST_LOG.
$standIn = @'
# The script runs this in its own session, so a -WhatIf run would reach it as $WhatIfPreference, and its log would stay
# empty: it has to record the calls of a -WhatIf run too, to show that they change nothing.
$WhatIfPreference = $false
$key = (@([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) + @($args | ForEach-Object { "$_" })) -join ' '
Add-Content -LiteralPath $env:ADOPTION_CHECKLIST_LOG -Value $key
$data = Get-Content -Raw -LiteralPath $env:ADOPTION_CHECKLIST_DATA | ConvertFrom-Json -AsHashtable
if (-not $data.ContainsKey($key)) {
    Write-Error -Message "stand-in: no answer for $key" -ErrorAction Continue
    exit 99
}
$answer = $data[$key]
foreach ($line in @($answer.out)) { $line }
if ($answer.err) { Write-Error -Message $answer.err -ErrorAction Continue }
exit ([int]$answer.exit)
'@
foreach ($name in 'gh', 'glab', 'copier', 'gitsign', 'node') { Write-Text (Join-Path $bin "$name.ps1") $standIn }
foreach ($name in 'Set-RepositoryBaseline', 'Dismiss-ScorecardAlerts', 'Set-GitLabBaseline') {
    Write-Text (Join-Path $tools "$name.ps1") $standIn
}

# A stand-in's answer: the lines it prints, its exit code and what it writes to the error stream.
function Answer($Out, [int]$Exit = 0, [string]$Err = '') {
    @{ out = $(if ($null -eq $Out) { @() } else { @($Out) }); exit = $Exit; err = $Err }
}
function Json($Object) { ConvertTo-Json -Compress -Depth 10 -InputObject $Object }

function Invoke-Git([string]$Folder, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    & git -C $Folder @Arguments 2>&1 | Out-Null
    if ($LASTEXITCODE) { throw "git $($Arguments -join ' ') failed in $Folder" }
}

# A git repository on main with the files, one commit per subject (the first holds the files, the later ones are
# empty), the tags on the last commit and the origin remote.
function New-Fixture([string]$Folder, [hashtable]$Files, [string[]]$Subjects, [string]$Origin = '', [string[]]$Tags = @()) {
    New-Item -ItemType Directory -Force $Folder | Out-Null
    Invoke-Git $Folder @('init', '-q', '-b', 'main')
    Invoke-Git $Folder @('config', 'user.name', 'Test')
    Invoke-Git $Folder @('config', 'user.email', 'test@example.com')
    Invoke-Git $Folder @('config', 'commit.gpgsign', 'false')
    Invoke-Git $Folder @('config', 'tag.gpgsign', 'false')
    foreach ($relative in $Files.Keys) { Write-Text (Join-Path $Folder $relative) $Files[$relative] }
    Invoke-Git $Folder @('add', '-A')
    foreach ($subject in $Subjects) { Invoke-Git $Folder @('commit', '-q', '--allow-empty', '-m', $subject) }
    foreach ($tag in $Tags) { Invoke-Git $Folder @('tag', $tag) }
    if ($Origin) { Invoke-Git $Folder @('remote', 'add', 'origin', $Origin) }
}

$dataFile = Join-Path $Work 'data.json'
$logFile = Join-Path $Work 'calls.log'
# Every command line the stand-ins got, over all runs.
$allCalls = [Collections.Generic.List[string]]::new()
# A run: the script's output and exit code, and every command line the stand-ins got.
function Invoke-Checklist([string]$Fixture, [hashtable]$Calls) {
    Write-Text $dataFile (Json $Calls)
    if (Test-Path -LiteralPath $logFile) { Remove-Item -LiteralPath $logFile -Force }
    $env:ADOPTION_CHECKLIST_DATA = $dataFile
    $env:ADOPTION_CHECKLIST_LOG = $logFile
    $output = & pwsh -NoProfile -File (Join-Path $tools 'Get-AdoptionChecklist.ps1') -Path $Fixture 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $log = if (Test-Path -LiteralPath $logFile) { @(Get-Content -LiteralPath $logFile) } else { @() }
    foreach ($line in $log) { $allCalls.Add("$line") }
    [pscustomobject]@{ Output = $output; ExitCode = $exitCode; Log = $log }
}
# A run with the answers of $calls changed: a key set to another answer.
function Invoke-Override([string]$Fixture, [hashtable]$Changes) {
    $changed = $calls.Clone()
    foreach ($key in $Changes.Keys) { $changed[$key] = $Changes[$key] }
    Invoke-Checklist $Fixture $changed
}
# A row's status in a run's output; $null when the row has no line.
function Get-Status($Run, [string]$Step) {
    $m = [regex]::Match($Run.Output, "(?m)^$([regex]::Escape($Step)) .+?: (done|not done|unreadable|does not apply)(?: \(|\r?$)")
    if ($m.Success) { $m.Groups[1].Value }
}
# The steps of a run's row lines, in order.
function Get-Steps($Run) {
    @([regex]::Matches($Run.Output, '(?m)^(\d\.\d) ') | ForEach-Object { $_.Groups[1].Value })
}
# The steps of a run whose rows apply.
function Get-Applying($Run) {
    @(Get-Steps $Run | Where-Object { (Get-Status $Run $_) -ne 'does not apply' })
}

# Fixtures
$template = Join-Path $Work 'template'
New-Fixture $template @{ 'README.md' = 'template' } @('Template') '' @('v0.111.2', 'v0.111.3')

$githubFiles = @{
    '.copier-answers.yml' = @"
_commit: v0.111.3
_src_path: $template
git_host: github
code_review: true
nuget_package: true
uses_node: true
best_practices_project: '16752'
"@
    '.template-version' = 'v0.111.3'
    'AGENTS.md' = "# Agents`n`n## Landing`n`n- release: tag+release`n"
    '.github/workflows/copilot-setup-steps.yml' = "name: Copilot Setup Steps`non: workflow_dispatch`n"
    '.github/workflows/coverage.yml' = "name: Coverage`njobs:`n  upload:`n    steps:`n      - uses: codecov/codecov-action@v5`n"
    '.github/workflows/docs.yml' = "name: Docs`njobs:`n  deploy:`n    steps:`n      - uses: actions/deploy-pages@v4`n"
    '.github/workflows/code-review.yml' = @'
name: Code Review
jobs:
  review:
    steps:
      - with:
          approve: true
          approver-private-key: ${{ secrets.NCODE_REVIEW_APPROVER_PRIVATE_KEY }}
'@
    '.github/dependabot.yml' = "version: 2`n"
    '.node-version' = '26'
    'README.md' = "# Sample`n`n[![Best Practices](https://www.bestpractices.dev/projects/16752/badge)](https://www.bestpractices.dev/projects/16752)`n"
    'Directory.Build.props' = "<Project>`n  <PropertyGroup>`n    <PackageValidationBaselineVersion>1.0.0</PackageValidationBaselineVersion>`n  </PropertyGroup>`n</Project>`n"
}
New-Fixture (Join-Path $Work 'github') $githubFiles @('Create project from project-template v0.111.3') 'https://github.com/NCodeGroup/sample.git' @('v1.0.0')
# A fixture like github's, at $Work/<Name>: the files of $Changes set, or deleted where the value is $null, and the tags.
function New-GitHubVariant([string]$Name, [hashtable]$Changes, [string[]]$Tags = @('v1.0.0')) {
    $files = $githubFiles.Clone()
    foreach ($key in $Changes.Keys) {
        if ($null -eq $Changes[$key]) { $files.Remove($key) } else { $files[$key] = $Changes[$key] }
    }
    New-Fixture (Join-Path $Work $Name) $files @('Create project from project-template v0.111.3') 'https://github.com/NCodeGroup/sample.git' $Tags
}

New-Fixture (Join-Path $Work 'private') @{
    '.copier-answers.yml' = @"
_commit: v0.111.2
_src_path: $template
git_host: github
code_review: false
nuget_package: false
uses_node: false
"@
    '.template-version' = 'v0.111.2'
    'AGENTS.md' = "# Agents`n`n## Landing`n`n- release: none`n"
} @('Initial commit', 'Adopt project-template v0.111.2') 'https://github.com/someone/private-sample.git'

New-Fixture (Join-Path $Work 'gitlab') @{
    '.copier-answers.yml' = @"
_commit: v0.111.3
_src_path: $template
git_host: gitlab
nuget_package: true
uses_node: true
"@
    '.template-version' = 'v0.111.3'
    'AGENTS.md' = "# Agents`n`n## Landing`n`n- release: none`n"
    '.node-version' = '24'
} @('Create project from project-template v0.111.3') 'https://gitlab.com/group/sub/sample.git' @('v1.2.0')

New-Fixture (Join-Path $Work 'bare') @{ 'README.md' = '# Bare' } @('Initial commit')

New-GitHubVariant 'blank' @{
    'AGENTS.md' = "# Agents`n`n## Landing`n`n- release:`n- changelog: CHANGELOG.md`n"
    '.github/workflows/code-review.yml' = "name: Code Review`njobs:`n  review:`n    steps:`n      - with:`n          approve: true`n          approver-private-key:`n          model: sonnet`n"
    '.github/workflows/coverage.yml' = $null
    '.github/workflows/empty.yml' = ''
}

New-GitHubVariant 'publisher' @{ '.copier-answers.yml' = "$($githubFiles['.copier-answers.yml'])`nnuget_publisher: publish-nuget.yml`n" }

New-GitHubVariant 'noemail' @{}
Invoke-Git (Join-Path $Work 'noemail') @('config', '--unset', 'user.email')

New-GitHubVariant 'prestable' @{} @('v0.9.0', 'v1.0.0-rc.1')

New-Fixture (Join-Path $Work 'untagged') @{ 'README.md' = 'untagged' } @('Untagged')
$answers = $githubFiles['.copier-answers.yml']
New-GitHubVariant 'shorthand' @{ '.copier-answers.yml' = $answers.Replace("_src_path: $template", '_src_path: gh:NCodeGroup/project-template.git') }
New-GitHubVariant 'oldaddress' @{ '.copier-answers.yml' = $answers.Replace("_src_path: $template", '_src_path: https://github.com/polewskm/project-template').Replace('_commit: v0.111.3', '_commit: v0.111.2-3-gabc1234'); '.template-version' = $null }
New-GitHubVariant 'notags' @{ '.copier-answers.yml' = $answers.Replace("_src_path: $template", "_src_path: $(Join-Path $Work 'untagged')") }
New-GitHubVariant 'badsource' @{ '.copier-answers.yml' = $answers.Replace("_src_path: $template", "_src_path: $(Join-Path $Work 'missing-template')") }
New-GitHubVariant 'noversion' @{ '.copier-answers.yml' = $answers.Replace('_commit: v0.111.3', '_commit: 1a2b3c4'); '.template-version' = $null }
New-GitHubVariant 'nosourceanswer' @{ '.copier-answers.yml' = $answers -replace '(?m)^_src_path: .*\r?\n', '' }

# Answers
$calls = @{
    'gh api repos/NCodeGroup/sample' = Answer (Json @{ visibility = 'public'; default_branch = 'main'; owner = @{ type = 'Organization' } })
    'gh api repos/someone/private-sample' = Answer (Json @{ visibility = 'private'; default_branch = 'main'; owner = @{ type = 'User' } })
    'gh auth status' = Answer $null
    'glab auth status --hostname gitlab.com' = Answer $null
    'copier --version' = Answer 'copier 9.4.1'
    'node --version' = Answer 'v26.1.0'
    'glab api --hostname gitlab.com projects/group%2Fsub%2Fsample' = Answer '{}'
    'Set-RepositoryBaseline -Repo sample -Owner NCodeGroup -WhatIf' = Answer @(
        'sample: allow auto-merge: already set'
        'sample: immutable releases: already set'
        'sample: organization two-factor requirement: required')
    'Set-RepositoryBaseline -OrganizationPolicy -Owner NCodeGroup -WhatIf' = Answer 'NCodeGroup: default workflow token read-only, and Actions not approving pull requests: already set'
    'Dismiss-ScorecardAlerts -Repo NCodeGroup/sample -WhatIf' = Answer 'NCodeGroup/sample: no open Scorecard alert'
    'Set-RepositoryBaseline -Repo private-sample -Owner someone -WhatIf' = Answer 'private-sample: allow auto-merge: would set'
    'gh api repos/NCodeGroup/sample/rules/branches/main' = Answer (Json @(@{ type = 'pull_request'; parameters = @{ required_approving_review_count = 1 } }))
    'gh secret list --env code-review --repo NCodeGroup/sample --json name' = Answer (Json @(@{ name = 'NCODE_REVIEW_APPROVER_PRIVATE_KEY' }))
    'gh api repos/NCodeGroup/sample/code-scanning/default-setup' = Answer (Json @{ state = 'configured'; languages = @('csharp', 'actions') })
    'gh secret list --org NCodeGroup --json name' = Answer (Json @(@{ name = 'NCODE_REVIEW_APP_PRIVATE_KEY' }, @{ name = 'AWS_BEARER_TOKEN_BEDROCK' }))
    'gh api repos/someone/private-sample/rules/branches/main' = Answer (Json @(@{ type = 'pull_request'; parameters = @{ required_approving_review_count = 1 } }))
    'gh api repos/someone/private-sample/code-scanning/default-setup' = Answer (Json @{ state = 'not-configured'; languages = @() })
    'gh pr list --repo NCodeGroup/sample --state merged --limit 20 --json number,author' = Answer (Json @(
            @{ number = 13; author = @{ login = 'app/dependabot'; is_bot = $true } },
            @{ number = 12; author = @{ login = 'maintainer'; is_bot = $false } }))
    'gh pr checks 13 --repo NCodeGroup/sample --json name,bucket' = Answer (Json @(
            @{ name = 'build-and-test'; bucket = 'pass' }, @{ name = 'Code review'; bucket = 'skipping' }))
    'gh api repos/NCodeGroup/sample/pulls/12/reviews?per_page=100' = Answer (Json @(
            @{ user = @{ login = 'ncode-review[bot]' }; state = 'COMMENTED' },
            @{ user = @{ login = 'ncode-review-approver[bot]' }; state = 'APPROVED' }))
    'gh run list --repo NCodeGroup/sample --workflow tag-release.yml --limit 1 --json conclusion,status' = Answer (Json @(@{ conclusion = 'success'; status = 'completed' }))
    'gh run list --repo NCodeGroup/sample --workflow copilot-setup-steps.yml --limit 1 --json conclusion,status' = Answer (Json @(@{ conclusion = 'success'; status = 'completed' }))
    'gh release view --repo NCodeGroup/sample --json tagName,assets' = Answer (Json @{
            tagName = 'v1.0.0'
            assets = @(@{ name = 'Sample.1.0.0.nupkg' }, @{ name = 'Sample.1.0.0.snupkg' }, @{ name = 'v1.0.0.intoto.jsonl' }, @{ name = 'v1.0.0.spdx.json' })
        })
    'gitsign verify-tag --certificate-identity https://github.com/NCodeGroup/sample/.github/workflows/tag-release.yml@refs/heads/main --certificate-oidc-issuer https://token.actions.githubusercontent.com v1.0.0' = Answer $null
    'gh pr list --repo someone/private-sample --state merged --limit 20 --json number,author' = Answer '[]'
    'glab api --hostname gitlab.com projects/group%2Fsub%2Fsample/merge_requests?state=merged&order_by=updated_at&per_page=1' = Answer (Json @(@{ iid = 4 }))
    'glab api --hostname gitlab.com projects/group%2Fsub%2Fsample/merge_requests/4' = Answer (Json @{ head_pipeline = @{ status = 'failed' } })
    'gh api repos/NCodeGroup/sample/environments/nuget/deployment-branch-policies' = Answer (Json @{
            total_count = 2
            branch_policies = @(@{ name = 'main'; type = 'branch' }, @{ name = 'v*'; type = 'tag' })
        })
    'gh variable list --repo NCodeGroup/sample --json name' = Answer (Json @(@{ name = 'NUGET_USER' }))
    'gh run list --repo NCodeGroup/sample --workflow publish.yml --limit 1 --json conclusion,status' = Answer (Json @(@{ conclusion = 'success'; status = 'completed' }))
    'gh pr list --repo NCodeGroup/sample --head baseline-1.0.0 --state merged --json number' = Answer (Json @(@{ number = 14 }))
    'gh api repos/NCodeGroup/sample/pages' = Answer (Json @{ build_type = 'workflow'; cname = 'sample.ncode.io'; https_enforced = $true })
    'gh label list --repo NCodeGroup/sample --json name --limit 500' = Answer (Json @(@{ name = 'documentation' }, @{ name = 'follow-up' }))
    'gh label list --repo someone/private-sample --json name --limit 500' = Answer (Json @(@{ name = 'bug' }))
    "Set-GitLabBaseline -Path $((Resolve-Path -LiteralPath (Join-Path $Work 'gitlab')).ProviderPath) -WhatIf -BaselineToken" = Answer @(
        'group/sub/sample: All threads must be resolved: already set'
        'group/sub/sample: protect the tags v*: would set')
}

# Git reads only this config: the PC's user.email never answers row 0.1, and the template's GitHub address reads the local template, so 7.1's address rewrites need no network.
$gitConfig = Join-Path $Work 'gitconfig'
Invoke-Git $Work @('config', '--file', $gitConfig, "url.$template.insteadOf", 'https://github.com/NCodeGroup/project-template.git')
$savedGitGlobal = $env:GIT_CONFIG_GLOBAL
$env:GIT_CONFIG_GLOBAL = $gitConfig
$savedGitNoSystem = $env:GIT_CONFIG_NOSYSTEM
$env:GIT_CONFIG_NOSYSTEM = '1'
$savedPath = $env:PATH
$env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
$savedNvsHome = $env:NVS_HOME
$env:NVS_HOME = Join-Path $Work 'nvs'
try {
    $stray = @('gh', 'glab', 'copier', 'gitsign', 'node' | Where-Object { $found = (Get-Command $_ -ErrorAction SilentlyContinue | Select-Object -First 1).Source; -not $found -or (Split-Path -Parent $found) -ne $bin })
    Check 'stand-ins: gh, glab, copier, gitsign and node run from the suite bin' ($stray.Count -eq 0) "not from ${bin}: $($stray -join ', ')"

    # Runs
    $gh = Invoke-Checklist (Join-Path $Work 'github') $calls
    $pr = Invoke-Checklist (Join-Path $Work 'private') $calls
    $gl = Invoke-Checklist (Join-Path $Work 'gitlab') $calls

    # Checks
    $adopt = Get-Content -LiteralPath (Join-Path $repoRoot 'docs/adopt.md') -Raw
    $section = ($adopt -split '(?m)^## 8\. Checklist\s*$', 2)[1]
    $section = ($section -split '(?m)^## ', 2)[0]
    $documented = @([regex]::Matches($section, '(?m)^\| \[(\d\.\d)\]\(') | ForEach-Object { $_.Groups[1].Value })
    $listed = Get-Steps $gh
    Check 'frame: the rows match docs/adopt.md''s checklist' ($documented.Count -eq 34 -and ($listed -join ',') -eq ($documented -join ',')) "documented=$($documented -join ',') listed=$($listed -join ',')"

    $expected = @($documented | Where-Object { $_ -notin '1.2', '2.5' })
    Check 'frame: github applies every row but 1.2 and 2.5' ((Get-Applying $gh) -join ',' -eq ($expected -join ',')) "applies=$((Get-Applying $gh) -join ',') output=$($gh.Output)"

    $expected = '0.1', '1.2', '1.4', '2.1', '2.2', '2.3', '6.1', '6.5', '7.1', '7.2'
    Check 'frame: private applies only 0.1, 1.2, 1.4, 2.1, 2.2, 2.3, 6.1, 6.5, 7.1 and 7.2' ((Get-Applying $pr) -join ',' -eq ($expected -join ',')) "applies=$((Get-Applying $pr) -join ',') output=$($pr.Output)"

    $expected = '0.1', '1.1', '1.3', '1.4', '2.5', '4.3', '7.1'
    Check 'frame: gitlab applies only 0.1, 1.1, 1.3, 1.4, 2.5, 4.3 and 7.1' ((Get-Applying $gl) -join ',' -eq ($expected -join ',')) "applies=$((Get-Applying $gl) -join ',') output=$($gl.Output)"

    Check 'frame: github ends with its count and exits 0' ($gh.ExitCode -eq 0 -and $gh.Output -match '(?m)^NCodeGroup/sample: \d+ done, 0 not done, \d+ unreadable, 2 do not apply\r?$') "exit=$($gh.ExitCode) output=$($gh.Output)"

    $bare = Invoke-Checklist (Join-Path $Work 'bare') $calls
    Check 'frame: a folder without .copier-answers.yml fails' ($bare.ExitCode -eq 1 -and $bare.Output -match [regex]::Escape('.copier-answers.yml')) "exit=$($bare.ExitCode) output=$($bare.Output)"

    # Rows a clone shows: 0.1, 1.1, 1.2, 1.3, 4.3, 6.1, 7.1
    foreach ($row in @(
            @('0.1', 'done', 'github', $gh), @('1.1', 'done', 'github', $gh), @('1.3', 'done', 'github', $gh),
            @('4.3', 'done', 'github', $gh), @('6.1', 'done', 'github', $gh), @('7.1', 'done', 'github', $gh),
            @('1.2', 'done', 'private', $pr), @('6.1', 'not done', 'private', $pr), @('7.1', 'not done', 'private', $pr),
            @('0.1', 'done', 'gitlab', $gl), @('1.1', 'done', 'gitlab', $gl), @('1.3', 'not done', 'gitlab', $gl),
            @('4.3', 'not done', 'gitlab', $gl))) {
        $step, $want, $label, $run = $row
        Check "row $step ${want}: $label" ((Get-Status $run $step) -eq $want) "status=$(Get-Status $run $step) output=$($run.Output)"
    }
    Check 'row 6.1 not done: private exits 1' ($pr.ExitCode -eq 1) "exit=$($pr.ExitCode) output=$($pr.Output)"
    Check 'row 1.3 not done: gitlab names Initialize-Nvs.ps1' ($gl.Output -match '(?m)^1\.3 .+Initialize-Nvs\.ps1') "output=$($gl.Output)"
    $nvsHome = Join-Path $Work 'nvs-home'
    Write-Text (Join-Path $nvsHome 'nvs.ps1') '# nvs'
    New-Item -ItemType Directory -Force (Join-Path $nvsHome 'node/24.3.0/x64') | Out-Null
    $env:NVS_HOME = $nvsHome
    $nvsRun = Invoke-Checklist (Join-Path $Work 'gitlab') $calls
    $env:NVS_HOME = Join-Path $Work 'nvs'
    Check 'row 1.3 done: gitlab with nvs''s 24.3.0' ((Get-Status $nvsRun '1.3') -eq 'done' -and $nvsRun.Output -match '(?m)^1\.3 .+24\.3\.0') "status=$(Get-Status $nvsRun '1.3') output=$($nvsRun.Output)"

    # Rows the baseline and Scorecard runs show: 0.2, 2.1, 2.4, 3.3
    $bad = Invoke-Override (Join-Path $Work 'github') @{
        'Set-RepositoryBaseline -Repo sample -Owner NCodeGroup -WhatIf' = Answer @(
            'sample: immutable releases: would set'
            'sample: organization two-factor requirement: not required')
        'Dismiss-ScorecardAlerts -Repo NCodeGroup/sample -WhatIf' = Answer '#8 (Branch-Protection): would dismiss'
    }
    $broken = Invoke-Override (Join-Path $Work 'github') @{
        'Set-RepositoryBaseline -Repo sample -Owner NCodeGroup -WhatIf' = Answer $null 1 'gh: Not Found (HTTP 404)'
        'Set-RepositoryBaseline -OrganizationPolicy -Owner NCodeGroup -WhatIf' = Answer $null 1 'gh: Not Found (HTTP 404)'
        'Dismiss-ScorecardAlerts -Repo NCodeGroup/sample -WhatIf' = Answer $null 1 'gh: Forbidden (HTTP 403)'
    }
    foreach ($row in @(
            @('0.2', 'done', 'github', $gh), @('2.1', 'done', 'github', $gh), @('2.4', 'done', 'github', $gh),
            @('3.3', 'done', 'github', $gh), @('2.1', 'not done', 'private', $pr),
            @('2.1', 'not done', 'bad', $bad), @('3.3', 'not done', 'bad', $bad), @('0.2', 'not done', 'bad', $bad),
            @('2.4', 'not done', 'bad', $bad),
            @('2.1', 'unreadable', 'broken', $broken), @('3.3', 'unreadable', 'broken', $broken),
            @('0.2', 'unreadable', 'broken', $broken), @('2.4', 'unreadable', 'broken', $broken))) {
        $step, $want, $label, $run = $row
        Check "row $step ${want}: $label" ((Get-Status $run $step) -eq $want) "status=$(Get-Status $run $step) output=$($run.Output)"
    }

    # Rows the approval, CodeQL and NCode Review secrets show: 2.2, 5.2, 2.3, 5.1, 0.3
    $nokey = Invoke-Override (Join-Path $Work 'github') @{
        'gh secret list --env code-review --repo NCodeGroup/sample --json name' = Answer $null 1 'gh: Not Found (HTTP 404)'
        'gh api repos/NCodeGroup/sample/collaborators?affiliation=all&permission=push&per_page=100' = Answer (Json @(@{ login = 'a'; type = 'User' }, @{ login = 'b'; type = 'Bot' }))
        'gh secret list --org NCodeGroup --json name' = Answer $null 1 'gh: Forbidden (HTTP 403)'
    }
    foreach ($row in @(
            @('2.2', 'done', 'github', $gh), @('5.2', 'done', 'github', $gh), @('2.3', 'done', 'github', $gh),
            @('5.1', 'done', 'github', $gh), @('0.3', 'done', 'github', $gh),
            @('2.2', 'not done', 'private', $pr), @('2.3', 'not done', 'private', $pr),
            @('5.1', 'not done', 'nokey', $nokey), @('2.2', 'not done', 'nokey', $nokey),
            @('0.3', 'unreadable', 'nokey', $nokey))) {
        $step, $want, $label, $run = $row
        Check "row $step ${want}: $label" ((Get-Status $run $step) -eq $want) "status=$(Get-Status $run $step) output=$($run.Output)"
    }

    # Rows the pull request, run and tag show: 1.4, 3.1, 3.2, 5.3, 5.4, 6.4
    $failing = Invoke-Override (Join-Path $Work 'github') @{
        'gh pr checks 13 --repo NCodeGroup/sample --json name,bucket' = Answer (Json @(
                @{ name = 'build-and-test'; bucket = 'fail' }, @{ name = 'Code review'; bucket = 'skipping' }))
        'gh api repos/NCodeGroup/sample/pulls/12/reviews?per_page=100' = Answer (Json @(
                @{ user = @{ login = 'ncode-review[bot]' }; state = 'COMMENTED' }))
        'gh run list --repo NCodeGroup/sample --workflow tag-release.yml --limit 1 --json conclusion,status' = Answer (Json @(@{ conclusion = 'failure'; status = 'completed' }))
        'gitsign verify-tag --certificate-identity https://github.com/NCodeGroup/sample/.github/workflows/tag-release.yml@refs/heads/main --certificate-oidc-issuer https://token.actions.githubusercontent.com v1.0.0' = Answer $null 1 'no matching signature'
    }
    foreach ($row in @(
            @('1.4', 'done', 'github', $gh), @('3.1', 'done', 'github', $gh), @('3.2', 'done', 'github', $gh),
            @('5.3', 'done', 'github', $gh), @('5.4', 'done', 'github', $gh), @('6.4', 'done', 'github', $gh),
            @('1.4', 'not done', 'private', $pr), @('1.4', 'not done', 'gitlab', $gl),
            @('1.4', 'not done', 'failing', $failing), @('5.3', 'not done', 'failing', $failing),
            @('5.4', 'not done', 'failing', $failing), @('3.1', 'not done', 'failing', $failing),
            @('3.2', 'not done', 'failing', $failing))) {
        $step, $want, $label, $run = $row
        Check "row $step ${want}: $label" ((Get-Status $run $step) -eq $want) "status=$(Get-Status $run $step) output=$($run.Output)"
    }

    # Rows the NuGet setup shows: 4.1, 4.2, 4.4, 4.5, 4.6, 4.7
    $unpublished = Invoke-Override (Join-Path $Work 'github') @{
        'gh api repos/NCodeGroup/sample/environments/nuget/deployment-branch-policies' = Answer $null 1 'gh: Not Found (HTTP 404)'
        'gh run list --repo NCodeGroup/sample --workflow publish.yml --limit 1 --json conclusion,status' = Answer (Json @(@{ conclusion = 'startup_failure'; status = 'completed' }))
        'gh pr list --repo NCodeGroup/sample --head baseline-1.0.0 --state merged --json number' = Answer '[]'
        'gh release view --repo NCodeGroup/sample --json tagName,assets' = Answer (Json @{
                tagName = 'v1.0.0'
                assets = @(@{ name = 'Sample.1.0.0.nupkg' }, @{ name = 'Sample.1.0.0.snupkg' }, @{ name = 'v1.0.0.intoto.jsonl' })
            })
    }
    foreach ($row in @(
            @('4.1', 'unreadable', 'github', $gh), @('4.2', 'done', 'github', $gh), @('4.4', 'done', 'github', $gh),
            @('4.5', 'done', 'github', $gh), @('4.6', 'done', 'github', $gh), @('4.7', 'done', 'github', $gh),
            @('4.2', 'not done', 'unpublished', $unpublished), @('4.4', 'not done', 'unpublished', $unpublished),
            @('4.5', 'not done', 'unpublished', $unpublished), @('4.6', 'not done', 'unpublished', $unpublished),
            @('4.7', 'not done', 'unpublished', $unpublished))) {
        $step, $want, $label, $run = $row
        Check "row $step ${want}: $label" ((Get-Status $run $step) -eq $want) "status=$(Get-Status $run $step) output=$($run.Output)"
    }
    Check 'row 4.1 unreadable: github names the trusted publishing page' ($gh.Output -match '(?m)^4\.1 .+nuget\.org/account/trustedpublishing') "output=$($gh.Output)"

    # The remaining rows: 2.5, 6.2, 6.3, 6.5, 7.2, 7.3
    foreach ($row in @(
            @('6.2', 'unreadable', 'github', $gh), @('6.3', 'done', 'github', $gh), @('6.5', 'done', 'github', $gh),
            @('7.2', 'unreadable', 'github', $gh), @('7.3', 'unreadable', 'github', $gh),
            @('6.5', 'not done', 'private', $pr), @('7.2', 'not done', 'private', $pr),
            @('2.5', 'not done', 'gitlab', $gl))) {
        $step, $want, $label, $run = $row
        Check "row $step ${want}: $label" ((Get-Status $run $step) -eq $want) "status=$(Get-Status $run $step) output=$($run.Output)"
    }
    Check 'row 7.3 every row checked: github' ($gh.Output -notmatch 'no check for this row yet' -and $gh.Output -match '(?m)^NCodeGroup/sample: 28 done, 0 not done, 4 unreadable, 2 do not apply\r?$') "output=$($gh.Output)"
    # Values left blank, and an empty workflow file: 3.1, 5.1, 6.2
    $blank = Invoke-Checklist (Join-Path $Work 'blank') $calls
    Check 'row 3.1 does not apply: blank reads release: none' ($blank.Output -match '(?m)^3\.1 .+: does not apply \(AGENTS\.md.s Landing says release: none\)') "output=$($blank.Output)"
    foreach ($row in @(@('5.1', 'not done', 'blank', $blank), @('6.2', 'does not apply', 'blank', $blank))) {
        $step, $want, $label, $run = $row
        Check "row $step ${want}: $label" ((Get-Status $run $step) -eq $want) "status=$(Get-Status $run $step) output=$($run.Output)"
    }
    # Branch rules: none that requires a pull request, and two pull request rules: 2.2, 5.2
    $noRule = Invoke-Override (Join-Path $Work 'github') @{ 'gh api repos/NCodeGroup/sample/rules/branches/main' = Answer '[]' }
    $twoRules = Invoke-Override (Join-Path $Work 'github') @{ 'gh api repos/NCodeGroup/sample/rules/branches/main' = Answer (Json @(@{ type = 'pull_request'; parameters = @{ required_approving_review_count = 0 } }, @{ type = 'pull_request'; parameters = @{ required_approving_review_count = 1 } })) }
    Check 'row 2.2 not done: norule names the missing rule' ($noRule.Output -match '(?m)^2\.2 .+: not done \(no rule requires a pull request on main\)') "output=$($noRule.Output)"
    Check 'row 5.2 not done: norule names the missing rule' ($noRule.Output -match '(?m)^5\.2 .+: not done \(no rule requires a pull request on main\)') "output=$($noRule.Output)"
    Check 'row 2.2 done: tworules takes the strictest rule' ((Get-Status $twoRules '2.2') -eq 'done') "output=$($twoRules.Output)"
    Check 'row 5.2 done: tworules takes the strictest rule' ((Get-Status $twoRules '5.2') -eq 'done') "output=$($twoRules.Output)"
    # Section 4 with nuget_publisher set
    $publisher = Invoke-Checklist (Join-Path $Work 'publisher') $calls
    foreach ($row in @(
            @('4.1', 'does not apply', 'publisher', $publisher), @('4.2', 'does not apply', 'publisher', $publisher),
            @('4.3', 'done', 'publisher', $publisher), @('4.4', 'does not apply', 'publisher', $publisher),
            @('4.5', 'does not apply', 'publisher', $publisher), @('4.6', 'does not apply', 'publisher', $publisher),
            @('4.7', 'does not apply', 'publisher', $publisher))) {
        $step, $want, $label, $run = $row
        Check "row $step ${want}: $label" ((Get-Status $run $step) -eq $want) "status=$(Get-Status $run $step) output=$($run.Output)"
    }
    Check 'publisher: section 4 names nuget_publisher' ($publisher.Output -match '(?m)^4\.4 .+: does not apply \(.*nuget_publisher') "output=$($publisher.Output)"
    # Row 0.1 with gh signed out, no copier and no user.email
    $signedOut = Invoke-Override (Join-Path $Work 'noemail') @{
        'gh auth status' = Answer $null 1 'You are not logged into any GitHub hosts.'
        'copier --version' = Answer $null 1 'No module named copier'
    }
    Check 'row 0.1 not done: signedout' ((Get-Status $signedOut '0.1') -eq 'not done') "output=$($signedOut.Output)"
    Check 'signedout: row 0.1 names gh, copier and user.email' ($signedOut.Output -match '(?m)^0\.1 .+gh isn.t signed in; copier: No module named copier; git has no user\.email') "output=$($signedOut.Output)"
    # Only a 0.x tag and a prerelease tag: 4.3, 4.6
    $prestable = Invoke-Checklist (Join-Path $Work 'prestable') $calls
    Check 'row 4.3 done: prestable has no stable release' ($prestable.Output -match '(?m)^4\.3 .+: done \(no stable release yet') "output=$($prestable.Output)"
    Check 'row 4.6 done: prestable has no stable release' ($prestable.Output -match '(?m)^4\.6 .+: done \(no stable release yet') "output=$($prestable.Output)"
    # Row 7.1's address rewrites and failures
    $shorthand = Invoke-Checklist (Join-Path $Work 'shorthand') $calls
    $oldAddress = Invoke-Checklist (Join-Path $Work 'oldaddress') $calls
    $noTags = Invoke-Checklist (Join-Path $Work 'notags') $calls
    $badSource = Invoke-Checklist (Join-Path $Work 'badsource') $calls
    $noVersion = Invoke-Checklist (Join-Path $Work 'noversion') $calls
    $noSourceAnswer = Invoke-Checklist (Join-Path $Work 'nosourceanswer') $calls
    foreach ($row in @(
            @('done', 'shorthand', $shorthand, 'on v0\.111\.3'),
            @('not done', 'oldaddress', $oldAddress, 'v0\.111\.3 is out; the project is on v0\.111\.2'),
            @('unreadable', 'notags', $noTags, '.+ has no version tags'),
            @('unreadable', 'badsource', $badSource, 'couldn.t read the template.s tags'),
            @('unreadable', 'noversion', $noVersion, 'can.t read the project.s template version'),
            @('unreadable', 'nosourceanswer', $noSourceAnswer, '\.copier-answers\.yml has no _src_path'))) {
        $want, $label, $run, $detail = $row
        Check "row 7.1 ${want}: $label" ($run.Output -match "(?m)^7\.1 Template Updates: $want \($detail") "output=$($run.Output)"
    }
    $checkerText = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'tools/Get-AdoptionChecklist.ps1')
    $updateText = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'template/.template/Get-TemplateUpdate.ps1')
    $shared = @('''^v?(\d+(?:\.\d+){0,3})$''', '''^gh:(.+)$''', '''^gl:(.+)$''', '''^https://github\.com/polewskm/project-template(?:\.git)?/?$''', '''https://github.com/NCodeGroup/project-template.git''')
    $apart = @($shared | Where-Object { -not ($checkerText.Contains($_) -and $updateText.Contains($_)) })
    Check 'frame: 7.1 reads versions and addresses as Get-TemplateUpdate.ps1 does' ($apart.Count -eq 0) "not in both: $($apart -join ', ')"
    # Immutable releases not available or unknown, and the GitLab baseline failing or not available: 3.3, 2.5
    $limited = Invoke-Override (Join-Path $Work 'github') @{
        'Set-RepositoryBaseline -Repo sample -Owner NCodeGroup -WhatIf' = Answer @(
            'sample: allow auto-merge: already set'
            'sample: immutable releases: not available for this account'
            'sample: organization two-factor requirement: required')
    }
    $odd = Invoke-Override (Join-Path $Work 'github') @{
        'Set-RepositoryBaseline -Repo sample -Owner NCodeGroup -WhatIf' = Answer @(
            'sample: allow auto-merge: already set'
            'sample: immutable releases: pending'
            'sample: organization two-factor requirement: required')
    }
    $glKey = "Set-GitLabBaseline -Path $((Resolve-Path -LiteralPath (Join-Path $Work 'gitlab')).ProviderPath) -WhatIf -BaselineToken"
    $glBroken = Invoke-Override (Join-Path $Work 'gitlab') @{ $glKey = Answer $null 1 'glab: 401 Unauthorized' }
    $glLimited = Invoke-Override (Join-Path $Work 'gitlab') @{
        $glKey = Answer @('group/sub/sample: All threads must be resolved: already set', 'group/sub/sample: merge trains: not available on this tier')
    }
    foreach ($row in @(
            @('3.3', 'done', 'limited', $limited), @('3.3', 'unreadable', 'odd', $odd),
            @('2.5', 'unreadable', 'glbroken', $glBroken), @('2.5', 'unreadable', 'gllimited', $glLimited))) {
        $step, $want, $label, $run = $row
        Check "row $step ${want}: $label" ((Get-Status $run $step) -eq $want) "status=$(Get-Status $run $step) output=$($run.Output)"
    }
    # The calls of every run
    $reads = '^(?:gh api [^ ]+|gh auth status|gh (?:pr list|pr checks|run list|release view|secret list|variable list|label list) .+|glab auth status --hostname [^ ]+|glab api --hostname [^ ]+ [^ ]+|copier --version|node --version|gitsign verify-tag .+|(?:Set-RepositoryBaseline|Dismiss-ScorecardAlerts|Set-GitLabBaseline) .*-WhatIf(?: .*)?)\z'
    $writes = @($allCalls | Where-Object { $_ -cnotmatch $reads })
    Check 'read-only: every command line the stand-ins got is a read' ($allCalls.Count -gt 0 -and $writes.Count -eq 0) "not reads: $($writes -join '; ')"
}
finally {
    $env:PATH = $savedPath
    if ($null -eq $savedNvsHome) { Remove-Item Env:NVS_HOME -ErrorAction SilentlyContinue } else { $env:NVS_HOME = $savedNvsHome }
    if ($null -eq $savedGitGlobal) { Remove-Item Env:GIT_CONFIG_GLOBAL -ErrorAction SilentlyContinue } else { $env:GIT_CONFIG_GLOBAL = $savedGitGlobal }
    if ($null -eq $savedGitNoSystem) { Remove-Item Env:GIT_CONFIG_NOSYSTEM -ErrorAction SilentlyContinue } else { $env:GIT_CONFIG_NOSYSTEM = $savedGitNoSystem }
    Remove-Item Env:ADOPTION_CHECKLIST_DATA, Env:ADOPTION_CHECKLIST_LOG -ErrorAction SilentlyContinue
}

''
if ($failures.Count) { "Kept the work folder: $Work"; "Adoption checklist tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Adoption checklist tests: PASSED'
exit 0
