# Functions Adopt-Project.ps1 uses to bring an existing repository under the template.

$script:SkipPath = '[\\/](bin|obj|node_modules|\.git)[\\/]'
# Folders at the root whose PowerShell files are build or CI helpers, not the project's code.
$script:HelperPath = '^(\.github|\.gitlab|build|eng|scripts|tools)[\\/]'

function Get-CopierList([string]$CopierYml, [string]$Key) {
    $inList = $false
    foreach ($line in Get-Content -LiteralPath $CopierYml) {
        if ($line -match "^${Key}:") { $inList = $true; continue }
        if ($inList -and $line -match '^\s+-\s+(.+?)\s*$') { $Matches[1].Trim("'", '"') }
        elseif ($inList -and $line -match '^\S') { break }
    }
}

# The files a repository can own: each file the template folder renders, named as the project has it, without the update's own files. Keep the rules the same as $ownable in template/.template/Update-Project.ps1.
function Get-OwnableFile([string]$TemplateFolder) {
    $root = (Resolve-Path -LiteralPath $TemplateFolder).Path.TrimEnd('\', '/')
    $jinjaTag = '\{' + '%.*?%' + '\}'
    foreach ($item in Get-ChildItem -LiteralPath $root -Recurse -File -Force) {
        $name = $item.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/') -replace $jinjaTag -replace '\.jinja$'
        if ($name -notmatch '^\.template/' -and -not $name.Contains('{') -and $name -notin '.copier-answers.yml', '.template-version') { $name }
    }
}

# The project_owned_files answer as the list Copier needs: a single file becomes a one-item list and empty or repeated items are dropped. Throws for a file the template doesn't render or the update itself needs.
function Get-OwnedFile($Value, [string[]]$Ownable) {
    $files = @($Value | Where-Object { $_ } | Select-Object -Unique)
    $notOwnable = @($files | Where-Object { $_ -notin $Ownable })
    if ($notOwnable) { throw "project_owned_files names $($notOwnable -join ', '), which the template doesn't render or the update itself needs. It can name any file the template renders except .copier-answers.yml, .template-version and the files in .template/." }
    , $files
}

function Get-MSBuildFile([string]$Path) {
    Get-ChildItem -LiteralPath $Path -Recurse -File -Include '*.csproj', '*.fsproj', '*.vbproj', 'Directory.Build.props', 'Directory.Build.targets', 'Directory.Packages.props' |
        Where-Object { $_.FullName -notmatch $script:SkipPath }
}

# The package manager a Node.js repository uses: the one its packageManager field names, else the one whose lockfile
# is at the root, else npm.
function Get-NodePackageManager([string]$Path, $Package) {
    if ("$($Package.packageManager)" -match '^(npm|pnpm|yarn|bun)@') { return $Matches[1] }
    $lockfiles = [ordered]@{ 'pnpm-lock.yaml' = 'pnpm'; 'yarn.lock' = 'yarn'; 'bun.lock' = 'bun'; 'bun.lockb' = 'bun' }
    foreach ($file in $lockfiles.Keys) {
        if (Test-Path -LiteralPath (Join-Path $Path $file)) { return $lockfiles[$file] }
    }
    'npm'
}

# The repository's name: the origin remote's last path segment, else the main checkout's folder, so a Claude Code
# worktree (.claude/worktrees/<name>) doesn't name the project after itself, else the folder's.
function Get-RepositoryName([string]$Path, [string]$Remote) {
    if ($Remote -match '[\\/:]([^\\/:]+?)(?:\.git)?/?$') { return $Matches[1] }
    $common = "$(git -C $Path rev-parse --path-format=absolute --git-common-dir 2>$null)"
    if ($common -and (Split-Path -Leaf $common) -eq '.git') { return Split-Path -Leaf (Split-Path -Parent $common) }
    Split-Path -Leaf $Path
}

# The workflow tools a repository already has files for, in copier.yml's order: claude always, copilot for Copilot
# agents, skills or prompt files, local for Hybrid agents. Nothing when it has neither, so the template's default applies.
function Get-WorkflowTools([string]$Path) {
    $github = Join-Path $Path '.github'
    $copilot = [bool](Get-ChildItem -LiteralPath (Join-Path $github 'agents') -Filter 'copilot-*.agent.md' -File -ErrorAction SilentlyContinue) -or
        (Test-Path -LiteralPath (Join-Path $github 'skills') -PathType Container) -or (Test-Path -LiteralPath (Join-Path $github 'prompts') -PathType Container)
    $local = [bool](Get-ChildItem -LiteralPath (Join-Path $github 'agents') -Filter 'hybrid-*.agent.md' -File -ErrorAction SilentlyContinue)
    if (-not ($copilot -or $local)) { return }
    'claude'
    if ($copilot) { 'copilot' }
    if ($local) { 'local' }
}

function Get-AdoptionAnswers([string]$Path) {
    $Path = (Resolve-Path -LiteralPath $Path).Path
    $found = @(Get-ChildItem -LiteralPath $Path -Recurse -Depth 2 -File -Include '*.sln', '*.slnx', '*.csproj', '*.fsproj', '*.vbproj' |
        Where-Object { $_.FullName -notmatch $script:SkipPath })
    $solutions = @($found | Where-Object Extension -In '.sln', '.slnx')
    # An OpenTofu or Terraform repository is 'other' even when it has PowerShell helper scripts.
    $stack = if ($found) { 'dotnet' }
    elseif (Test-Path -LiteralPath (Join-Path $Path 'package.json')) { 'node' }
    elseif ('pyproject.toml', 'requirements.txt', 'setup.py' | Where-Object { Test-Path -LiteralPath (Join-Path $Path $_) }) { 'python' }
    elseif (Get-ChildItem -LiteralPath $Path -Recurse -Depth 2 -File -Include '*.tf', '*.tofu', '*.tftest.hcl' | Where-Object { $_.FullName -notmatch $script:SkipPath }) { 'other' }
    elseif (Get-ChildItem -LiteralPath $Path -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1' | Where-Object { $_.FullName -notmatch $script:SkipPath -and [IO.Path]::GetRelativePath($Path, $_.FullName) -notmatch $script:HelperPath }) { 'powershell' }
    else { 'other' }

    $remote = "$(git -C $Path remote get-url origin 2>$null)"
    $answers = [ordered]@{
        stack        = $stack
        project_name = if ($solutions.Count -eq 1) { $solutions[0].BaseName } else { Get-RepositoryName $Path $remote }
        git_host     = if ($remote -match 'gitlab') { 'gitlab' } else { 'github' }
    }
    $tools = @(Get-WorkflowTools $Path)
    if ($tools.Count) { $answers.workflow_tools = $tools }
    if ($stack -eq 'dotnet') {
        $props = Join-Path $Path 'Directory.Build.props'
        if (Test-Path -LiteralPath $props) {
            $text = Get-Content -LiteralPath $props -Raw
            $author = if ($text -match '<Authors>(.*?)</Authors>') { $Matches[1].Trim() }
            elseif ($text -match '<Company>(.*?)</Company>') { $Matches[1].Trim() }
            if ($author -and -not $author.Contains('$(')) { $answers.author_name = $author }
        }
        if ($solutions.Count -eq 1 -and $solutions[0].DirectoryName -ne $Path) {
            $relative = [IO.Path]::GetRelativePath($Path, $solutions[0].FullName) -replace '\\', '/'
            $answers.build_command = "dotnet build $relative"
            $answers.test_command = "dotnet test $relative"
        }
    }
    if ($stack -eq 'node') {
        # Only the scripts package.json has: the template's npm defaults fail where there is no such script.
        $package = Get-Content -LiteralPath (Join-Path $Path 'package.json') -Raw | ConvertFrom-Json -AsHashtable
        $scripts = if ($package.scripts -is [System.Collections.IDictionary]) { $package.scripts } else { @{} }
        $manager = Get-NodePackageManager $Path $package
        $answers.package_manager = $manager
        $answers.build_command = if ($scripts['build']) { "$manager run build" } else { '' }
        # npm init writes a test script that only fails.
        $answers.test_command = if ($scripts['test'] -and $scripts['test'] -notmatch 'no test specified') { "$manager run test" } else { '' }
    }
    $answers
}

function Merge-JsonValue($Template, $Repository) {
    if ($Template -is [System.Collections.IDictionary] -and $Repository -is [System.Collections.IDictionary]) {
        foreach ($key in @($Repository.Keys)) {
            if ($Template.Contains($key)) { $Template[$key] = Merge-JsonValue $Template[$key] $Repository[$key] }
            else { $Template[$key] = $Repository[$key] }
        }
        return $Template
    }
    if ($Template -is [System.Collections.IList] -and $Repository -is [System.Collections.IList]) {
        $list = [Collections.Generic.List[object]]::new()
        $seen = [Collections.Generic.HashSet[string]]::new()
        foreach ($item in $Template) { $list.Add($item); [void]$seen.Add((ConvertTo-Json $item -Compress -Depth 32)) }
        foreach ($item in $Repository) { if ($seen.Add((ConvertTo-Json $item -Compress -Depth 32))) { $list.Add($item) } }
        return , ([object[]]$list)
    }
    $Repository
}

function Merge-AdoptedFile([string]$Name, [string]$Original, [string]$Rendered) {
    $Original = $Original -replace "`r`n", "`n"
    $Rendered = $Rendered -replace "`r`n", "`n"
    $leaf = Split-Path -Leaf $Name
    $keepNote = 'kept as is; a template change to it will stop an update with a conflict: keep your side'
    $keep = [pscustomobject]@{ Text = $Original; Strategy = 'Keep'; Note = $keepNote }
    if ($Original.Trim() -eq $Rendered.Trim()) {
        return [pscustomobject]@{ Text = $Rendered; Strategy = 'Same'; Note = $null }
    }
    $marker = "# Kept from this repository's own $leaf when it adopted the project template"
    if ($Name -in '.gitignore', '.gitattributes', '.editorconfig') {
        $lines = if ($Name -eq '.editorconfig') { ($Original -split "`n" | Where-Object { $_ -notmatch '^\s*root\s*=' }) -join "`n" } else { $Original }
        $note = $null
        if ($Name -eq '.gitattributes') {
            # Git uses the last rule that matches, and the kept lines come after the template's. A catch-all text rule of the
            # repository's own, such as "* text eol=lf", would then override the template's "*.png binary" and the rest, so a
            # binary file is committed as text and corrupted. The template's first rule says the same thing, so drop them.
            $catchAll = @($lines -split "`n" | Where-Object { $_ -match '^\*\s+text(?:=auto)?(?:\s+eol=lf)?\s*$' })
            if ($catchAll) {
                $lines = ($lines -split "`n" | Where-Object { $_ -notin $catchAll }) -join "`n"
                $note = "left out its catch-all text rule ($($catchAll.ForEach({ $_.Trim() }) -join '; ')), which would override the template's binary rules"
            }
        }
        $text = $Rendered.TrimEnd("`n") + "`n`n$marker`n" + $lines.Trim("`n") + "`n"
        return [pscustomobject]@{ Text = $text; Strategy = 'Lines'; Note = $note }
    }
    if ($Name -like '*.json') {
        try {
            $template = ConvertFrom-Json $Rendered -AsHashtable
            $repository = ConvertFrom-Json $Original -AsHashtable
        }
        catch { return [pscustomobject]@{ Text = $Original; Strategy = 'Keep'; Note = 'not valid JSON' } }
        # The template's CI reads global.json with actions/setup-dotnet, which rejects a partial SDK version, such as 10.0.0,
        # when rollForward is set ("a full SDK version is required"). Merging would keep the repository's, so use the template's.
        if ($leaf -eq 'global.json' -and $repository -is [hashtable] -and $repository['sdk'] -is [hashtable]) {
            $version = "$($repository['sdk']['version'])"
            if ($version -and $version -notmatch '^\d+\.\d+\.\d{3}' -and $repository['sdk'].ContainsKey('rollForward')) {
                return [pscustomobject]@{ Text = $Rendered; Strategy = 'Template'; Note = "its SDK version $version isn't a full version, which actions/setup-dotnet rejects when rollForward is set; used the template's" }
            }
        }
        $result = Merge-JsonValue $template $repository
        $text = (ConvertTo-Json $result -Depth 32) -replace "`r`n", "`n"
        $note = $null
        try { [System.Text.Json.JsonDocument]::Parse($Original).Dispose() } catch { $note = 'comments dropped' }
        return [pscustomobject]@{ Text = $text + "`n"; Strategy = 'Json'; Note = $note }
    }
    if ($Name -like '*.props') {
        $end = $Rendered.LastIndexOf('</Project>')
        if ($Original -match '(?s)<Project\b[^>]*>(.*)</Project>' -and $end -ge 0) {
            $text = $Rendered.Substring(0, $end).TrimEnd() + "`n`n  <!-- Kept from this repository's own $leaf when it adopted the project template -->`n" + $Matches[1].Trim("`n") + "`n`n</Project>`n"
            return [pscustomobject]@{ Text = $text; Strategy = 'MSBuild'; Note = $null }
        }
    }
    $keep
}

function Add-TemplateIndexEntry([string]$Text) {
    if ($Text.Contains('project-template.instructions.md')) { return $Text }
    $entry = '- @.github/instructions/project-template.instructions.md ' + [char]0x2014 + ' the plan-then-execute workflow and base conventions, from the project template. Template updates replace it; never edit it. Where this file or a file it lists says otherwise, the project''s instruction wins.'
    $lines = [Collections.Generic.List[string]]::new([string[]]@($Text -replace "`r`n", "`n" -split "`n"))
    $out = [Collections.Generic.List[string]]::new()
    $at = $lines.IndexOf('## Instructions')
    if ($at -ge 0) {
        $next = $at + 1
        while ($next -lt $lines.Count -and $lines[$next].Trim() -eq '') { $next++ }
        $out.AddRange($lines.GetRange(0, $at + 1))
        if ($next -eq $at + 1) { $out.Add('') } else { $out.AddRange($lines.GetRange($at + 1, $next - $at - 1)) }
        $out.Add($entry)
        if ($next -lt $lines.Count -and $lines[$next].StartsWith('#')) { $out.Add('') }
        $out.AddRange($lines.GetRange($next, $lines.Count - $next))
    }
    else {
        $first = $lines.FindIndex({ param($l) $l.StartsWith('## ') })
        if ($first -ge 0) {
            $out.AddRange($lines.GetRange(0, $first))
            if ($out.Count -and $out[$out.Count - 1].Trim() -ne '') { $out.Add('') }
            $out.AddRange([string[]]@('## Project Template', '', $entry, ''))
            $out.AddRange($lines.GetRange($first, $lines.Count - $first))
        }
        else {
            $out.AddRange($lines)
            $out.AddRange([string[]]@('', '## Project Template', '', $entry))
        }
    }
    ($out -join "`n").TrimEnd("`n") + "`n"
}

function Add-ProjectTemplateImport([string]$Text) {
    if ($Text.Contains('ProjectTemplate.props')) { return $Text }
    $Text = $Text -replace "`r`n", "`n"
    $regex = [regex]::new('<Project\b[^>]*>')
    if (-not $regex.IsMatch($Text)) { throw 'No <Project> element found.' }
    $import = "`n`n  <!-- Shared settings from the project template; this file's own settings, after the import, override them. -->`n  <Import Project=""`$(MSBuildThisFileDirectory)build/ProjectTemplate.props"" />`n"
    $evaluator = [Text.RegularExpressions.MatchEvaluator] { param($m) $m.Value + $import }
    $regex.Replace($Text, $evaluator, 1)
}

function Move-PackageVersionsToCentral([string]$Path) {
    $pairs = [Collections.Generic.List[object]]::new()
    $changes = [Collections.Generic.List[object]]::new()
    $tagRegex = [regex]::new('<PackageReference\b[^>]*>')
    foreach ($file in Get-MSBuildFile $Path) {
        $text = [IO.File]::ReadAllText($file.FullName)
        $found = $pairs
        $evaluator = [Text.RegularExpressions.MatchEvaluator] {
            param($m)
            $tag = $m.Value
            $include = [regex]::Match($tag, '\sInclude="([^"]+)"')
            $version = [regex]::Match($tag, '\sVersion="([^"]*)"')
            if (-not $include.Success -or -not $version.Success) { return $tag }
            $found.Add([pscustomobject]@{ Include = $include.Groups[1].Value; Version = $version.Groups[1].Value })
            $tag.Remove($version.Index, $version.Length)
        }
        $new = $tagRegex.Replace($text, $evaluator)
        if ($new -ne $text) { $changes.Add([pscustomobject]@{ File = $file.FullName; Text = $new }) }
    }
    if ($pairs.Count -eq 0) { return }

    $central = Join-Path $Path 'Directory.Packages.props'
    $centralText = [IO.File]::ReadAllText($central)
    $itemGroup = [regex]::new('(?s)  <ItemGroup>\s*</ItemGroup>')
    if (-not $itemGroup.IsMatch($centralText)) { throw "No empty <ItemGroup> found in $central." }

    $lines = [Collections.Generic.List[string]]::new()
    $chosenLines = [Collections.Generic.List[string]]::new()
    $packages = @($pairs | Group-Object Include | Sort-Object Name -CaseSensitive)
    foreach ($package in $packages) {
        $versions = @($package.Group.Version | Select-Object -Unique)
        $chosen = $versions[0]
        $best = $null
        foreach ($v in $versions) {
            $parsed = $null
            if (-not [System.Management.Automation.SemanticVersion]::TryParse($v, [ref]$parsed)) { $parsed = [System.Management.Automation.SemanticVersion]::new(0, 0, 0) }
            if ($null -eq $best -or $parsed -gt $best) { $best = $parsed; $chosen = $v }
        }
        $chosenLines.Add("    <PackageVersion Include=""$($package.Name)"" Version=""$chosen"" />")
        if ($versions.Count -gt 1) { $lines.Add("$($package.Name): $($versions -join ', ') -> $chosen") }
    }

    $nl = if ($centralText.Contains("`r`n")) { "`r`n" } else { "`n" }
    $block = '  <ItemGroup>' + $nl + ($chosenLines -join $nl) + $nl + '  </ItemGroup>'
    $replacement = $block
    $evaluator = [Text.RegularExpressions.MatchEvaluator] { $replacement }

    foreach ($change in $changes) {
        if ($change.File -ne (Resolve-Path -LiteralPath $central).Path) { [IO.File]::WriteAllText($change.File, $change.Text, [Text.UTF8Encoding]::new($false)) }
    }
    $centralText = [IO.File]::ReadAllText($central)
    [IO.File]::WriteAllText($central, $itemGroup.Replace($centralText, $evaluator, 1), [Text.UTF8Encoding]::new($false))

    "Directory.Packages.props: moved the versions of $($packages.Count) packages out of the project files"
    $lines
}

# Files that list the build's files one by one, so a file the build newly imports must be added to each: the
# .dockerignore files, and the CI files that name Directory.Build.props (such as in a cache key).
function Get-BuildFileList([string]$Path) {
    foreach ($file in @(git -C $Path -c core.quotePath=false ls-files)) {
        $leaf = Split-Path -Leaf $file
        $isCi = $file -eq '.gitlab-ci.yml' -or $file -match '^\.github/workflows/[^/]+\.ya?ml$'
        if ($leaf.EndsWith('.dockerignore')) { $file }
        elseif ($isCi -and [IO.File]::ReadAllText((Join-Path $Path $file)).Contains('Directory.Build.props')) { $file }
    }
}

# How to run the template's .githooks in this clone: HooksPath when core.hooksPath can point at it, otherwise the
# Note to warn with. A hooks path turns off the hooks in .git/hooks, and pre-commit won't install while one is set, so
# a clone that uses pre-commit gets a local pre-commit hook to add instead, and no note once its config runs it.
# A hooks path the clone already has, from any Git config, is never changed: one that names a .githooks folder runs the
# template's hooks, and any other, such as husky's or a global hooks folder, gets a note naming the command to run.
# With "- protect: hook" in AGENTS.md's Landing section, it also says how to run .githooks/pre-push until something does.
# template/.template/Update-Project.ps1 has a deliberate copy of this function, since it runs on its own. Change both
# together, or Update and Adopt can decide differently for the same clone; tests/Test-GitHooks.ps1 runs both copies
# through the same cases.
function Get-GitHooksSetup {
    $config = '.pre-commit-config.yaml'
    $hooksDir = git rev-parse --path-format=absolute --git-path hooks
    $hooksRel = git rev-parse --git-path hooks
    $ownHooks = @(Get-ChildItem -LiteralPath $hooksDir -File -ErrorAction SilentlyContinue | Where-Object Extension -NE '.sample')
    $preCommit = (Test-Path -LiteralPath $config) -or [bool]($ownHooks | Select-String -SimpleMatch 'File generated by pre-commit' -List)

    # The value of the "- protect:" line in AGENTS.md's Landing section, when it has one.
    $protect = $null
    if (Test-Path -LiteralPath AGENTS.md) {
        $inLanding = $false
        foreach ($line in Get-Content -LiteralPath AGENTS.md) {
            if ($line -match '^## Landing\s*$') { $inLanding = $true; continue }
            if ($inLanding -and $line -match '^## ') { break }
            if ($inLanding -and $line -match '^- protect:\s*(\S+)') { $protect = $Matches[1]; break }
        }
    }

    $current = git config --get core.hooksPath
    if ($current) {
        if ((Split-Path -Leaf $current.TrimEnd('\', '/')) -eq '.githooks') { return [pscustomobject]@{ HooksPath = $false; Note = $null } }
        $push = if ($protect -eq 'hook') { ', or .githooks/pre-push, which refuses a push to the default branch as AGENTS.md''s Landing section says (protect: hook)' } else { '' }
        $call = if ($protect -eq 'hook') { "call .githooks/commit-msg from $current/commit-msg and .githooks/pre-push from $current/pre-push" } else { "call .githooks/commit-msg from $current/commit-msg" }
        return [pscustomobject]@{ HooksPath = $false; Note = "Git hooks: .githooks not enabled. core.hooksPath is already $current (git config --show-origin core.hooksPath says where it's set), so Git never runs .githooks/commit-msg, which strips AI agent attribution from commit messages$push. To run both, $call. To run the template's hooks instead, run: git config core.hooksPath .githooks" }
    }

    # True when the clone's pre-push hook, or the pre-push.legacy that pre-commit runs first, calls .githooks/pre-push.
    $pushRuns = $false
    foreach ($name in 'pre-push', 'pre-push.legacy') {
        $file = Join-Path $hooksDir $name
        if ((Test-Path -LiteralPath $file) -and (Select-String -LiteralPath $file -SimpleMatch '.githooks/pre-push' -Quiet)) { $pushRuns = $true }
    }

    $parts = @()
    if ($preCommit -and -not ((Test-Path -LiteralPath $config) -and (Select-String -LiteralPath $config -SimpleMatch '.githooks/commit-msg' -Quiet))) {
        $parts += @('Git hooks: .githooks not enabled. This clone uses pre-commit, which won''t install its hooks while core.hooksPath is set. To run .githooks/commit-msg through pre-commit, add this hook to the repos list in .pre-commit-config.yaml, then run: pre-commit install --hook-type commit-msg',
            '  - repo: local', '    hooks:', '      - id: strip-agent-attribution', '        name: strip agent attribution', '        entry: .githooks/commit-msg', '        language: script', '        stages: [commit-msg]') -join "`n"
    }
    elseif (-not $preCommit -and $ownHooks) {
        $parts += "Git hooks: .githooks not enabled. This clone has hooks of its own in .git/hooks ($(($ownHooks | ForEach-Object Name) -join ', ')), and core.hooksPath would turn them off. To run both, call .githooks/commit-msg from your commit-msg hook, or move your hooks into .githooks and run: git config core.hooksPath .githooks"
    }
    if (($preCommit -or $ownHooks) -and $protect -eq 'hook' -and -not $pushRuns) {
        $pushHook = Join-Path $hooksDir 'pre-push'
        $lead = 'Git hooks: AGENTS.md''s Landing section says protect: hook, but nothing runs .githooks/pre-push in this clone.'
        if ((Test-Path -LiteralPath $pushHook) -and -not (Select-String -LiteralPath $pushHook -SimpleMatch 'File generated by pre-commit' -Quiet)) {
            $parts += "$lead Call .githooks/pre-push from $hooksRel/pre-push with the same arguments and standard input, and refuse the push when it fails."
        }
        elseif ((Test-Path -LiteralPath $pushHook) -and (Test-Path -LiteralPath (Join-Path $hooksDir 'pre-push.legacy'))) {
            # pre-commit moved a hook of the clone's own aside as pre-push.legacy, so the wrapper must not replace it.
            $parts += "$lead Call .githooks/pre-push from $hooksRel/pre-push.legacy with the same arguments and standard input, and refuse the push when it fails."
        }
        else {
            $legacy = Test-Path -LiteralPath $pushHook
            $target = if ($legacy) { "$hooksRel/pre-push.legacy" } else { "$hooksRel/pre-push" }
            $aside = if ($legacy) { ' (pre-commit''s own pre-push hook runs it first, with the same arguments and refs)' } else { '' }
            $parts += @("$lead pre-commit's pre-push stage checks only one of the refs a push updates, so run the hook from Git: save these two lines as $target$aside and, on Linux or macOS, run: chmod +x $target",
                '#!/usr/bin/env sh', 'exec .githooks/pre-push "$@"') -join "`n"
        }
    }
    [pscustomobject]@{ HooksPath = -not $preCommit -and -not $ownHooks; Note = if ($parts) { $parts -join "`n" } else { $null } }
}

# Reads the format as workflow/Get-PlanState.ps1's Get-ChangelogFormat does.
function Test-KeepAChangelog([string]$Text) { $Text -match '(?m)^## \[(Unreleased|v?\d+\.\d+\.\d+)\]' }

# The changelog AGENTS.md's Landing section names (CHANGELOG.md by default) as File, and as Range the version tags merged into HEAD
# that have no release heading in it: <oldest>..<newest>, the tag alone, or -. workflow/Get-PlanState.ps1 prints Range as changelog-backfill.
function Get-ChangelogBackfill {
    $file = 'CHANGELOG.md'
    if (Test-Path -LiteralPath AGENTS.md) {
        $inLanding = $false
        foreach ($line in Get-Content -LiteralPath AGENTS.md) {
            if ($line -match '^## Landing\s*$') { $inLanding = $true; continue }
            if ($inLanding -and $line -match '^## ') { break }
            if ($inLanding -and $line -match '^- changelog:\s*`?([^`\s]+)') { $file = $Matches[1]; break }
        }
    }
    $listed = @(if (Test-Path -LiteralPath $file -PathType Leaf) { foreach ($line in Get-Content -LiteralPath $file) { if ($line -match '^## \[?v?(\d+\.\d+\.\d+)\]?(?: - \d{4}-\d{2}-\d{2})?(?: \[YANKED\])?\s*$') { [version]$Matches[1] } } })
    $missing = @(git tag --list --merged HEAD 2>$null | Where-Object { $_ -match '^v?(\d+\.\d+\.\d+)$' -and [version]$Matches[1] -notin $listed } | Sort-Object { [version]($_ -replace '^v') })
    $range = if ($missing.Count -eq 0) { '-' } elseif ($missing.Count -eq 1) { $missing[0] } else { "$($missing[0])..$($missing[-1])" }
    [pscustomobject]@{ File = $file; Range = $range }
}

Export-ModuleMember -Function Test-KeepAChangelog, Get-ChangelogBackfill, Get-CopierList, Get-OwnableFile, Get-OwnedFile, Get-MSBuildFile, Get-AdoptionAnswers, Merge-AdoptedFile, Add-TemplateIndexEntry, Add-ProjectTemplateImport, Move-PackageVersionsToCentral, Get-BuildFileList, Get-GitHooksSetup
