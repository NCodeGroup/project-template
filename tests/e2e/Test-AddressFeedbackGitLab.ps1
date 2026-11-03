<#
.SYNOPSIS
    Run /address-feedback end to end in headless Claude Code on a fixture GitLab merge request with a local origin and a
    glab stand-in, and check what it pushed and replied, and that its read-backs see the notes without the session footer.

.DESCRIPTION
    Makes the fixture project with New-FixtureProject in Fixture.ps1, with git_host gitlab, a local origin under a
    gitlab.com folder and the glab stand-in (glab.ps1), and opens a fixture merge request, !1 from add-farewell, that adds
    Get-Farewell. The merge request has a discussion from a developer that asks for a real fix, and an individual note
    from a reporter that asks a question. The stand-in appends a Claude Code cloud session's footer to every note it
    saves (footer.txt), so the checks show that the run reads each note back, edits out the footer with PUT, and replies
    in the discussion without it. It costs model usage, so Invoke-AllTests.ps1 doesn't run it; run it by hand. CI runs
    only its fixture setup (-SetupOnly), so a template change that breaks the fixture still fails CI. Prints PASS or FAIL
    per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated unless -CheckOnly. Defaults to project-template-address-feedback-gitlab-e2e
    in the temp folder.

.PARAMETER SetupOnly
    Build the fixture and check it, without calling a model.

.PARAMETER CheckOnly
    Check the fixture of an earlier run again, without building it or calling a model.

.PARAMETER Claude
    The Claude Code CLI. Defaults to claude.

.PARAMETER MaxBudgetUsd
    The most each claude call may spend, passed as --max-budget-usd. 0 passes nothing. Defaults to 30.

.EXAMPLE
    .\tests\e2e\Test-AddressFeedbackGitLab.ps1

.EXAMPLE
    .\tests\e2e\Test-AddressFeedbackGitLab.ps1 -SetupOnly
#>
[CmdletBinding()]
param(
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) 'project-template-address-feedback-gitlab-e2e'),
    [switch]$SetupOnly,
    [switch]$CheckOnly,
    [string]$Claude = 'claude',
    [double]$MaxBudgetUsd = 30
)
$ErrorActionPreference = 'Stop'
if ($SetupOnly -and $CheckOnly) { throw '-SetupOnly and -CheckOnly can''t be used together.' }
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [Collections.Generic.List[string]]::new()
. (Join-Path $PSScriptRoot 'Fixture.ps1')

$app = Join-Path $Work 'app'
$origin = Join-Path $Work 'gitlab.com/fixture/app.git'
$bin = Join-Path $Work 'bin'
$hostDir = Join-Path $bin 'host'
$head = 'add-farewell'
$mrUrl = 'https://gitlab.com/fixture/app/-/merge_requests/1'
$commandFile = Join-Path $app '.claude/commands/address-feedback.md'

if (-not $CheckOnly) {
    New-FixtureProject -RepoRoot $repoRoot -Work $Work -App $app -Origin $origin -Bin $bin -Data @{ git_host = 'gitlab' }

    Invoke-Git -C $app switch -q -c $head
    Write-Text (Join-Path $app 'src/Farewell.ps1') @'
function Get-Farewell {
    param([string]$Name)
    "Goodbye, $Name!"
}
'@
    Invoke-Git -C $app add src/Farewell.ps1
    Invoke-Git -C $app commit -q -m 'Add Get-Farewell'
    Write-Text (Join-Path $app 'tests/Test-Greeting.ps1') @'
. "$PSScriptRoot/../src/Greeting.ps1"
. "$PSScriptRoot/../src/Farewell.ps1"
if ((Get-Greeting -Name Ada) -ne 'Hello, Ada!') { 'FAIL  Get-Greeting -Name Ada'; exit 1 }
'PASS  Get-Greeting -Name Ada'
if ((Get-Farewell -Name Ada) -ne 'Goodbye, Ada!') { 'FAIL  Get-Farewell -Name Ada'; exit 1 }
'PASS  Get-Farewell -Name Ada'
exit 0
'@
    Invoke-Git -C $app add tests/Test-Greeting.ps1
    Invoke-Git -C $app commit -q -m 'Check Get-Farewell -Name Ada'
    # The merge request's branch reaches origin as main did, and the main checkout is back on main, as a person's would be.
    Invoke-Git --git-dir=$origin fetch -q $app "${head}:$head"
    Invoke-Git -C $app switch -q main
    Invoke-Git -C $app branch -q -D $head
    Invoke-Git -C $app fetch -q origin
    $headOid = "$(git --git-dir=$origin rev-parse $head)".Trim()

    $mrs = @(
        @{
            iid = 1; title = 'Add Get-Farewell'; state = 'opened'; draft = $false; web_url = $mrUrl
            description = "Adds ``Get-Farewell``.`n"
            source_branch = $head; target_branch = 'main'; sha = $headOid; source_project_id = 1; target_project_id = 1
        }
    )
    $discussions = @(
        @{
            id = 'd-writer'; mr = 1; individual_note = $false
            notes = @(@{
                    id = 4001; author = @{ id = 2; username = 'ada-writer' }; system = $false; resolvable = $true; resolved = $false
                    body = 'With no name, or an empty one, this says `Goodbye, !`. Please make it say `Goodbye, world!` in both cases, and check both in `tests/Test-Greeting.ps1`.'
                })
        },
        @{
            id = 'd-question'; mr = 1; individual_note = $true
            notes = @(@{
                    id = 4002; author = @{ id = 3; username = 'grace-reader' }; system = $false; resolvable = $false; resolved = $false
                    body = 'Question: is `Get-Farewell` called anywhere yet, apart from the test?'
                })
        }
    )
    $members = @{
        '1' = @{ id = 1; username = 'fixture-owner'; access_level = 50 }
        '2' = @{ id = 2; username = 'ada-writer'; access_level = 30 }
        '3' = @{ id = 3; username = 'grace-reader'; access_level = 10 }
    }
    Write-Text (Join-Path $hostDir 'mrs.json') (ConvertTo-Json -InputObject $mrs -Depth 10)
    Write-Text (Join-Path $hostDir 'discussions.json') (ConvertTo-Json -InputObject $discussions -Depth 10)
    Write-Text (Join-Path $hostDir 'members.json') (ConvertTo-Json -InputObject $members -Depth 10)
    Write-Text (Join-Path $hostDir 'footer.txt') '_Generated by [Claude Code](https://claude.ai/code/session_01AbCdEf)_'

    # The self-checks below call the stand-in, which changes its state: they run on a copy that is put back afterwards.
    $saved = @{}
    foreach ($file in Get-ChildItem -LiteralPath $hostDir -File) { $saved[$file.Name] = [IO.File]::ReadAllText($file.FullName) }
    Use-FixtureEnvironment $Work $bin {
        # The setup checks go here.
    }
    Remove-Item -LiteralPath $hostDir -Recurse -Force
    New-Item -ItemType Directory -Force $hostDir | Out-Null
    foreach ($name in $saved.Keys) { [IO.File]::WriteAllText((Join-Path $hostDir $name), $saved[$name]) }
}

if ($SetupOnly) {
    ''
    if ($failures.Count) { "Address-feedback GitLab end-to-end setup: FAILED ($($failures.Count))"; exit 1 }
    'Address-feedback GitLab end-to-end setup: PASSED'
    exit 0
}
