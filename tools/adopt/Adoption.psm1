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

# Whether a repository uses Node.js (ADR-0200): a package.json within two folders of the root, outside bin, obj, node_modules and .git, or a .nvmrc or .node-version at the root.
function Test-NodeUse([string]$Path) {
    if (Get-ChildItem -LiteralPath $Path -Recurse -Depth 2 -File -Filter package.json | Where-Object { $_.FullName -notmatch $script:SkipPath }) { return $true }
    foreach ($name in '.nvmrc', '.node-version') {
        if (Test-Path -LiteralPath (Join-Path $Path $name) -PathType Leaf) { return $true }
    }
    $false
}

# The Node.js version file a repository already has, .node-version before .nvmrc, with its version when it is a number such as 22 or 22.11.0.
function Get-NodeVersionFile([string]$Path) {
    foreach ($name in '.node-version', '.nvmrc') {
        $file = Join-Path $Path $name
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        $text = "$(Get-Content -LiteralPath $file -TotalCount 1)".Trim()
        $version = $text -replace '^[vV]', ''
        return [pscustomobject]@{ File = $name; Version = $(if ($version -match '^\d+(\.\d+){0,2}$') { $version } else { $null }); Text = $text }
    }
    $null
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
        # A repository with a history tracks its changes (ADR-0015): an AGENTS.md the template writes for it says pre-release: tracked.
        pre_release  = 'tracked'
    }
    # An adopted repository's CI doesn't start failing on coverage: coverage_gate = $true opts it in (the template's ADR-0026).
    $answers.coverage_gate = $false
    # Nor on file headers it never had: file_headers = $true, then ./.template/Test-FileHeaders.ps1 -Fix (the template's ADR-0027).
    $answers.file_headers = $false
    $tools = @(Get-WorkflowTools $Path)
    if ($tools.Count) { $answers.workflow_tools = $tools }
    # A .NET, Python or other repository with a frontend or Node.js tooling needs Node.js too; a Node.js stack's default is already yes.
    if ($stack -ne 'node' -and (Test-NodeUse $Path)) { $answers.uses_node = $true }
    if ($stack -eq 'dotnet') {
        # An adopted repository keeps its formatting until it opts in: csharp_format = $true, then dotnet csharpier format .
        $answers.csharp_format = $false
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
        # An adopted repository keeps its own linting until it opts in: node_lint = $true, then <package_manager> run format.
        $answers.node_lint = $false
        # Only the scripts package.json has: the template's npm defaults fail where there is no such script.
        $package = Get-Content -LiteralPath (Join-Path $Path 'package.json') -Raw | ConvertFrom-Json -AsHashtable
        $scripts = if ($package.scripts -is [System.Collections.IDictionary]) { $package.scripts } else { @{} }
        $manager = Get-NodePackageManager $Path $package
        $answers.package_manager = $manager
        $answers.build_command = if ($scripts['build']) { "$manager run build" } else { '' }
        # npm init writes a test script that only fails.
        $answers.test_command = if ($scripts['test'] -and $scripts['test'] -notmatch 'no test specified') { "$manager run test" } else { '' }
    }
    # The license: a .NET repository's PackageLicenseExpression, else the root license file's text when it is Apache-2.0 or MIT.
    $license = $null
    if ($stack -eq 'dotnet') {
        $props = Join-Path $Path 'Directory.Build.props'
        if (Test-Path -LiteralPath $props) {
            $text = Get-Content -LiteralPath $props -Raw
            if ($text -match '<PackageLicenseExpression>\s*([^<\s]+)\s*</PackageLicenseExpression>') { $license = $Matches[1] }
        }
    }
    if (-not $license) {
        $licenseFile = Get-ChildItem -LiteralPath $Path -File | Where-Object Name -Match '^(LICEN[CS]E|COPYING)(\.(txt|md))?$' | Select-Object -First 1
        if ($licenseFile) {
            $text = Get-Content -LiteralPath $licenseFile.FullName -Raw
            if ($text -match 'Apache License\s+Version 2\.0') { $license = 'Apache-2.0' }
            elseif ($text -match '(?m)^\s*MIT License' -or $text -match 'Permission is hereby granted, free of charge') { $license = 'MIT' }
        }
    }
    if ($license) { $answers.license = $license }
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
            # .template/Update-Project.ps1 drops the same rule from a project's kept lines with a copy of this pattern; change both together.
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

