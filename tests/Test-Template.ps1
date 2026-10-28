<#
.SYNOPSIS
    Render the template for every stack and check the result: expected files, LF line endings, valid JSON, no
    leftover Jinja, a .NET layer that builds, and runs of each project's .template\Update-Project.ps1 that hand
    over to the new version's script, replace template-owned files, merge merged files, leave project-owned files
    alone, and stop on a conflict.

.DESCRIPTION
    Tests a committed, tagged (v0.1.0) snapshot of the current working tree in %TEMP%\project-template-test, so
    uncommitted template changes are tested too. Renders every stack for GitHub and GitLab and checks YAML with
    PyYAML through uv. Also checks that .github/workflows/test-template.yml runs every tests/Test-*.ps1, that the generated workflow files under template/ and at the repository root
    match a fresh run of workflow\Install-HybridWorkflow.ps1, that the installer writes .template-version and template/ has no copy of it, that the Claude Code commands, and no Copilot file, carry the plan-worktree sections, that run-issues reaches only Claude Code, and that the workflow scripts run and New-PlanPrompt.ps1 -List shows each template's targets. Prints PASS or FAIL
    per check and exits 1 on any failure.

.EXAMPLE
    .\tests\Test-Template.ps1
    .\tests\Test-Template.ps1 -SkipDotnetBuild -SkipUpdate
    .\tests\Test-Template.ps1 -SkipDotnetBuild -Only python, node

.PARAMETER Only
    Render only these cases, by name; the update tests need python and node.
