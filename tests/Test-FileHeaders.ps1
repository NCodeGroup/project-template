<#
.SYNOPSIS
    Test the file header check every project gets, template/.template/Test-FileHeaders.ps1.

.DESCRIPTION
    Runs the script with pwsh -NoProfile -File and -Root set to a fixture Git repository, and checks its exit code,
    output and files. Prints PASS or FAIL per check and exits 1 on any failure (ADR-0024).
      check        A run fails and names the files without the copyright line or the SPDX line, among them .astro and
                   stylesheet files and an .astro file whose lines sit outside its frontmatter, and not the files
                   under .template/ or a vendor/ folder, the files of other kinds, or the files that have both lines.
      fix          -Fix exits 0, adds the header at the top or after a #! line, inside an .astro file's frontmatter or
                   in a --- block of its own, and as /* */ comments in a stylesheet, adds only the SPDX line to a file
                   with a copyright line, leaves the other files as they were, and a second run passes.
      endings      -Fix keeps a file's CRLF line endings and its UTF-8 byte order mark.
      no-license   With a blank license answer only the copyright line is required.
      no-author    Without an author_name answer there is nothing to check.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-file-headers-test-<process ID> in the temp
    folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-FileHeaders.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-file-headers-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$repoRoot = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repoRoot 'template/.template/Test-FileHeaders.ps1'
$failures = [Collections.Generic.List[string]]::new()
$copyright = "Copyright $([char]0x00A9) Test Org"

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Write-Fixture([string]$Path, [string]$Text) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Text)
}
# A Git repository with .copier-answers.yml and the given files, all committed.
function New-Fixture([string]$Name, [string]$Answers, [hashtable]$Files) {
    $path = Join-Path $Work $Name
    New-Item -ItemType Directory -Force $path | Out-Null
    git -C $path init -q 2>&1 | Out-Null
    if ($LASTEXITCODE) { throw "git init exited with code $LASTEXITCODE." }
    if ($Answers) { Write-Fixture (Join-Path $path '.copier-answers.yml') $Answers }
    foreach ($file in $Files.Keys) { Write-Fixture (Join-Path $path $file) $Files[$file] }
    git -C $path add . 2>&1 | Out-Null
    git -C $path -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false -c core.hooksPath=NUL commit -q -m fixture 2>&1 | Out-Null
    if ($LASTEXITCODE) { throw "git commit exited with code $LASTEXITCODE." }
    $path
}
function Invoke-Headers([string]$Root, [string[]]$Extra = @()) {
    $out = & pwsh -NoProfile -File $script -Root $Root @Extra 2>&1 | Out-String
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $out }
}
function Read-Text([string]$Root, [string]$Name) { [IO.File]::ReadAllText((Join-Path $Root $Name)) }

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null

# check and fix: a project with an MIT license.
$answers = "author_name: Test Org`nlicense: MIT`n"
$files = @{
    'src/ok.py'            = "# $copyright`n# SPDX-License-Identifier: MIT`n`nprint('ok')`n"
    'src/no-header.ts'     = "export const x = 1;`n"
    'run.sh'               = "#!/bin/sh`necho hi`n"
    'src/half.ps1'         = "# $copyright`n`nWrite-Output 'half'`n"
    'src/Card.astro'       = "---`nconst { title } = Astro.props;`n---`n<h1>{title}</h1>`n"
    'src/Plain.astro'      = "<p>plain</p>`n"
    'src/Empty.astro'      = "---`n---`n<p>empty</p>`n"
    'src/Outside.astro'    = "---`nconst a = 1;`n---`n// $copyright`n// SPDX-License-Identifier: MIT`n<p>{a}</p>`n"
    'src/Ok.astro'         = "---`n// $copyright`n// SPDX-License-Identifier: MIT`n`nconst a = 1;`n---`n<p>{a}</p>`n"
    'styles/site.css'      = "body { margin: 0; }`n"
    'styles/ok.scss'       = "/* $copyright */`n/* SPDX-License-Identifier: MIT */`n`n`$gap: 1rem;`n"
    'styles/half.less'     = "/* $copyright */`n`n@gap: 1rem;`n"
    'vendor/lib/fonts.css' = "@font-face { font-family: Lib; }`n"
    'web/vendor/lib.js'    = "export const lib = 1;`n"
    '.template/Script.ps1' = "Write-Output 'template'`n"
    'notes.md'             = "# Notes`n"
}
$project = New-Fixture 'project' $answers $files
$run = Invoke-Headers $project
Check 'check: a run fails' ($run.ExitCode -eq 1) $run.Output
Check 'check: names the files without a header' ($run.Output.Contains('src/no-header.ts: no copyright line') -and $run.Output.Contains('run.sh: no copyright line') -and $run.Output.Contains('src/half.ps1: no SPDX-License-Identifier line')) $run.Output
Check 'check: names the Astro and stylesheet files without a header, and an Astro file whose lines sit outside its frontmatter' ($run.Output.Contains('src/Card.astro: no copyright line') -and $run.Output.Contains('src/Plain.astro: no copyright line') -and $run.Output.Contains('src/Outside.astro: no copyright line') -and $run.Output.Contains('styles/site.css: no copyright line') -and $run.Output.Contains('styles/half.less: no SPDX-License-Identifier line') -and -not $run.Output.Contains('styles/half.less: no copyright line')) $run.Output
Check 'check: leaves out the template files, vendor/ folders, other kinds and the files with both lines' (-not $run.Output.Contains('Script.ps1') -and -not $run.Output.Contains('vendor/') -and -not $run.Output.Contains('notes.md') -and -not $run.Output.Contains('src/ok.py') -and -not $run.Output.Contains('src/Ok.astro') -and -not $run.Output.Contains('styles/ok.scss')) $run.Output
Check 'check: says how to fix and counts the files' ($run.Output.Contains('Run ./.template/Test-FileHeaders.ps1 -Fix to add them.') -and $run.Output.Contains('File headers: FAILED (9 files)')) $run.Output

