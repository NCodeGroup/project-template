<#
.SYNOPSIS
    Test that a project whose .copier-answers.yml names a template folder that isn't on this PC updates, moving to the template's address.

.DESCRIPTION
    A project created from a local clone of the template names that folder, which no other PC has. Renders a
    project from v0.1.0, points its answers at a folder that doesn't exist, then updates eight times: once as is, which
    must move the project to https://github.com/NCodeGroup/project-template.git, once with -TemplateClone, a clone whose
    origin is another address with a user name and token in it, which must move the project to that address without
    them, once with a clone whose origin is a GitHub SSH address, which must move it to that address's https form, and
    once more after a v0.2.0 whose update script differs, which the update must hand over to and that script must make
    the move. The fifth names the old polewskm/project-template address and updates to a v0.3.0 whose update script
    differs again, which must make that move after the hand-over too. The last three pass -TemplateClone with a GitLab
    ssh:// origin, a local path as its origin and no origin, which must move the project to
    https://gitlab.com/fork/project-template.git, then twice to https://github.com/NCodeGroup/project-template.git.
    Each of the first three runs, at the newest version already, must commit only the _src_path line; the fourth and
    the fifth must commit the move with the v0.2.0 and v0.3.0 updates, and the last three only the _src_path line.
    Prints PASS or FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-update-address-test-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-UpdateTemplateAddress.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-update-address-test-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$failures = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { "PASS  $Name" } else { "FAIL  $Name  $Detail"; $failures.Add($Name) }
}
function Invoke-Copier {
    if (Get-Command copier -ErrorAction SilentlyContinue) { & copier @args }
    elseif (Get-Command uvx -ErrorAction SilentlyContinue) { & uvx --from copier copier @args }
    else { throw 'Copier not found. Install it with: uv tool install copier' }
    if ($LASTEXITCODE) { throw "copier $($args[0]) exited with code $LASTEXITCODE." }
}
function Invoke-Git {
    git -c user.name=template-test -c user.email=template-test@example.invalid @args
    if ($LASTEXITCODE) { throw "git $($args -join ' ') failed." }
}

