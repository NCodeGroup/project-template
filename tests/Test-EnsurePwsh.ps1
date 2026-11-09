<#
.SYNOPSIS
    Test the SessionStart hook that makes pwsh available in a Claude Code cloud session.

.DESCRIPTION
    Checks template\.claude\hooks\ensure-pwsh.sh, which .claude\hooks\session-start.sh runs in a cloud session, and this
    repository's own copy in .claude\hooks\. Checks that both copies are identical and parse as bash, and, with bash,
    that the script exits 0 and prints nothing outside a cloud session and when pwsh is already on the PATH, and that
    on a system it has no pinned package for it prints one line and still exits 0. The install itself downloads a
    package from Microsoft, so it is not run here. Prints PASS or FAIL per check and exits 1 on any failure; the bash
    checks are skipped, with a SKIP line, when bash is not on the PATH.

.EXAMPLE
    .\tests\Test-EnsurePwsh.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}

$copies = [ordered]@{
    'template' = Join-Path $repoRoot 'template/.claude/hooks/ensure-pwsh.sh'
    'repository' = Join-Path $repoRoot '.claude/hooks/ensure-pwsh.sh'
}
foreach ($name in $copies.Keys) { Check "the $name copy of ensure-pwsh.sh exists" (Test-Path -LiteralPath $copies[$name]) $copies[$name] }
if (-not ((Test-Path -LiteralPath $copies['template']) -and (Test-Path -LiteralPath $copies['repository']))) {
    "Tests: FAILED ($($failures.Count))"
    exit 1
}
$script = $copies['template']
Check 'both copies of ensure-pwsh.sh are identical' ((Get-FileHash $copies['template']).Hash -eq (Get-FileHash $copies['repository']).Hash)
Check 'ensure-pwsh.sh has LF line endings' (-not ((Get-Content -Raw -LiteralPath $script) -match "`r"))

$bash = Get-Command bash -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $bash) {
    'SKIP  bash is not on the PATH, so the script is not run'
} else {
    function Invoke-Hook([hashtable]$Environment, [string]$ScriptPath = $script) {
        $saved = @{}
        foreach ($key in $Environment.Keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key); [Environment]::SetEnvironmentVariable($key, $Environment[$key]) }
        try {
            $output = & $bash.Source $ScriptPath 2>&1
            [pscustomobject]@{ Code = $LASTEXITCODE; Output = (($output | ForEach-Object { "$_" }) -join "`n").Trim() }
        } finally {
            foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key]) }
        }
    }

    & $bash.Source -n $script
    Check 'ensure-pwsh.sh parses as bash' ($LASTEXITCODE -eq 0)

    $r = Invoke-Hook @{ CLAUDE_CODE_REMOTE = $null }
    Check 'outside a cloud session it exits 0 and prints nothing' ($r.Code -eq 0 -and $r.Output -eq '') "exit $($r.Code): $($r.Output)"
    $r = Invoke-Hook @{ CLAUDE_CODE_REMOTE = 'false' }
    Check 'with CLAUDE_CODE_REMOTE=false it exits 0 and prints nothing' ($r.Code -eq 0 -and $r.Output -eq '') "exit $($r.Code): $($r.Output)"

    $r = Invoke-Hook @{ CLAUDE_CODE_REMOTE = 'true' }
    Check 'in a cloud session that has pwsh it exits 0 and prints nothing' ($r.Code -eq 0 -and $r.Output -eq '') "exit $($r.Code): $($r.Output)"

    $work = Join-Path ([IO.Path]::GetTempPath()) "ensure-pwsh-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    New-Item -ItemType Directory -Force $work | Out-Null
    try {
        # A copy that finds no pwsh and a system with no pinned package: the one-line message, and still exit 0.
        $text = (Get-Content -Raw -LiteralPath $script) -replace 'command -v pwsh >/dev/null 2>&1 && exit 0', 'false && exit 0' -replace 'ubuntu:24\.04:\*:x86_64\)', 'no-such-system:0:*:x86_64)'
        Check 'the test copy differs from the script in the two lines it changes' ($text -ne (Get-Content -Raw -LiteralPath $script) -and $text.Contains('no-such-system'))
        $copy = Join-Path $work 'ensure-pwsh.sh'
        [IO.File]::WriteAllText($copy, $text.Replace("`r`n", "`n"))
        $r = Invoke-Hook @{ CLAUDE_CODE_REMOTE = 'true' } $copy
        Check 'without pwsh on an unpinned system it exits 0 with one explanatory line' ($r.Code -eq 0 -and $r.Output -match '^ensure-pwsh: pwsh is missing' -and ($r.Output -split "`n").Count -eq 1) "exit $($r.Code): $($r.Output)"
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count) { "Tests: FAILED ($($failures.Count))"; exit 1 }
'Tests: PASSED'
