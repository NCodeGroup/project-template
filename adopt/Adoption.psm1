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
        $note = if ($Original.Contains('//') -or $Original.Contains('/*')) { 'comments dropped' }
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

Export-ModuleMember -Function Get-CopierList, Get-MSBuildFile, Get-AdoptionAnswers, Merge-AdoptedFile, Add-TemplateIndexEntry, Add-ProjectTemplateImport