#>
[CmdletBinding()]
param(
    [switch]$SkipDotnetBuild,
    [switch]$SkipUpdate,
    [string[]]$Only,
    [string]$Work = (Join-Path $env:TEMP 'project-template-test')
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Invoke-Copier {
    if (Get-Command copier -ErrorAction SilentlyContinue) { & copier @args }
    elseif (Get-Command uvx -ErrorAction SilentlyContinue) { & uvx --from copier copier @args }
    else { throw 'Copier not found. Install it with: uv tool install copier' }
    if ($LASTEXITCODE) { throw "copier $($args[0]) exited with code $LASTEXITCODE." }
}
function Edit-File([string]$Path, [string]$Old, [string]$New) {
    $full = (Resolve-Path -LiteralPath $Path).Path
    $text = [IO.File]::ReadAllText($full)
    if (-not $text.Contains($Old)) { throw "'$Old' not found in $full." }
    [IO.File]::WriteAllText($full, $text.Replace($Old, $New))
}
function Invoke-Git {
    git -c user.name=template-test -c user.email=template-test@example.invalid @args
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed." }
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$tpl = Join-Path $Work 'template-repo'
New-Item -ItemType Directory -Force $tpl | Out-Null
Get-ChildItem -LiteralPath $repoRoot -Force | Where-Object Name -NotIn '.git', '.claude' | Copy-Item -Destination $tpl -Recurse -Force
# Claude Code's plan worktrees are other checkouts, not part of the snapshot.
$claudeCopy = New-Item -ItemType Directory -Force (Join-Path $tpl '.claude')
Get-ChildItem -LiteralPath (Join-Path $repoRoot '.claude') -Force | Where-Object Name -NE 'worktrees' | Copy-Item -Destination $claudeCopy.FullName -Recurse -Force
Push-Location $tpl
try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Snapshot'; Invoke-Git tag v0.1.0 }
finally { Pop-Location }
# Serve the snapshot as a host does: over a URL with partial clones allowed, so a --filter=blob:none clone really is blob-filtered; Git ignores the filter for a plain path.
Invoke-Git -C $tpl config uploadpack.allowFilter true
Invoke-Git -C $tpl config uploadpack.allowAnySHA1InWant true
$tplUrl = 'file:///' + ($tpl -replace '\\', '/') + '/.git'

$common = 'AGENTS.md', 'README.md', '.copier-answers.yml', '.template-version', '.gitignore', '.gitattributes', '.editorconfig',
    '.github\instructions\project-template.instructions.md', '.template\Update-Project.ps1', '.template\Test-CommitAttribution.ps1', '.template\Get-PlanState.ps1', '.vscode\settings.json', '.vscode\extensions.json'
$allTools = 'claude', 'copilot', 'local'
$toolFiles = @{
    claude = 'CLAUDE.md', '.claude\settings.json', '.claude\agents\plan-executor.md', '.claude\commands\plan-feature.md',
        '.claude\commands\orchestrate-plan.md', '.claude\commands\replan-step.md', '.claude\commands\review-plan-diff.md'
    copilot = '.github\agents\copilot-planner.agent.md', '.github\agents\plan-executor.agent.md',
        '.github\prompts\plan-feature.prompt.md', '.github\prompts\execute-step.prompt.md', '.github\skills\plan-feature\SKILL.md'
    local = '.github\agents\local-implementer.agent.md', '.github\agents\hybrid-planner.agent.md',
        '.github\prompts\plan-feature.prompt.md', '.github\prompts\execute-step-local.prompt.md'
}
$dotnetOnly = 'Directory.Build.props', 'build\ProjectTemplate.props', 'Directory.Packages.props', 'global.json', '.claude\rules\csharp.md',
    '.github\instructions\csharp.instructions.md'
$hostOnly = @{ github = '.github\workflows\ci.yml', '.github\dependabot.yml'; gitlab = @('.gitlab-ci.yml') }
$cases = @(
    @{ Name = 'dotnet'; Stack = 'dotnet'; Host = 'github' }
    @{ Name = 'python'; Stack = 'python'; Host = 'github' }
    @{ Name = 'node'; Stack = 'node'; Host = 'github' }
    @{ Name = 'powershell'; Stack = 'powershell'; Host = 'github' }
    @{ Name = 'other'; Stack = 'other'; Host = 'github' }
    @{ Name = 'dotnet-gitlab'; Stack = 'dotnet'; Host = 'gitlab' }
    @{ Name = 'python-gitlab'; Stack = 'python'; Host = 'gitlab' }
    @{ Name = 'node-gitlab'; Stack = 'node'; Host = 'gitlab' }
    @{ Name = 'node-pnpm'; Stack = 'node'; Host = 'github'; Data = @{ package_manager = 'pnpm' } }
    @{ Name = 'node-bun'; Stack = 'node'; Host = 'github'; Data = @{ package_manager = 'bun' } }
    @{ Name = 'node-yarn-gitlab'; Stack = 'node'; Host = 'gitlab'; Data = @{ package_manager = 'yarn' } }
    @{ Name = 'node-bun-gitlab'; Stack = 'node'; Host = 'gitlab'; Data = @{ package_manager = 'bun' } }
    @{ Name = 'powershell-gitlab'; Stack = 'powershell'; Host = 'gitlab' }
    @{ Name = 'other-gitlab'; Stack = 'other'; Host = 'gitlab' }
    @{ Name = 'dotnet-library'; Stack = 'dotnet'; Host = 'github'; Tools = 'claude', 'copilot'; Data = @{ nuget_package = 'true'; package_license = 'MIT'; package_icon = 'icon.png' } }
    @{ Name = 'python-copilot'; Stack = 'python'; Host = 'gitlab'; Tools = @('copilot') }
)
if ($Only) { $cases = @($cases | Where-Object { $_.Name -in $Only }) }
$yamlCheck = 'import sys, yaml; [yaml.safe_load(open(p, encoding="utf-8")) for p in sys.argv[1:]]'

foreach ($case in $cases) {
    $name = $case.Name
    $dest = Join-Path $Work $name
    $tools = if ($case.Tools) { @($case.Tools) } else { $allTools }
    $extraData = foreach ($k in $case.Data.Keys) { '--data'; "$k=$($case.Data[$k])" }
    Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data "project_name=Test $name" --data "stack=$($case.Stack)" --data "git_host=$($case.Host)" --data "workflow_tools=[$($tools -join ', ')]" @extraData $tplUrl $dest

    $missing = $common | Where-Object { -not (Test-Path (Join-Path $dest $_)) }
    Check "${name}: common files" (-not $missing) ($missing -join ', ')
    $present = @($dotnetOnly | Where-Object { Test-Path (Join-Path $dest $_) })
    if ($case.Stack -eq 'dotnet') { Check "${name}: .NET layer present" ($present.Count -eq $dotnetOnly.Count) }
    else { Check "${name}: no .NET layer" ($present.Count -eq 0) ($present -join ', ') }
    if ($case.Stack -eq 'dotnet') {
        $buildProps = Get-Content -LiteralPath (Join-Path $dest 'build\ProjectTemplate.props') -Raw
        $nugetOk = if ($case.Data.nuget_package) { $buildProps.Contains('<PackageLicenseExpression>MIT</PackageLicenseExpression>') -and $buildProps.Contains('<PackageIcon>icon.png</PackageIcon>') -and $buildProps.Contains('../icon.png') }
            else { -not $buildProps.Contains('PackageLicenseExpression') }
        Check "${name}: NuGet package settings" $nugetOk
    }
    $otherHost = if ($case.Host -eq 'github') { 'gitlab' } else { 'github' }
    $wrong = @($hostOnly[$case.Host] | Where-Object { -not (Test-Path (Join-Path $dest $_)) }) + @($hostOnly[$otherHost] | Where-Object { Test-Path (Join-Path $dest $_) })
    Check "${name}: $($case.Host) files only" (-not $wrong) ($wrong -join ', ')
    if ($case.Host -eq 'github') {
        $ci = Get-Content -LiteralPath (Join-Path $dest '.github\workflows\ci.yml') -Raw
        Check "${name}: CI runs the commit attribution check" ($ci.Contains('./.template/Test-CommitAttribution.ps1 -Base $env:BASE -Head $env:HEAD') -and $ci.Contains('merge_group:') -and $ci.Contains('${{ github.event.pull_request.base.sha'))
        $checkouts = [regex]::Matches($ci, '(?m)^\s+- uses: actions/checkout@').Count
        Check "${name}: CI checkouts set persist-credentials false" ($checkouts -gt 0 -and [regex]::Matches($ci, '(?m)^\s+persist-credentials: false\r?$').Count -eq $checkouts) $ci
    }
    else {
        $ci = Get-Content -LiteralPath (Join-Path $dest '.gitlab-ci.yml') -Raw
        Check "${name}: CI runs the commit attribution check" ($ci.Contains('commit-attribution:') -and $ci.Contains('mcr.microsoft.com/dotnet/sdk:10.0') -and $ci.Contains('GIT_DEPTH: "0"') -and $ci.Contains('.template/Test-CommitAttribution.ps1 -Base'))
    }
    if ($case.Stack -eq 'node') {
        $pm = if ($case.Data.package_manager) { $case.Data.package_manager } else { 'npm' }
        $install = @{ npm = 'npm ci'; pnpm = 'pnpm install --frozen-lockfile'; yarn = 'yarn install'; bun = 'bun install --frozen-lockfile' }[$pm]
        $setup = @{ npm = ''; pnpm = 'corepack enable pnpm'; yarn = 'corepack enable yarn'; bun = if ($case.Host -eq 'github') { 'oven-sh/setup-bun@' } else { 'image: oven/bun:1' } }[$pm]
        $otherManagers = @('npm', 'pnpm', 'yarn', 'bun') | Where-Object { $_ -ne $pm }
        $managerOk = $ci.Contains($install) -and $ci.Contains($setup) -and ($ci.Contains('corepack') -eq ($pm -in 'pnpm', 'yarn')) -and
            $ci -match "(?<![\w-])$pm run build" -and $ci -match "(?<![\w-])$pm run test" -and -not ($otherManagers | Where-Object { $ci -match "(?<![\w-])$_ (run|ci|install(?! --global))" })
        if ($case.Host -eq 'github') {
            $ecosystem = if ($pm -eq 'bun') { 'bun' } else { 'npm' }
            $managerOk = $managerOk -and (Get-Content -LiteralPath (Join-Path $dest '.github\dependabot.yml') -Raw).Contains("package-ecosystem: $ecosystem")
        }
        Check "${name}: CI installs and runs with $pm" $managerOk $ci
    }
    $wanted = @($tools | ForEach-Object { $toolFiles[$_] } | Select-Object -Unique)
    $unwanted = @($allTools | Where-Object { $_ -notin $tools } | ForEach-Object { $toolFiles[$_] } | Select-Object -Unique | Where-Object { $_ -notin $wanted })
    $wrong = @($wanted | Where-Object { -not (Test-Path (Join-Path $dest $_)) }) + @($unwanted | Where-Object { Test-Path (Join-Path $dest $_) })
    Check "${name}: workflow files for $($tools -join ', ') only" (-not $wrong) ($wrong -join ', ')

    $files = Get-ChildItem -LiteralPath $dest -Recurse -File -Force
    $crlf = $files | Where-Object { $_.Extension -notin '.cmd', '.bat' -and [IO.File]::ReadAllText($_.FullName).Contains("`r") } | ForEach-Object Name
    Check "${name}: LF line endings" (-not $crlf) ($crlf -join ', ')
    $badEnd = $files | Where-Object { $b = [IO.File]::ReadAllBytes($_.FullName); $b.Length -and ($b[-1] -ne 10 -or ($b.Length -gt 1 -and $b[-2] -eq 10)) } | ForEach-Object { $_.FullName.Substring($dest.Length).TrimStart('\', '/') }
    Check "${name}: every text file ends with exactly one newline" (-not $badEnd) ($badEnd -join ', ')
    $jinja = $files | Where-Object { Select-String -LiteralPath $_.FullName -Pattern '(?<!\$)\{\{|\{%' -Quiet } | ForEach-Object Name
    Check "${name}: no leftover Jinja" (-not $jinja) ($jinja -join ', ')
    $badJson = $files | Where-Object Extension -EQ '.json' | Where-Object {
        try { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Out-Null; $false } catch { $true }
    } | ForEach-Object Name
    Check "${name}: valid JSON" (-not $badJson) ($badJson -join ', ')
    $yamlFiles = @($files | Where-Object Extension -In '.yml', '.yaml' | ForEach-Object FullName)
    $yamlOutput = uv run --quiet --no-project --with pyyaml python -c $yamlCheck @yamlFiles 2>&1 | Out-String
    Check "${name}: valid YAML ($($yamlFiles.Count) files)" ($LASTEXITCODE -eq 0) $yamlOutput.Trim()
    $extensions = Get-Content -LiteralPath (Join-Path $dest '.vscode/extensions.json') -Raw
    $settings = Get-Content -LiteralPath (Join-Path $dest '.vscode/settings.json') -Raw
    $local = 'local' -in $tools
    Check "${name}: editor settings for the chosen tools" (($extensions.Contains('ollama.ollama') -eq $local) -and ($settings.Contains('ollama.inferenceTimeoutMinutes') -eq $local) -and ($extensions.Contains('anthropic.claude-code') -eq ('claude' -in $tools)))
    $agents = Get-Content -LiteralPath (Join-Path $dest 'AGENTS.md') -Raw
    $ignore = Get-Content -LiteralPath (Join-Path $dest '.gitignore') -Raw
    $claude = 'claude' -in $tools
    Check "${name}: AGENTS.md and .gitignore for the chosen tools" (($agents.Contains('CLAUDE.md') -eq $claude) -and ($ignore.Contains('CLAUDE.local.md') -eq $claude))
    Check "${name}: .gitignore ignores the plan" ($ignore -match '(?m)^PLAN\.md\r?$')
    $rules = Get-Content -LiteralPath (Join-Path $dest '.github\instructions\project-template.instructions.md') -Raw
    Check "${name}: template rules for the chosen tools" (($rules.Contains('.claude/') -eq $claude) -and ($rules.Contains('.github/skills/') -eq ('copilot' -in $tools)))
    $readme = Get-Content -LiteralPath (Join-Path $dest 'README.md') -Raw
    Check "${name}: README for the chosen tools" (($readme.Contains('| Claude Code |') -eq $claude) -and ($readme.Contains('| Copilot CLI |') -eq ('copilot' -in $tools)) -and ($readme.Contains('Hybrid Planner') -eq $local))
    Check "${name}: answers record v0.1.0" ((Get-Content -LiteralPath (Join-Path $dest '.copier-answers.yml') -Raw) -match '(?m)^_commit: v0\.1\.0$')
    Check "${name}: .template-version records v0.1.0" ((Get-Content -LiteralPath (Join-Path $dest '.template-version') -Raw) -eq "v0.1.0`n")
}

$listProject = Join-Path $Work 'new-project-list'
& (Join-Path $repoRoot 'New-Project.ps1') -Path $listProject -Template $tpl -Ref v0.1.0 -Defaults -Data @{ project_name = 'List Answer'; stack = 'other'; workflow_tools = 'claude', 'copilot' } | Out-Null
$listAnswers = [IO.File]::ReadAllText((Join-Path $listProject '.copier-answers.yml')) -replace "`r`n", "`n"
Check 'New-Project: a list answer in -Data reaches Copier' (($listAnswers -match '(?m)^workflow_tools:\n- claude\n- copilot\n') -and -not (Test-Path (Join-Path $listProject '.github\agents\hybrid-planner.agent.md'))) $listAnswers
$hooksPath = (git -C $listProject config core.hooksPath) -join ''
$hookMode = (git -C $listProject ls-files -s .githooks/commit-msg) -join ''
$pushMode = (git -C $listProject ls-files -s .githooks/pre-push) -join ''
Check 'New-Project: enables the hooks with an executable commit-msg and pre-push' (($hooksPath -eq '.githooks') -and $hookMode.StartsWith('100755') -and $pushMode.StartsWith('100755')) "$hooksPath $hookMode $pushMode"
$secretsIgnored = @(foreach ($p in 'secrets/key.txt', 'src/secrets/x.cs', 'src/Secrets/New.cs') { git -C $listProject check-ignore -q --no-index $p; $LASTEXITCODE }) -join ','
$secretsDeny = @((Get-Content -LiteralPath (Join-Path $listProject '.claude\settings.json') -Raw | ConvertFrom-Json).permissions.deny)
Check 'project: only the root secrets/ folder is gitignored and denied to Claude Code' (($secretsIgnored -eq '0,1,1') -and ('Read(/secrets/**)' -in $secretsDeny) -and ('Read(./secrets/**)' -notin $secretsDeny)) "check-ignore exit codes $secretsIgnored; deny $($secretsDeny -join ', ')"
$hookMessage = Join-Path $Work 'hook-message.txt'
[IO.File]::WriteAllText($hookMessage, "Hook check`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`nClaude-Session: https://claude.ai/code/session_1`n$([char]::ConvertFromUtf32(0x1F916)) Generated with [Claude Code](https://claude.com/claude-code)`nCo-authored-by: Jane Doe <jane@example.com>`n", [Text.UTF8Encoding]::new($false))
$proseMessage = Join-Path $Work 'hook-prose-message.txt'
[IO.File]::WriteAllText($proseMessage, "Prose check`n`nThe hook strips the Generated with Claude Code line.`n", [Text.UTF8Encoding]::new($false))
# A UTF-8 locale is where a bare pattern failed to strip the emoji line.
$previousLocale = $env:LC_ALL
$env:LC_ALL = 'en_US.UTF-8'
Push-Location $listProject
try {
    [IO.File]::WriteAllText((Join-Path $listProject 'hook-check.txt'), "hook check`n", [Text.UTF8Encoding]::new($false))
    Invoke-Git add hook-check.txt
    Invoke-Git commit -q -F $hookMessage
    $hookLog = (git log -1 --format=%B) -join "`n"
    [IO.File]::WriteAllText((Join-Path $listProject 'hook-prose.txt'), "hook prose`n", [Text.UTF8Encoding]::new($false))
    Invoke-Git add hook-prose.txt
    Invoke-Git commit -q -F $proseMessage
    $proseLog = (git log -1 --format=%B) -join "`n"
}
finally {
    Pop-Location
    if ($null -eq $previousLocale) { Remove-Item Env:LC_ALL -ErrorAction SilentlyContinue } else { $env:LC_ALL = $previousLocale }
}
Check 'hooks: commit-msg strips AI agent attribution and keeps people' ($hookLog.Contains('Jane Doe') -and -not $hookLog.Contains('anthropic.com') -and -not $hookLog.Contains('Copilot@') -and -not $hookLog.Contains('Claude-Session') -and -not $hookLog.Contains('Generated with')) $hookLog
Check 'hooks: commit-msg keeps a prose line that mentions the advertising phrase' ($proseLog.Contains('The hook strips the Generated with Claude Code line.')) $proseLog
$attributionBase = (git -C $listProject rev-list --max-parents=0 HEAD) -join ''
$attributionOutput = & pwsh -NoProfile -File (Join-Path $listProject '.template\Test-CommitAttribution.ps1') -Base $attributionBase -Head HEAD 2>&1 | Out-String
Check 'project: the shipped commit attribution check passes on its own history' (($LASTEXITCODE -eq 0) -and $attributionOutput.Contains('none is attributed to an AI agent')) $attributionOutput

$workflow = Join-Path $repoRoot 'workflow'
$fresh = Join-Path $Work 'generated'
New-Item -ItemType Directory -Force $fresh | Out-Null
& (Join-Path $workflow 'Install-HybridWorkflow.ps1') -Repo $fresh -Variant Both -Target VSCode, Claude, CopilotCli -NoVersionMarker | Out-Null
# Generated files under $Root that differ from a fresh install, or are missing or extra.
function Get-StaleWorkflowFile([string]$Root) {
    foreach ($dir in '.claude\commands', '.claude\agents', '.github\agents', '.github\prompts', '.github\skills') {
        $freshDir = Join-Path $fresh $dir; $rootDir = Join-Path $Root $dir
        $a = @(Get-ChildItem -LiteralPath $freshDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { "$dir\$([IO.Path]::GetRelativePath($freshDir, $_.FullName)) $((Get-FileHash $_.FullName).Hash)" })
        $b = @(Get-ChildItem -LiteralPath $rootDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { "$dir\$([IO.Path]::GetRelativePath($rootDir, $_.FullName)) $((Get-FileHash $_.FullName).Hash)" })
        @($a | Where-Object { $_ -notin $b }) + @($b | Where-Object { $_ -notin $a }) | ForEach-Object { ($_ -split ' ')[0] }
    }
}
$stale = @(Get-StaleWorkflowFile (Join-Path $repoRoot 'template') | Select-Object -Unique)
Check 'generated workflow files match workflow/templates (else run tools\Update-Template.ps1)' (-not $stale) ($stale -join ', ')
$stale = @(Get-StaleWorkflowFile $repoRoot | Select-Object -Unique)
Check 'this repository''s own workflow files match workflow/templates (else run tools\Update-Template.ps1)' (-not $stale) ($stale -join ', ')
# Text files Git tracks with LF endings; binary files are left out.
$ownFiles = git -C $repoRoot -c core.quotePath=false ls-files --eol | Where-Object { $_ -match '^i/lf\s' } | ForEach-Object { Join-Path $repoRoot (($_ -split "`t", 2)[1]) }
$badEnd = $ownFiles | Where-Object { $b = [IO.File]::ReadAllBytes($_); $b.Length -and ($b[-1] -ne 10 -or ($b.Length -gt 1 -and $b[-2] -eq 10)) } | ForEach-Object { $_.Substring($repoRoot.Length).TrimStart('\', '/') }
Check 'repository: every text file ends with exactly one newline' (-not $badEnd) ($badEnd -join ', ')
# Names of the tests/Test-*.ps1 scripts under $Root that .github/workflows/test-template.yml has no "run: ./tests/<name>" line for.
function Get-UnlistedTestScript([string]$Root) {
    $yml = [IO.File]::ReadAllText((Join-Path $Root '.github\workflows\test-template.yml'))
    Get-ChildItem -LiteralPath (Join-Path $Root 'tests') -File | Where-Object Name -like 'Test-*.ps1' |
        Where-Object { $yml -notmatch "(?m)^\s*run:\s*\./tests/$([regex]::Escape($_.Name))\s*$" } | ForEach-Object Name
}
$ciFixture = Join-Path $Work 'ci-listing'
New-Item -ItemType Directory -Force (Join-Path $ciFixture 'tests'), (Join-Path $ciFixture '.github\workflows') | Out-Null
[IO.File]::WriteAllText((Join-Path $ciFixture 'tests\Test-Listed.ps1'), '')
[IO.File]::WriteAllText((Join-Path $ciFixture 'tests\Test-Unlisted.ps1'), '')
[IO.File]::WriteAllText((Join-Path $ciFixture '.github\workflows\test-template.yml'), "      - name: Not run: ./tests/Test-Unlisted.ps1`n        run: ./tests/Test-Listed.ps1`n")
$unlisted = @(Get-UnlistedTestScript $ciFixture)
Check 'repository: the CI listing check names a test script the workflow leaves out' (($unlisted -join ',') -eq 'Test-Unlisted.ps1') ($unlisted -join ',')
$unlisted = @(Get-UnlistedTestScript $repoRoot)
Check 'repository: CI runs every tests/Test-*.ps1 (add a "run: ./tests/<name>" step to .github/workflows/test-template.yml)' (-not $unlisted) ($unlisted -join ', ')
$excludeCheck = 'import sys, yaml, jinja2; c = yaml.safe_load(open(sys.argv[1], encoding="utf-8")); e = jinja2.Environment(); bad = [p for p in c["_exclude"] if e.from_string(p).render().strip()]; print("; ".join(bad)); sys.exit(1 if bad else 0)'
$excludeOutput = uv run --quiet --no-project --with pyyaml --with jinja2 python -c $excludeCheck (Join-Path $repoRoot 'copier.yml') 2>&1 | Out-String
Check 'copier.yml: _exclude patterns exclude nothing when workflow_tools is missing' ($LASTEXITCODE -eq 0) $excludeOutput.Trim()
$executorChecks = @(
    @{ Path = 'template\.github\agents\copilot-implementer.agent.md'; Text = "model: 'Claude Sonnet 5.5 (copilot)'" }
    @{ Path = 'template\.github\agents\plan-executor.agent.md'; Text = 'model: claude-sonnet-5.5' }
    @{ Path = 'template\.claude\agents\plan-executor.md'; Text = 'model: claude-sonnet-5-5' }
    @{ Path = 'template\.github\prompts\execute-step.prompt.md'; Text = 'Claude Sonnet 5.5 (copilot)' }
)
$executorMissing = @($executorChecks | Where-Object { -not [IO.File]::ReadAllText((Join-Path $repoRoot $_.Path)).Contains($_.Text) } | ForEach-Object Path)
$executorAuto = @(
    foreach ($dir in 'template\.github', 'template\.claude') {
        Get-ChildItem -LiteralPath (Join-Path $repoRoot $dir) -Recurse -File -Force | Where-Object {
            $t = [IO.File]::ReadAllText($_.FullName)
            $t.Contains('Auto (copilot)') -or $t -match '(?m)^\s*model:\s*[''"]?auto[''"]?\s*$'
        } | ForEach-Object Name
    }
)
Check 'workflow: every executor runs on Claude Sonnet 5.5' (-not $executorMissing -and -not $executorAuto) ((@($executorMissing) + @($executorAuto)) -join ', ')
$coordinatorMissing = @(
    foreach ($p in 'template\.claude\agents\plan-executor.md', 'template\.github\agents\plan-executor.agent.md', 'template\.github\skills\execute-step\SKILL.md') {
        if (-not [IO.File]::ReadAllText((Join-Path $repoRoot $p)).Contains('never substitute a check of your own')) { $p }
    }
    if (-not [IO.File]::ReadAllText((Join-Path $repoRoot 'template\.claude\commands\orchestrate-plan.md')).Contains('a check the subagent made instead does not count')) { 'template\.claude\commands\orchestrate-plan.md' }
)
Check 'workflow: an executor that cannot run the Done-when command leaves the check to the coordinator' (-not $coordinatorMissing) ($coordinatorMissing -join ', ')
# Each issue fix's text in the files it must reach: "<path>: <text>" for each one missing, or "<path>: the file is missing".
function Get-MissingText([string[]]$Path, [string[]]$Text) {
    foreach ($p in $Path) {
        $full = Join-Path $repoRoot $p
        if (-not (Test-Path -LiteralPath $full)) { "${p}: the file is missing"; continue }
        $content = [IO.File]::ReadAllText($full)
        foreach ($t in $Text) { if (-not $content.Contains($t)) { "${p}: $t" } }
    }
}
$m = @(Get-MissingText 'template\.claude\agents\plan-executor.md' ('tools: Read, Edit, Write, Bash, PowerShell, Grep, Glob', 'with the PowerShell tool'))
Check 'workflow: the Claude Code plan-executor has the PowerShell tool and runs commands with it' (-not $m) ($m -join '; ')
$m = @(Get-MissingText ('template\.claude\commands\finish-plan.md', 'template\.github\prompts\finish-plan.prompt.md', 'template\.github\skills\finish-plan\SKILL.md') ('pwsh -NoProfile -File .template/Get-PlanState.ps1', '`landed`'))
Check 'workflow: finish-plan reads whether the work landed from .template/Get-PlanState.ps1' (-not $m) ($m -join '; ')
$m = @(Get-MissingText 'template\.claude\commands\finish-plan.md' ('Filename too long', 'git config --global core.longpaths true'))
Check 'workflow: finish-plan deletes what a path too long for Windows left behind' (-not $m) ($m -join '; ')
$m = @(Get-MissingText 'USAGE.md' 'git config --global core.longpaths true')
Check 'USAGE.md: the Git setup turns on core.longpaths' (-not $m) ($m -join '; ')
$m = @(Get-MissingText ('template\.claude\commands\plan-feature.md', 'template\.github\prompts\plan-bugfix.prompt.md', 'template\.github\skills\handoff-plan\SKILL.md', 'template\.github\agents\copilot-planner.agent.md') ('Issue: <issue reference', 'gh issue comment', 'glab issue note', '<details>'))
$m += @(Get-MissingText 'template\.github\agents\copilot-planner.agent.md' 'post its snapshot comment')
Check 'workflow: a planning command links the plan to its issue and posts a snapshot there' (-not $m) ($m -join '; ')
$m = @(Get-MissingText ('template\.claude\commands\replan-step.md', 'template\.github\skills\replan-step\SKILL.md', 'template\.claude\commands\orchestrate-plan.md') ('gh issue comment', 'glab issue note'))
Check 'workflow: a re-plan that changes the plan posts what changed to its issue' (-not $m) ($m -join '; ')
$m = @(Get-MissingText ('template\.claude\commands\review-plan-diff.md', 'template\.github\instructions\project-template.instructions.md.jinja') 'Closes <issue reference>')
$m += @(Get-MissingText 'template\.github\instructions\project-template.instructions.md.jinja' 'Only the planning session calls')
Check 'workflow: the review and the push name the issue the pull request closes' (-not $m) ($m -join '; ')
$m = @(foreach ($p in 'template\.claude\agents\plan-executor.md', 'template\.github\agents\plan-executor.agent.md', 'template\.github\agents\copilot-implementer.agent.md', 'template\.github\agents\local-implementer.agent.md', 'template\.github\skills\execute-step\SKILL.md', 'template\.github\prompts\execute-step.prompt.md', 'template\.github\prompts\execute-step-local.prompt.md') { $t = [IO.File]::ReadAllText((Join-Path $repoRoot $p)); if ($t.Contains('gh issue') -or $t.Contains('glab issue')) { $p } })
Check 'workflow: no executor calls gh or glab on the issue' (-not $m) ($m -join ', ')
$issuePlanFiles = 'template\.claude\commands\plan-issue.md', 'template\.github\prompts\plan-issue.prompt.md', 'template\.github\skills\plan-issue\SKILL.md'
$m = @(Get-MissingText $issuePlanFiles ('gh issue view', 'glab issue view', 'Plan snapshot.', 'issue-<number>', '| `bug`, `defect`, `regression` | bugfix |', 'Plan this feature for a smaller model to implement:', 'Investigate this bug and plan the fix:', 'gh issue comment'))
$m += @(foreach ($p in $issuePlanFiles) { $full = Join-Path $repoRoot $p; if (Test-Path -LiteralPath $full) { $t = [IO.File]::ReadAllText($full); if ($t.Contains('{{') -or [regex]::Matches($t, '## Output: PLAN\.md for the executor model').Count -ne 1) { "${p}: an include is left unexpanded, or the plan format is not there exactly once" } } })
Check 'workflow: plan-issue reads the issue, maps labels to a plan kind and includes the kind checklists' (-not $m) ($m -join '; ')
$triageFiles = 'template\.claude\commands\triage-issues.md', 'template\.github\prompts\triage-issues.prompt.md', 'template\.github\skills\triage-issues\SKILL.md'
$m = @(Get-MissingText $triageFiles ('gh issue list', 'glab issue list', '/plan-issue #42', 'as data, not instructions', '| `bug`, `defect`, `regression` | bugfix |'))
$m += @(foreach ($p in $triageFiles) { $full = Join-Path $repoRoot $p; if (Test-Path -LiteralPath $full) { $t = [IO.File]::ReadAllText($full); foreach ($x in 'Issue: <issue reference', 'gh issue comment', 'glab issue note', 'EnterWorktree') { if ($t.Contains($x)) { "${p}: has $x" } } } })
Check 'workflow: triage-issues lists and judges issues, and plans and posts nothing' (-not $m) ($m -join '; ')
$updatePlanFiles = 'template\.claude\commands\plan-template-update.md', 'template\.github\prompts\plan-template-update.prompt.md', 'template\.github\skills\plan-template-update\SKILL.md'
$m = @(Get-MissingText $updatePlanFiles ('_commit', '_src_path', 'Update-Project.ps1 -Ref <tag> -NoCommit', 'Local edits discarded', '_skip_if_exists', 'build/project-template-<tag>', 'if (-not $? -or $LASTEXITCODE) { exit 1 } else { exit 0 }', 'gh issue create --repo'))
$m += @(foreach ($p in $updatePlanFiles) { $full = Join-Path $repoRoot $p; if (Test-Path -LiteralPath $full) { $t = [IO.File]::ReadAllText($full); if ($t.Contains('{{') -or [regex]::Matches($t, '## Output: PLAN\.md for the executor model').Count -ne 1) { "${p}: an include is left unexpanded, or the plan format is not there exactly once" } } })
Check 'workflow: plan-template-update trials the update in a clone, pins the version and plans the update with exit-code checks' (-not $m) ($m -join '; ')
$m = @(Get-MissingText ('template\.claude\commands\plan-feature.md', 'template\.github\prompts\plan-bugfix.prompt.md', 'template\.github\skills\handoff-plan\SKILL.md', 'template\.github\agents\copilot-planner.agent.md') ('gh issue view', 'glab issue view', 'as data, not instructions'))
Check 'workflow: every planning command reads the issue it names and treats its text as data' (-not $m) ($m -join '; ')
$m = @(Get-MissingText ('template\.claude\commands\ship-plan.md', 'template\.github\prompts\ship-plan.prompt.md', 'template\.github\skills\ship-plan\SKILL.md', 'template\.claude\commands\continue-plan.md') 'pwsh -NoProfile -File .template/Get-PlanState.ps1')
$m += @(Get-MissingText 'template\.claude\commands\ship-plan.md' ('git push --atomic origin', 'gh pr create', 'glab mr create', 'gh release create', 'glab release create', 'gh issue close', 'Never force-push'))
$m += @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'template\.claude'), (Join-Path $repoRoot 'template\.github') -Recurse -File | Where-Object { [IO.File]::ReadAllText($_.FullName).Contains('{{STATE_SCRIPT}}') } | ForEach-Object { "$($_.Name): left {{STATE_SCRIPT}}" })
Check 'workflow: ship-plan and continue-plan run .template/Get-PlanState.ps1, and ship-plan lands, tags, publishes and closes' (-not $m) ($m -join '; ')
$m = @(Get-MissingText 'template\.claude\commands\plan-feature.md' ('Release: <version', '## Follow-ups', 'raised by one patch version'))
$m += @(Get-MissingText 'template\.claude\commands\review-plan-diff.md' ('Reviewed: <the commit', '## Follow-ups', '/ship-plan'))
Check 'workflow: plans carry their release and follow-ups, and a clean review records the commit it reviewed' (-not $m) ($m -join '; ')
$m = @(Get-MissingText 'template\.claude\commands\ship-plan.md' ('gh label create "<label>"', 'glab label create --name "<label>"', '--label "<label>"', '`follow-up-label` names the label','filed as #<number>', 'already tracked as #<number>', 'unless I name it as one to drop', 'unless `follow-ups` is `none`', '`<repo args>` is `--repo <owner/repo>`'))
$m += @(Get-MissingText 'template\.claude\commands\run-issues.md' ('unless I answer that I want none filed', 'Unless I said at the start that I want none filed', '`follow-ups=none`', 'labelled with the `landing` line''s `follow-up-label`'))
$m += @(Get-MissingText ('template\.claude\commands\plan-feature.md', 'template\.claude\commands\review-plan-diff.md') 'as an issue')
$m += @(Get-MissingText 'template\.claude\commands\plan-feature.md' '`follow-up-label`')
Check 'workflow: ship-plan files the follow-ups as labelled issues unless dropped or already tracked, run-issues files them by default, and planners list only work worth an issue' (-not $m) ($m -join '; ')
$runFiles = 'template\.claude\commands\run-issues.md', '.claude\commands\run-issues.md'
$m = @(Get-MissingText $runFiles ('pwsh -NoProfile -File .template/Get-PlanState.ps1', 'Ask me once', 'Open each one as a draft', 'the state script''s `protected` value must be `host`','git worktree add .claude/worktrees/issue-<number>', 'plan-executor', 'third review', 'addPullRequestReviewThreadReply', 'Autopilot:', 'ExitWorktree'))
$m += @(foreach ($p in $runFiles) { $full = Join-Path $repoRoot $p; if ((Test-Path -LiteralPath $full) -and ([regex]::Matches([IO.File]::ReadAllText($full), [regex]::Escape('$ARGUMENTS')).Count -ne 1 -or [IO.File]::ReadAllText($full).Contains('{{'))) { "${p}: the arguments placeholder is not there exactly once, or a template token is left" } })
$m += @('template\.github\prompts\run-issues.prompt.md', 'template\.github\skills\run-issues', '.github\prompts\run-issues.prompt.md', '.github\skills\run-issues' | Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot $_) } | ForEach-Object { "${_}: a Claude Code-only command reached Copilot" })
Check 'workflow: run-issues is a Claude Code command that gates on pull requests, plans, executes, reviews and lands each issue, and no Copilot file has it' (-not $m) ($m -join '; ')
$m = @(Get-MissingText $runFiles ('its top-level comments and its review summaries', 'reviews(first: 100) { nodes { author { login } body url } }', '`individual_note` true', 'A top-level comment or review summary awaits an answer when it is mine', 'no top-level comment starting with `Autopilot:` names its URL', 'gh pr comment <number> --body-file <file>', 'merge_requests/<number>/notes" -F body=@<file>'))
Check 'workflow: run-issues reads and answers my top-level pull request comments and review summaries, not only review threads' (-not $m) ($m -join '; ')
$m = @(Get-MissingText $runFiles ('Then refresh the pull request description', 'gh pr edit <number> --body-file <file>', 'glab mr update <number> --description (Get-Content -Raw <file>)'))
Check 'workflow: run-issues refreshes the pull request description after a review round adds fix steps' (-not $m) ($m -join '; ')
$m = @(Get-MissingText $runFiles ('First take a `wait:<hours>` word', 'It sets the wait limit', 'for up to the wait limit, in hours, with nothing to answer', 'Note the time with `Get-Date` at the first check', 'unless the wait limit has passed since the time you noted'))
Check 'workflow: run-issues waits for a merge no longer than the wait limit, 24 hours unless wait:<hours> sets it, then stops the entry' (-not $m) ($m -join '; ')
$m = @(Get-MissingText ('template\.claude\commands\ship-plan.md', 'template\.github\prompts\ship-plan.prompt.md', 'template\.github\skills\ship-plan\SKILL.md') ('open it as a draft', '--draft', 'When `protect` is `hook` and `integrate` is `direct`', 'or the `landing` line says `draft=yes`', 'Stop when `draft` is neither'))
$m += @(if (-not ((git -C $repoRoot ls-files -s template/.githooks/pre-push) -join '').StartsWith('100755')) { 'template/.githooks/pre-push: not executable in the index' })
Check 'workflow: ship-plan opens a draft pull request when asked or when the Landing section says draft: yes, and the pre-push hook is executable' (-not $m) ($m -join '; ')
$m = @(Get-MissingText ('template\.claude\commands\ship-plan.md', 'template\.github\prompts\ship-plan.prompt.md', 'template\.github\skills\ship-plan\SKILL.md') ('`gate` is `none` or the command to run before a push', 'if (-not $? -or $LASTEXITCODE) { exit 1 } else { exit 0 }', 'stop before pushing: say the gate failed', 'the gate changed files'))
Check 'workflow: ship-plan runs the Landing section''s gate before it pushes and stops when it fails or changes a file' (-not $m) ($m -join '; ')
$m = @(Get-MissingText $runFiles ('that the gate runs before each push', 'run the gate as `ship-plan` item 6 says'))
Check 'workflow: run-issues runs the gate before the pushes it makes itself' (-not $m) ($m -join '; ')
$m = @(Get-MissingText ('template\.claude\commands\ship-plan.md', 'template\.github\prompts\ship-plan.prompt.md', 'template\.github\skills\ship-plan\SKILL.md') ('`pr-format` is `none` or `<file>#<heading>`', 'say to fix the `- pr-format:` line', 'write the title and the description as its section says instead', 'Either way, the description ends with one `Closes <issue reference>` line'))
Check 'workflow: ship-plan writes the pull request as the Landing section''s pr-format section says, keeping the Closes lines' (-not $m) ($m -join '; ')
$m = @(Get-MissingText $issuePlanFiles ('up to three related issues named one by one', 'stop for the whole group', 'after the first issue the request names'))
$m += @(Get-MissingText 'template\.claude\commands\plan-feature.md' ('Issue: #25 #24 #26', '- Issue: <reference>', 'largest raise', 'once to each issue on its'))
$m += @(Get-MissingText ('template\.claude\commands\ship-plan.md', 'template\.github\prompts\ship-plan.prompt.md', 'template\.github\skills\ship-plan\SKILL.md') ('line for each reference on the plan', 'issue-states', 'one comment per issue'))
$m += @(Get-MissingText $triageFiles ('group:<n>', '/plan-issue #25 #24 #26'))
$m += @(Get-MissingText $runFiles ('one entry per', 'A group stops together'))
Check 'workflow: a plan covers up to three related issues: plan-issue takes them, the plan lists them, ship-plan closes each, triage groups them and run-issues runs a group as one entry' (-not $m) ($m -join '; ')
$m = @(foreach ($p in 'template\.template\Get-PlanState.ps1', '.template\Get-PlanState.ps1') {
    $full = Join-Path $repoRoot $p
    if (-not (Test-Path -LiteralPath $full) -or [IO.File]::ReadAllText($full) -ne [IO.File]::ReadAllText((Join-Path $repoRoot 'workflow\Get-PlanState.ps1'))) { $p }
})
Check 'workflow: the generated Get-PlanState.ps1 copies match workflow/Get-PlanState.ps1 (else run tools\Update-Template.ps1)' (-not $m) ($m -join ', ')
$testHunk = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null).FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-HunkApplied' }, $true) | Select-Object -First 1
$results = if ($testHunk) {
    & {
        $hunkRepo = Join-Path $Work 'hunk-applied'
        New-Item -ItemType Directory -Force $hunkRepo | Out-Null
        Push-Location $hunkRepo
        try {
            Invoke-Git init -q
            . ([scriptblock]::Create($testHunk.Extent.Text))
            $hunk = '@@ -1,2 +1,2 @@', ' <Project>', '-</Project>', '\ No newline at end of file', '+</Project>'
            [IO.File]::WriteAllText((Join-Path $hunkRepo 'Directory.Build.props'), "<Project>`n</Project>`n")
            Test-HunkApplied 'Directory.Build.props' $hunk $Work
            [IO.File]::WriteAllText((Join-Path $hunkRepo 'Directory.Build.props'), "<Project>`n</Project>")
            Test-HunkApplied 'Directory.Build.props' $hunk $Work
        }
        finally { Pop-Location }
    }
}
Check 'update: a project-owned change the project already has is recognized, one it lacks is not' ((@($results) -join ',') -eq 'True,False') (@($results) -join ',')
$worktreeKinds = [ordered]@{
    create = 'plan-feature', 'plan-bugfix', 'plan-refactor', 'plan-tests', 'plan-migration', 'plan-performance', 'plan-security', 'plan-docs', 'handoff-plan', 'plan-issue', 'plan-template-update'
    join   = 'orchestrate-plan', 'execute-step', 'replan-step', 'review-plan-diff', 'ship-plan'
    finish = 'finish-plan'
}
$worktreeMissing = @(
    foreach ($kind in $worktreeKinds.Keys) {
        $section = [IO.File]::ReadAllText((Join-Path $workflow "templates\_claude-worktree-$kind.md")).Replace("`r`n", "`n").Trim()
        $worktreeKinds[$kind] | Where-Object { -not [IO.File]::ReadAllText((Join-Path $repoRoot "template\.claude\commands\$_.md")).Contains($section) }
    }
)
$worktreeLeaked = @(
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'template\.github'), (Join-Path $repoRoot 'template\.claude\agents') -Recurse -File |
        Where-Object { $text = [IO.File]::ReadAllText($_.FullName); $text.Contains('EnterWorktree') -or $text -match '(?m)^isolation:' } | ForEach-Object Name
    'analyze-architecture', 'analyze-decision', 'review-code', 'triage-issues', 'continue-plan' | Where-Object { [IO.File]::ReadAllText((Join-Path $repoRoot "template\.claude\commands\$_.md")).Contains('EnterWorktree') }
)
Check 'workflow: Claude Code planning commands create the plan''s worktree, and the commands that work on a plan move into it' (-not $worktreeMissing) ($worktreeMissing -join ', ')
Check 'workflow: no Copilot file, plan-executor subagent or analysis command enters a worktree' (-not $worktreeLeaked) ($worktreeLeaked -join ', ')
$both = Join-Path $Work 'installed-both'
New-Item -ItemType Directory -Force $both | Out-Null
$installed = & (Join-Path $workflow 'Install-HybridWorkflow.ps1') -Repo $both | Out-String
Check 'workflow: installer writes both variants for every tool' ($installed -match 'Wrote (\d+) files' -and [int]$Matches[1] -gt 37 -and (Test-Path (Join-Path $both '.github\agents\copilot-planner.agent.md')) -and (Test-Path (Join-Path $both '.github\skills\plan-feature\SKILL.md')))
$templateVersion = git -C $repoRoot describe --tags --always --dirty --match 'v[0-9]*'
$installedVersion = Join-Path $both '.template-version'
Check 'workflow: installer records the template version in .template-version' ((Test-Path -LiteralPath $installedVersion) -and ([IO.File]::ReadAllText($installedVersion) -eq "$templateVersion`n")) $templateVersion
$versionLeaked = @('template\.template-version', '.template-version' | Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot $_) })
Check 'workflow: template/ and this repository have no installer-written .template-version' (-not $versionLeaked) ($versionLeaked -join ', ')
$list = & (Join-Path $workflow 'New-PlanPrompt.ps1') -List | Out-String
$prompt = & (Join-Path $workflow 'New-PlanPrompt.ps1') plan-feature 'Add CSV export' | Out-String
Check 'workflow: New-PlanPrompt lists the templates and composes a prompt' ($list.Contains('execute-step') -and $prompt.Contains('Add CSV export') -and $prompt.Contains('### [ ] 1.'))
Check 'workflow: New-PlanPrompt -List shows each template''s targets' ($list -match '(?m)^run-issues\s+orchestrator\s+Claude\s{2,}\S' -and $list -match '(?m)^execute-step\s+executor\s+VSCode, Claude, CopilotCli\s')
$runnerRepo = Join-Path $Work 'runner'
New-Item -ItemType Directory -Force $runnerRepo | Out-Null
Copy-Item -LiteralPath (Join-Path $workflow 'templates\PLAN.example.md') (Join-Path $runnerRepo 'PLAN.md')
Push-Location $runnerRepo
try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Plan' }
finally { Pop-Location }
$dryRun = & (Join-Path $workflow 'Invoke-PlanSteps.ps1') -Plan (Join-Path $runnerRepo 'PLAN.md') -DryRun *>&1 | Out-String
Check 'workflow: Invoke-PlanSteps parses the example plan' ($dryRun.Contains('Add divide with zero-divisor validation') -and $dryRun.Contains('--- Prompt for step 1 ---')) $dryRun.Trim()
$stagesPlan = @(
    foreach ($dir in 'template\.github', 'template\.claude') {
        Get-ChildItem -LiteralPath (Join-Path $repoRoot $dir) -Recurse -File -Force |
            Where-Object { $t = [IO.File]::ReadAllText($_.FullName); $t.Contains('run `git add -A`') -or $t.Contains('`git add PLAN.md`') } | ForEach-Object Name
    }
)
Check 'workflow: no generated command, agent or skill stages everything with git add -A or commits PLAN.md' (-not $stagesPlan) ($stagesPlan -join ', ')
$commitRepo = Join-Path $Work 'runner-commit'
New-Item -ItemType Directory -Force $commitRepo | Out-Null
$saveCommit = [Management.Automation.Language.Parser]::ParseFile((Join-Path $workflow 'Invoke-PlanSteps.ps1'), [ref]$null, [ref]$null).FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Save-Commit' }, $true) | Select-Object -First 1
Push-Location $commitRepo
try {
    Invoke-Git init -q -b main; Invoke-Git config user.name template-test; Invoke-Git config user.email template-test@example.invalid
    Set-Content a.txt 'one'; Invoke-Git add a.txt; Invoke-Git commit -q -m 'Start'
    # The plan is untracked and not ignored here, so only the runner's own exclusion keeps it out of the commits.
    Set-Content PLAN.md '# Plan: x'; Set-Content a.txt 'two'; Set-Content b.txt 'new'
    & {
        $repo = $commitRepo; $planRel = 'PLAN.md'; $NoCommit = $false
        . ([scriptblock]::Create($saveCommit.Extent.Text))
        Save-Commit 'Plan step 1: x'
        Add-Content PLAN.md 'edit'
        Save-Commit 'Plan step 2: nothing changed'
        Save-Commit 'Re-plan step 2: x' -AllowEmpty
    }
    $subjects = @(git log --format=%s) -join '|'
    $tracked = @(git ls-files) -join ','
    $stepFiles = @(git show --name-only --format= HEAD~1) -join ','
    $replanFiles = @(git show --name-only --format= HEAD) -join ','
}
finally { Pop-Location }
Check 'workflow: Invoke-PlanSteps commits step files, records a re-plan as an empty commit, and never commits the plan' ($subjects -eq 'Re-plan step 2: x|Plan step 1: x|Start' -and $tracked -eq 'a.txt,b.txt' -and $stepFiles -eq 'a.txt,b.txt' -and -not $replanFiles) "$subjects | $tracked | $stepFiles | $replanFiles"