# Drops the repository's own Nerdbank.GitVersioning reference, since build/ProjectTemplate.props references it too once
# version.json exists and two references fail the build (NU1504, NU1506). A text edit, like Move-PackageVersionsToCentral.
# Returns one File and Version object per edited file.
function Remove-GitVersioningReference([string]$Path) {
    $root = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\', '/')
    $referenceRegex = [regex]::new('(?s)[ \t]*<PackageReference\b[^>]*?\bInclude="Nerdbank\.GitVersioning"(?:[^>/]|/(?!>))*(?:/>|>.*?</PackageReference>)[ \t]*\r?\n?')
    $emptyGroupRegex = [regex]::new('(?s)[ \t]*<ItemGroup>\s*</ItemGroup>[ \t]*\r?\n?')
    $versionTagRegex = [regex]::new('<PackageVersion\b[^>]*\bInclude="Nerdbank\.GitVersioning"[^>]*/>')
    $versionLineRegex = [regex]::new('[ \t]*<PackageVersion\b[^>]*\bInclude="Nerdbank\.GitVersioning"[^>]*/>[ \t]*\r?\n?')
    $dropped = [Collections.Generic.List[object]]::new()
    foreach ($file in Get-MSBuildFile $Path) {
        $text = [IO.File]::ReadAllText($file.FullName)
        $version = $null
        if ($file.Name -eq 'Directory.Packages.props') {
            if ($versionTagRegex.Matches($text).Count -lt 2) { continue }
            $state = @{ Count = 0; Version = $null }
            $evaluator = [Text.RegularExpressions.MatchEvaluator] {
                param($m)
                $state.Count++
                if ($state.Count -eq 1) { return $m.Value }
                $v = [regex]::Match($m.Value, '\bVersion="([^"]*)"')
                if ($v.Success) { $state.Version = $v.Groups[1].Value }
                ''
            }
            $new = $versionLineRegex.Replace($text, $evaluator)
            $version = $state.Version
        }
        else {
            $state = @{ Version = $null }
            $evaluator = [Text.RegularExpressions.MatchEvaluator] {
                param($m)
                $v = [regex]::Match($m.Value, '\bVersion="([^"]*)"')
                if ($v.Success) { $state.Version = $v.Groups[1].Value }
                ''
            }
            $new = $referenceRegex.Replace($text, $evaluator)
            if ($new -ne $text) { $new = $emptyGroupRegex.Replace($new, '') }
            $version = $state.Version
        }
        if ($new -eq $text) { continue }
        [IO.File]::WriteAllText($file.FullName, $new, [Text.UTF8Encoding]::new($false))
        $relative = $file.FullName.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
        $dropped.Add([pscustomobject]@{ File = $relative; Version = $version })
    }
    $dropped.ToArray()
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
# Note to warn with. A hooks path turns off the hooks in .git/hooks.
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
        $push = if ($protect -eq 'hook') { ' as AGENTS.md''s Landing section says (protect: hook)' } else { ' when AGENTS.md''s Landing section says protect: hook' }
        return [pscustomobject]@{ HooksPath = $false; Note = "Git hooks: .githooks not enabled. core.hooksPath is already $current (git config --show-origin core.hooksPath says where it's set), so Git never runs .githooks/pre-push, which refuses a push to the default branch$push. To run both, call .githooks/pre-push from $current/pre-push. To run the template's hooks instead, run: git config core.hooksPath .githooks" }
    }

    # True when the clone's pre-push hook, or the pre-push.legacy that pre-commit runs first, calls .githooks/pre-push.
    $pushRuns = $false
    foreach ($name in 'pre-push', 'pre-push.legacy') {
        $file = Join-Path $hooksDir $name
        if ((Test-Path -LiteralPath $file) -and (Select-String -LiteralPath $file -SimpleMatch '.githooks/pre-push' -Quiet)) { $pushRuns = $true }
    }

    $parts = @()
    if (-not $preCommit -and $ownHooks) {
        $parts += "Git hooks: .githooks not enabled. This clone has hooks of its own in .git/hooks ($(($ownHooks | ForEach-Object Name) -join ', ')), and core.hooksPath would turn them off. To run both, call .githooks/pre-push from your pre-push hook, or move your hooks into .githooks and run: git config core.hooksPath .githooks"
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
    $untracked = $false
    if (Test-Path -LiteralPath AGENTS.md) {
        $inLanding = $false
        foreach ($line in Get-Content -LiteralPath AGENTS.md) {
            if ($line -match '^## Landing\s*$') { $inLanding = $true; continue }
            if ($inLanding -and $line -match '^## ') { break }
            if ($inLanding -and $line -match '^- changelog:\s*`?([^`\s]+)') { $file = $Matches[1] }
            if ($inLanding -and $line -match '^- pre-release:\s*`?untracked`?\s*$') { $untracked = $true }
        }
    }
    $listed = @(if (Test-Path -LiteralPath $file -PathType Leaf) { foreach ($line in Get-Content -LiteralPath $file) { if ($line -match '^## \[?v?(\d+\.\d+\.\d+)\]?(?: - \d{4}-\d{2}-\d{2})?(?: \[YANKED\])?\s*$') { [version]$Matches[1] } } })
    $missing = @(git tag --list --merged HEAD 2>$null | Where-Object { $_ -match '^v?(\d+\.\d+\.\d+)$' -and [version]$Matches[1] -notin $listed -and -not ($untracked -and ([version]$Matches[1]).Major -lt 1) } | Sort-Object { [version]($_ -replace '^v') })
    $range = if ($missing.Count -eq 0) { '-' } elseif ($missing.Count -eq 1) { $missing[0] } else { "$($missing[0])..$($missing[-1])" }
    [pscustomobject]@{ File = $file; Range = $range }
}

