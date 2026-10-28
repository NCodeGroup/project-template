<#
.SYNOPSIS
    Test adopting existing repositories into the template.

.DESCRIPTION
    Unit-tests the adoption functions on small inputs and, unless -UnitOnly is given, adopts fixture repositories
    from a tagged snapshot of the working tree (added in later steps). Prints PASS or FAIL per check and exits 1 on
    any failure.

.PARAMETER UnitOnly
    Run only the unit checks, which take seconds.

.PARAMETER SkipDotnetBuild
    Skip the .NET build and pack.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-adopt-test in the temp folder.

.EXAMPLE
    .\tests\Test-Adoption.ps1
    .\tests\Test-Adoption.ps1 -UnitOnly
    .\tests\Test-Adoption.ps1 -SkipDotnetBuild
#>
[CmdletBinding()]
param(
    [switch]$UnitOnly,
    [switch]$SkipDotnetBuild,
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) 'project-template-adopt-test')
)
$ErrorActionPreference = 'Stop'
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
function Invoke-Git {
    git -c user.name=template-test -c user.email=template-test@example.invalid @args
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed." }
}
# Creates $Work\$Name with the given files (relative paths with forward slashes) and returns its path.
function New-TestFolder([string]$Name, [hashtable]$Files) {
    $folder = Join-Path $Work $Name
    New-Item -ItemType Directory -Force $folder | Out-Null
    foreach ($relative in $Files.Keys) {
        $file = Join-Path $folder $relative
        New-Item -ItemType Directory -Force (Split-Path -Parent $file) | Out-Null
        if ($relative.EndsWith('.png')) { [IO.File]::WriteAllBytes($file, [Convert]::FromBase64String($Files[$relative])) }
        else { [IO.File]::WriteAllText($file, $Files[$relative], [Text.UTF8Encoding]::new($false)) }
    }
    $folder
}

Import-Module (Join-Path $repoRoot 'tools\adopt\Adoption.psm1') -Force
if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

$copierYml = Join-Path $repoRoot 'copier.yml'
$skip = @(Get-CopierList $copierYml '_skip_if_exists')
$merged = @(Get-CopierList $copierYml '_merged_files')
Check 'unit: Get-CopierList reads the file lists' (($skip -join ',') -eq 'AGENTS.md,README.md,Directory.Build.props' -and '.gitignore' -in $merged -and 'global.json' -in $merged) "$($skip -join ',') | $($merged -join ',')"
$one = Get-OwnedMergedFile '.github/workflows/ci.yml' $merged
$dropped = Get-OwnedMergedFile @('.gitignore', '', $null) $merged
$none = Get-OwnedMergedFile @() $merged
$ownedMsg = try { Get-OwnedMergedFile 'CLAUDE.md' $merged | Out-Null } catch { $_.Exception.Message }
Check 'unit: Get-OwnedMergedFile makes a list and rejects a file that isn''t merged' (($one -is [array]) -and $one.Count -eq 1 -and $one[0] -eq '.github/workflows/ci.yml' -and $dropped.Count -eq 1 -and $none.Count -eq 0 -and "$ownedMsg".Contains('which isn''t a merged file')) "$($one -join ',') | $($dropped.Count) | $($none.Count) | $ownedMsg"