if (Test-Path $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
# A direct run keeps its Copier mirror in its own work folder, not in the user's cache; under tests\Invoke-AllTests.ps1 it keeps the runner's folder.
$copierCache = $env:COPIER_CACHE_DIR
if (-not $copierCache) { $env:COPIER_CACHE_DIR = Join-Path $Work 'copier-cache' }
$tpl = Join-Path $Work 'template-repo'
$null = & (Join-Path $PSScriptRoot 'New-TemplateSnapshot.ps1') $tpl

$project = Join-Path $Work 'project'
Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data 'project_name=Test Template Address' --data stack=python --data git_host=github --data 'workflow_tools=[claude]' $tpl $project
Push-Location $project
try {
    Invoke-Git init -q -b main
    Invoke-Git add -A
    if (Test-Path -LiteralPath .githooks/pre-push) { Invoke-Git update-index --chmod=+x .githooks/pre-push }
    Invoke-Git commit -q -m 'Create project'
}
finally { Pop-Location }

# The folder a clone on another PC would name: it is never created.
$missing = Join-Path $Work 'missing-template'
$fork = Join-Path $Work 'fork'
Invoke-Git clone -q $tpl $fork
Invoke-Git -C $fork remote set-url origin https://template-test:secret@example.invalid/fork/project-template.git

# Names the missing folder in the answers, commits that, then updates with git serving every address from the local snapshot, as a host would.
function Invoke-AddressUpdate([hashtable]$Extra = @{}, [string]$Source = $missing) {
    Push-Location $project
    try {
        $answersFile = Join-Path $project '.copier-answers.yml'
        $answers = [IO.File]::ReadAllText($answersFile)
        [IO.File]::WriteAllText($answersFile, [regex]::Replace($answers, '(?m)^_src_path:[^\r\n]*', "_src_path: $Source"))
        if (git status --porcelain) { Invoke-Git commit -q -am 'Name a template folder that isn''t here' }
        $before = git rev-parse HEAD
        $answersBefore = [IO.File]::ReadAllText($answersFile)
        $snapshot = $tpl -replace '\\', '/'
        $savedConfig = @{ Count = $env:GIT_CONFIG_COUNT; Key0 = $env:GIT_CONFIG_KEY_0; Value0 = $env:GIT_CONFIG_VALUE_0; Key1 = $env:GIT_CONFIG_KEY_1; Value1 = $env:GIT_CONFIG_VALUE_1; Key2 = $env:GIT_CONFIG_KEY_2; Value2 = $env:GIT_CONFIG_VALUE_2; Key3 = $env:GIT_CONFIG_KEY_3; Value3 = $env:GIT_CONFIG_VALUE_3 }
        $env:GIT_CONFIG_COUNT = '4'
        $env:GIT_CONFIG_KEY_0 = "url.$snapshot.insteadOf"
        $env:GIT_CONFIG_VALUE_0 = 'https://github.com/NCodeGroup/project-template.git'
        $env:GIT_CONFIG_KEY_1 = "url.$snapshot.insteadOf"
        $env:GIT_CONFIG_VALUE_1 = 'https://example.invalid/fork/project-template.git'
        $env:GIT_CONFIG_KEY_2 = "url.$snapshot.insteadOf"
        $env:GIT_CONFIG_VALUE_2 = 'https://github.com/fork/project-template.git'
        $env:GIT_CONFIG_KEY_3 = "url.$snapshot.insteadOf"
        $env:GIT_CONFIG_VALUE_3 = 'https://gitlab.com/fork/project-template.git'
        try {
            $lines = [Collections.Generic.List[string]]::new()
            try { & (Join-Path $project '.template\Update-Project.ps1') @Extra 2>&1 | ForEach-Object { $lines.Add("$_") }; $exitCode = $LASTEXITCODE } catch { $lines.Add("THROWN: $_"); $exitCode = -1 }
        }
        finally {
            $env:GIT_CONFIG_COUNT = $savedConfig.Count
            $env:GIT_CONFIG_KEY_0 = $savedConfig.Key0; $env:GIT_CONFIG_VALUE_0 = $savedConfig.Value0
            $env:GIT_CONFIG_KEY_1 = $savedConfig.Key1; $env:GIT_CONFIG_VALUE_1 = $savedConfig.Value1
            $env:GIT_CONFIG_KEY_2 = $savedConfig.Key2; $env:GIT_CONFIG_VALUE_2 = $savedConfig.Value2
            $env:GIT_CONFIG_KEY_3 = $savedConfig.Key3; $env:GIT_CONFIG_VALUE_3 = $savedConfig.Value3
        }
        [pscustomobject]@{
            Output = $lines -join "`n"
            ExitCode = $exitCode
            Before = $before
            AnswersBefore = $answersBefore
            AnswersAfter = [IO.File]::ReadAllText($answersFile)
            Changed = @(git diff --name-only $before HEAD)
        }
    }
    finally { Pop-Location }
}

function Test-MovedTo($Result, [string]$Address) {
    Push-Location $project
    try {
        ($Result.ExitCode -eq 0) -and
        $Result.Output.Contains("a folder that isn't on this PC; it now names $Address") -and
        ($Result.AnswersAfter -match "(?m)^_src_path: $([regex]::Escape($Address))\r?$") -and
        ((git rev-parse HEAD) -ne $Result.Before) -and
        ($Result.Changed.Count -eq 1) -and ($Result.Changed[0] -eq '.copier-answers.yml') -and
        -not (git status --porcelain)
    }
    finally { Pop-Location }
}
function Get-OtherAnswers([string]$Text) {
    @($Text -split '\r?\n' | Where-Object { $_ -notmatch '^_src_path:' }) -join "`n"
}

$canonical = 'https://github.com/NCodeGroup/project-template.git'
$r = Invoke-AddressUpdate
Check 'update: a project whose _src_path is a folder that isn''t here moves to NCodeGroup/project-template' (Test-MovedTo $r $canonical) "exit=$($r.ExitCode) changed=$($r.Changed -join ',') $($r.Output)"
Check 'update: moving off the missing folder changes no other answer' ((Get-OtherAnswers $r.AnswersAfter) -eq (Get-OtherAnswers $r.AnswersBefore))

$forkAddress = 'https://example.invalid/fork/project-template.git'
$r = Invoke-AddressUpdate @{ TemplateClone = $fork }
Check 'update -TemplateClone: a project whose _src_path is a folder that isn''t here moves to the clone''s origin, without its user name and token' ((Test-MovedTo $r $forkAddress) -and -not $r.AnswersAfter.Contains('secret') -and -not $r.Output.Contains('secret')) "exit=$($r.ExitCode) changed=$($r.Changed -join ',') $($r.Output)"
Invoke-Git -C $fork remote set-url origin git@github.com:fork/project-template.git
$r = Invoke-AddressUpdate @{ TemplateClone = $fork }
Check 'update -TemplateClone: a clone whose origin is a GitHub SSH address moves the project to its https address' (Test-MovedTo $r 'https://github.com/fork/project-template.git') "exit=$($r.ExitCode) changed=$($r.Changed -join ',') $($r.Output)"
# A later version whose update script differs: the update hands over to it, and that script makes the move.
$nextScript = Join-Path $tpl 'template/.template/Update-Project.ps1'
$nextText = [IO.File]::ReadAllText($nextScript)
if (-not $nextText.Contains("`$ErrorActionPreference = 'Stop'`n")) { throw "No `$ErrorActionPreference line in $nextScript." }
[IO.File]::WriteAllText($nextScript, $nextText.Replace("`$ErrorActionPreference = 'Stop'`n", "`$ErrorActionPreference = 'Stop'`n'Update-Project.ps1 from v0.2.0 is running.'`n"))
Invoke-Git -C $tpl commit -q -am 'A later update script'
Invoke-Git -C $tpl tag v0.2.0
$r = Invoke-AddressUpdate
$subject = git -C $project log -1 --format=%s
Check 'update: a later version''s script, handed the update, moves a project whose _src_path is a folder that isn''t here' (($r.ExitCode -eq 0) -and $r.Output.Contains('Handing the update over to the v0.2.0 version') -and $r.Output.Contains('Update-Project.ps1 from v0.2.0 is running.') -and $r.Output.Contains("a folder that isn't on this PC; it now names $canonical") -and ($r.AnswersAfter -match "(?m)^_src_path: $([regex]::Escape($canonical))\r?$") -and ($subject -eq 'Update from project-template v0.2.0') -and -not (git -C $project status --porcelain)) "exit=$($r.ExitCode) subject=$subject $($r.Output)"
# The old polewskm address, with a v0.3.0 whose update script differs again: that move waits for the hand-over too.
$nextText = [IO.File]::ReadAllText($nextScript)
[IO.File]::WriteAllText($nextScript, $nextText.Replace("'Update-Project.ps1 from v0.2.0 is running.'", "'Update-Project.ps1 from v0.3.0 is running.'"))
Invoke-Git -C $tpl commit -q -am 'Another later update script'
Invoke-Git -C $tpl tag v0.3.0
$r = Invoke-AddressUpdate @{} 'https://github.com/polewskm/project-template.git'
$subject = git -C $project log -1 --format=%s
Check 'update: a later version''s script, handed the update, moves a project on the old polewskm/project-template address' (($r.ExitCode -eq 0) -and $r.Output.Contains('Handing the update over to the v0.3.0 version') -and $r.Output.Contains('Update-Project.ps1 from v0.3.0 is running.') -and $r.Output.Contains("The template moved to $canonical") -and ($r.AnswersAfter -match "(?m)^_src_path: $([regex]::Escape($canonical))\r?$") -and ($subject -eq 'Update from project-template v0.3.0') -and -not (git -C $project status --porcelain)) "exit=$($r.ExitCode) subject=$subject $($r.Output)"
# The fork clone predates v0.2.0 and v0.3.0: bring their tags over, so it reads the version the project is on.
Invoke-Git -C $fork fetch -q --tags $tpl
Invoke-Git -C $fork remote set-url origin ssh://git@gitlab.com/fork/project-template.git
$r = Invoke-AddressUpdate @{ TemplateClone = $fork }
Check 'update -TemplateClone: a clone whose origin is a GitLab ssh:// address moves the project to its https address' (Test-MovedTo $r 'https://gitlab.com/fork/project-template.git') "exit=$($r.ExitCode) changed=$($r.Changed -join ',') $($r.Output)"
Invoke-Git -C $fork remote set-url origin (Join-Path $Work 'elsewhere')
$r = Invoke-AddressUpdate @{ TemplateClone = $fork }
Check 'update -TemplateClone: a clone whose origin is a local path moves the project to NCodeGroup/project-template' (Test-MovedTo $r $canonical) "exit=$($r.ExitCode) changed=$($r.Changed -join ',') $($r.Output)"
Invoke-Git -C $fork remote remove origin
$r = Invoke-AddressUpdate @{ TemplateClone = $fork }
Check 'update -TemplateClone: a clone without an origin moves the project to NCodeGroup/project-template' (Test-MovedTo $r $canonical) "exit=$($r.ExitCode) changed=$($r.Changed -join ',') $($r.Output)"
''
$env:COPIER_CACHE_DIR = $copierCache
if ($failures.Count) { "Kept the work folder: $Work"; "Update template address tests: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Update template address tests: PASSED'
exit 0