# The workflows other than publish.yml that run nuget push, as .github/workflows/<name>, sorted: a repository with one
# has its own NuGet publisher, and a second one would publish every package twice.
function Get-NuGetPublisher {
    if (-not (Test-Path -LiteralPath .github/workflows -PathType Container)) { return }
    $found = foreach ($file in Get-ChildItem -LiteralPath .github/workflows -File) {
        if ($file.Extension -in '.yml', '.yaml' -and $file.Name -ne 'publish.yml' -and (Get-Content -LiteralPath $file.FullName -Raw) -match '(?i)\bnuget(?:\.exe)?\s+push\b') { ".github/workflows/$($file.Name)" }
    }
    @($found) | Sort-Object
}

# For a library whose build/ProjectTemplate.props pins the assembly version and whose Directory.Build.props sets none:
# the highest assembly version a version tag of the newest major shipped, when it exceeds <major>.0.0.0, as Tag,
# AssemblyVersion and Major. A tag shipped its Directory.Build.props's AssemblyVersion, else <major>.0.0.0 when its
# build/ProjectTemplate.props already pinned, else major.minor.patch.0. Nothing when there is no such version.
# template/.template/Update-Project.ps1 has a deliberate copy of this function, since it runs on its own. Change both
# together; tests keep the two equal.
function Get-AssemblyVersionFloor {
    if (-not (Test-Path -LiteralPath build/ProjectTemplate.props -PathType Leaf)) { return }
    if ((Get-Content -LiteralPath build/ProjectTemplate.props -Raw) -notmatch 'Name="ProjectTemplatePinAssemblyVersion"') { return }
    if ((Test-Path -LiteralPath Directory.Build.props -PathType Leaf) -and (Get-Content -LiteralPath Directory.Build.props -Raw) -match '<AssemblyVersion[\s>]') { return }
    $tags = @(git tag --list --merged HEAD 2>$null | Where-Object { $_ -match '^v?(\d+\.\d+\.\d+)(?:-[0-9A-Za-z.-]+)?$' } |
        Sort-Object { [version]($_ -replace '^v' -replace '-.*$') })
    if ($tags.Count -eq 0) { return }
    $major = ([version]($tags[-1] -replace '^v' -replace '-.*$')).Major
    $best = $null
    $bestTag = $null
    foreach ($tag in $tags) {
        $number = [version]($tag -replace '^v' -replace '-.*$')
        if ($number.Major -ne $major) { continue }
        $shipped = $null
        $props = git show "${tag}:Directory.Build.props" 2>$null
        if ($LASTEXITCODE -eq 0 -and ($props -join "`n") -match '<AssemblyVersion>\s*(\d+(?:\.\d+){1,3})\s*</AssemblyVersion>') { $shipped = [version]$Matches[1] }
        if (-not $shipped) {
            $template = git show "${tag}:build/ProjectTemplate.props" 2>$null
            $shipped = if ($LASTEXITCODE -eq 0 -and ($template -join "`n") -match 'Name="ProjectTemplatePinAssemblyVersion"') { [version]::new($major, 0, 0, 0) } else { $number }
        }
        $shipped = [version]::new($shipped.Major, $shipped.Minor, [Math]::Max($shipped.Build, 0), [Math]::Max($shipped.Revision, 0))
        if (-not $best -or $shipped -gt $best) { $best = $shipped; $bestTag = $tag }
    }
    if ($best -gt [version]::new($major, 0, 0, 0)) { [pscustomobject]@{ Tag = $bestTag; AssemblyVersion = $best.ToString(); Major = $major } }
}