$demo = New-TestFolder 'demo' @{
    'src/NCode.Demo.slnx'   = '<Solution />'
    'Directory.Build.props' = "<Project>`n  <PropertyGroup>`n    <Authors>NCode Group</Authors>`n  </PropertyGroup>`n</Project>`n"
}
Push-Location $demo
try { Invoke-Git init -q -b main; Invoke-Git remote add origin https://gitlab.com/example/demo.git }
finally { Pop-Location }
$a = Get-AdoptionAnswers $demo
$detail = ($a.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; '
Check 'unit: Get-AdoptionAnswers works out a .NET repository' (($a.stack -eq 'dotnet') -and ($a.project_name -eq 'NCode.Demo') -and ($a.git_host -eq 'gitlab') -and ($a.author_name -eq 'NCode Group') -and ($a.build_command -eq 'dotnet build src/NCode.Demo.slnx') -and ($a.test_command -eq 'dotnet test src/NCode.Demo.slnx')) $detail

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
    if (-not ($a.stack -eq $others[$name].Stack -and $a.git_host -eq 'github' -and $a.project_name -eq $name -and -not $a.Contains('build_command'))) {
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
    if (-not ($a.stack -eq 'node' -and $a.git_host -eq 'github' -and $a.project_name -eq $name -and $a.package_manager -eq $nodes[$name].Manager -and $a.Contains('build_command') -and $a.build_command -eq $nodes[$name].Build -and $a.Contains('test_command') -and $a.test_command -eq $nodes[$name].Test)) {
        "${name}: $(($a.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ')"
    }
}
Check 'unit: Get-AdoptionAnswers works out Node.js commands from package.json' (-not $bad) ($bad -join ' | ')

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
$x = "<?xml version=""1.0""?>`n<Project>`n  <PropertyGroup>`n    <A>1</A>`n  </PropertyGroup>`n</Project>`n"
$r = Add-ProjectTemplateImport $x
Check 'unit: Add-ProjectTemplateImport' ($r.StartsWith("<?xml version=""1.0""?>`n<Project>`n") -and $r.Contains('<Import Project="$(MSBuildThisFileDirectory)build/ProjectTemplate.props" />') -and $r.IndexOf('<Import') -lt $r.IndexOf('<PropertyGroup>') -and (Add-ProjectTemplateImport $r) -eq $r) $r
$central = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "template\{% if stack == 'dotnet' %}Directory.Packages.props{% endif %}")
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
$png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
$adapters = Join-Path $repoRoot 'tools\adopt\legacy'
$scaffold = Join-Path $adapters 'NCode.ProjectSettings.Scaffold.ps1'
$folder = New-TestFolder 'scaffold-adapter' @{
    'NCodeGroup.png' = $png
    'src/A/A.csproj' = "<Project Sdk=""Microsoft.NET.Sdk"">`n  <ItemGroup>`n    <PackageReference Include=""NCode.ProjectSettings.Scaffold""`n                      Version=""1.0.0"">`n      <PrivateAssets>all</PrivateAssets>`n    </PackageReference>`n    <PackageReference Include=""JetBrains.Annotations"" Version=""2.0.0"" />`n  </ItemGroup>`n</Project>`n"
}
$detected = & $scaffold -Path $folder -Phase Detect
$a = & $scaffold -Path $folder -Phase Answers
$out = @(& $scaffold -Path $folder -Phase Apply)
$proj = Get-Content -Raw -LiteralPath (Join-Path $folder 'src/A/A.csproj')
$after = & $scaffold -Path $folder -Phase Detect
Check 'unit: scaffold adapter' ($detected -eq $true -and $a.nuget_package -eq $true -and $a.package_license -eq 'Apache-2.0' -and $a.author_name -eq 'NCode Group' -and $a.package_icon -eq 'NCodeGroup.png' -and $out[0] -like '*src/A/A.csproj' -and $proj.Contains('JetBrains.Annotations') -and -not $proj.Contains('NCode.ProjectSettings.Scaffold') -and $after -eq $false) "$detected | $($out -join ' / ') | $proj | $after"

$workflow = Join-Path $adapters 'HybridWorkflowInstall.ps1'
$folder = New-TestFolder 'workflow-install' @{ '.github/prompts/execute-step-copilot.prompt.md' = "old`n" }
$detected = & $workflow -Path $folder -Phase Detect
$out = @(& $workflow -Path $folder -Phase Apply)
$gone = -not (Test-Path -LiteralPath (Join-Path $folder '.github/prompts/execute-step-copilot.prompt.md'))
$after = & $workflow -Path $folder -Phase Detect
Check 'unit: workflow install adapter' ($detected -eq $true -and $gone -and $out.Count -eq 1 -and $after -eq $false) "$detected | $($out -join ' / ') | $after"

if (-not $UnitOnly) {
    $tpl = Join-Path $Work 'template-repo'
    New-Item -ItemType Directory -Force $tpl | Out-Null
    Get-ChildItem -LiteralPath $repoRoot -Force | Where-Object Name -NotIn '.git', '.claude' | Copy-Item -Destination $tpl -Recurse -Force
    # Claude Code's plan worktrees are other checkouts, not part of the snapshot.
    $claudeCopy = New-Item -ItemType Directory -Force (Join-Path $tpl '.claude')
    Get-ChildItem -LiteralPath (Join-Path $repoRoot '.claude') -Force | Where-Object Name -NE 'worktrees' | Copy-Item -Destination $claudeCopy.FullName -Recurse -Force
    Push-Location $tpl
    try { Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Snapshot'; Invoke-Git tag v0.1.0 }
    finally { Pop-Location }

    function New-Fixture([string]$Name, [hashtable]$Files, [string]$Remote) {
        $folder = New-TestFolder $Name $Files
        Push-Location $folder
        try { Invoke-Git init -q -b main; Invoke-Git remote add origin $Remote; Invoke-Git add -A; Invoke-Git commit -q -m 'Initial' }
        finally { Pop-Location }
        $folder
    }

    $plain = New-Fixture 'plain' @{
        'AGENTS.md'             = "# Legacy Agents`n`nOwn rules.`n`n## Conventions`n`n- Keep it simple.`n"
        'README.md'             = "# Plain`n"
        '.gitignore'            = "*.local-test`n"
        'main.py'               = "print('hi')`n"
        'pyproject.toml'        = "[project]`nname = ""plain""`n"
        '.vscode/settings.json' = "{`n  // editor`n  ""editor.rulers"": [100]`n}`n"
        '.gitlab-ci.yml'        = "test:`n  script: echo hi`n"
    } 'https://gitlab.com/example/plain.git'
    $adopt = Join-Path $repoRoot 'Adopt-Project.ps1'
    [IO.File]::WriteAllText((Join-Path $plain '.git\hooks\pre-commit'), "#!/bin/sh`n")
    $out = & $adopt -Path $plain -Template $tpl -Ref v0.1.0 -Data @{ workflow_tools = 'claude', 'copilot' } -NoVerify | Out-String
    $answersText = Get-Content -Raw -LiteralPath (Join-Path $plain '.copier-answers.yml')
    Check 'plain: answers recorded' ($answersText -match '(?m)^_commit: v0\.1\.0\s*$' -and $answersText -match '(?m)^stack: python\s*$' -and $answersText -match '(?m)^git_host: gitlab\s*$' -and $answersText -match '(?m)^project_name: plain\s*$') "$answersText | $out"
    $subject = git -C $plain log -1 --format=%s
    $count = git -C $plain rev-list --count HEAD
    $status = git -C $plain status --porcelain
    Check 'plain: one commit, nothing left over' ($subject -eq 'Adopt project-template v0.1.0' -and $count -eq '2' -and -not $status) "$subject | $count | $status"
    Check 'plain: leaves core.hooksPath alone when the clone has hooks in .git/hooks' (-not (git -C $plain config core.hooksPath) -and $out.Contains('has hooks of its own in .git/hooks (pre-commit)')) $out
    Check 'plain: README.md untouched' ((Get-Content -Raw -LiteralPath (Join-Path $plain 'README.md')) -eq "# Plain`n") ''
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
    Check 'plain: asks to add the commit attribution job to the kept .gitlab-ci.yml' ($out.Contains("add the template's commit-attribution job to .gitlab-ci.yml")) $out

    $scaffoldRepo = New-Fixture 'scaffold' @{
        'NCode.Demo.slnx'                   = "<Solution>`n  <Project Path=""src/NCode.Demo/NCode.Demo.csproj"" />`n</Solution>`n"
        'src/NCode.Demo/NCode.Demo.csproj'  = "<Project Sdk=""Microsoft.NET.Sdk"">`n  <PropertyGroup>`n    <TargetFramework>net10.0</TargetFramework>`n  </PropertyGroup>`n  <ItemGroup>`n    <PackageReference Include=""NCode.ProjectSettings.Scaffold""`n                      Version=""1.0.21"">`n      <PrivateAssets>all</PrivateAssets>`n    </PackageReference>`n    <PackageReference Include=""JetBrains.Annotations"" Version=""2025.2.4"" PrivateAssets=""All"" />`n  </ItemGroup>`n</Project>`n"
        'src/NCode.Demo/Greeter.cs'         = "namespace NCode.Demo;`n`n/// <summary>Greets people.</summary>`npublic static class Greeter`n{`n    /// <summary>Builds a greeting.</summary>`n    /// <param name=""name"">Who to greet.</param>`n    /// <returns>The greeting.</returns>`n    public static string Greet(string name) => `$""Hello, {name}!"";`n}`n"
        'Directory.Build.props'             = "<Project>`n  <PropertyGroup>`n    <LangVersion>latest</LangVersion>`n  </PropertyGroup>`n</Project>`n"
        '.gitignore'                        = "bin/`nobj/`n*.local-test`n"
        '.editorconfig'                     = "root = true`n`n[*.cs]`nindent_size = 4`n"
        'README.md'                         = "# NCode.Demo`n"
        'NCodeGroup.png'                    = $png
        '.github/copilot-instructions.md'   = "# Copilot Instructions`n"
        '.github/instructions/csharp-production.instructions.md' = "---`napplyTo: ""**/*.cs""`n---`n# C#`n"
        '.github/workflows/main.yml'        = "name: main`non: [push]`njobs:`n  build:`n    runs-on: ubuntu-latest`n    steps:`n      - uses: actions/checkout@v4`n      - run: dotnet build`n"
        '.dockerignore'                     = "*`n!src/`n!Directory.Build.props`n"
    } 'https://github.com/NCodeGroup/Demo.git'
    $out = & $adopt -Path $scaffoldRepo -Template $tpl -Ref v0.1.0 -Data @{ workflow_tools = 'claude', 'copilot'; test_command = '' } -NoVerify:$SkipDotnetBuild | Out-String
    $answersText = Get-Content -Raw -LiteralPath (Join-Path $scaffoldRepo '.copier-answers.yml')
    Check 'scaffold: answers from the adapter' ($answersText -match '(?m)^stack: dotnet\s*$' -and $answersText -match '(?m)^project_name: NCode\.Demo\s*$' -and $answersText -match '(?m)^nuget_package: true\s*$' -and $answersText -match '(?m)^package_license: Apache-2\.0\s*$' -and $answersText -match '(?m)^package_icon: NCodeGroup\.png\s*$' -and $answersText -match '(?m)^author_name: NCode Group\s*$') "$answersText | $out"
    $csproj = Get-Content -Raw -LiteralPath (Join-Path $scaffoldRepo 'src/NCode.Demo/NCode.Demo.csproj')
    $packages = Get-Content -Raw -LiteralPath (Join-Path $scaffoldRepo 'Directory.Packages.props')
    Check 'scaffold: package removed and versions central' (-not $csproj.Contains('NCode.ProjectSettings.Scaffold') -and -not $csproj.Contains('Version="') -and $csproj.Contains('JetBrains.Annotations') -and $packages.Contains('<PackageVersion Include="JetBrains.Annotations" Version="2025.2.4" />') -and -not $packages.Contains('NCode.ProjectSettings.Scaffold')) "$csproj | $packages"
    $props = Get-Content -Raw -LiteralPath (Join-Path $scaffoldRepo 'Directory.Build.props')
    $editorconfig = Get-Content -Raw -LiteralPath (Join-Path $scaffoldRepo '.editorconfig')
    Check 'scaffold: Directory.Build.props imports the template settings' ($props.Contains('build/ProjectTemplate.props') -and $props.Contains('<LangVersion>latest</LangVersion>') -and @($editorconfig -split "`n" | Where-Object { $_ -match '^\s*root\s*=' }).Count -eq 1) "$props | $editorconfig"
    Check 'scaffold: report lists the follow-ups' ($out.Contains('/plan-migration Finish adopting the project template') -and $out.Contains('.github/copilot-instructions.md') -and $out.Contains('.github/workflows/main.yml')) $out
    Check 'scaffold: asks to re-admit the imported build files in .dockerignore' ($out.Contains("re-admit Directory.Build.props and build/ProjectTemplate.props, which it imports, in each list of the build's files: .dockerignore")) $out
    Check 'scaffold: reconciles the C# instructions' ($out.Contains('reconcile .github/instructions/csharp.instructions.md with csharp-production.instructions.md')) $out
    Check 'scaffold: no commit attribution follow-up when the template added ci.yml' (-not $out.Contains('commit-attribution job')) $out
    Check 'scaffold: enables the template hooks' (((git -C $scaffoldRepo config core.hooksPath) -join '') -eq '.githooks') ''

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
        Check 'scaffold: verified, committed, and packed with README, icon and license' ($out.Contains('Running dotnet build') -and $subject -eq 'Adopt project-template v0.1.0' -and $nupkg.Count -eq 1 -and 'README.md' -in $entries -and 'NCodeGroup.png' -in $entries -and $nuspec.Contains('<license type="expression">Apache-2.0</license>') -and $snupkg.Count -eq 1) "$subject | $($entries -join ',') | $nuspec | $packOut | $out"
    }

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
    $ciOut = & $adopt -Path $ciExisting -Template $tpl -Ref v0.1.0 -NoVerify | Out-String
    Check 'ci-existing: no reconcile follow-up when the repository already had ci.yml' (-not $ciOut.Contains('reconcile .github/workflows')) $ciOut
    Check 'ci-existing: asks to add the commit attribution job to the kept ci.yml' ($ciOut.Contains("add the template's commit-attribution job to .github/workflows/ci.yml")) $ciOut
    Check 'ci-existing: says it included local and how to leave it out' ($ciOut.Contains("workflow_tools: [claude, copilot, local], the template's default") -and $ciOut.Contains("-Data @{ workflow_tools = 'claude', 'copilot' }")) $ciOut

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
if ($failures.Count) { "Adoption tests: FAILED ($($failures.Count))"; exit 1 }
'Adoption tests: PASSED'
exit 0
