# Functions Adopt-Project.ps1 uses to bring an existing repository under the template.

$script:SkipPath = '[\\/](bin|obj|node_modules|\.git)[\\/]'

function Get-CopierList([string]$CopierYml, [string]$Key) {
    $inList = $false
    foreach ($line in Get-Content -LiteralPath $CopierYml) {
        if ($line -match "^${Key}:") { $inList = $true; continue }
        if ($inList -and $line -match '^\s+-\s+(.+?)\s*$') { $Matches[1].Trim("'", '"') }
        elseif ($inList -and $line -match '^\S') { break }
    }
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

function Get-AdoptionAnswers([string]$Path) {
    $Path = (Resolve-Path -LiteralPath $Path).Path
    $found = @(Get-ChildItem -LiteralPath $Path -Recurse -Depth 2 -File -Include '*.sln', '*.slnx', '*.csproj', '*.fsproj', '*.vbproj' |
        Where-Object { $_.FullName -notmatch $script:SkipPath })
    $solutions = @($found | Where-Object Extension -In '.sln', '.slnx')
    $stack = if ($found) { 'dotnet' }
    elseif (Test-Path -LiteralPath (Join-Path $Path 'package.json')) { 'node' }
    elseif ('pyproject.toml', 'requirements.txt', 'setup.py' | Where-Object { Test-Path -LiteralPath (Join-Path $Path $_) }) { 'python' }
    elseif (Get-ChildItem -LiteralPath $Path -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1' | Where-Object { $_.FullName -notmatch $script:SkipPath }) { 'powershell' }
    else { 'other' }

    $remote = "$(git -C $Path remote get-url origin 2>$null)"
    $answers = [ordered]@{
        stack        = $stack
        project_name = if ($solutions.Count -eq 1) { $solutions[0].BaseName } else { Split-Path -Leaf $Path }
        git_host     = if ($remote -match 'gitlab') { 'gitlab' } else { 'github' }
    }
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
        $text = $Rendered.TrimEnd("`n") + "`n`n$marker`n" + $lines.Trim("`n") + "`n"
        return [pscustomobject]@{ Text = $text; Strategy = 'Lines'; Note = $null }
    }
    if ($Name -like '*.json') {
        try {
            $template = ConvertFrom-Json $Rendered -AsHashtable
            $repository = ConvertFrom-Json $Original -AsHashtable
        }
        catch { return [pscustomobject]@{ Text = $Original; Strategy = 'Keep'; Note = 'not valid JSON' } }
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
    $evaluator = [Text.RegularExpressions.MatchEvaluator] { param($m) $replacement }

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

Export-ModuleMember -Function Get-CopierList, Get-MSBuildFile, Get-AdoptionAnswers, Merge-AdoptedFile, Add-TemplateIndexEntry, Add-ProjectTemplateImport, Move-PackageVersionsToCentral, Get-BuildFileList