# The newest stable version on nuget.org of each packable project's package under the current folder, as Id and Version;
# a package that was never published, or a lookup that fails, gives nothing. Fetch stands in for nuget.org in tests.
# template/.template/Update-Project.ps1 has a deliberate copy of this function, since it runs on its own. Change both
# together; tests keep the two equal.
function Get-PublishedPackageVersion {
    param([scriptblock]$Fetch = { param($Uri) Invoke-RestMethod -Uri $Uri -TimeoutSec 20 })
    foreach ($file in Get-ChildItem -LiteralPath . -Filter *.csproj -File -Recurse -ErrorAction SilentlyContinue) {
        if ($file.FullName -match '[\\/](bin|obj|node_modules|artifacts|\.git)[\\/]' -or $file.Name -like '*.Tests.csproj') { continue }
        $text = Get-Content -LiteralPath $file.FullName -Raw
        if ($text -match '<IsPackable>\s*false') { continue }
        $id = if ($text -match '<PackageId>\s*([^<\s]+)\s*</PackageId>') { $Matches[1] } else { $file.BaseName }
        try { $response = & $Fetch "https://api.nuget.org/v3-flatcontainer/$($id.ToLowerInvariant())/index.json" } catch { continue }
        $stable = @($response.versions | Where-Object { $_ -and $_ -notmatch '-' } | Sort-Object { [version]$_ })
        if ($stable.Count -gt 0) { [pscustomobject]@{ Id = $id; Version = $stable[-1] } }
    }
}

# The Description and PackageTags each packable project would publish, where they differ from the newest stable package
# on nuget.org, as Id, Version, Field and Message: metadata that stopped reaching a package, such as when a .props file was
# dropped. A project that cannot be evaluated, a package never published, or a lookup that fails gives nothing. Fetch stands
# in for nuget.org and Evaluate for MSBuild in tests. Nothing is edited.
# template/.template/Update-Project.ps1 has a deliberate copy of this function, since it runs on its own. Change both
# together; tests keep the two equal.
function Get-PackageMetadataDrift {
    param(
        [scriptblock]$Fetch = { param($Uri) Invoke-RestMethod -Uri $Uri -TimeoutSec 20 },
        [scriptblock]$Evaluate = {
            param($Project)
            try {
                $json = & dotnet msbuild $Project -getProperty:Description -getProperty:PackageTags -nologo 2>$null
                if ($LASTEXITCODE -ne 0) { return $null }
                $properties = ($json -join "`n" | ConvertFrom-Json).Properties
                @{ Description = $properties.Description; PackageTags = $properties.PackageTags }
            }
            catch { $null }
        }
    )
    $root = (Get-Location).ProviderPath
    foreach ($file in Get-ChildItem -LiteralPath . -Filter *.csproj -File -Recurse -ErrorAction SilentlyContinue) {
        if ($file.FullName -match '[\\/](bin|obj|node_modules|artifacts|\.git)[\\/]' -or $file.Name -like '*.Tests.csproj') { continue }
        $text = Get-Content -LiteralPath $file.FullName -Raw
        if ($text -match '<IsPackable>\s*false') { continue }
        $id = if ($text -match '<PackageId>\s*([^<\s]+)\s*</PackageId>') { $Matches[1] } else { $file.BaseName }
        $lower = $id.ToLowerInvariant()
        try {
            $response = & $Fetch "https://api.nuget.org/v3-flatcontainer/$lower/index.json"
            $stable = @($response.versions | Where-Object { $_ -and $_ -notmatch '-' } | Sort-Object { [version]$_ })
            if ($stable.Count -eq 0) { continue }
            $version = $stable[-1]
            $nuspec = & $Fetch "https://api.nuget.org/v3-flatcontainer/$lower/$version/$lower.nuspec"
            if ($nuspec -is [string]) { $nuspec = [xml]$nuspec }
            $metadata = $nuspec.package.metadata
            $publishedValues = @{ Description = [string]$metadata.description; PackageTags = [string]$metadata.tags }
            $local = & $Evaluate $file.FullName
        }
        catch { continue }
        if (-not $local) { continue }
        $relative = [IO.Path]::GetRelativePath($root, $file.FullName) -replace '\\', '/'
        foreach ($field in 'Description', 'PackageTags') {
            $publishedText = ($publishedValues[$field] -replace '\s+', ' ').Trim()
            $localText = ([string]$local[$field] -replace '\s+', ' ').Trim()
            if (-not $publishedText) { continue }
            if ($field -eq 'PackageTags') {
                $publishedKey = (@($publishedText -split '[;,\s]+' | Where-Object { $_ } | Sort-Object -Unique) -join ' ')
                $localKey = (@($localText -split '[;,\s]+' | Where-Object { $_ } | Sort-Object -Unique) -join ' ')
            }
            else { $publishedKey = $publishedText; $localKey = $localText }
            if ($publishedKey -ne $localKey) {
                [pscustomobject]@{ Id = $id; Version = $version; Field = $field; Message = "$relative would publish $field '$localText' where $id $version published '$publishedText': restore it in the project or Directory.Build.props (NCodeGroup/Buffers#33 lost both when a .props file stopped being imported)." }
            }
        }
    }
}

