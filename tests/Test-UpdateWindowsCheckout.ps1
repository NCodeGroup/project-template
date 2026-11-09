<#
.SYNOPSIS
    Test that an update on Windows stops early for a project on a template version Windows can't check out.

.DESCRIPTION
    Loads Test-WindowsName and Get-WindowsCheckoutProblem from template/.template/Update-Project.ps1, checks names
    Windows refuses and accepts, and that they match Get-WindowsNameProblem in tests/Test-WindowsFileNames.ps1,
    builds a Git repository whose tag v0.1.0 holds only names Windows accepts and whose v0.2.0 adds a uses_node name
    with a |, written to Git's index only so it runs on any OS, checks what the function finds at each, runs the
    script's $IsWindows guard body on it at both tags, then checks that the script calls it under $IsWindows after
    the hand-over and before its first Copier call. Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-windows-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-UpdateWindowsCheckout.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-windows-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$failures = [Collections.Generic.List[string]]::new()
$repoRoot = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repoRoot 'template\.template\Update-Project.ps1'

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Invoke-Git {
    git -c user.name=template-test -c user.email=template-test@example.invalid @args
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed." }
}

$ast = [Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$null)
$functions = foreach ($name in 'Test-WindowsName', 'Get-WindowsCheckoutProblem') {
    $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true) | Select-Object -First 1
}
Check 'update script: defines Test-WindowsName and Get-WindowsCheckoutProblem' (@($functions | Where-Object { $_ }).Count -eq 2)

if (@($functions | Where-Object { $_ }).Count -eq 2) {
    foreach ($f in $functions) { . ([scriptblock]::Create($f.Extent.Text)) }

    $refused = [ordered]@{
        'a|b' = 'a|b'; 'a<b' = 'a<b'; 'a>b' = 'a>b'; 'a:b' = 'a:b'; 'a"b' = 'a"b'; 'a?b' = 'a?b'; 'a*b' = 'a*b'; 'a\b' = 'a\b'
        'a tab' = "a$([char]9)b"
        'CON' = 'CON'; 'con.txt' = 'con.txt'; 'Nul' = 'Nul'; 'COM1' = 'COM1'; 'lpt9.log' = 'lpt9.log'; 'CONIN$' = 'CONIN$'
        'name.' = 'name.'; 'name ' = 'name '
    }
    foreach ($label in $refused.Keys) { Check "name: refuses $label" (-not (Test-WindowsName $refused[$label])) }
    $accepted = @(
        "{% if stack == 'dotnet' %}global.json{% endif %}"
        "{% if (uses_node is defined and uses_node) or (uses_node is not defined and stack == 'node') %}.node-version{% endif %}"
        '.node-version', 'console.md', 'COM10', 'LPT', 'README.md.jinja'
    )
    foreach ($n in $accepted) { Check "name: accepts $n" (Test-WindowsName $n) }
    $fileNames = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Test-WindowsFileNames.ps1'), [ref]$null, [ref]$null).FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-WindowsNameProblem' }, $true) | Select-Object -First 1
    $disagree = @()
    if ($fileNames) {
        . ([scriptblock]::Create($fileNames.Extent.Text))
        $disagree = @(@($refused.Values) + $accepted + 'PRN.md', 'AUX', 'CONTRIBUTING.md' | Where-Object { (Test-WindowsName $_) -ne (-not (Get-WindowsNameProblem $_)) })
    }
    Check 'name: agrees with Get-WindowsNameProblem in tests/Test-WindowsFileNames.ps1' ($fileNames -and -not $disagree) ($disagree -join ', ')

    if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
    $repo = Join-Path $Work 'template-repo'
    New-Item -ItemType Directory -Force $repo | Out-Null
    Invoke-Git -C $repo init -q
    $blob = 'x' | git -C $repo hash-object -w --stdin
    foreach ($path in 'README.md', 'template/a.txt') { Invoke-Git -C $repo -c core.protectNTFS=false update-index --add --cacheinfo "100644,$blob,$path" }
    Invoke-Git -C $repo commit -q -m 'v0.1.0'
    Invoke-Git -C $repo tag v0.1.0
    $bad = "template/.template/{% if uses_node | default(stack == 'node') %}Use-Node.ps1{% endif %}"
    Invoke-Git -C $repo -c core.protectNTFS=false update-index --add --cacheinfo "100644,$blob,$bad"
    Invoke-Git -C $repo commit -q -m 'v0.2.0'
    Invoke-Git -C $repo tag v0.2.0
    Invoke-Git -C $repo commit -q --allow-empty -m 'After v0.2.0'
    $described = git -C $repo describe --tags HEAD

    Check 'checkout: finds nothing at a version Windows can check out' (-not (Get-WindowsCheckoutProblem $repo v0.1.0))
    Check 'checkout: finds the uses_node path at a version that has it' ((Get-WindowsCheckoutProblem $repo v0.2.0) -eq $bad)
    Check 'checkout: finds it at a git describe version' (($described -match '^v0\.2\.0-1-g[0-9a-f]+$') -and ((Get-WindowsCheckoutProblem $repo $described) -eq $bad)) $described
    Check 'checkout: finds nothing at a version the repository lacks' (-not (Get-WindowsCheckoutProblem $repo v9.9.9))

    $guardIf = $ast.FindAll({ param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$IsWindows' -and $n.Clauses[0].Item2.Extent.Text.Contains('Get-WindowsCheckoutProblem') }, $true) | Select-Object -First 1
    Check 'guard: the update script has an $IsWindows block that calls Get-WindowsCheckoutProblem' ([bool]$guardIf)
    if ($guardIf) {
        $body = $guardIf.Clauses[0].Item2.Extent.Text
        $guardRun = [scriptblock]::Create("param([string]`$TemplateClone, [string]`$from)`n" + $body.Substring(1, $body.Length - 2))
        $stop = try { & $guardRun $repo v0.2.0; '' } catch { $_.Exception.Message }
        Check 'guard: stops at a version Windows can''t check out, naming the path and saying to update from Linux, macOS or WSL' ($stop.Contains($bad) -and $stop.Contains('Linux, macOS or WSL')) $stop
        $pass = try { & $guardRun $repo v0.1.0; '' } catch { $_.Exception.Message }
        Check 'guard: lets a version Windows can check out through' (-not $pass) $pass
    }
}

$text = [IO.File]::ReadAllText($script)
$handover = $text.IndexOf('exit $LASTEXITCODE')
$guard = [regex]::Match($text, 'if \(\$IsWindows\) \{\s*\$badPath = Get-WindowsCheckoutProblem \$TemplateClone \$from\s*if \(\$badPath\) \{ throw "[^"]*Linux, macOS or WSL[^"]*" \}')
$first = [Math]::Min($text.IndexOf('Invoke-TemplateRender $from'), $text.IndexOf('Invoke-Copier recopy'))
Check 'update script: on Windows, stops after the hand-over and before Copier, saying to update from Linux, macOS or WSL' ($guard.Success -and $handover -ge 0 -and $handover -lt $guard.Index -and $guard.Index -lt $first)

''
if ($failures.Count) { "Kept the work folder: $Work"; "Update Windows checkout tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Update Windows checkout tests: PASSED'
exit 0
