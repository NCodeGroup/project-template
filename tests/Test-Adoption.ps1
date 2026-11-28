<#
.SYNOPSIS
    Test adopting existing repositories into the template.

.DESCRIPTION
    Unit-tests the adoption functions and legacy adapters on small inputs and, unless -UnitOnly is given, adopts a
    Python repository on GitHub and a .NET repository built on the NCodeGroup scaffold from a tagged snapshot of the
    working tree, then updates the first to a later template version. tests/Test-AdoptEdgeCases.ps1 adopts the other
    fixture repositories. Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER UnitOnly
    Run only the unit checks, which take seconds.

.PARAMETER SkipDotnetBuild
    Skip the .NET build and pack.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-adopt-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-Adoption.ps1
    .\tests\Test-Adoption.ps1 -UnitOnly
    .\tests\Test-Adoption.ps1 -SkipDotnetBuild
#>
[CmdletBinding()]
param(
    [switch]$UnitOnly,
    [switch]$SkipDotnetBuild,
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-adopt-test-$PID")
)
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Edit-File([string]$Path, [string]$Old, [string]$New) {
    $full = (Resolve-Path -LiteralPath $Path).Path
    $text = [IO.File]::ReadAllText($full)
    if (-not $text.Contains($Old)) { throw "'$Old' not found in $full." }
    [IO.File]::WriteAllText($full, $text.Replace($Old, $New))
}
. (Join-Path $PSScriptRoot 'AdoptionFixtures.ps1')

Import-Module (Join-Path $repoRoot 'tools\adopt\Adoption.psm1') -Force
if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
# A direct run keeps its Copier mirror in its own work folder, not in the user's cache; under tests\Invoke-AllTests.ps1 it keeps the runner's folder.
$copierCache = $env:COPIER_CACHE_DIR
if (-not $copierCache) { $env:COPIER_CACHE_DIR = Join-Path $Work 'copier-cache' }
New-Item -ItemType Directory -Force $Work | Out-Null

$copierYml = Join-Path $repoRoot 'copier.yml'
$skip = @(Get-CopierList $copierYml '_skip_if_exists')
$merged = @(Get-CopierList $copierYml '_merged_files')
Check 'unit: Get-CopierList reads the file lists' (($skip -join ',') -eq '/AGENTS.md,/README.md,/.node-version,/Directory.Build.props,/version.json,/.github/workflows/code-review.yml,/.github/workflows/publish.yml,/docs/decisions/README.md,/docs/decisions/0000-template.md,/LICENSE.txt,/COPYRIGHT.txt,/NCodeGroup.png,/SECURITY.md,/CONTRIBUTING.md,/GOVERNANCE.md,/CODE_OF_CONDUCT.md,/ROADMAP.md,/docs/README.md,/docs/metrics.md,/docs/api-compatibility.md,/docs/architecture.md,/docs/assurance-case.md,/docs/best-practices-badge.md,/.config/dotnet-tools.json,/.csharpierignore,/biome.json,/docs/designs/_template.md' -and '.gitignore' -in $merged -and 'global.json' -in $merged -and 'nuget.config' -in $merged -and '.github/workflows/copilot-setup-steps.yml' -in $merged) "$($skip -join ',') | $($merged -join ',')"
$ownable = @(Get-OwnableFile (Join-Path $repoRoot 'template'))
$one = Get-OwnedFile '.github/workflows/ci.yml' $ownable
$dropped = Get-OwnedFile @('build/dod.ps1', '', $null, 'build/dod.ps1') $ownable
$none = Get-OwnedFile @() $ownable
$ownedMsg = try { Get-OwnedFile @('.template/Update-Project.ps1', '.copier-answers.yml', '.template-version', 'no-such-file.txt') $ownable | Out-Null } catch { $_.Exception.Message }
Check 'unit: Get-OwnedFile makes a list of files the template renders and rejects the update''s own files' (($one -is [array]) -and $one.Count -eq 1 -and $one[0] -eq '.github/workflows/ci.yml' -and $dropped.Count -eq 1 -and $dropped[0] -eq 'build/dod.ps1' -and $none.Count -eq 0 -and 'CLAUDE.md' -in $ownable -and '.github/workflows/copilot-setup-steps.yml' -in $ownable -and '.template-version' -notin $ownable -and "$ownedMsg".Contains('project_owned_files names .template/Update-Project.ps1, .copier-answers.yml, .template-version, no-such-file.txt, which the template doesn''t render or the update itself needs')) "$($one -join ',') | $($dropped -join ',') | $($none.Count) | $ownedMsg"
# Update-Project.ps1 ships alone and can't import Adoption.psm1, so the two copies of the ownable rule must agree: apply the update's own functions to the files Git tracks in template/.
$updateAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'template\.template\Update-Project.ps1'), [ref]$null, [ref]$null)
foreach ($fnName in 'ConvertTo-ProjectName', 'Test-OwnableName') {
    $fn = $updateAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $fnName }, $true)
    if ($fn) { . ([scriptblock]::Create($fn.Extent.Text)) }
}
$updateOwnable = @(git -C $repoRoot ls-files -- template/ | ForEach-Object { ConvertTo-ProjectName $_ } | Where-Object { Test-OwnableName $_ } | Sort-Object -Unique)
$adoptOwnable = @(Get-OwnableFile (Join-Path $repoRoot 'template') | Sort-Object -Unique)
$onlyOne = @(Compare-Object $updateOwnable $adoptOwnable | ForEach-Object { "$($_.InputObject) $($_.SideIndicator)" })
Check 'unit: Get-OwnableFile and Update-Project.ps1 agree on which files a project can own' ($updateOwnable.Count -gt 50 -and -not $onlyOne.Count) "update=$($updateOwnable.Count) adopt=$($adoptOwnable.Count) $($onlyOne -join '; ')"
$msbuild = New-TestFolder 'bin/msbuild' @{ 'Directory.Build.props' = "<Project />`n"; 'src/A/A.csproj' = "<Project />`n"; 'src/A/obj/B.csproj' = "<Project />`n"; '.claude/worktrees/wt/src/C/C.csproj' = "<Project />`n" }
$found = @(Get-MSBuildFile $msbuild | ForEach-Object { [IO.Path]::GetRelativePath($msbuild, $_.FullName) -replace '\\', '/' } | Sort-Object) -join ','
$inWorktree = @(Get-MSBuildFile (Join-Path $msbuild '.claude/worktrees/wt') | ForEach-Object Name) -join ','
Check 'unit: Get-MSBuildFile skips bin, obj and .claude folders below the folder it scans, also in a clone below a folder named bin, and reads a plan''s worktree' ($found -eq 'Directory.Build.props,src/A/A.csproj' -and $inWorktree -eq 'C.csproj') "$found | $inWorktree"

