<#
.SYNOPSIS
    Test adopting repositories with edge cases: a rollback, CI and a hooks path of their own, catch-all attributes,
    Copilot-only agents, a failing build, and Node.js without build or test scripts.

.DESCRIPTION
    Adopts six small fixture repositories from a tagged snapshot of the working tree, which
    tests/New-TemplateSnapshot.ps1 builds. They run apart from tests/Test-Adoption.ps1, which adopts the plain and
    scaffold fixtures, so a parallel tests/Invoke-AllTests.ps1 run ends sooner. Prints PASS or FAIL per check and exits
    1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-adopt-edge-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-AdoptEdgeCases.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-adopt-edge-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
. (Join-Path $PSScriptRoot 'AdoptionFixtures.ps1')

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
# A direct run keeps its Copier mirror in its own work folder, not in the user's cache; under tests\Invoke-AllTests.ps1 it keeps the runner's folder.
$copierCache = $env:COPIER_CACHE_DIR
if (-not $copierCache) { $env:COPIER_CACHE_DIR = Join-Path $Work 'copier-cache' }
New-Item -ItemType Directory -Force $Work | Out-Null
$tpl = Join-Path $Work 'template-repo'
$null = & (Join-Path $PSScriptRoot 'New-TemplateSnapshot.ps1') $tpl
$adopt = Join-Path $repoRoot 'Adopt-Project.ps1'

$broken = New-Fixture 'broken' @{
    'App.csproj'            = '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>'
    'Directory.Build.props' = 'this is not xml'
} 'https://github.com/example/broken.git'
$brokenMessage = try { & $adopt -Path $broken -Template $tpl -Ref v0.1.0 -NoVerify | Out-Null } catch { $_.Exception.Message }
$brokenStatus = git -C $broken status --porcelain
$brokenCount = git -C $broken rev-list --count HEAD
Check 'broken: a failure after Copier rolls the repository back' ("$brokenMessage".Contains('rolled back') -and -not $brokenStatus -and -not (Test-Path -LiteralPath (Join-Path $broken '.copier-answers.yml')) -and $brokenCount -eq '1') "$brokenMessage | $brokenStatus | $brokenCount"

$ciExisting = New-Fixture 'ci-existing' @{
    'README.md'                   = "# Ci Existing`n"
    '.github/workflows/ci.yml'    = "name: CI`n"
    '.github/workflows/frontend.yml' = "name: Frontend`n"
} 'https://github.com/example/ci-existing.git'
Invoke-Git -C $ciExisting config core.hooksPath .husky
$ciOut = & $adopt -Path $ciExisting -Template $tpl -Ref v0.1.0 -NoVerify 3>&1 | Out-String
Check 'ci-existing: keeps a hooks path of its own and warns with the command to run' ((((git -C $ciExisting config --local core.hooksPath) -join '') -eq '.husky') -and $ciOut.Contains('core.hooksPath is already .husky') -and $ciOut.Contains('git config core.hooksPath .githooks')) $ciOut
Check 'ci-existing: no reconcile follow-up when the repository already had ci.yml' (-not $ciOut.Contains('reconcile .github/workflows')) $ciOut
Check 'ci-existing: asks to add the commit attribution job to the kept ci.yml' ($ciOut.Contains("add the template's commit-attribution job to .github/workflows/ci.yml")) $ciOut
Check 'ci-existing: the baseline command suggests -RequireChecks auto for its own CI' ($ciOut.Contains('-Repo ci-existing -Owner example') -and $ciOut.Contains('keeps its own CI: add -RequireChecks auto')) $ciOut
Check 'ci-existing: says it left local out and how to add it' ($ciOut.Contains("workflow_tools: [claude, copilot], the template's default") -and $ciOut.Contains("-Data @{ workflow_tools = 'claude', 'copilot', 'local' }")) $ciOut

# A .NET repository with catch-all .gitattributes rules, a global.json with a partial SDK version, an image and its own
# workflow: three gaps found by adopting NCodeGroup's libraries. It answers the code review question
# (code_review = 'true' in -Data), so the template adds its own code-review.yml beside the repository's main.yml, and
# the report must ask to reconcile only main.yml with ci.yml.
$gaps = New-Fixture 'gaps' @{
    'README.md'                = "# Gaps`n"
    'Gaps.csproj'              = "<Project Sdk=""Microsoft.NET.Sdk"">`n  <PropertyGroup>`n    <TargetFramework>net10.0</TargetFramework>`n  </PropertyGroup>`n</Project>`n"
    '.gitattributes'           = "* text=auto`n* text eol=lf`n*.cs text diff=csharp`n"
    'global.json'              = "{`n  ""sdk"": {`n    ""version"": ""10.0.0"",`n    ""rollForward"": ""latestMinor""`n  }`n}`n"
    'logo.png'                 = $png
    '.github/workflows/main.yml' = "name: main`non: [push]`njobs:`n  build:`n    runs-on: ubuntu-latest`n    steps:`n      - run: echo hi`n"
} 'https://github.com/example/gaps.git'
$gapsOut = & $adopt -Path $gaps -Template $tpl -Ref v0.1.0 -Data @{ workflow_tools = 'claude', 'copilot'; code_review = 'true' } -NoVerify | Out-String
$gapsAttributes = Get-Content -Raw -LiteralPath (Join-Path $gaps '.gitattributes')
$pngText = (git -C $gaps check-attr text -- logo.png) -join ''
Check 'gaps: a catch-all text rule of the repository does not override the template''s binary rules' ($pngText -like '*: text: unset' -and $gapsAttributes -notmatch '(?s)# Kept from.*\n\* text') "$pngText | $gapsAttributes"
Check 'gaps: the repository''s other attribute lines are kept, and the report says what was left out' ($gapsAttributes.Contains('*.cs text diff=csharp') -and $gapsOut.Contains('left out its catch-all text rule')) $gapsOut
$gapsGlobal = Get-Content -Raw -LiteralPath (Join-Path $gaps 'global.json')
Check 'gaps: a partial SDK version in global.json is replaced by the template''s, which setup-dotnet accepts' ($gapsGlobal -match '"version":\s*"\d+\.\d+\.\d{3}"' -and -not $gapsGlobal.Contains('"10.0.0"') -and $gapsOut.Contains('isn''t a full version')) "$gapsGlobal | $gapsOut"
Check 'gaps: the code review workflows are not asked to be reconciled with ci.yml, but the repository''s own workflow is' ($gapsOut.Contains('reconcile .github/workflows/main.yml with ci.yml') -and -not $gapsOut.Contains('code-review.yml with ci.yml') -and -not $gapsOut.Contains('code-review-auto-merge.yml with ci.yml')) $gapsOut