if (-not $SkipDotnetBuild) {
    Push-Location (Join-Path $Work 'dotnet')
    try {
        dotnet new classlib -o src/Demo | Out-Null
        dotnet new xunit -o tests/Demo.Tests --no-restore | Out-Null
        # As AGENTS.md tells the executor: move the template's PackageReference versions into Directory.Packages.props.
        $projPath = (Resolve-Path 'tests/Demo.Tests/Demo.Tests.csproj').Path
        $proj = [xml](Get-Content -LiteralPath $projPath -Raw)
        $versions = foreach ($ref in $proj.SelectNodes('//PackageReference[@Version]')) {
            "    <PackageVersion Include=""$($ref.Include)"" Version=""$($ref.Version)"" />"
            $ref.RemoveAttribute('Version')
        }
        $proj.Save($projPath)
        $propsPath = (Resolve-Path 'Directory.Packages.props').Path
        $props = [IO.File]::ReadAllText($propsPath) -replace '(?s)  <ItemGroup>\s*</ItemGroup>', ("  <ItemGroup>`n" + ($versions -join "`n") + "`n  </ItemGroup>")
        [IO.File]::WriteAllText($propsPath, $props)
        dotnet add tests/Demo.Tests reference src/Demo | Out-Null
        # As AGENTS.md tells the executor: every project joins the root solution, so the default commands cover it.
        dotnet new sln | Out-Null
        dotnet sln add src/Demo tests/Demo.Tests | Out-Null
        $output = dotnet build 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { $output = dotnet test 2>&1 | Out-String }
        $errors = ($output -split "`n" | Select-String -Pattern ' error ' | Select-Object -First 3) -join ' | '
        Check 'dotnet: classlib and xunit in the root solution pass dotnet build and dotnet test' ($LASTEXITCODE -eq 0) $errors
    }
    finally { Pop-Location }
}