$demo = New-TestFolder 'demo' @{
    'src/NCode.Demo.slnx'   = '<Solution />'
    'Directory.Build.props' = "<Project>`n  <PropertyGroup>`n    <Authors>NCode Group</Authors>`n  </PropertyGroup>`n</Project>`n"
}
Push-Location $demo
try { Invoke-Git init -q -b main; Invoke-Git remote add origin https://github.com/example/demo.git }
finally { Pop-Location }
$a = Get-AdoptionAnswers $demo
$detail = ($a.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; '
Check 'unit: Get-AdoptionAnswers works out a .NET repository' (($a.stack -eq 'dotnet') -and ($a.project_name -eq 'NCode.Demo') -and ($a.author_name -eq 'NCode Group') -and ($a.build_command -eq 'dotnet build src/NCode.Demo.slnx') -and ($a.test_command -eq 'dotnet test src/NCode.Demo.slnx')) $detail
Check 'unit: Get-AdoptionAnswers answers pre_release tracked, since a repository has a history' ($a.pre_release -eq 'tracked') $detail
# The refusals come before the adoption touches anything; the fixtures carry a local identity, which the script's own check needs.
$adoptScript = Join-Path $repoRoot 'Adopt-Project.ps1'
$gitlabOrigin = New-Fixture 'gitlab-origin' @{ 'README.md' = "t`n" } 'https://user:secret@gitlab.com/example/gitlab-origin.git'
Invoke-Git -C $gitlabOrigin config user.name template-test
Invoke-Git -C $gitlabOrigin config user.email template-test@example.invalid
$gitlabMessage = try { & $adoptScript -Path $gitlabOrigin -Template $repoRoot | Out-Null; '' } catch { $_.Exception.Message }
$gitlabStatus = "$(git -C $gitlabOrigin status --porcelain)"
Check 'unit: Adopt-Project.ps1 refuses a repository whose origin isn''t on GitHub, without its credentials, and leaves it alone' ($gitlabMessage.Contains('NCodeGroup''s GitHub repositories only') -and $gitlabMessage.Contains('https://gitlab.com/example/gitlab-origin.git') -and -not $gitlabMessage.Contains('secret') -and -not $gitlabStatus) "$gitlabMessage | $gitlabStatus"
$githubOrigin = New-Fixture 'github-origin' @{ 'README.md' = "t`n" } 'https://github.com/example/github-origin.git'
Invoke-Git -C $githubOrigin config user.name template-test
Invoke-Git -C $githubOrigin config user.email template-test@example.invalid
$hostMessage = try { & $adoptScript -Path $githubOrigin -Template $repoRoot -Data @{ git_host = 'gitlab' } | Out-Null; '' } catch { $_.Exception.Message }
$hostStatus = "$(git -C $githubOrigin status --porcelain)"
Check 'unit: Adopt-Project.ps1 refuses -Data that answers git_host other than github and leaves the repository alone' ($hostMessage.Contains('NCodeGroup''s GitHub repositories only') -and $hostMessage.Contains('git_host ''gitlab''') -and -not $hostStatus) "$hostMessage | $hostStatus"
$remoteWanted = [ordered]@{
    'https://github.com/example/x.git'                 = $true
    'https://user:token@github.com/example/x.git'      = $true
    'git@github.com:example/x.git'                     = $true
    'ssh://git@github.com/example/x.git'               = $true
    'https://gitlab.com/example/x.git'                 = $false
    'git@gitlab.com:example/x.git'                     = $false
    'https://github.com.evil.example/example/x.git'    = $false
}
$remoteWrong = @($remoteWanted.Keys | Where-Object { [bool](Test-GitHubRemote $_) -ne $remoteWanted[$_] })
Check 'unit: Test-GitHubRemote accepts GitHub over https, with credentials, scp-style SSH and ssh://, and nothing else' ($remoteWrong.Count -eq 0) ($remoteWrong -join ' | ')
$apacheText = "                                 Apache License`n                           Version 2.0, January 2004`n"
$licenseFolders = [ordered]@{
    'license-props' = @{ Files = @{ 'src/A/A.csproj' = "<Project />`n"; 'Directory.Build.props' = "<Project>`n  <PropertyGroup>`n    <PackageLicenseExpression>MIT</PackageLicenseExpression>`n  </PropertyGroup>`n</Project>`n"; 'LICENSE' = $apacheText }; License = 'MIT' }
    'license-apache' = @{ Files = @{ 'pyproject.toml' = "x`n"; 'LICENSE.txt' = $apacheText }; License = 'Apache-2.0' }
    'license-mit'    = @{ Files = @{ 'pyproject.toml' = "x`n"; 'LICENSE.md' = "MIT License`n`nCopyright (c) 2026 Example`n" }; License = 'MIT' }
    'license-own'    = @{ Files = @{ 'pyproject.toml' = "x`n"; 'LICENSE' = "Own license.`n" }; License = $null }
}
$badLicense = foreach ($name in $licenseFolders.Keys) {
    $a = Get-AdoptionAnswers (New-TestFolder $name $licenseFolders[$name].Files)
    $want = $licenseFolders[$name].License
    if ($want) { if ($a.license -ne $want) { "${name}: license=$($a.license)" } }
    elseif ($a.Contains('license')) { "${name}: license=$($a.license)" }
}
Check 'unit: Get-AdoptionAnswers works out the license' (-not $badLicense) ($badLicense -join ' | ')

$others = [ordered]@{
    'only-python' = @{ Files = @('pyproject.toml'); Stack = 'python' }
    'only-ps'     = @{ Files = @('tool.ps1'); Stack = 'powershell' }
    'only-other'  = @{ Files = @('main.tf'); Stack = 'other' }
    'tofu-helper' = @{ Files = @('modules/net/main.tf', 'live/dev/main.tf', 'build/helper.ps1', 'build/tests/helper.tests.ps1'); Stack = 'other' }
    'tofu-script' = @{ Files = @('main.tofu', 'tests/main.tftest.hcl', 'deploy.ps1'); Stack = 'other' }
    'go-helper' = @{ Files = @('go.mod', 'scripts/build.ps1', '.github/scripts/release.ps1', 'tools/lint.psm1'); Stack = 'other' }
    'ps-module' = @{ Files = @('src/Demo/Demo.psd1', 'src/Demo/Demo.psm1', 'build/build.ps1'); Stack = 'powershell' }
}
$bad = foreach ($name in $others.Keys) {
    $files = @{}
    foreach ($file in $others[$name].Files) { $files[$file] = "x`n" }
    $folder = New-TestFolder $name $files
    $a = Get-AdoptionAnswers $folder
    if (-not ($a.stack -eq $others[$name].Stack -and $a.project_name -eq $name -and -not $a.Contains('build_command'))) {
        "${name}: $(($a.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ')"
    }
}
Check 'unit: Get-AdoptionAnswers works out other stacks' (-not $bad) ($bad -join ' | ')

$nodes = [ordered]@{
    'node-yarn'       = @{ Files = @{ 'package.json' = '{"packageManager":"yarn@4.14.1","scripts":{"build":"tsc","test":"vitest run"}}' }; Manager = 'yarn'; Build = 'yarn run build'; Test = 'yarn run test' }
    'node-pnpm'       = @{ Files = @{ 'package.json' = '{"scripts":{"test":"vitest run"}}'; 'pnpm-lock.yaml' = "lockfileVersion: '9.0'`n" }; Manager = 'pnpm'; Build = ''; Test = 'pnpm run test' }
    'node-bun'        = @{ Files = @{ 'package.json' = '{"scripts":{"build":"bun build ./index.ts"}}'; 'bun.lock' = "{}`n" }; Manager = 'bun'; Build = 'bun run build'; Test = '' }
    'node-npm'        = @{ Files = @{ 'package.json' = '{"scripts":{"build":"tsc","test":"echo \"Error: no test specified\" && exit 1"}}' }; Manager = 'npm'; Build = 'npm run build'; Test = '' }
    'node-no-scripts' = @{ Files = @{ 'package.json' = '{"packageManager":"yarn@4.14.1","scripts":{"diagram:export":"echo export"}}'; 'yarn.lock' = "`n" }; Manager = 'yarn'; Build = ''; Test = '' }
}
$bad = foreach ($name in $nodes.Keys) {
    $folder = New-TestFolder $name $nodes[$name].Files
    $a = Get-AdoptionAnswers $folder
    if (-not ($a.stack -eq 'node' -and $a.project_name -eq $name -and $a.package_manager -eq $nodes[$name].Manager -and $a.Contains('build_command') -and $a.build_command -eq $nodes[$name].Build -and $a.Contains('test_command') -and $a.test_command -eq $nodes[$name].Test)) {
        "${name}: $(($a.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ')"
    }
}
Check 'unit: Get-AdoptionAnswers works out Node.js commands from package.json' (-not $bad) ($bad -join ' | ')

$nodeUse = [ordered]@{
    'use-dotnet-web'     = @{ Files = @('src/A/A.csproj', 'src/Web/package.json'); Stack = 'dotnet'; UsesNode = $true }
    'use-python-nvmrc'   = @{ Files = @('pyproject.toml', '.nvmrc'); Stack = 'python'; UsesNode = $true }
    'use-dotnet-modules' = @{ Files = @('src/A/A.csproj', 'node_modules/x/package.json'); Stack = 'dotnet'; UsesNode = $false }
    'use-python'         = @{ Files = @('pyproject.toml'); Stack = 'python'; UsesNode = $false }
    'use-python-deep'    = @{ Files = @('pyproject.toml', 'a/b/c/package.json'); Stack = 'python'; UsesNode = $false }
    'use-node'           = @{ Files = @('package.json'); Stack = 'node'; UsesNode = $false }
}
$bad = foreach ($name in $nodeUse.Keys) {
    $files = @{}
    foreach ($file in $nodeUse[$name].Files) { $files[$file] = if ($file -like '*package.json') { '{}' } else { "x`n" } }
    $folder = New-TestFolder $name $files
    $a = Get-AdoptionAnswers $folder
    $want = $nodeUse[$name]
    if (-not ($a.stack -eq $want.Stack -and $a.Contains('uses_node') -eq $want.UsesNode -and (-not $want.UsesNode -or $a.uses_node -eq $true))) {
        "${name}: $(($a.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ')"
    }
}
Check 'unit: Get-AdoptionAnswers answers uses_node for a repository that uses Node.js without being a Node.js project' (-not $bad) ($bad -join ' | ')

$versionCases = [ordered]@{
    'ver-nvmrc'   = @{ Files = @{ '.nvmrc' = "v22`n" }; File = '.nvmrc'; Version = '22'; Text = 'v22' }
    'ver-alias'   = @{ Files = @{ '.nvmrc' = "lts/iron`n" }; File = '.nvmrc'; Version = $null; Text = 'lts/iron' }
    'ver-both'    = @{ Files = @{ '.node-version' = "24.1.0`n"; '.nvmrc' = "20`n" }; File = '.node-version'; Version = '24.1.0'; Text = '24.1.0' }
    'ver-none'    = @{ Files = @{}; File = $null }
}
$bad = foreach ($name in $versionCases.Keys) {
    $want = $versionCases[$name]
    $v = Get-NodeVersionFile (New-TestFolder $name $want.Files)
    $ok = if ($null -eq $want.File) { $null -eq $v } else { $v -and $v.File -eq $want.File -and $v.Version -eq $want.Version -and $v.Text -eq $want.Text }
    if (-not $ok) { "${name}: $($v | ConvertTo-Json -Compress)" }
}
Check 'unit: Get-NodeVersionFile reads .node-version before .nvmrc, without a leading v' (-not $bad) ($bad -join ' | ')

$toolCases = [ordered]@{
    'tools-copilot' = @{ Files = @{ '.github/agents/copilot-implementer.agent.md' = "x`n"; '.github/agents/plan-executor.agent.md' = "x`n" }; Tools = 'claude,copilot' }
    'tools-skills'  = @{ Files = @{ '.github/skills/a/SKILL.md' = "x`n" }; Tools = 'claude,copilot' }
    'tools-prompts' = @{ Files = @{ '.github/prompts/a.prompt.md' = "x`n" }; Tools = 'claude,copilot' }
    'tools-hybrid'  = @{ Files = @{ '.github/agents/hybrid-planner.agent.md' = "x`n" }; Tools = 'claude,local' }
    'tools-all'     = @{ Files = @{ '.github/agents/copilot-planner.agent.md' = "x`n"; '.github/agents/hybrid-planner.agent.md' = "x`n" }; Tools = 'claude,copilot,local' }
    'tools-none'    = @{ Files = @{ '.github/agents/reviewer.agent.md' = "x`n"; '.github/workflows/ci.yml' = "x`n" }; Tools = '' }
}
$bad = foreach ($name in $toolCases.Keys) {
    $a = Get-AdoptionAnswers (New-TestFolder $name $toolCases[$name].Files)
    $expected = $toolCases[$name].Tools
    $ok = if ($expected) { $a.workflow_tools -is [array] -and ($a.workflow_tools -join ',') -eq $expected } else { -not $a.Contains('workflow_tools') }
    if (-not $ok) { "${name}: $($a.workflow_tools -join ',')" }
}
Check 'unit: Get-AdoptionAnswers works out workflow_tools from the agent files' (-not $bad) ($bad -join ' | ')

# A Claude Code plan worktree, .claude/worktrees/<name>, is named after the plan, not the repository.
$wtRemote = New-TestFolder 'wt-remote' @{ 'README.md' = "# x`n" }
$wtLocal = New-TestFolder 'wt-local' @{ 'README.md' = "# x`n" }
foreach ($folder in $wtRemote, $wtLocal) {
    Invoke-Git -C $folder init -q -b main
    Invoke-Git -C $folder add -A
    Invoke-Git -C $folder commit -q -m Initial
    Invoke-Git -C $folder worktree add -q (Join-Path $folder '.claude/worktrees/adopt-project-template') -b adopt
}
Invoke-Git -C $wtRemote remote add origin https://github.com/example/identity-platform.git
$n1 = (Get-AdoptionAnswers $wtRemote).project_name
$n2 = (Get-AdoptionAnswers (Join-Path $wtRemote '.claude/worktrees/adopt-project-template')).project_name
Check 'unit: Get-AdoptionAnswers names the project after the origin remote, in a worktree too' (($n1 -eq 'identity-platform') -and ($n2 -eq 'identity-platform')) "$n1 | $n2"
$n3 = (Get-AdoptionAnswers (Join-Path $wtLocal '.claude/worktrees/adopt-project-template')).project_name
Check 'unit: Get-AdoptionAnswers names a worktree without a remote after the main checkout' ($n3 -eq 'wt-local') $n3

$m = Merge-AdoptedFile '.gitignore' "bin/`nmine.log`n" "*.user`nobj/`n"
Check 'unit: Merge-AdoptedFile appends lines' ($m.Strategy -eq 'Lines' -and $m.Text.StartsWith("*.user`nobj/`n") -and $m.Text.EndsWith("`nbin/`nmine.log`n")) $m.Text

$m = Merge-AdoptedFile '.editorconfig' "root = true`n`n[*.cs]`nindent_size = 4`n" "root = true`n`n[*]`nindent_style = space`n"
Check 'unit: Merge-AdoptedFile keeps one editorconfig root' (@($m.Text -split "`n" | Where-Object { $_ -match '^\s*root\s*=' }).Count -eq 1 -and $m.Text.Contains('[*.cs]')) $m.Text

$m = Merge-AdoptedFile '.vscode/settings.json' ('{' + "`n" + '  // mine' + "`n" + '  "files.eol": "\r\n", "recommendations": ["a","b"], "editor.rulers": [100]' + "`n" + '}') '{"files.eol":"\n","recommendations":["a"]}'
$j = $m.Text | ConvertFrom-Json -AsHashtable
Check 'unit: Merge-AdoptedFile merges JSON' ($m.Strategy -eq 'Json' -and ($j.Keys -join ',') -eq 'files.eol,recommendations,editor.rulers' -and $j['files.eol'] -eq "`r`n" -and ($j.recommendations -join ',') -eq 'a,b' -and $m.Note -like '*comments*') $m.Text
$m = Merge-AdoptedFile '.claude/settings.json' '{"$schema":"https://json.schemastore.org/claude-code-settings.json","a":1}' '{"b":2}'
$j = $m.Text | ConvertFrom-Json -AsHashtable
Check 'unit: Merge-AdoptedFile does not report comments for a schema URL' ([string]::IsNullOrEmpty($m.Note) -and $j.ContainsKey('a') -and $j.ContainsKey('b')) $m.Note
$m = Merge-AdoptedFile 'x.json' '{"l":["a"]}' '{"l":["a"],"z":1}'
Check 'unit: Merge-AdoptedFile keeps a single-item JSON list' ($m.Text -match '"l":\s*\[\s*"a"\s*\]') $m.Text

$m = Merge-AdoptedFile 'Directory.Build.props' "<Project>`n  <PropertyGroup><LangVersion>latest</LangVersion></PropertyGroup>`n</Project>`n" "<Project>`n  <PropertyGroup>`n    <Nullable>enable</Nullable>`n  </PropertyGroup>`n</Project>`n"
$i1 = $m.Text.IndexOf('<Nullable>'); $i2 = $m.Text.IndexOf('<!-- Kept'); $i3 = $m.Text.IndexOf('<LangVersion>')
Check 'unit: Merge-AdoptedFile appends MSBuild elements' ($m.Strategy -eq 'MSBuild' -and $i1 -ge 0 -and $i1 -lt $i2 -and $i2 -lt $i3 -and $m.Text.EndsWith("</Project>`n")) $m.Text

$m = Merge-AdoptedFile '.github/workflows/ci.yml' "name: mine`n" "name: template`n"
Check 'unit: Merge-AdoptedFile keeps YAML' ($m.Strategy -eq 'Keep' -and $m.Text -eq "name: mine`n") $m.Strategy

$m = Merge-AdoptedFile '.gitignore' "bin/`n" "bin/`n`n"
Check 'unit: Merge-AdoptedFile leaves a matching file' ($m.Strategy -eq 'Same') $m.Strategy

$entryMarker = 'project-template.instructions.md'
$r = Add-TemplateIndexEntry "# Guide`n`n## Instructions`n`n- @a.md - mine`n`n## Layout`n"
$lines = $r -split "`n"
$h = [array]::IndexOf($lines, '## Instructions')
Check 'unit: Add-TemplateIndexEntry under Instructions' ($h -ge 0 -and $lines[$h + 1] -eq '' -and $lines[$h + 2].Contains($entryMarker) -and $lines[$h + 3] -eq '- @a.md - mine' -and $r.EndsWith("## Layout`n")) $r
$r = Add-TemplateIndexEntry "# Guide`n`nSome text.`n`n## Layout`n- x`n"
$lines = $r -split "`n"
$pt = [array]::IndexOf($lines, '## Project Template'); $ly = [array]::IndexOf($lines, '## Layout')
Check 'unit: Add-TemplateIndexEntry before the first section' ($lines[2] -eq 'Some text.' -and $pt -eq 4 -and $lines[3] -eq '' -and $lines[5] -eq '' -and $lines[6].Contains($entryMarker) -and $lines[7] -eq '' -and $ly -eq 8 -and $r.EndsWith("`n") -and -not $r.EndsWith("`n`n")) $r
Check 'unit: Add-TemplateIndexEntry once' ((Add-TemplateIndexEntry $r) -eq $r) ''
Check 'unit: Test-KeepAChangelog' ((Test-KeepAChangelog "# Changelog`n`n## [Unreleased]`n") -and (Test-KeepAChangelog "# Changelog`n`n## [1.0.0] - 2026-01-01`n") -and -not (Test-KeepAChangelog "# Changes`n`n## v1.0.0`n`n- First.`n")) ''
$x = "<?xml version=""1.0""?>`n<Project>`n  <PropertyGroup>`n    <A>1</A>`n  </PropertyGroup>`n</Project>`n"
$r = Add-ProjectTemplateImport $x
Check 'unit: Add-ProjectTemplateImport' ($r.StartsWith("<?xml version=""1.0""?>`n<Project>`n") -and $r.Contains('<Import Project="$(MSBuildThisFileDirectory)build/ProjectTemplate.props" />') -and $r.IndexOf('<Import') -lt $r.IndexOf('<PropertyGroup>') -and (Add-ProjectTemplateImport $r) -eq $r) $r
# The template's Directory.Packages.props as a project without nuget_package renders it.
$central = (Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'template\Directory.Packages.props.jinja')) -replace '\{%-? if nuget_package %\}[\s\S]*?\{%-? endif %\}', ''
if ($central.Contains('{%')) { throw "The test can't render the template's Directory.Packages.props: it has Jinja this test doesn't strip." }
$folder = New-TestFolder 'central' @{
    'Directory.Packages.props' = $central
    'A/A.csproj'               = "<Project Sdk=""Microsoft.NET.Sdk"">`n  <ItemGroup>`n    <PackageReference Include=""Foo"" Version=""1.0.0"" />`n  </ItemGroup>`n</Project>`n"
    'B/B.csproj'               = "<Project Sdk=""Microsoft.NET.Sdk"">`n  <ItemGroup>`n    <PackageReference Version=""1.2.0"" Include=""Foo"" />`n    <PackageReference Include=""Bar"" Version=""2.0.0"" PrivateAssets=""all"" />`n  </ItemGroup>`n</Project>`n"
}
$report = @(Move-PackageVersionsToCentral $folder)
$pa = Get-Content -Raw -LiteralPath (Join-Path $folder 'A/A.csproj')
$pb = Get-Content -Raw -LiteralPath (Join-Path $folder 'B/B.csproj')
$pp = Get-Content -Raw -LiteralPath (Join-Path $folder 'Directory.Packages.props')
$iBar = $pp.IndexOf('<PackageVersion Include="Bar" Version="2.0.0" />')
$iFoo = $pp.IndexOf('<PackageVersion Include="Foo" Version="1.2.0" />')
Check 'unit: Move-PackageVersionsToCentral' (-not $pa.Contains('Version="') -and -not $pb.Contains('Version="') -and $pb.Contains('PrivateAssets="all"') -and $iBar -ge 0 -and $iBar -lt $iFoo -and 'Foo: 1.0.0, 1.2.0 -> 1.2.0' -in $report) "$pa | $pb | $pp | $($report -join ' / ')"
$adapters = Join-Path $repoRoot 'tools\adopt\legacy'
$scaffold = Join-Path $adapters 'NCode.ProjectSettings.Scaffold.ps1'
$folder = New-TestFolder 'bin/scaffold-adapter' @{
    'NCodeGroup.png'                           = $png
    'src/A/A.csproj'                           = "<Project Sdk=""Microsoft.NET.Sdk"">`n  <PropertyGroup>`n    <DocumentationFile>bin\`$(Configuration)\A.xml</DocumentationFile>`n  </PropertyGroup>`n  <ItemGroup>`n    <PackageReference Include=""NCode.ProjectSettings.Scaffold""`n                      Version=""1.0.0"">`n      <PrivateAssets>all</PrivateAssets>`n    </PackageReference>`n    <PackageReference Include=""JetBrains.Annotations"" Version=""2.0.0"" />`n    <PackageReference Include=""Microsoft.SourceLink.GitHub"" Version=""10.0.0"" PrivateAssets=""all"" />`n  </ItemGroup>`n</Project>`n"
    'src/A/project.props'                      = "<Project>`n  <PropertyGroup>`n    <Description>A.</Description>`n  </PropertyGroup>`n</Project>`n"
    # Build output the leftover reports must leave alone.
    'src/A/bin/Debug/project.props'            = "<Project />`n"
    '.claude/worktrees/wt/src/B/project.props' = "<Project />`n"
    'A.sln.DotSettings'                        = "<wpf:ResourceDictionary />`n"
    '.github/workflows/main.yml'               = "on: release`njobs:`n  publish:`n    runs-on: ubuntu-latest`n    steps:`n      - run: dotnet nuget push x.nupkg`n"
    '.github/workflows/publish.yml'            = "on: release`njobs:`n  publish:`n    runs-on: ubuntu-latest`n    steps:`n      - run: dotnet nuget push x.nupkg`n"
}
$detected = & $scaffold -Path $folder -Phase Detect
$a = & $scaffold -Path $folder -Phase Answers
$out = @(& $scaffold -Path $folder -Phase Apply)
$proj = Get-Content -Raw -LiteralPath (Join-Path $folder 'src/A/A.csproj')
$after = & $scaffold -Path $folder -Phase Detect
Check 'unit: scaffold adapter' ($detected -eq $true -and $a.nuget_package -eq $true -and $a.license -eq 'Apache-2.0' -and $a.author_name -eq 'NCode Group' -and $a.package_icon -eq 'NCodeGroup.png' -and $out[0] -like '*src/A/A.csproj' -and $proj.Contains('JetBrains.Annotations') -and -not $proj.Contains('NCode.ProjectSettings.Scaffold') -and $after -eq $false) "$detected | $($out -join ' / ') | $proj | $after"
$leftovers = $out -join "`n"
Check 'unit: scaffold adapter reports what the package left behind' ($leftovers.Contains('References Microsoft.SourceLink.GitHub, which the .NET SDK builds in: remove it from src/A/A.csproj') -and $leftovers.Contains('Sets DocumentationFile') -and $leftovers.Contains('Nothing imports src/A/project.props now') -and -not $leftovers.Contains('bin/Debug/project.props') -and -not $leftovers.Contains('.claude/') -and $leftovers.Contains('A.sln.DotSettings holds the scaffold''s ReSharper file header') -and $leftovers.Contains('.github/workflows/main.yml pushes packages to NuGet too') -and -not $leftovers.Contains('.github/workflows/publish.yml pushes')) $leftovers

$workflow = Join-Path $adapters 'HybridWorkflowInstall.ps1'
$folder = New-TestFolder 'workflow-install' @{ '.github/prompts/execute-step-copilot.prompt.md' = "old`n" }
$detected = & $workflow -Path $folder -Phase Detect
$out = @(& $workflow -Path $folder -Phase Apply)
$gone = -not (Test-Path -LiteralPath (Join-Path $folder '.github/prompts/execute-step-copilot.prompt.md'))
$after = & $workflow -Path $folder -Phase Detect
Check 'unit: workflow install adapter' ($detected -eq $true -and $gone -and $out.Count -eq 1 -and $after -eq $false) "$detected | $($out -join ' / ') | $after"

$withOrigin = New-Fixture 'source-origin' @{ 'README.md' = "t`n" } 'https://example.invalid/fork/project-template.git'
$sourceProject = New-TestFolder 'source-project' @{ '.copier-answers.yml' = "# Written by Copier`n_commit: v0.1.0`n_src_path: first part`n  second part`nproject_name: Demo`n" }
$note = @(Set-TemplateSource $sourceProject $withOrigin)
$sourceAnswers = Get-Content -Raw -LiteralPath (Join-Path $sourceProject '.copier-answers.yml')
Check 'unit: Set-TemplateSource records a local clone''s origin' ($sourceAnswers -eq "# Written by Copier`n_commit: v0.1.0`n_src_path: https://example.invalid/fork/project-template.git`nproject_name: Demo`n" -and $note[0].Contains('the origin remote of')) "$sourceAnswers | $($note -join ' / ')"
$plainFolder = New-TestFolder 'source-plain' @{ 'README.md' = "t`n" }
$plainAnswersText = "# Written by Copier`n_commit: v0.1.0`n_src_path: $plainFolder`nproject_name: Demo`n"
$plainProject = New-TestFolder 'source-project2' @{ '.copier-answers.yml' = $plainAnswersText }
$out = @(Set-TemplateSource $plainProject $plainFolder 3>&1)
$plainAnswers = Get-Content -Raw -LiteralPath (Join-Path $plainProject '.copier-answers.yml')
Check 'unit: Set-TemplateSource warns for a folder without an origin address and leaves the answers' ($plainAnswers -eq $plainAnswersText -and $out.Count -eq 1 -and $out[0] -is [Management.Automation.WarningRecord] -and $out[0].Message.Contains('which only this PC has')) "$plainAnswers | $($out -join ' / ')"
$url = @(Set-TemplateSource $plainProject 'https://github.com/NCodeGroup/project-template.git' 3>&1)
$urlAnswers = Get-Content -Raw -LiteralPath (Join-Path $plainProject '.copier-answers.yml')
Check 'unit: Set-TemplateSource leaves an address alone' ($url.Count -eq 0 -and $urlAnswers -eq $plainAnswersText) "$($url -join ' / ') | $urlAnswers"
$withToken = New-Fixture 'source-token' @{ 'README.md' = "t`n" } 'https://template-test:secret@example.invalid/fork/project-template.git'
$tokenProject = New-TestFolder 'source-project3' @{ '.copier-answers.yml' = "_commit: v0.1.0`n_src_path: $withToken`n" }
$tokenNote = @(Set-TemplateSource $tokenProject $withToken)
$tokenAnswers = Get-Content -Raw -LiteralPath (Join-Path $tokenProject '.copier-answers.yml')
Check 'unit: Set-TemplateSource leaves the user name and token of an https origin out' ($tokenAnswers -eq "_commit: v0.1.0`n_src_path: https://example.invalid/fork/project-template.git`n" -and -not ($tokenNote -join ' ').Contains('secret')) "$tokenAnswers | $($tokenNote -join ' / ')"
$nested = Join-Path (Join-Path $withOrigin 'vendor') 'project-template'
New-Item -ItemType Directory -Force $nested | Out-Null
$nestedAnswersText = "_commit: v0.1.0`n_src_path: $nested`n"
$nestedProject = New-TestFolder 'source-project4' @{ '.copier-answers.yml' = $nestedAnswersText }
$nestedOut = @(Set-TemplateSource $nestedProject $nested 3>&1)
$nestedAnswers = Get-Content -Raw -LiteralPath (Join-Path $nestedProject '.copier-answers.yml')
Check 'unit: Set-TemplateSource takes no origin from the repository a template folder sits in' ($nestedAnswers -eq $nestedAnswersText -and $nestedOut.Count -eq 1 -and $nestedOut[0] -is [Management.Automation.WarningRecord]) "$nestedAnswers | $($nestedOut -join ' / ')"
$withSsh = New-Fixture 'source-ssh' @{ 'README.md' = "t`n" } 'git@github.com:fork/project-template.git'
$sshProject = New-TestFolder 'source-project5' @{ '.copier-answers.yml' = "_commit: v0.1.0`n_src_path: $withSsh`n" }
$null = Set-TemplateSource $sshProject $withSsh
$sshAnswers = Get-Content -Raw -LiteralPath (Join-Path $sshProject '.copier-answers.yml')
Check 'unit: Set-TemplateSource records a GitHub SSH origin as its https address' ($sshAnswers -eq "_commit: v0.1.0`n_src_path: https://github.com/fork/project-template.git`n") $sshAnswers
$withSshUrl = New-Fixture 'source-sshurl' @{ 'README.md' = "t`n" } 'ssh://git@github.com/group/project-template.git'
$sshUrlProject = New-TestFolder 'source-project6' @{ '.copier-answers.yml' = "_commit: v0.1.0`n_src_path: $withSshUrl`n" }
$null = Set-TemplateSource $sshUrlProject $withSshUrl
$sshUrlAnswers = Get-Content -Raw -LiteralPath (Join-Path $sshUrlProject '.copier-answers.yml')
Check 'unit: Set-TemplateSource records a GitHub ssh:// origin as its https address' ($sshUrlAnswers -eq "_commit: v0.1.0`n_src_path: https://github.com/group/project-template.git`n") $sshUrlAnswers
$crlfProject = New-TestFolder 'source-project7' @{ '.copier-answers.yml' = "# Written by Copier`r`n_commit: v0.1.0`r`n_src_path: first part`r`n  second part`r`nproject_name: Demo`r`n" }
$null = Set-TemplateSource $crlfProject $withOrigin
$crlfAnswers = Get-Content -Raw -LiteralPath (Join-Path $crlfProject '.copier-answers.yml')
Check 'unit: Set-TemplateSource keeps CRLF line endings and the other answers' ($crlfAnswers -eq "# Written by Copier`r`n_commit: v0.1.0`r`n_src_path: https://example.invalid/fork/project-template.git`r`nproject_name: Demo`r`n") ($crlfAnswers -replace "`r", '\r' -replace "`n", '\n')
# Set-TemplateSource and Update-Project.ps1 clean a clone's origin and rewrite _src_path with the same patterns.
$updateScriptText = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'template/.template/Update-Project.ps1')
$moduleText = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'tools/adopt/Adoption.psm1')
$originPatterns = @(
    '''^(?:[A-Za-z][A-Za-z0-9+.-]+://|gh:|[^@/\\\s]+@[^:/\\\s]+:)'''
    '''^(https?://)[^/@]*@'', ''$1'''
    '''^(?:git@github\.com:|ssh://git@github\.com/)'', ''https://github.com/'''
    '''(?m)^_src_path:[^\r\n]*(?:\r?\n[ \t]+[^\r\n]*)*'''
)
$apart = @($originPatterns | Where-Object { -not ($updateScriptText.Contains($_) -and $moduleText.Contains($_)) })
Check 'unit: Set-TemplateSource and Update-Project.ps1 clean a clone''s origin with the same patterns' (-not $apart) ($apart -join ' | ')

