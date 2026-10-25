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

Export-ModuleMember -Function Get-CopierList, Get-MSBuildFile, Get-AdoptionAnswers