# Copilot agents and no Hybrid ones, like a public repository: the adoption leaves out the local model's files.
$copilotOnly = New-Fixture 'copilot-only' @{
    'README.md'                                   = "# Copilot Only`n"
    '.github/agents/copilot-implementer.agent.md' = "old`n"
    '.github/agents/plan-executor.agent.md'       = "old`n"
} 'https://github.com/example/copilot-only.git'
$coOut = & $adopt -Path $copilotOnly -Template $tpl -Ref v0.1.0 -NoVerify | Out-String
$coAnswers = Get-Content -Raw -LiteralPath (Join-Path $copilotOnly '.copier-answers.yml')
$coSettings = Get-Content -Raw -LiteralPath (Join-Path $copilotOnly '.vscode\settings.json')
$coLocal = @('.github\agents\hybrid-planner.agent.md', '.github\agents\local-implementer.agent.md', '.github\prompts\execute-step-local.prompt.md' | Where-Object { Test-Path -LiteralPath (Join-Path $copilotOnly $_) })
Check 'copilot-only: works out workflow_tools without local' ($coAnswers -match '(?m)^workflow_tools:\r?\n- claude\r?\n- copilot\r?\n(?!- )' -and -not $coLocal -and -not $coSettings.Contains('ollama') -and (Test-Path -LiteralPath (Join-Path $copilotOnly '.github\skills\plan-feature\SKILL.md')) -and -not $coOut.Contains("the template's default")) "$coAnswers | $($coLocal -join ', ') | $coOut"

$failing = New-Fixture 'failing' @{ 'README.md' = "# Failing`n" } 'https://github.com/example/failing.git'
$failOut = & $adopt -Path $failing -Template $tpl -Ref v0.1.0 -Data @{ stack = 'other'; build_command = 'exit 3'; test_command = '' } | Out-String
$failExit = $LASTEXITCODE
$failCount = git -C $failing rev-list --count HEAD
$failStaged = git -C $failing diff --cached --name-only
Check 'failing: a failed build stages the adoption and commits nothing' ($failExit -eq 1 -and $failCount -eq '1' -and '.copier-answers.yml' -in $failStaged -and $failOut.Contains('"exit 3" fails after adopting')) "$failExit | $failCount | $failOut"

# Node.js only for tooling: a package.json without build or test scripts.
$notes = New-Fixture 'notes' @{
    'README.md'    = "# Notes`n"
    'package.json' = '{"name":"notes","private":true,"packageManager":"yarn@4.14.1","scripts":{"diagram:export":"echo export"}}' + "`n"
    'yarn.lock'    = "`n"
} 'https://github.com/example/notes.git'
$notesOut = & $adopt -Path $notes -Template $tpl -Ref v0.1.0 | Out-String
$notesAnswers = Get-Content -Raw -LiteralPath (Join-Path $notes '.copier-answers.yml')
$notesCi = Get-Content -Raw -LiteralPath (Join-Path $notes '.github\workflows\ci.yml')
$notesSubject = git -C $notes log -1 --format=%s
Check 'notes: a Node.js repository without build or test scripts commits without running a command' ($notesSubject -eq 'Adopt project-template v0.1.0' -and $notesAnswers -match '(?m)^stack: node\s*$' -and $notesAnswers -match "(?m)^build_command: ''\s*$" -and $notesAnswers -match "(?m)^test_command: ''\s*$" -and -not $notesOut.Contains('Running ') -and -not $notesCi.Contains('run build') -and -not $notesCi.Contains('npm test')) "$notesSubject | $notesAnswers | $notesOut | $notesCi"
Check 'notes: CI installs with the package manager package.json names' ($notesAnswers -match '(?m)^package_manager: yarn\s*$' -and $notesCi.Contains('corepack enable yarn') -and $notesCi.Contains('yarn install') -and -not $notesCi.Contains('npm ci')) "$notesAnswers | $notesCi"
''
$env:COPIER_CACHE_DIR = $copierCache
if ($failures.Count) { "Kept the work folder: $Work"; "Adopt edge-case tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Adopt edge-case tests: PASSED'
exit 0