# Whether Directory.Build.props, or a project file under the current folder, already sets PackageValidationBaselineVersion.
# template/.template/Update-Project.ps1 has a deliberate copy of this function, since it runs on its own. Change both together; tests keep the two equal.
function Test-PackageValidationBaseline {
    if ((Test-Path -LiteralPath Directory.Build.props -PathType Leaf) -and (Get-Content -LiteralPath Directory.Build.props -Raw) -match 'PackageValidationBaselineVersion') { return $true }
    @(Get-ChildItem -LiteralPath . -Filter *.csproj -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '[\\/](bin|obj|node_modules|artifacts|\.git)[\\/]' -and (Get-Content -LiteralPath $_.FullName -Raw) -match 'PackageValidationBaselineVersion' }).Count -gt 0
}

# The stale NuGet logistics an older library carries, found under the current folder, as Kind and Message in a fixed
# order: OrphanProps, GeneratePackageOnBuild, RepeatedSettings, Solution, ByteOrderMark, RootProject. Nothing for none.
# template/.template/Update-Project.ps1 has a deliberate copy of this function, since it runs on its own. Change both
# together; tests keep the two equal.
function Get-NuGetLogistics {
    $root = (Get-Location).ProviderPath
    $excluded = 'bin', 'obj', 'node_modules', 'artifacts', '.git'
    $found = [Collections.Generic.List[object]]::new()
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($root)
    while ($pending.Count) {
        foreach ($entry in Get-ChildItem -LiteralPath $pending.Pop() -Force -ErrorAction SilentlyContinue) {
            if ($entry.PSIsContainer) {
                if ($entry.Name -notin $excluded) { $pending.Push($entry.FullName) }
                continue
            }
            $path = $entry.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
            $found.Add([pscustomobject]@{ Path = $path; Name = $entry.Name; Full = $entry.FullName })
        }
    }
    $files = @($found | Sort-Object { $_.Path } -CaseSensitive)
    $projectFiles = @($files | Where-Object { $_.Path -ne 'build/ProjectTemplate.props' -and $_.Name -match '\.(csproj|props)$' })
    $mentioning = @($files | Where-Object { $_.Name -match '\.(csproj|props|targets|slnx)$' } | ForEach-Object { [pscustomobject]@{ Path = $_.Path; Text = Get-Content -LiteralPath $_.Full -Raw } })

    foreach ($file in $files | Where-Object { $_.Name -like '*.props' -and $_.Name -notlike 'Directory.*.props' -and $_.Name -ne 'ProjectTemplate.props' }) {
        if ($mentioning | Where-Object { $_.Path -ne $file.Path -and $_.Text -and $_.Text.IndexOf($file.Name, [StringComparison]::OrdinalIgnoreCase) -ge 0 }) { continue }
        $text = Get-Content -LiteralPath $file.Full -Raw
        $settings = @('Description', 'PackageTags', 'Authors', 'PackageProjectUrl', 'PackageReleaseNotes', 'PackageIcon' | Where-Object { $text -match "<$_[\s>]" })
        $message = if ($settings.Count) { "$($file.Path) is imported by no project, so the $($settings -join ', ') it sets no longer reach the package: import it from Directory.Build.props, after the import of build/ProjectTemplate.props, or move its settings into the project file." }
        else { "$($file.Path) is imported by no project: import it or delete it." }
        [pscustomobject]@{ Kind = 'OrphanProps'; Message = $message }
    }

    foreach ($file in $projectFiles) {
        if ((Get-Content -LiteralPath $file.Full -Raw) -match '<GeneratePackageOnBuild>\s*true') {
            [pscustomobject]@{ Kind = 'GeneratePackageOnBuild'; Message = "$($file.Path) sets GeneratePackageOnBuild to true, which races with dotnet pack from a clean tree (NU5026): delete it; build/dod.ps1 packs on its own." }
        }
    }

    $elements = 'ImplicitUsings', 'Nullable', 'LangVersion', 'PublishRepositoryUrl', 'EmbedUntrackedSources', 'IncludeSymbols', 'SymbolPackageFormat', 'DocumentationFile'
    foreach ($file in $projectFiles | Where-Object { $_.Name -like '*.csproj' -or $_.Name -in 'Directory.Build.props', 'Directory.Packages.props' }) {
        $text = Get-Content -LiteralPath $file.Full -Raw
        $repeated = @($elements | Where-Object { $text -match "<$_[\s>]" })
        if ($text -match '<Package(Reference|Version)\b[^>]*\bInclude\s*=\s*"Microsoft\.SourceLink\.GitHub"') { $repeated += 'Microsoft.SourceLink.GitHub' }
        if ($repeated.Count) {
            [pscustomobject]@{ Kind = 'RepeatedSettings'; Message = "$($file.Path) repeats settings build/ProjectTemplate.props makes: $($repeated -join ', '). Delete them, or keep one only to differ from the template on purpose." }
        }
    }

    foreach ($file in $files | Where-Object { $_.Name -like '*.sln' }) {
        $folder = if ($file.Path.Contains('/')) { $file.Path.Substring(0, $file.Path.LastIndexOf('/') + 1) } else { '' }
        if (($file.Path.Split('/').Count -le 3) -and -not ($files | Where-Object { $_.Name -like '*.slnx' -and $_.Path -eq "$folder$($_.Name)" })) {
            $name = [IO.Path]::GetFileNameWithoutExtension($file.Name)
            [pscustomobject]@{ Kind = 'Solution'; Message = "$($file.Path) is a .sln where the template and current SDKs use .slnx: run dotnet sln $($file.Path) migrate, delete the .sln, and rename $name.sln.DotSettings to $name.slnx.DotSettings if it exists." }
        }
    }

    $bomExtensions = '.cs', '.csproj', '.props', '.targets', '.slnx', '.json', '.md', '.yml', '.yaml', '.xml', '.txt', '.editorconfig'
    $withBom = [Collections.Generic.List[string]]::new()
    foreach ($file in $files | Where-Object { [IO.Path]::GetExtension($_.Name) -in $bomExtensions }) {
        $bytes = [byte[]]::new(3)
        try {
            $stream = [IO.File]::Open($file.Full, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            try { $read = $stream.Read($bytes, 0, 3) } finally { $stream.Dispose() }
        }
        catch [IO.IOException], [UnauthorizedAccessException] {
            Write-Verbose "Skipped $($file.Path), which can't be read for a byte order mark: $($_.Exception.Message)"
            continue
        }
        if ($read -eq 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $withBom.Add($file.Path) }
    }
    if ($withBom.Count) {
        $listed = ($withBom | Select-Object -First 5) -join ', '
        if ($withBom.Count -gt 5) { $listed += ", and $($withBom.Count - 5) more" }
        [pscustomobject]@{ Kind = 'ByteOrderMark'; Message = "$($withBom.Count) file(s) start with a UTF-8 byte order mark, which the template's encoding rule (UTF-8 without BOM) forbids: $listed. Save them without it." }
    }

    $rootProjects = @($files | Where-Object { $_.Name -like '*.csproj' -and -not $_.Path.Contains('/') })
    if ($rootProjects.Count) {
        [pscustomobject]@{ Kind = 'RootProject'; Message = "$($rootProjects.Name -join ', ') $(if ($rootProjects.Count -eq 1) { 'is' } else { 'are' }) at the repository root: move each project into src/ (a test project into tests/), as the template's layout has it." }
    }
}

# The *.cs files under the current folder that don't start with the header .editorconfig's file_header_template sets,
# as relative paths with /: what IDE0073 fails once a project turns csharp_format on (the template's ADR-0148). Nothing
# when .editorconfig sets no header. Generated code is skipped, as IDE0073 skips it.
# template/.template/Update-Project.ps1 has a deliberate copy of this function, since it runs on its own. Change both together; tests keep the two equal.
function Get-CSharpFileWithoutHeader {
    if (-not (Test-Path -LiteralPath .editorconfig -PathType Leaf)) { return }
    $setting = [regex]::Match([IO.File]::ReadAllText((Join-Path (Get-Location).Path '.editorconfig')), '(?m)^file_header_template\s*=\s*(.+?)\r?$')
    if (-not $setting.Success) { return }
    $header = (($setting.Groups[1].Value -split '\\n') | ForEach-Object { "// $_" }) -join "`n"
    foreach ($file in Get-ChildItem -LiteralPath . -Filter *.cs -File -Recurse -ErrorAction SilentlyContinue) {
        if ($file.FullName -match '[\\/](bin|obj|node_modules|artifacts|\.git|Migrations)[\\/]' -or $file.Name -match '\.(g|generated|designer)\.cs$') { continue }
        $text = ([IO.File]::ReadAllText($file.FullName).TrimStart([char]0xFEFF)) -replace "`r`n", "`n"
        if (-not $text.StartsWith("$header`n")) { [IO.Path]::GetRelativePath((Get-Location).Path, $file.FullName) -replace '\\', '/' }
    }
}

# Fills the version.json in the current folder from the repository: Version is the patch after the newest stable tag merged
# into HEAD, and the assembly version is the one Directory.Build.props sets, else Get-AssemblyVersionFloor's. Returns Version,
# Tag, AssemblyVersion and Precision, each $null when unchanged, and nothing without a version.json.
# template/.template/Update-Project.ps1 has a deliberate copy of this function, since it runs on its own. Change both
# together; tests keep the two equal.
function Update-VersionFile {
    $path = Join-Path (Get-Location) 'version.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    $text = [IO.File]::ReadAllText($path)
    $result = [pscustomobject]@{ Version = $null; Tag = $null; AssemblyVersion = $null; Precision = $null }
    $tag = @(git tag --list --merged HEAD 2>$null | Where-Object { $_ -match '^v?\d+\.\d+\.\d+$' } | Sort-Object { [version]($_ -replace '^v') }) | Select-Object -Last 1
    if ($tag) {
        $number = [version]($tag -replace '^v')
        $version = "$($number.Major).$($number.Minor).$($number.Build + 1)"
        $updated = [regex]::Replace($text, '(?m)^  "version": "[^"]*"', "  `"version`": `"$version`"")
        if ($updated -ne $text) { $text = $updated; $result.Version = $version; $result.Tag = $tag }
    }
    $shipped = $null
    if ((Test-Path -LiteralPath Directory.Build.props -PathType Leaf) -and (Get-Content -LiteralPath Directory.Build.props -Raw) -match '<AssemblyVersion>\s*(\d+(?:\.\d+){1,3})\s*</AssemblyVersion>') { $shipped = $Matches[1] }
    if (-not $shipped) { $shipped = (Get-AssemblyVersionFloor).AssemblyVersion }
    if ($shipped) {
        $number = [version]$shipped
        $parts = @($number.Major, $number.Minor, [Math]::Max($number.Build, 0), [Math]::Max($number.Revision, 0))
        if ($parts[3] -gt 0) { $assembly = $parts -join '.'; $precision = 'revision' }
        elseif ($parts[2] -gt 0) { $assembly = $parts[0..2] -join '.'; $precision = 'build' }
        else { $assembly = $parts[0..1] -join '.'; $precision = 'minor' }
        $updated = $text.Replace('"assemblyVersion": { "precision": "major" }', "`"assemblyVersion`": { `"version`": `"$assembly`", `"precision`": `"$precision`" }")
        if ($updated -ne $text) { $text = $updated; $result.AssemblyVersion = $assembly; $result.Precision = $precision }
    }
    if ($result.Version -or $result.AssemblyVersion) { [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false)) }
    $result
}

# The project's own build scripts that run CSharpier's check, which build/dod.ps1 runs in its Format stage once .config/dotnet-tools.json names CSharpier (ADR-0148): such a wrapper checks the formatting twice. template/.template/Update-Project.ps1 has a deliberate copy of this function, since it runs on its own. Change both together; tests keep the two equal.
function Get-CSharpierWrapper([string[]]$TemplateFiles) {
    if (-not (Test-Path -LiteralPath .config/dotnet-tools.json -PathType Leaf) -or (Get-Content -LiteralPath .config/dotnet-tools.json -Raw) -notmatch '(?i)csharpier') { return }
    foreach ($file in @(Get-ChildItem -LiteralPath build -Filter *.ps1 -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $relative = "build/$($file.Name)"
        if ($relative -notin $TemplateFiles -and (Get-Content -LiteralPath $file.FullName -Raw) -match '(?m)^[^#\r\n]*\bcsharpier\s+check\b') { $relative }
    }
}

# tag-release.yml runs ci.yml as a reusable workflow before it tags a release (ADR-0026): without the trigger, no release is tagged.
# template/.template/Update-Project.ps1 has a deliberate copy of this function, since it runs on its own. Change both together; tests/Test-UpdateNotes.ps1 runs both copies through the same cases.
function Get-CiCallNote {
    $release = '.github/workflows/tag-release.yml'
    if (-not (Test-Path -LiteralPath $release) -or (Get-Content -LiteralPath $release -Raw) -notmatch '(?m)^\s+uses:\s*\./\.github/workflows/ci\.yml\s*$') { return }
    $ci = '.github/workflows/ci.yml'
    if ((Test-Path -LiteralPath $ci) -and (Get-Content -LiteralPath $ci -Raw) -match '(?m)^\s+workflow_call:') { return }
    ''
    '.github/workflows/ci.yml is missing or has no workflow_call trigger. .github/workflows/tag-release.yml runs it as a reusable workflow before it tags a release, so until it has that trigger, no release is tagged or published. Add workflow_call: to its on: section, as the ci.yml the project template gives a GitHub project does (the template''s ADR-0026, in docs/decisions/project-template/).'
}

# tag-release.yml grants ci.yml only contents: read (ADR-0026). GitHub checks every job of a called workflow against that
# as the run starts, whatever the job's if: says, and fails the run when one asks for more: no release is tagged.
# template/.template/Update-Project.ps1 has a deliberate copy of this function, since it runs on its own. Change both together; tests/Test-UpdateNotes.ps1 runs both copies through the same cases.
function Get-CiPermissionNote {
    $release = '.github/workflows/tag-release.yml'
    if (-not (Test-Path -LiteralPath $release) -or (Get-Content -LiteralPath $release -Raw) -notmatch '(?m)^\s+uses:\s*\./\.github/workflows/ci\.yml\s*$') { return }
    $ci = '.github/workflows/ci.yml'
    if (-not (Test-Path -LiteralPath $ci)) { return }
    # Each permissions: block of ci.yml, the workflow's own (Owner '') or a job's, with its scope: level pairs.
    $blocks = [Collections.Generic.List[object]]::new()
    $inJobs = $false
    $jobIndent = -1
    $keyIndent = -1
    $job = ''
    $block = $null
    $blockIndent = -1
    foreach ($line in Get-Content -LiteralPath $ci) {
        if ($line -notmatch '^(\s*)([\w-]+):\s*(.*?)\s*(?:#.*)?$') { continue }
        $indent, $key, $value = $Matches[1].Length, $Matches[2], $Matches[3].Trim('''', '"')
        if ($block -and $indent -gt $blockIndent) { $block.Pairs += "${key}: $value"; continue }
        $block = $null
        if ($indent -eq 0) { $inJobs = $key -eq 'jobs'; $jobIndent = -1 }
        elseif ($inJobs -and ($jobIndent -lt 0 -or $indent -le $jobIndent)) { $jobIndent = $indent; $job = $key; $keyIndent = -1; continue }
        elseif ($inJobs -and $keyIndent -lt 0) { $keyIndent = $indent }
        $isJob = $inJobs -and $indent -eq $keyIndent
        if ($key -ne 'permissions' -or -not ($indent -eq 0 -or $isJob)) { continue }
        $block = [pscustomobject]@{ Owner = $(if ($isJob) { $job } else { '' }); Pairs = @() }
        $blockIndent = $indent
        $blocks.Add($block)
        if ($value) {
            $block.Pairs = @($value.Trim('{', '}', ' ') -split ',' | ForEach-Object { ($_ -replace '[''"]', '').Trim() } | Where-Object { $_ })
            $block = $null
        }
    }
    $findings = foreach ($b in $blocks) {
        $extra = @($b.Pairs | Where-Object { $_ -notmatch '^contents:\s*read$' -and $_ -notmatch '^[\w-]+:\s*none$' })
        if (-not $extra.Count) { continue }
        if ($b.Owner) { "job $($b.Owner) asks for $($extra -join ', ')" } else { "its top-level permissions ask for $($extra -join ', ')" }
    }
    if (-not $findings) { return }
    ''
    ".github/workflows/ci.yml asks for more than contents: read: $($findings -join '; '). .github/workflows/tag-release.yml runs ci.yml as a reusable workflow before it tags a release and grants it only contents: read, and GitHub fails that run as it starts when a job of ci.yml asks for more, whatever the job's if: says, so no release is tagged or published. Move each such job into a workflow of its own, such as .github/workflows/coverage.yml, and keep ci.yml's top-level permissions at contents: read (the template's ADR-0026, in docs/decisions/project-template/)."
}

Export-ModuleMember -Function Test-KeepAChangelog, Get-ChangelogBackfill, Get-NuGetPublisher, Get-AssemblyVersionFloor, Get-PublishedPackageVersion, Get-PackageMetadataDrift, Test-PackageValidationBaseline, Get-CSharpFileWithoutHeader, Get-NuGetLogistics, Get-CSharpierWrapper, Update-VersionFile, Get-CopierList, Get-OwnableFile, Get-OwnedFile, Get-MSBuildFile, Get-AdoptionAnswers, Get-NodeVersionFile, Merge-AdoptedFile, Add-TemplateIndexEntry, Add-ProjectTemplateImport, Move-PackageVersionsToCentral, Remove-GitVersioningReference, Get-BuildFileList, Get-GitHooksSetup, Get-CiCallNote, Get-CiPermissionNote