$fix = Invoke-Headers $project @('-Fix')
Check 'fix: exits 0 and reports each file' ($fix.ExitCode -eq 0 -and $fix.Output.Contains('src/no-header.ts: header added')) $fix.Output
Check 'fix: a file gets the header at its top' ((Read-Text $project 'src/no-header.ts') -eq "// $copyright`n// SPDX-License-Identifier: MIT`n`nexport const x = 1;`n") (Read-Text $project 'src/no-header.ts')
Check 'fix: a #! line stays first and the header follows it' ((Read-Text $project 'run.sh') -eq "#!/bin/sh`n# $copyright`n# SPDX-License-Identifier: MIT`n`necho hi`n") (Read-Text $project 'run.sh')
Check 'fix: a file with a copyright line gets only the SPDX line after it' ((Read-Text $project 'src/half.ps1') -eq "# $copyright`n# SPDX-License-Identifier: MIT`n`nWrite-Output 'half'`n") (Read-Text $project 'src/half.ps1')
Check 'fix: an Astro file gets the header right after its opening --- line' ((Read-Text $project 'src/Card.astro') -eq "---`n// $copyright`n// SPDX-License-Identifier: MIT`n`nconst { title } = Astro.props;`n---`n<h1>{title}</h1>`n") (Read-Text $project 'src/Card.astro')
Check 'fix: an Astro file without frontmatter gets a --- block that holds the header' ((Read-Text $project 'src/Plain.astro') -eq "---`n// $copyright`n// SPDX-License-Identifier: MIT`n---`n<p>plain</p>`n") (Read-Text $project 'src/Plain.astro')
Check 'fix: an empty Astro frontmatter gets the header and no blank line before its closing ---' ((Read-Text $project 'src/Empty.astro') -eq "---`n// $copyright`n// SPDX-License-Identifier: MIT`n---`n<p>empty</p>`n") (Read-Text $project 'src/Empty.astro')
Check 'fix: a stylesheet gets the header as /* */ comments' ((Read-Text $project 'styles/site.css') -eq "/* $copyright */`n/* SPDX-License-Identifier: MIT */`n`nbody { margin: 0; }`n") (Read-Text $project 'styles/site.css')
Check 'fix: a stylesheet with a copyright line gets only the SPDX line after it' ((Read-Text $project 'styles/half.less') -eq "/* $copyright */`n/* SPDX-License-Identifier: MIT */`n`n@gap: 1rem;`n") (Read-Text $project 'styles/half.less')
Check 'fix: other files are left as they were' ((Read-Text $project 'notes.md') -eq $files['notes.md'] -and (Read-Text $project '.template/Script.ps1') -eq $files['.template/Script.ps1'] -and (Read-Text $project 'vendor/lib/fonts.css') -eq $files['vendor/lib/fonts.css'] -and (Read-Text $project 'web/vendor/lib.js') -eq $files['web/vendor/lib.js'] -and (Read-Text $project 'src/ok.py') -eq $files['src/ok.py'] -and (Read-Text $project 'src/Ok.astro') -eq $files['src/Ok.astro'] -and (Read-Text $project 'styles/ok.scss') -eq $files['styles/ok.scss'])
$again = Invoke-Headers $project
Check 'fix: a second run passes' ($again.ExitCode -eq 0 -and $again.Output.Contains('File headers: PASSED')) $again.Output

# endings: a file with CRLF line endings and a byte order mark.
$crlf = New-Fixture 'crlf' $answers @{ 'src/win.js' = "$([char]0xFEFF)const a = 1;`r`nconst b = 2;`r`n" }
$crlfFix = Invoke-Headers $crlf @('-Fix')
$bytes = [IO.File]::ReadAllBytes((Join-Path $crlf 'src/win.js'))
$expected = [Text.UTF8Encoding]::new($true).GetPreamble() + [Text.UTF8Encoding]::new($false).GetBytes("// $copyright`r`n// SPDX-License-Identifier: MIT`r`n`r`nconst a = 1;`r`nconst b = 2;`r`n")
Check 'endings: -Fix keeps CRLF and the byte order mark' ($crlfFix.ExitCode -eq 0 -and ($bytes -join ',') -eq ($expected -join ',')) ($bytes -join ',')

# no-license: a blank license answer.
$unlicensed = New-Fixture 'no-license' "author_name: Test Org`nlicense: ''`n" @{ 'a.py' = "# $copyright`nprint('a')`n"; 'b.py' = "print('b')`n" }
$unlicensedRun = Invoke-Headers $unlicensed
Check 'no-license: only the copyright line is required' ($unlicensedRun.ExitCode -eq 1 -and $unlicensedRun.Output.Contains('b.py: no copyright line') -and -not $unlicensedRun.Output.Contains('a.py') -and -not $unlicensedRun.Output.Contains('SPDX')) $unlicensedRun.Output

# no-author: no author_name answer.
$noAuthor = New-Fixture 'no-author' "license: MIT`n" @{ 'a.py' = "print('a')`n" }
$noAuthorRun = Invoke-Headers $noAuthor
Check 'no-author: nothing to check' ($noAuthorRun.ExitCode -eq 0 -and $noAuthorRun.Output.Contains('No author_name answer, so there is no header to check.')) $noAuthorRun.Output

''
if ($failures.Count) { "Kept the work folder: $Work"; "File headers tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'File headers tests: PASSED'
exit 0