if (-not $UnitOnly) {
    $tpl = Join-Path $Work 'template-repo'
    $null = & (Join-Path $PSScriptRoot 'New-TemplateSnapshot.ps1') $tpl

    $plain = New-Fixture 'plain' @{
        'AGENTS.md'             = "# Legacy Agents`n`nOwn rules.`n`n## Conventions`n`n- Keep it simple.`n"
        'README.md'             = "# Plain`n"
        'CHANGELOG.md'          = "# Changelog`n`n## [Unreleased]`n`n## [1.0.0] - 2026-01-01`n`n### Added`n`n- First.`n"
        '.gitignore'            = "*.local-test`n"
        'main.py'               = "print('hi')`n"
        'pyproject.toml'        = "[project]`nname = ""plain""`n"
        '.vscode/settings.json' = "{`n  // editor`n  ""editor.rulers"": [100]`n}`n"
        '.gitlab-ci.yml'        = "test:`n  script: echo hi`n"
        'web/package.json'      = "{}`n"
        '.nvmrc'                = "v22`n"
    } 'https://github.com/example/plain.git'
    Invoke-Git -C $plain tag v1.0.0
    $adopt = Join-Path $repoRoot 'Adopt-Project.ps1'
    [IO.File]::WriteAllText((Join-Path $plain '.git\hooks\pre-commit'), "#!/bin/sh`n")
    $out = & $adopt -Path $plain -Template $tpl -Ref v0.1.0 -Data @{ workflow_tools = 'claude', 'copilot' } -NoVerify 3>&1 | Out-String
    $answersText = Get-Content -Raw -LiteralPath (Join-Path $plain '.copier-answers.yml')
    Check 'plain: answers recorded' ($answersText -match '(?m)^_commit: v0\.1\.0\s*$' -and $answersText -match '(?m)^stack: python\s*$' -and $answersText -match '(?m)^project_name: plain\s*$') "$answersText | $out"
    Check 'plain: a Python repository with a frontend answers uses_node and carries .nvmrc over to .node-version' ($answersText -match '(?m)^uses_node: true\s*$' -and (Get-Content -Raw -LiteralPath (Join-Path $plain '.node-version')) -eq "22`n" -and $out.Contains('Carried .node-version') -and (Test-Path -LiteralPath (Join-Path $plain '.nvmrc'))) "$answersText | $out"
    $subject = git -C $plain log -1 --format=%s
    $count = git -C $plain rev-list --count HEAD
    $status = git -C $plain status --porcelain
    Check 'plain: one commit, nothing left over' ($subject -eq 'Adopt project-template v0.1.0' -and $count -eq '2' -and -not $status) "$subject | $count | $status"
    $plainSource = (git -C $plain show HEAD:.copier-answers.yml | Select-String -Pattern '^_src_path:\s*(.+?)\s*$' | Select-Object -First 1).Matches.Groups[1].Value.Trim("'", '"')
    Check 'plain: the adoption names the template by its folder and warns that the folder has no origin address' (($plainSource -eq $tpl) -and (($out -replace '\s+', ' ').Contains('which only this PC has')) -and $out.Contains($tpl)) "$plainSource | $out"
    Check 'plain: leaves core.hooksPath alone when the clone has hooks in .git/hooks, and warns' (-not (git -C $plain config core.hooksPath) -and $out.Contains('has hooks of its own in .git/hooks (pre-commit)')) $out
    Check 'plain: a GitHub origin gets the command that protects the default branch' ($out.Contains('Set-RepositoryBaseline.ps1') -and $out.Contains('-Repo plain -Owner example')) $out
    Check 'plain: README.md untouched' ((Get-Content -Raw -LiteralPath (Join-Path $plain 'README.md')) -eq "# Plain`n") ''
    Check 'plain: a Keep a Changelog file stays as it is, with no follow-up' ((Get-Content -Raw -LiteralPath (Join-Path $plain 'CHANGELOG.md')) -eq "# Changelog`n`n## [Unreleased]`n`n## [1.0.0] - 2026-01-01`n`n### Added`n`n- First.`n" -and -not $out.Contains('convert CHANGELOG.md') -and -not $out.Contains('backfill CHANGELOG.md')) $out
    Check 'plain: workflow files for claude, copilot only' ((Test-Path -LiteralPath (Join-Path $plain 'CLAUDE.md')) -and (Test-Path -LiteralPath (Join-Path $plain '.github\skills\plan-feature\SKILL.md')) -and -not (Test-Path -LiteralPath (Join-Path $plain '.github\agents\hybrid-planner.agent.md'))) ''
    $message = try { & $adopt -Path $plain -Template $tpl -Ref v0.1.0 | Out-Null } catch { $_.Exception.Message }
    Check 'plain: a second run refuses' ("$message".Contains('already uses the project template')) "$message"
    $gitignore = Get-Content -Raw -LiteralPath (Join-Path $plain '.gitignore')
    $settingsText = Get-Content -Raw -LiteralPath (Join-Path $plain '.vscode\settings.json')
    $settings = try { $settingsText | ConvertFrom-Json -AsHashtable } catch { @{} }
    Check 'plain: merged files are the template plus the repository' ($gitignore.StartsWith('# Operating system and editor files') -and $gitignore.Contains('*.local-test') -and $settings.ContainsKey('files.eol') -and $settings.ContainsKey('editor.rulers')) "$gitignore | $settingsText"
    $agents = Get-Content -Raw -LiteralPath (Join-Path $plain 'AGENTS.md')
    $iEntry = $agents.IndexOf('@.github/instructions/project-template.instructions.md')
    Check 'plain: AGENTS.md gains the template rules' ($iEntry -ge 0 -and $iEntry -lt $agents.IndexOf('## Conventions') -and $agents.Contains('Own rules.')) $agents
    Check 'plain: CI file kept' ((Get-Content -Raw -LiteralPath (Join-Path $plain '.gitlab-ci.yml')) -eq "test:`n  script: echo hi`n") ''

    $scaffoldRepo = New-Fixture 'scaffold' @{
        'NCode.Demo.slnx'                   = "<Solution>`n  <Project Path=""src/NCode.Demo/NCode.Demo.csproj"" />`n</Solution>`n"
        'src/NCode.Demo/NCode.Demo.csproj'  = "<Project Sdk=""Microsoft.NET.Sdk"">`n  <PropertyGroup>`n    <TargetFramework>net10.0</TargetFramework>`n  </PropertyGroup>`n  <ItemGroup>`n    <PackageReference Include=""NCode.ProjectSettings.Scaffold""`n                      Version=""1.0.21"">`n      <PrivateAssets>all</PrivateAssets>`n    </PackageReference>`n    <PackageReference Include=""JetBrains.Annotations"" Version=""2025.2.4"" PrivateAssets=""All"" />`n  </ItemGroup>`n</Project>`n"
        'src/NCode.Demo/Greeter.cs'         = "namespace NCode.Demo;`n`n/// <summary>Greets people.</summary>`npublic static class Greeter`n{`n    /// <summary>Builds a greeting.</summary>`n    /// <param name=""name"">Who to greet.</param>`n    /// <returns>The greeting.</returns>`n    public static string Greet(string name) => `$""Hello, {name}!"";`n}`n"
        'Directory.Build.props'             = "<Project>`n  <PropertyGroup>`n    <LangVersion>latest</LangVersion>`n  </PropertyGroup>`n</Project>`n"
        '.gitignore'                        = "bin/`nobj/`n*.local-test`n"
        '.editorconfig'                     = "root = true`n`n[*.cs]`nindent_size = 4`nfile_header_template = Copyright Demo`n"
        'README.md'                         = "# NCode.Demo`n"
        'CHANGELOG.md'                      = "# Changes`n`n## 1.0.0`n`n- First.`n"
        'NCodeGroup.png'                    = $png
        '.github/copilot-instructions.md'   = "# Copilot Instructions`n"
        '.github/instructions/csharp-production.instructions.md' = "---`napplyTo: ""**/*.cs""`n---`n# C#`n"
        '.github/workflows/main.yml'        = "name: main`non: [push]`njobs:`n  build:`n    runs-on: ubuntu-latest`n    steps:`n      - uses: actions/checkout@v4`n      - run: dotnet build`n"
        '.dockerignore'                     = "*`n!src/`n!Directory.Build.props`n"
    } 'https://github.com/NCodeGroup/Demo.git'
    Invoke-Git -C $scaffoldRepo tag v0.9.0
    Invoke-Git -C $scaffoldRepo tag v1.0.0
    $out = & $adopt -Path $scaffoldRepo -Template $tpl -Ref v0.1.0 -Data @{ workflow_tools = 'claude', 'copilot'; test_command = '' } -NoVerify:$SkipDotnetBuild | Out-String
    $answersText = Get-Content -Raw -LiteralPath (Join-Path $scaffoldRepo '.copier-answers.yml')
    Check 'scaffold: answers from the adapter' ($answersText -match '(?m)^stack: dotnet\s*$' -and $answersText -match '(?m)^project_name: NCode\.Demo\s*$' -and $answersText -match '(?m)^nuget_package: true\s*$' -and $answersText -match '(?m)^license: Apache-2\.0\s*$' -and $answersText -match '(?m)^package_icon: NCodeGroup\.png\s*$' -and $answersText -match '(?m)^author_name: NCode Group\s*$') "$answersText | $out"
    Check 'scaffold: the adoption counts the C# file without the header .editorconfig sets, and rewrites none' ($out.Contains('1 C# file don''t start with the header .editorconfig sets') -and $out.Contains('src/NCode.Demo/Greeter.cs') -and (Get-Content -Raw -LiteralPath (Join-Path $scaffoldRepo 'src/NCode.Demo/Greeter.cs')).StartsWith('namespace NCode.Demo;')) $out
    $csproj = Get-Content -Raw -LiteralPath (Join-Path $scaffoldRepo 'src/NCode.Demo/NCode.Demo.csproj')
    $packages = Get-Content -Raw -LiteralPath (Join-Path $scaffoldRepo 'Directory.Packages.props')
    Check 'scaffold: package removed and versions central' (-not $csproj.Contains('NCode.ProjectSettings.Scaffold') -and -not $csproj.Contains('Version="') -and $csproj.Contains('JetBrains.Annotations') -and $packages.Contains('<PackageVersion Include="JetBrains.Annotations" Version="2025.2.4" />') -and -not $packages.Contains('NCode.ProjectSettings.Scaffold')) "$csproj | $packages"
    $props = Get-Content -Raw -LiteralPath (Join-Path $scaffoldRepo 'Directory.Build.props')
    $editorconfig = Get-Content -Raw -LiteralPath (Join-Path $scaffoldRepo '.editorconfig')
    Check 'scaffold: Directory.Build.props imports the template settings' ($props.Contains('build/ProjectTemplate.props') -and $props.Contains('<LangVersion>latest</LangVersion>') -and @($editorconfig -split "`n" | Where-Object { $_ -match '^\s*root\s*=' }).Count -eq 1) "$props | $editorconfig"
    Check 'scaffold: a GitHub origin gets the command that protects the default branch' ($out.Contains('Set-RepositoryBaseline.ps1') -and $out.Contains('-Repo Demo -Owner NCodeGroup') -and $out.Contains('-RequireChecks ''build-and-test''')) $out
    Check 'scaffold: report lists the follow-ups' ($out.Contains('/plan-migration Finish adopting the project template') -and $out.Contains('.github/copilot-instructions.md') -and $out.Contains('.github/workflows/main.yml')) $out
    Check 'scaffold: its own changelog stays as it is, with a follow-up to convert it' ((Get-Content -Raw -LiteralPath (Join-Path $scaffoldRepo 'CHANGELOG.md')) -eq "# Changes`n`n## 1.0.0`n`n- First.`n" -and $out.Contains('convert CHANGELOG.md to Keep a Changelog 1.1.0')) $out
    Check 'scaffold: asks to backfill the changelog from a tag it has no section for' ($out.Contains('backfill CHANGELOG.md from the releases v0.9.0')) $out
    Check 'scaffold: asks to re-admit the imported build files in .dockerignore' ($out.Contains("re-admit Directory.Build.props and build/ProjectTemplate.props, which it imports, in each list of the build's files: .dockerignore")) $out
    Check 'scaffold: reconciles the C# instructions' ($out.Contains('reconcile .github/instructions/csharp.instructions.md with csharp-production.instructions.md')) $out
    Check 'scaffold: no commit attribution follow-up' (-not $out.Contains('commit-attribution job')) $out
    Check 'scaffold: enables the template hooks' (((git -C $scaffoldRepo config core.hooksPath) -join '') -eq '.githooks') ''
    Check 'scaffold: a library without a license of its own gets the template''s LICENSE.txt and COPYRIGHT.txt' ((Test-Path -LiteralPath (Join-Path $scaffoldRepo 'LICENSE.txt')) -and (Test-Path -LiteralPath (Join-Path $scaffoldRepo 'COPYRIGHT.txt')) -and -not $out.Contains('Skipped LICENSE.txt')) $out

    # A library with a license file of its own keeps it alone, without the template's beside it.
    $ownLicense = New-Fixture 'own-license' @{
        'src/Lib/Lib.csproj' = "<Project Sdk=""Microsoft.NET.Sdk"">`n  <PropertyGroup>`n    <TargetFramework>net10.0</TargetFramework>`n  </PropertyGroup>`n</Project>`n"
        'README.md'          = "# Lib`n"
        'LICENSE'            = "Own license.`n"
        'AGENTS.md'          = "# Lib`n`nOwn rules.`n"
        '.github/workflows/release.yml' = "name: release`non: release`njobs:`n  push:`n    runs-on: ubuntu-latest`n    steps:`n      - uses: actions/checkout@v4`n      - run: dotnet nuget push out/*.nupkg`n"
    } 'https://github.com/example/lib.git'
    Invoke-Git -C $ownLicense tag v2.3.0
    $licenseOut = & $adopt -Path $ownLicense -Template $tpl -Ref v0.1.0 -Data @{ workflow_tools = 'claude', 'copilot'; nuget_package = $true; license = 'Apache-2.0'; test_command = '' } -NoVerify | Out-String
    Check 'own-license: keeps its own license, without LICENSE.txt or COPYRIGHT.txt, and says so' ((Get-Content -Raw -LiteralPath (Join-Path $ownLicense 'LICENSE')) -eq "Own license.`n" -and -not (Test-Path -LiteralPath (Join-Path $ownLicense 'LICENSE.txt')) -and -not (Test-Path -LiteralPath (Join-Path $ownLicense 'COPYRIGHT.txt')) -and $licenseOut.Contains('Skipped LICENSE.txt') -and $licenseOut.Contains('Skipped COPYRIGHT.txt') -and -not (git -C $ownLicense status --porcelain)) $licenseOut
    Check 'own-license: leaves publish.yml out beside its own publishing workflow, and says so' (-not (Test-Path -LiteralPath (Join-Path $ownLicense '.github/workflows/publish.yml')) -and (Test-Path -LiteralPath (Join-Path $ownLicense '.github/workflows/release.yml')) -and $licenseOut.Contains('Skipped .github/workflows/publish.yml')) $licenseOut
    Check 'own-license: leaves out release-provenance.yml and raise-baseline.yml, and records nuget_publisher' (-not (Test-Path -LiteralPath (Join-Path $ownLicense '.github/workflows/release-provenance.yml')) -and -not (Test-Path -LiteralPath (Join-Path $ownLicense '.github/workflows/raise-baseline.yml')) -and (Select-String -LiteralPath (Join-Path $ownLicense '.copier-answers.yml') -Pattern '^nuget_publisher: \.github/workflows/release\.yml\s*$' -Quiet)) $licenseOut
    Check 'own-license: a kept AGENTS.md without a release line leaves the gitsign section out of SECURITY.md' ((Test-Path -LiteralPath (Join-Path $ownLicense 'SECURITY.md')) -and -not (Select-String -LiteralPath (Join-Path $ownLicense 'SECURITY.md') -SimpleMatch -Pattern 'gitsign' -Quiet) -and -not (Select-String -LiteralPath (Join-Path $ownLicense '.copier-answers.yml') -Pattern '^release_policy:' -Quiet)) $licenseOut
    $licenseVersion = Get-Content -Raw -LiteralPath (Join-Path $ownLicense 'version.json') | ConvertFrom-Json
    Check 'own-license: adds version.json at the patch after v2.3.0, with the AssemblyVersion v2.3.0 shipped, and no Directory.Build.props follow-up' ($licenseVersion.version -eq '2.3.1' -and $licenseVersion.assemblyVersion.version -eq '2.3' -and $licenseVersion.assemblyVersion.precision -eq 'minor' -and $licenseOut.Contains('Set version.json') -and -not $licenseOut.Contains('set <AssemblyVersion>')) $licenseOut
    Check 'own-license: names release.yml''s shallow checkout, which Nerdbank.GitVersioning breaks' ($licenseOut.Contains('.github/workflows/release.yml, job push: actions/checkout without fetch-depth: 0')) $licenseOut

    # A library with a publish.yml of its own that packs without -p:PublicRelease=true keeps it, and the report asks to add it.
    $ownPublishYml = "name: publish`non: release`njobs:`n  pack:`n    runs-on: ubuntu-latest`n    steps:`n      - run: dotnet pack --output out -p:Version=1.0.0`n"
    $ownPublish = New-Fixture 'own-publish' @{
        'src/Lib/Lib.csproj' = "<Project Sdk=""Microsoft.NET.Sdk"">`n  <PropertyGroup>`n    <TargetFramework>net10.0</TargetFramework>`n  </PropertyGroup>`n</Project>`n"
        'README.md'          = "# Lib`n"
        '.github/workflows/publish.yml' = $ownPublishYml
    } 'https://github.com/example/own-publish.git'
    $publishOut = & $adopt -Path $ownPublish -Template $tpl -Ref v0.1.0 -Data @{ workflow_tools = 'claude', 'copilot'; nuget_package = $true; license = 'Apache-2.0'; test_command = '' } -NoVerify | Out-String
    Check 'own-publish: keeps its own publish.yml, adds version.json, and asks to add -p:PublicRelease=true' ((Get-Content -Raw -LiteralPath (Join-Path $ownPublish '.github/workflows/publish.yml')) -notmatch 'PublicRelease' -and (Test-Path -LiteralPath (Join-Path $ownPublish 'version.json')) -and $publishOut.Contains('add -p:PublicRelease=true to the dotnet test and dotnet pack commands of .github/workflows/publish.yml')) $publishOut

    # A library that references Nerdbank.GitVersioning itself loses that reference, because the template's build/ProjectTemplate.props references it once version.json exists.
    $ownGitVersioning = New-Fixture 'own-gitversioning' @{
        'src/Lib/Lib.csproj' = "<Project Sdk=""Microsoft.NET.Sdk"">`n  <PropertyGroup>`n    <TargetFramework>net10.0</TargetFramework>`n  </PropertyGroup>`n  <ItemGroup>`n    <PackageReference Include=""Nerdbank.GitVersioning"" Version=""3.6.0"" PrivateAssets=""all"" />`n  </ItemGroup>`n</Project>`n"
        'README.md'          = "# Lib`n"
    } 'https://github.com/example/own-gitversioning.git'
    $gitVersioningOut = & $adopt -Path $ownGitVersioning -Template $tpl -Ref v0.1.0 -Data @{ workflow_tools = 'claude', 'copilot'; nuget_package = $true; license = 'Apache-2.0'; test_command = '' } -NoVerify | Out-String
    $gvPackages = Get-Content -Raw -LiteralPath (Join-Path $ownGitVersioning 'Directory.Packages.props')
    Check 'own-gitversioning: drops the project''s own reference, keeps the template''s one, and says so' (((Get-Content -Raw -LiteralPath (Join-Path $ownGitVersioning 'src/Lib/Lib.csproj')) -notmatch 'Nerdbank\.GitVersioning') -and ([regex]::Matches($gvPackages, '<PackageVersion\s+Include="Nerdbank\.GitVersioning"')).Count -eq 1 -and ((Get-Content -Raw -LiteralPath (Join-Path $ownGitVersioning 'build/ProjectTemplate.props')) -match 'Nerdbank\.GitVersioning') -and $gitVersioningOut.Contains('Dropped src/Lib/Lib.csproj') -and $gitVersioningOut.Contains('pinned version 3.6.0') -and -not (git -C $ownGitVersioning status --porcelain)) $gitVersioningOut

    # A repository that isn't a library keeps its own reference, also beside a version.json of its own: its build/ProjectTemplate.props references Nerdbank.GitVersioning nowhere, so that reference is its only one.
    $ownGitVersioningNone = New-Fixture 'own-gitversioning-none' @{
        'src/Lib/Lib.csproj' = "<Project Sdk=""Microsoft.NET.Sdk"">`n  <PropertyGroup>`n    <TargetFramework>net10.0</TargetFramework>`n  </PropertyGroup>`n  <ItemGroup>`n    <PackageReference Include=""Nerdbank.GitVersioning"" Version=""3.6.0"" PrivateAssets=""all"" />`n  </ItemGroup>`n</Project>`n"
        'README.md'          = "# Lib`n"
        'version.json'       = "{`n  `"version`": `"1.0`"`n}`n"
    } 'https://github.com/example/own-gitversioning-none.git'
    $gitVersioningNoneOut = & $adopt -Path $ownGitVersioningNone -Template $tpl -Ref v0.1.0 -Data @{ workflow_tools = 'claude', 'copilot'; nuget_package = $false; license = 'Apache-2.0'; test_command = '' } -NoVerify | Out-String
    Check 'own-gitversioning-none: keeps the project''s own reference and its version.json when the template adds no reference, and drops nothing' (((Get-Content -Raw -LiteralPath (Join-Path $ownGitVersioningNone 'src/Lib/Lib.csproj')) -match 'Nerdbank\.GitVersioning') -and (Test-Path -LiteralPath (Join-Path $ownGitVersioningNone 'version.json')) -and ((Get-Content -Raw -LiteralPath (Join-Path $ownGitVersioningNone 'build/ProjectTemplate.props')) -notmatch 'Nerdbank\.GitVersioning') -and -not $gitVersioningNoneOut.Contains('Dropped')) $gitVersioningNoneOut

    if (-not $SkipDotnetBuild) {
        $subject = git -C $scaffoldRepo log -1 --format=%s
        $packOut = dotnet pack (Join-Path $scaffoldRepo 'src\NCode.Demo') -o (Join-Path $Work 'pack') 2>&1 | Out-String
        $nupkg = @(Get-ChildItem -LiteralPath (Join-Path $Work 'pack') -Filter '*.nupkg' -ErrorAction SilentlyContinue | Where-Object Name -NotLike '*.snupkg')
        $snupkg = @(Get-ChildItem -LiteralPath (Join-Path $Work 'pack') -Filter '*.snupkg' -ErrorAction SilentlyContinue)
        $entries = @(); $nuspec = ''
        if ($nupkg.Count) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [IO.Compression.ZipFile]::OpenRead($nupkg[0].FullName)
            try {
                $entries = @($zip.Entries | ForEach-Object FullName)
                $nuspecEntry = $zip.Entries | Where-Object FullName -Like '*.nuspec' | Select-Object -First 1
                $reader = [IO.StreamReader]::new($nuspecEntry.Open())
                try { $nuspec = $reader.ReadToEnd() } finally { $reader.Dispose() }
            }
            finally { $zip.Dispose() }
        }
        $unshippedApi = Join-Path $scaffoldRepo 'src/NCode.Demo/PublicAPI.Unshipped.txt'
        $apiText = if (Test-Path -LiteralPath $unshippedApi) { [IO.File]::ReadAllText($unshippedApi) } else { '' }
        Check 'scaffold: records the public API before verifying, and commits it' ($out.Contains('Running ./build/Update-PublicApi.ps1') -and $apiText.StartsWith("#nullable enable`n") -and $apiText.Contains('static NCode.Demo.Greeter.Greet(string! name) -> string!') -and (Test-Path -LiteralPath (Join-Path $scaffoldRepo 'src/NCode.Demo/PublicAPI.Shipped.txt')) -and -not (git -C $scaffoldRepo status --porcelain)) "$apiText | $out"
        Check 'scaffold: verified, committed, and packed with README, icon and license' ($out.Contains('Running dotnet build') -and $subject -eq 'Adopt project-template v0.1.0' -and $nupkg.Count -eq 1 -and 'README.md' -in $entries -and 'NCodeGroup.png' -in $entries -and $nuspec.Contains('<license type="expression">Apache-2.0</license>') -and $snupkg.Count -eq 1) "$subject | $($entries -join ',') | $nuspec | $packOut | $out"
    }

    # A later template version changes the merged files.
    Push-Location (Join-Path $tpl 'template')
    try {
        Edit-File .gitignore.jinja 'Thumbs.db' "Thumbs.db`ndesktop.ini"
        Edit-File .vscode/settings.json.jinja '"files.eol": "\n",' ('"editor.formatOnSave": false,' + "`n" + '  "files.eol": "\n",')
    }
    finally { Pop-Location }
    Push-Location $tpl
    try { Invoke-Git add -A; Invoke-Git commit -q -m 'Template change'; Invoke-Git tag v0.2.0 }
    finally { Pop-Location }
    Push-Location $plain
    try {
        $updateOut = & (Join-Path $plain '.template\Update-Project.ps1') | Out-String
        $exitCode = $LASTEXITCODE
        $gitignore = Get-Content -Raw -LiteralPath .gitignore
        $settingsText = Get-Content -Raw -LiteralPath .vscode\settings.json
        Check 'plain: a later template update merges cleanly' ($exitCode -eq 0 -and (git log -1 --format=%s) -eq 'Update from project-template v0.2.0' -and $gitignore.Contains('desktop.ini') -and $gitignore.Contains('*.local-test') -and $settingsText.Contains('editor.formatOnSave') -and $settingsText.Contains('editor.rulers')) "$exitCode | $updateOut | $gitignore | $settingsText"
    }
    finally { Pop-Location }
}
''
$env:COPIER_CACHE_DIR = $copierCache
if ($failures.Count) { "Kept the work folder: $Work"; "Adoption tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Adoption tests: PASSED'
exit 0