if (-not $SkipUpdate) {
    $project = Join-Path $Work 'python'
    # Each project runs its own copy of the update script.
    $updateProject = Join-Path $project '.template\Update-Project.ps1'
    $handoffMarker = 'Update-Project.ps1 from v0.2.0 is running.'
    $rules = '.github/instructions/project-template.instructions.md'
    $added = '.claude/commands/added-in-v0.2.0.md'
    Push-Location $project
    try {
        Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Create project'
        # The project edits its own and its merged files, as it should, and edits and deletes template-owned files, which it shouldn't.
        Edit-File AGENTS.md "- (Add the project's conventions here, and any template rule this project overrides.)" '- Local convention added in the project.'
        Edit-File README.md '## AI-Assisted Workflow' '## AI-Assisted Workflow in This Project'
        [IO.File]::AppendAllText((Resolve-Path -LiteralPath .gitignore).Path, "local-cache/`n")
        Edit-File CLAUDE.md '## Claude Code' '## Claude Code, Edited in the Project'
        Remove-Item -LiteralPath .claude/commands/plan-docs.md, .vscode/extensions.json
        Invoke-Git add -A; Invoke-Git commit -q -m 'Local edits'
        $projectOwnedHashes = (Get-FileHash -LiteralPath AGENTS.md, README.md).Hash -join ','
    }
    finally { Pop-Location }

    # v0.2.0 changes the project-owned files, another part of .gitignore, CLAUDE.md and the rules, and removes and adds a template file.
    Push-Location (Join-Path $tpl 'template')
    try {
        Edit-File AGENTS.md.jinja 'Run from the repository root in PowerShell 7.' 'Run from the root of the {{ project_name }} repository in PowerShell 7.'
        Edit-File README.md.jinja '{{ project_description }}' '{{ project_description }} Updated.'
        Edit-File AGENTS.md.jinja "- (Add the project's conventions here, and any template rule this project overrides.)" '- Local convention added in the project.'
        Edit-File README.md.jinja '## AI-Assisted Workflow' '## AI-Assisted Workflow in This Project'
        Edit-File .gitignore.jinja 'Thumbs.db' "Thumbs.db`ndesktop.ini"
        Edit-File CLAUDE.md '## Claude Code' '## Claude Code, Updated'
        Edit-File "$rules.jinja" '## Conventions' '## Conventions, Updated'
        Edit-File .vscode/extensions.json.jinja '"editorconfig.editorconfig"' '"editorconfig.editorconfig", "example.added-in-v0-2-0"'
        Remove-Item -LiteralPath .claude/commands/analyze-decision.md
        Set-Content -LiteralPath $added 'Added in v0.2.0.' -NoNewline
        # A new version of the update script, which the project's v0.1.0 copy must hand the update over to.
        Edit-File .template/Update-Project.ps1 "`$ErrorActionPreference = 'Stop'`n" "`$ErrorActionPreference = 'Stop'`n'$handoffMarker'`n"
    }
    finally { Pop-Location }
    Push-Location $tpl
    try { Invoke-Git add -A; Invoke-Git commit -q -m 'Template change'; Invoke-Git tag v0.2.0 }
    finally { Pop-Location }

    # On the default branch the update refuses before it changes anything.
    Push-Location $project
    try {
        Invoke-Git update-ref refs/remotes/origin/main HEAD
        Invoke-Git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
        $before = git rev-parse HEAD
        $refusal = try { & $updateProject | Out-Null; 'no refusal' } catch { $_.Exception.Message }
        Check 'update: refuses to commit on the default branch' ($refusal.Contains('git switch -c build/project-template-v0.2.0') -and (git rev-parse HEAD) -eq $before -and -not (git status --porcelain)) $refusal
        Invoke-Git symbolic-ref --delete refs/remotes/origin/HEAD
        Invoke-Git update-ref -d refs/remotes/origin/main
    }
    finally { Pop-Location }

    $output = & $updateProject | Out-String
    Push-Location $project
    try {
        Check 'update: hands over to the v0.2.0 script through a blob-filtered clone' ($output.Contains('Handing the update over to the v0.2.0 version') -and $output.Contains($handoffMarker) -and (Select-String -LiteralPath .template/Update-Project.ps1 -SimpleMatch $handoffMarker -Quiet)) $output.Trim()
        Check 'update: one commit, nothing left over' (((git log -1 --format=%s) -eq 'Update from project-template v0.2.0') -and ((git rev-list --count HEAD) -eq 3) -and -not (git status --porcelain)) $output.Trim()
        $gitVersion = [version]((git version) -replace '^git version (\d+\.\d+\.\d+).*$', '$1')
        Check 'update: replaces the false Git version warning from Copier' (-not $output.Contains('installed to improve updates') -and ($gitVersion -lt [version]'2.55' -or $output.Contains('copier-org/copier#2759'))) $output.Trim()
        Check 'update: project-owned files untouched' (((Get-FileHash -LiteralPath AGENTS.md, README.md).Hash -join ',') -eq $projectOwnedHashes)
        $owned = if ($output -match '(?s)The template changed these project-owned files.*?(?=\r?\n\r?\nCommitted)') { $Matches[0] } else { '' }
        Check 'update: shows project-owned changes rendered with the project answers' ($owned -match '(?m)^  AGENTS\.md:\r?$' -and $owned.Contains('+Run from the root of the Test python repository in PowerShell 7.') -and $owned -notmatch '\{%|\{\{' -and $owned -notmatch '(?m)^  README\.md') $output.Trim()
        Check 'update: leaves out project-owned changes the project already has' ($owned -match '(?m)^  AGENTS\.md:\r?$' -and -not $owned.Contains('+- Local convention added in the project.') -and $owned -notmatch '(?m)^  README\.md') $output.Trim()
        $gitignore = Get-Content -LiteralPath .gitignore -Raw
        Check 'update: merged file keeps the project''s edit and gains the template''s' ($gitignore.Contains('local-cache/') -and $gitignore.Contains('desktop.ini'))
        Check 'update: deleted merged file stays deleted' (-not (Test-Path -LiteralPath .vscode/extensions.json))
        Check 'update: template-owned files replaced' ((Select-String -LiteralPath $rules -Pattern '## Conventions, Updated' -Quiet) -and (Select-String -LiteralPath CLAUDE.md -Pattern '## Claude Code, Updated' -Quiet))
        Check 'update: edit to a template-owned file discarded and reported' ((-not (Select-String -LiteralPath CLAUDE.md -Pattern 'Edited in the Project' -Quiet)) -and $output -match '(?s)Local edits discarded.*\n  CLAUDE\.md')
        Check 'update: deleted template-owned file restored and reported' ((Test-Path -LiteralPath .claude/commands/plan-docs.md) -and $output -match '(?s)Restored.*\n  \.claude/commands/plan-docs\.md')
        Check 'update: file removed from the template deleted' (-not (Test-Path -LiteralPath .claude/commands/analyze-decision.md))
        Check 'update: file added to the template created' ([bool](git ls-files -- $added))
        Check 'update: no conflict markers or .rej files' (-not (git grep -lE '^(<<<<<<<|>>>>>>>) ') -and -not (Get-ChildItem -Recurse -Filter '*.rej' -File))
        Check 'update: answers record v0.2.0' ((Get-Content -LiteralPath .copier-answers.yml -Raw) -match '(?m)^_commit: v0\.2\.0$')
        Check 'update: .template-version records v0.2.0' ((Get-Content -LiteralPath .template-version -Raw) -eq "v0.2.0`n")
        Check 'update: enables the hooks in the clone' (((git config core.hooksPath) -join '') -eq '.githooks')
        $head = git rev-parse HEAD
    }
    finally { Pop-Location }

    $output = & $updateProject | Out-String
    Check 'update: second run changes nothing' ($output.Contains('Already up to date') -and -not $output.Contains('Handing the update over') -and ((git -C $project rev-parse HEAD) -eq $head) -and -not (git -C $project status --porcelain)) $output.Trim()

    # v0.3.0 changes the .gitignore line the project changed too, and CLAUDE.md, which the project edited again: one conflict.
    Push-Location $project
    try {
        Edit-File .gitignore 'Thumbs.db' 'Thumbs.db # project'
        Edit-File CLAUDE.md '## Claude Code, Updated' '## Claude Code, Edited Again'
        Invoke-Git commit -q -am 'More local edits'
        $head = git rev-parse HEAD
    }
    finally { Pop-Location }
    Push-Location (Join-Path $tpl 'template')
    try { Edit-File .gitignore.jinja 'Thumbs.db' 'Thumbs.db # template'; Edit-File CLAUDE.md '## Claude Code, Updated' '## Claude Code, Updated Again' }
    finally { Pop-Location }
    Push-Location $tpl
    try { Invoke-Git commit -q -am 'Conflicting template change'; Invoke-Git tag v0.3.0 }
    finally { Pop-Location }

    $output = & $updateProject | Out-String
    $exitCode = $LASTEXITCODE
    Push-Location $project
    try {
        Check 'update: a conflict exits 1 and commits nothing' (($exitCode -eq 1) -and ((git rev-parse HEAD) -eq $head)) $output.Trim()
        Check 'update: the conflict is inline, unmerged in git, and reported' (((Get-Content -LiteralPath .gitignore -Raw) -match '(?s)<<<<<<< before updating\nThumbs\.db # project\n=======\nThumbs\.db # template\n>>>>>>> after updating') -and ((git status --porcelain -- .gitignore) -match '^UU ') -and $output.Contains('conflict  .gitignore'))
        Check 'update: only merged files conflict; template-owned ones are still replaced' ((@(git diff --name-only --diff-filter=U) -join ',') -eq '.gitignore' -and (Select-String -LiteralPath CLAUDE.md -Pattern '## Claude Code, Updated Again' -Quiet))
        Edit-File .gitignore "<<<<<<< before updating`nThumbs.db # project`n=======`nThumbs.db # template`n>>>>>>> after updating" 'Thumbs.db # project'
        Invoke-Git add -A
        Check 'update: resolving and committing completes it' (-not (git diff --cached --check) -and $LASTEXITCODE -eq 0)
        Invoke-Git commit -q -m 'Update from project-template v0.3.0'
        Check 'update: answers record v0.3.0' ((Get-Content -LiteralPath .copier-answers.yml -Raw) -match '(?m)^_commit: v0\.3\.0$' -and -not (git status --porcelain))
    }
    finally { Pop-Location }

    # The repository root's wrapper updates another project from this clone, handing over to the newest script.
    $other = Join-Path $Work 'node'
    Push-Location $other
    try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Create project'; [IO.File]::WriteAllText((Join-Path $other '.git\hooks\pre-commit'), "#!/bin/sh`n") }
    finally { Pop-Location }
    $output = & (Join-Path $repoRoot 'Update-Project.ps1') -Path $other | Out-String
    Check 'update: the root wrapper updates a project by -Path' (($LASTEXITCODE -eq 0) -and $output.Contains('Handing the update over to the v0.3.0 version') -and ((git -C $other log -1 --format=%s) -eq 'Update from project-template v0.3.0') -and -not (git -C $other status --porcelain)) $output.Trim()
    Check 'update: leaves core.hooksPath alone when the clone has hooks in .git/hooks' (-not (git -C $other config core.hooksPath) -and $output.Contains('has hooks of its own in .git/hooks (pre-commit)')) $output.Trim()
}
''
if ($failures.Count) { "Template tests: FAILED ($($failures.Count))"; exit 1 }
'Template tests: PASSED'
exit 0
