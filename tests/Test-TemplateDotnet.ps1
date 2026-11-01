<#
.SYNOPSIS
    Render the template's .NET cases and check that the .NET layer builds, tests and packs.

.DESCRIPTION
    Renders the dotnet and dotnet-library-apache cases of tests\Test-Template.ps1 from a committed, tagged (v0.1.0) snapshot of the working tree in the work folder (-Work), runs the .NET build checks on them, prints PASS or FAIL per check and exits 1 on any failure. With -SkipDotnetBuild it renders nothing and exits 0.

.EXAMPLE
    .\tests\Test-TemplateDotnet.ps1

.PARAMETER SkipDotnetBuild
    Render nothing and run no .NET check; exit 0.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-dotnet-test-<process ID> in the temp folder, the
    run's own: deleted when every check passes, kept when one fails.
#>
[CmdletBinding()]
param(
    [switch]$SkipDotnetBuild,
    [string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-dotnet-test-$PID")
)
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
if ($SkipDotnetBuild) { 'Template .NET tests: skipped (-SkipDotnetBuild)'; exit 0 }
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$tpl = Join-Path $Work 'template-repo'
$tplUrl = & (Join-Path $PSScriptRoot 'New-TemplateSnapshot.ps1') $tpl
$copierCommand = @(if (Get-Command copier -ErrorAction SilentlyContinue) { 'copier' } elseif (Get-Command uvx -ErrorAction SilentlyContinue) { 'uvx', '--from', 'copier', 'copier' } else { throw 'Copier not found. Install it with: uv tool install copier' })
$exe = $copierCommand[0]
$prefix = @($copierCommand | Select-Object -Skip 1)
# A direct run keeps its Copier mirror in its own work folder, not in the user's cache; under tests\Invoke-AllTests.ps1 it keeps the runner's folder.
$copierCache = $env:COPIER_CACHE_DIR
if (-not $copierCache) { $env:COPIER_CACHE_DIR = Join-Path $Work 'copier-cache' }
# These answers repeat the dotnet and dotnet-library-apache cases of $cases in tests\Test-Template.ps1: change both together.
try {
    $output = & $exe @prefix copy --defaults --quiet --vcs-ref v0.1.0 --data "project_name=Test dotnet" --data 'stack=dotnet' --data 'git_host=github' --data "workflow_tools=[claude, copilot, local]" $tplUrl (Join-Path $Work 'dotnet') 2>&1 | Out-String
    if ($LASTEXITCODE) { throw "copier copy for dotnet exited with code ${LASTEXITCODE}: $($output.Trim())" }
    $output = & $exe @prefix copy --defaults --quiet --vcs-ref v0.1.0 --data "project_name=Test dotnet-library-apache" --data 'stack=dotnet' --data 'git_host=github' --data "workflow_tools=[claude, copilot]" --data 'nuget_package=true' --data 'package_license=Apache-2.0' $tplUrl (Join-Path $Work 'dotnet-library-apache') 2>&1 | Out-String
    if ($LASTEXITCODE) { throw "copier copy for dotnet-library-apache exited with code ${LASTEXITCODE}: $($output.Trim())" }
}
finally { $env:COPIER_CACHE_DIR = $copierCache }
Push-Location (Join-Path $Work 'dotnet')
try {
    dotnet new classlib -o src/Demo | Out-Null
    dotnet new xunit -o tests/Demo.Tests --no-restore | Out-Null
    # As AGENTS.md tells the executor: move the template's PackageReference versions into Directory.Packages.props.
    $projPath = (Resolve-Path 'tests/Demo.Tests/Demo.Tests.csproj').Path
    $proj = [xml](Get-Content -LiteralPath $projPath -Raw)
    $versions = foreach ($ref in $proj.SelectNodes('//PackageReference[@Version]')) {
        "    <PackageVersion Include=""$($ref.Include)"" Version=""$($ref.Version)"" />"
        $ref.RemoveAttribute('Version')
    }
    $proj.Save($projPath)
    $propsPath = (Resolve-Path 'Directory.Packages.props').Path
    $props = [IO.File]::ReadAllText($propsPath) -replace '(?s)  <ItemGroup>\s*</ItemGroup>', ("  <ItemGroup>`n" + ($versions -join "`n") + "`n  </ItemGroup>")
    [IO.File]::WriteAllText($propsPath, $props)
    dotnet add tests/Demo.Tests reference src/Demo | Out-Null
    # As AGENTS.md tells the executor: every project joins the root solution, so the default commands cover it.
    dotnet new sln | Out-Null
    dotnet sln add src/Demo tests/Demo.Tests | Out-Null
    $output = dotnet build 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { $output = dotnet test 2>&1 | Out-String }
    $errors = ($output -split "`n" | Select-String -Pattern ' error ' | Select-Object -First 3) -join ' | '
    Check 'dotnet: classlib and xunit in the root solution pass dotnet build and dotnet test' ($LASTEXITCODE -eq 0) $errors

    # A malformed or mistyped entry in build/BannedSymbols.txt bans nothing, silently: a bare M:Type.Method matches only
    # the overload without parameters. Each probe line calls one banned method or property overload, and every line
    # must fail the build with RS0030; the type entries (Newtonsoft.Json) need the package, so they are checked by form.
    $entries = @(Get-Content -LiteralPath 'build/BannedSymbols.txt' | Where-Object { $_ -and -not $_.StartsWith('#') })
    $malformed = @($entries | Where-Object { $_ -notmatch '^[TMPFE]:[^;\s]+;\S.*$' })
    Check 'dotnet: every banned symbol is a documentation ID with a message' ($entries.Count -gt 0 -and -not $malformed) ($malformed -join ' | ')
    $calls = @(
        '_ = t.Result;', '_ = vt.Result;', 'task.Wait();', 'task.Wait(1);', 'task.Wait(TimeSpan.Zero);', 'task.Wait(CancellationToken.None);',
        'task.Wait(1, CancellationToken.None);', 'task.Wait(TimeSpan.Zero, CancellationToken.None);', 'Task.WaitAll(tasks);', 'Task.WaitAll(task);',
        'Task.WaitAll(tasks, TimeSpan.Zero);', 'Task.WaitAll(tasks, 1);', 'Task.WaitAll(tasks, CancellationToken.None);', 'Task.WaitAll(tasks, 1, CancellationToken.None);',
        'Task.WaitAll(new List<Task> { task }, CancellationToken.None);', 'Task.WaitAny(tasks);', 'Task.WaitAny(tasks, TimeSpan.Zero);', 'Task.WaitAny(tasks, CancellationToken.None);',
        'Task.WaitAny(tasks, 1);', 'Task.WaitAny(tasks, 1, CancellationToken.None);', 'task.GetAwaiter().GetResult();', '_ = t.GetAwaiter().GetResult();',
        'v.GetAwaiter().GetResult();', '_ = vt.GetAwaiter().GetResult();', 'JsonDocument.Parse("{}").Dispose();', 'JsonDocument.Parse(new ReadOnlyMemory<byte>([])).Dispose();',
        'JsonDocument.Parse("{}".AsMemory()).Dispose();', 'JsonDocument.Parse(new ReadOnlySequence<byte>([])).Dispose();', 'JsonDocument.Parse(stream).Dispose();',
        '_ = JsonDocument.ParseAsync(stream);', 'JsonDocument.ParseValue(ref reader).Dispose();', '_ = JsonDocument.TryParseValue(ref reader, out _);')
    $methodEntries = @($entries | Where-Object { $_ -match '^[MP]:' })
    $probe = "using System.Buffers;`nusing System.Text.Json;`n`nnamespace Demo;`n`ninternal static class BannedProbe`n{`n    public static void Run(Task task, Task<int> t, ValueTask<int> vt, ValueTask v, Stream stream)`n    {`n        Task[] tasks = [task];`n        var reader = new Utf8JsonReader(""{}""u8);`n" + (($calls | ForEach-Object { "        $_" }) -join "`n") + "`n    }`n}`n"
    $first = 12
    [IO.File]::WriteAllText((Join-Path (Get-Location) 'src/Demo/BannedProbe.cs'), $probe)
    try { $probeOutput = dotnet build src/Demo 2>&1 | Out-String }
    finally { [IO.File]::Delete((Join-Path (Get-Location) 'src/Demo/BannedProbe.cs')) }
    $hitLines = @([regex]::Matches($probeOutput, 'BannedProbe\.cs\((\d+),\d+\): error RS0030') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique)
    $missed = @(for ($i = 0; $i -lt $calls.Count; $i++) { if (($first + $i) -notin $hitLines) { $calls[$i] } })
    Check 'dotnet: every banned method and property overload fails the build with RS0030' ($calls.Count -eq $methodEntries.Count -and -not $missed) "$($calls.Count) probe calls for $($methodEntries.Count) method and property entries; not banned: $($missed -join ' ')"

    # The null-forgiving operator fails the build outside test projects.
    [IO.File]::WriteAllText((Join-Path (Get-Location) 'src/Demo/Forgiving.cs'), "namespace Demo;`n`ninternal static class Forgiving`n{`n    public static int Length(string? text) => text!.Length;`n}`n")
    try { $forgivingOutput = dotnet build src/Demo 2>&1 | Out-String }
    finally { [IO.File]::Delete((Join-Path (Get-Location) 'src/Demo/Forgiving.cs')) }
    Check 'dotnet: the null-forgiving operator fails the build' ($forgivingOutput -match 'Forgiving\.cs\(\d+,\d+\): error NX000\d') (($forgivingOutput -split "`n" | Select-String -Pattern ' error ' | Select-Object -First 3) -join ' | ')

    $dodOutput = pwsh -NoProfile -File build/dod.ps1 2>&1 | Out-String
    Check 'dotnet: build/dod.ps1 passes and says so' ($LASTEXITCODE -eq 0 -and $dodOutput.TrimEnd().EndsWith('Definition of Done: PASSED') -and $dodOutput.Contains('== Decisions') -and $dodOutput.Contains('== Test') -and -not $dodOutput.Contains('== Pack')) $dodOutput
}
finally { Pop-Location }

# A library: its public API is recorded and checked, the Definition of Done packs it, and AssemblyVersion follows the major version.
$libraryDest = Join-Path $Work 'dotnet-library-apache'
if (Test-Path -LiteralPath $libraryDest) {
    Push-Location $libraryDest
    try {
        dotnet new classlib -o src/Greetings | Out-Null
        [IO.File]::WriteAllText((Join-Path (Get-Location) 'src/Greetings/Class1.cs'), "namespace Greetings;`n`n/// <summary>`n/// A greeter.`n/// </summary>`npublic sealed class Greeter`n{`n    /// <summary>`n    /// Greets someone.`n    /// </summary>`n    /// <param name=`"name`">Who to greet.</param>`n    /// <returns>The greeting.</returns>`n    public static string Greet(string name) => `$`"Hello, {name}!`";`n}`n")
        dotnet new sln | Out-Null
        dotnet sln add src/Greetings | Out-Null
        $apiOutput = pwsh -NoProfile -File build/Update-PublicApi.ps1 2>&1 | Out-String
        $unshipped = Join-Path (Get-Location) 'src/Greetings/PublicAPI.Unshipped.txt'
        $apiText = if (Test-Path -LiteralPath $unshipped) { [IO.File]::ReadAllText($unshipped) } else { '' }
        Check 'dotnet-library-apache: Update-PublicApi.ps1 creates the files and records the public API' ($LASTEXITCODE -eq 0 -and $apiText.StartsWith("#nullable enable`n") -and $apiText.Contains('static Greetings.Greeter.Greet(string! name) -> string!') -and (Test-Path -LiteralPath (Join-Path (Get-Location) 'src/Greetings/PublicAPI.Shipped.txt'))) "$apiOutput | $apiText"
        $libDod = pwsh -NoProfile -File build/dod.ps1 2>&1 | Out-String
        $packed = @(Get-ChildItem -LiteralPath (Join-Path (Get-Location) 'artifacts/packages') -Filter 'Greetings.*' -ErrorAction SilentlyContinue | ForEach-Object Name)
        Check 'dotnet-library-apache: build/dod.ps1 builds, tests and packs the library with its symbols' ($LASTEXITCODE -eq 0 -and $libDod.Contains('== Pack') -and $packed -contains 'Greetings.1.0.0.nupkg' -and $packed -contains 'Greetings.1.0.0.snupkg') "$($packed -join ', ') | $libDod"
        [IO.File]::WriteAllText((Join-Path (Get-Location) 'src/Greetings/Extra.cs'), "namespace Greetings;`n`n/// <summary>`n/// Not recorded.`n/// </summary>`npublic sealed class Extra`n{`n}`n")
        $unrecorded = dotnet build src/Greetings 2>&1 | Out-String
        [IO.File]::Delete((Join-Path (Get-Location) 'src/Greetings/Extra.cs'))
        Check 'dotnet-library-apache: a public type the API files do not record fails the build' ($unrecorded -match "error RS0016: Symbol 'Greetings\.Extra'") (($unrecorded -split "`n" | Select-String -Pattern ' error ' | Select-Object -First 3) -join ' | ')
        dotnet build src/Greetings --configuration Release -p:Version=2.5.0-rc.1 2>&1 | Out-Null
        $dll = Join-Path (Get-Location) 'src/Greetings/bin/Release/net10.0/Greetings.dll'
        $assemblyVersion = if (Test-Path -LiteralPath $dll) { "$([Reflection.AssemblyName]::GetAssemblyName($dll).Version)" } else { 'missing' }
        $fileVersion = if (Test-Path -LiteralPath $dll) { [Diagnostics.FileVersionInfo]::GetVersionInfo($dll).FileVersion } else { 'missing' }
        Check 'dotnet-library-apache: AssemblyVersion moves only with the major version, FileVersion keeps the exact one' ($assemblyVersion -eq '2.0.0.0' -and $fileVersion -eq '2.5.0') "AssemblyVersion=$assemblyVersion FileVersion=$fileVersion"
    }
    finally { Pop-Location }
}
''
if ($failures.Count) { "Kept the work folder: $Work"; "Template .NET tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Template .NET tests: PASSED'
exit 0
