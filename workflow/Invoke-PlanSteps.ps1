<#
.SYNOPSIS
    Execute PLAN.md step by step on a cheap execution model, verify each step independently, commit it,
    and send steps that need deep reasoning back to the planner.

.DESCRIPTION
    Loop, until no "### [ ] N. Title" step is left (or only the steps given with -Step):
      1. Execute: sends the execute-step prompt plus the step text to Copilot CLI — offline against the
         shack PC's Ollama server (-Executor local, default) or with a GitHub-hosted model
         (-Executor copilot; Claude Sonnet 5.5 unless -Model says otherwise).
      2. Escalation: if the executor marks the step [?] with an "- Escalation:" note (it needs a decision,
         a refactor or a redesign the plan didn't make), the step goes to re-planning.
      3. Verify: runs the step's "- Done when: `command`" itself; the model's own claim is not trusted.
         Pass: marks [x] and commits "Plan step N: Title". Fail: retries with the error (-MaxAttempts),
         then marks [!].
      4. Re-plan: with -Replan claude|copilot|local, the planner model runs the replan-step prompt on the
         [?] or [!] step, the result is recorded as an empty "Re-plan step N" commit, and the loop continues — up to
         -MaxReplans per step. With -Replan none (default), the runner stops so you can re-plan by hand.
    Edits the executor makes to PLAN.md are discarded, except step markers and escalation notes the runner
    applies itself. The plan is a local working file: commits never include it. Logs: %TEMP%\plan-runs\<repo>\.

    Exit codes: 0 all done · 1 a step failed ([!]) · 2 a step needs re-planning ([?]) ·
                3 re-planning limit reached or the planner left the step unresolved.

.EXAMPLE
    .\Invoke-PlanSteps.ps1 -Plan C:\src\app\PLAN.md -DryRun
    .\Invoke-PlanSteps.ps1 -Plan .\PLAN.md                                  # local executor, manual re-planning
    .\Invoke-PlanSteps.ps1 -Plan .\PLAN.md -Replan claude                   # Opus on Claude Max re-plans automatically
    .\Invoke-PlanSteps.ps1 -Plan .\PLAN.md -Executor copilot -Replan copilot   # all Copilot
#>
param(
    [string]$Plan = '.\PLAN.md',
    [int[]]$Step,
    [ValidateSet('local', 'copilot')][string]$Executor = 'local',
    [string]$Model,
    [int]$MaxAttempts = 2,
    [ValidateSet('none', 'claude', 'copilot', 'local')][string]$Replan = 'none',
    [string]$ReplanModel,
    [int]$MaxReplans = 2,
    [string]$Server = $(if ($env:COMPUTERNAME -eq 'K0MTP-SHACK') { 'http://localhost:11434' } else { 'http://10.65.1.102:11434' }),
    [switch]$NoCommit,
    [switch]$AllowDirty,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'HybridWorkflow.psm1') -Force

if (-not $Model) { $Model = if ($Executor -eq 'local') { 'qwen3.6:35b-a3b-coding' } else { 'claude-sonnet-5.5' } }
if (-not $ReplanModel) { $ReplanModel = @{ none = ''; claude = 'opus'; copilot = 'claude-opus-5.5'; local = 'qwen3.6:35b-a3b-coding' }[$Replan] }

$planPath = (Resolve-Path $Plan).Path
$repo = (git -C (Split-Path $planPath) rev-parse --show-toplevel 2>$null)
if (-not $repo) { throw "$planPath is not inside a git repository." }
$repo = (Resolve-Path $repo).Path
$planRel = [IO.Path]::GetRelativePath($repo, $planPath).Replace('\', '/')
$copilot = (Get-Command copilot -ErrorAction SilentlyContinue).Source
if (-not $copilot) { $copilot = Join-Path $env:LOCALAPPDATA 'Programs\copilot-cli\copilot.exe' }
if (-not $DryRun -and -not (Test-Path $copilot)) { throw 'Copilot CLI not found. Install it, for example with personal-notes'' Install-CopilotCli.ps1.' }
if (-not $DryRun -and $Replan -eq 'claude' -and -not (Get-Command claude -ErrorAction SilentlyContinue)) { throw 'Claude Code (claude) not found on PATH.' }
$logDir = Join-Path $env:TEMP "plan-runs\$(Split-Path $repo -Leaf)"
New-Item -ItemType Directory -Force $logDir | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
$byokVars = 'COPILOT_OFFLINE', 'COPILOT_PROVIDER_BASE_URL', 'COPILOT_MODEL', 'COPILOT_PROVIDER_MAX_PROMPT_TOKENS', 'COPILOT_PROVIDER_MAX_OUTPUT_TOKENS'

function Read-Plan { [IO.File]::ReadAllText($planPath) }
function Write-Plan([string]$Text) { [IO.File]::WriteAllText($planPath, $Text, $utf8) }

function Get-PlanStep([string]$Text) {
    $lines = $Text -split "`r?`n"
    $steps = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^### \[([ xX!?])\] (\d+)\. (.+?)\s*$') {
            $s = [pscustomobject]@{ Marker = $Matches[1].ToLower(); Number = [int]$Matches[2]; Title = $Matches[3]; Text = ''; DoneWhen = $null; Escalation = @() }
            $body = @($lines[$i])
            for ($j = $i + 1; $j -lt $lines.Count -and $lines[$j] -notmatch '^#{1,3} '; $j++) { $body += $lines[$j] }
            $s.Text = ($body -join "`n").Trim()
            $dw = $body | Where-Object { $_ -match '^\s*-\s*Done when:\s*`(.+)`\s*$' } | Select-Object -First 1
            if ($dw -and $dw -match '`(.+)`') { $s.DoneWhen = $Matches[1] }
            $s.Escalation = @($body | Where-Object { $_ -match '^\s*-\s*Escalation:' } | ForEach-Object { $_.Trim() })
            $steps += $s
        }
    }
    $steps
}

function Set-StepMarker([string]$Text, [int]$Number, [string]$Marker) {
    [regex]::Replace($Text, "(?m)^### \[[ xX!?]\] $Number\. ", "### [$Marker] $Number. ")
}

# Appends lines to the end of a step's block (before the next heading or trailing blank lines).
function Add-StepLine([string]$Text, [int]$Number, [string[]]$NewLines) {
    if (-not $NewLines) { return $Text }
    $nl = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [Collections.Generic.List[string]]($Text -split "`r?`n")
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match "^### \[[ xX!?]\] $Number\. ") { $start = $i; break } }
    if ($start -lt 0) { return $Text }
    $end = $start + 1
    while ($end -lt $lines.Count -and $lines[$end] -notmatch '^#{1,3} ') { $end++ }
    $insert = $end
    while ($insert - 1 -gt $start -and $lines[$insert - 1].Trim() -eq '') { $insert-- }
    $lines.InsertRange($insert, [string[]]$NewLines)
    $lines -join $nl
}

function Invoke-DoneWhen([string]$Command) {
    Push-Location $repo
    try {
        $out = & pwsh -NoProfile -NonInteractive -Command $Command 2>&1 | Out-String
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $out }
    }
    finally { Pop-Location }
}

# Runs Copilot CLI: offline against Ollama (local) or with a GitHub-hosted model (copilot).
function Invoke-CopilotCli([string]$Prompt, [string]$Mode, [string]$UseModel, [string]$LogFile, [string[]]$Extra = @()) {
    $saved = @{}
    foreach ($k in $byokVars) { $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process') }
    if ($Mode -eq 'local') {
        $set = @{ COPILOT_OFFLINE = 'true'; COPILOT_PROVIDER_BASE_URL = "$Server/v1"; COPILOT_MODEL = $UseModel; COPILOT_PROVIDER_MAX_PROMPT_TOKENS = '120000'; COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = '8192' }
        foreach ($k in $byokVars) { [Environment]::SetEnvironmentVariable($k, $set[$k], 'Process') }
        $modelArgs = @()
    }
    else {
        foreach ($k in $byokVars) { [Environment]::SetEnvironmentVariable($k, $null, 'Process') }
        $modelArgs = @('--model', $UseModel)
    }
    Push-Location $repo
    try { & $copilot @modelArgs @Extra --trust-folder --allow-all-tools --no-ask-user -p $Prompt 2>&1 | Tee-Object -FilePath $LogFile | Out-Host }
    finally {
        Pop-Location
        foreach ($k in $byokVars) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') }
    }
}

function Invoke-Planner([string]$Prompt, [string]$LogFile) {
    switch ($Replan) {
        'claude' {
            Push-Location $repo
            try { & claude -p $Prompt --model $ReplanModel --permission-mode auto 2>&1 | Tee-Object -FilePath $LogFile | Out-Host }
            finally { Pop-Location }
        }
        'copilot' { Invoke-CopilotCli $Prompt 'copilot' $ReplanModel $LogFile @('--reasoning-effort', 'high') }
        'local' { Invoke-CopilotCli $Prompt 'local' $ReplanModel $LogFile }
    }
}

function Save-Commit([string]$Message, [switch]$AllowEmpty) {
    if ($NoCommit) { return }
    # The plan is a local working file: never stage it, whatever the repository's .gitignore says.
    git -C $repo add -A -- . ":(exclude)$planRel" | Out-Null
    git -C $repo diff --cached --quiet
    if ($LASTEXITCODE -eq 0 -and -not $AllowEmpty) { return }
    $commit = @('commit', '-q', '-m', $Message)
    if ($AllowEmpty) { $commit += '--allow-empty' }
    git -C $repo @commit | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git commit failed (exit $LASTEXITCODE): $Message" }
}

# Runs one step through the executor; returns passed, escalated or failed.
function Invoke-Step($s) {
    $basePrompt = (Get-HybridPromptText -Name 'execute-step' -Placeholder "$($s.Number)") +
    "`nStep text, copied from $planRel (the runner verifies the Done-when command and records the step marker itself):`n`n$($s.Text)`n"
    $prompt = $basePrompt
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-Host "`n=== Step $($s.Number): $($s.Title) — attempt $attempt of $MaxAttempts ($Executor, $Model) ===" -ForegroundColor Cyan
        $planBefore = Read-Plan
        Invoke-CopilotCli $prompt $Executor $Model (Join-Path $logDir ('step-{0}-attempt-{1}.log' -f $s.Number, $attempt))
        $after = Get-PlanStep (Read-Plan) | Where-Object Number -EQ $s.Number | Select-Object -First 1
        Write-Plan $planBefore
        $changed = git -C $repo status --porcelain | Where-Object { $_.Substring(3).Trim('"') -ne $planRel }
        if ($after -and ($after.Marker -eq '?' -or $after.Escalation.Count -gt $s.Escalation.Count)) {
            $note = @($after.Escalation | Where-Object { $_ -notin $s.Escalation })
            if (-not $note) { $note = @('- Escalation: the executor stopped without a note; see its log.') }
            Write-Plan (Add-StepLine (Set-StepMarker (Read-Plan) $s.Number '?') $s.Number $note)
            Write-Host "Step $($s.Number) escalated: $($note -join ' ')" -ForegroundColor Yellow
            return [pscustomobject]@{ Result = 'escalated'; Attempts = $attempt; Detail = ($note -join "`n") }
        }
        if (-not $changed) {
            Write-Host 'The executor changed no files; not counting this attempt as done.' -ForegroundColor Yellow
            $prompt = $basePrompt + "`nA previous attempt changed no files. Make the step's changes, or — if the step cannot be done as written — escalate it with [?] and an Escalation line.`n"
            $lastFailure = 'The executor changed no files.'
            continue
        }
        Write-Host "--- Verifying: $($s.DoneWhen)" -ForegroundColor Cyan
        $check = Invoke-DoneWhen $s.DoneWhen
        if ($check.ExitCode -eq 0) {
            Write-Plan (Set-StepMarker (Read-Plan) $s.Number 'x')
            Save-Commit "Plan step $($s.Number): $($s.Title)"
            Write-Host "Step $($s.Number) passed." -ForegroundColor Green
            return [pscustomobject]@{ Result = 'passed'; Attempts = $attempt; Detail = '' }
        }
        $tail = ($check.Output -split "`r?`n" | Select-Object -Last 60) -join "`n"
        Write-Host "Done-when failed (exit $($check.ExitCode))." -ForegroundColor Yellow
        $prompt = $basePrompt + "`nA previous attempt did not finish this step. The Done-when command ``$($s.DoneWhen)`` exited with code $($check.ExitCode). Its last output was:`n`n``````text`n$tail`n```````n`nFix the cause if it is a mistake in your edit; escalate if it needs a decision or a change the step does not list.`n"
        $lastFailure = "Done-when ``$($s.DoneWhen)`` exited $($check.ExitCode):`n$tail"
    }
    Write-Plan (Set-StepMarker (Read-Plan) $s.Number '!')
    [pscustomobject]@{ Result = 'failed'; Attempts = $MaxAttempts; Detail = $lastFailure }
}

# --- Pre-flight -------------------------------------------------------------------------------
$all = Get-PlanStep (Read-Plan)
if (-not $all) { throw "No steps found. Headings must look like '### [ ] 1. Title'." }
$missing = $all | Where-Object { -not $_.DoneWhen }
if ($missing) { throw "Step(s) $($missing.Number -join ', ') have no '- Done when: ``command``' line." }

"Plan: $planPath"
"Executor: $Executor ($Model)   Re-plan: $Replan$(if ($Replan -ne 'none') { " ($ReplanModel, up to $MaxReplans per step)" })"
$all | Format-Table @{ n = 'Step'; e = { $_.Number } }, @{ n = 'Status'; e = { switch ($_.Marker) { 'x' { 'done' } '!' { 'failed' } '?' { 'needs re-plan' } default { 'pending' } } } }, Title, DoneWhen -AutoSize | Out-String -Width 220
if ($DryRun) {
    $first = $all | Where-Object { $_.Marker -eq ' ' -and (-not $Step -or $_.Number -in $Step) } | Select-Object -First 1
    if ($first) { "--- Prompt for step $($first.Number) ---"; (Get-HybridPromptText -Name 'execute-step' -Placeholder "$($first.Number)") + "`nStep text, copied from $planRel`:`n`n$($first.Text)" }
    return
}
if (-not $AllowDirty) {
    $dirty = git -C $repo status --porcelain | Where-Object { $_.Substring(3).Trim('"') -ne $planRel }
    if ($dirty) { throw "Uncommitted changes besides $planRel. Commit or stash them, or pass -AllowDirty.`n$($dirty -join "`n")" }
}
if (-not $NoCommit -and -not (git -C $repo config user.email)) {
    throw "Git has no user.email for $repo, so step commits would fail. Set one (git config --global user.name/user.email) or pass -NoCommit."
}
if ($Step) { $text = Read-Plan; foreach ($n in $Step) { $text = Set-StepMarker $text $n ' ' }; Write-Plan $text }

# --- Main loop --------------------------------------------------------------------------------
$results = [Collections.Generic.List[object]]::new()
$replans = @{}
$exitCode = 0
while ($true) {
    $s = Get-PlanStep (Read-Plan) | Where-Object { $_.Marker -eq ' ' -and (-not $Step -or $_.Number -in $Step) } | Select-Object -First 1
    if (-not $s) { break }
    if (-not $s.DoneWhen) { throw "Step $($s.Number) has no '- Done when:' line." }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = Invoke-Step $s
    $results.Add([pscustomobject]@{ Step = $s.Number; Result = $r.Result; Attempts = $r.Attempts; Seconds = [int]$sw.Elapsed.TotalSeconds; Title = $s.Title })
    if ($r.Result -eq 'passed') { continue }

    $code = if ($r.Result -eq 'escalated') { 2 } else { 1 }
    if ($Replan -eq 'none') { $exitCode = $code; break }
    $count = [int]$replans[$s.Number]
    if ($count -ge $MaxReplans) {
        Write-Host "Step $($s.Number) was re-planned $count times and still came back; it needs you." -ForegroundColor Red
        $exitCode = 3; break
    }
    $replans[$s.Number] = $count + 1
    Write-Host "`n=== Re-planning step $($s.Number) with $Replan ($ReplanModel), round $($count + 1) of $MaxReplans ===" -ForegroundColor Magenta
    $replanInput = "Step $($s.Number) ($($s.Title)) $(if ($r.Result -eq 'escalated') { 'was escalated by the executor' } else { 'failed verification' }):`n$($r.Detail)`n`n" +
    'You are running non-interactively inside the step runner: do not ask questions. Fix the plan only — do not implement the step and do not commit; the runner hands the re-planned step back to the executor model and commits the result. When you are done, the step heading must read "### [ ] N. <title>" and its Escalation line must be gone. If a decision truly needs the user, leave the step marked [?] and explain why in its Escalation line.'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $beforePlan = Get-PlanStep (Read-Plan) | Where-Object Number -EQ $s.Number | Select-Object -First 1
    Invoke-Planner (Get-HybridPromptText -Name 'replan-step' -Placeholder $replanInput) (Join-Path $logDir ('replan-step-{0}-round-{1}.log' -f $s.Number, ($count + 1)))
    $afterPlan = Get-PlanStep (Read-Plan) | Where-Object Number -EQ $s.Number | Select-Object -First 1
    if ($afterPlan -and $afterPlan.Marker -in '?', '!' -and $afterPlan.Escalation.Count -eq 0 -and $afterPlan.Text -ne $beforePlan.Text) {
        Write-Plan (Set-StepMarker (Read-Plan) $s.Number ' ')
        $afterPlan.Marker = ' '
        Write-Host "The planner revised step $($s.Number) and cleared its escalation; handing it back as [ ]." -ForegroundColor Cyan
    }
    Save-Commit "Re-plan step $($s.Number): $($s.Title)" -AllowEmpty
    $results.Add([pscustomobject]@{ Step = $s.Number; Result = "re-planned ($Replan)"; Attempts = 1; Seconds = [int]$sw.Elapsed.TotalSeconds; Title = $(if ($afterPlan) { $afterPlan.Title } else { '(removed)' }) })
    if ($afterPlan -and $afterPlan.Marker -in '?', '!') {
        Write-Host "The planner left step $($s.Number) marked [$($afterPlan.Marker)]; it needs you." -ForegroundColor Red
        $exitCode = 3; break
    }
    if ($afterPlan -and $afterPlan.Marker -eq 'x') {
        $check = Invoke-DoneWhen $afterPlan.DoneWhen
        if ($check.ExitCode -ne 0) {
            Write-Plan (Set-StepMarker (Read-Plan) $s.Number '!')
            Write-Host "The planner marked step $($s.Number) done, but its Done-when check fails; it needs you." -ForegroundColor Red
            $exitCode = 3; break
        }
        Write-Host "The planner completed step $($s.Number) itself; its Done-when check passes." -ForegroundColor Green
    }
}

$results | Format-Table -AutoSize | Out-String -Width 200
switch ($exitCode) {
    0 { "All requested steps passed. Logs: $logDir" }
    1 { "A step failed and is marked [!]. Re-plan it (replan-step), or rerun with -Replan claude|copilot|local. Logs: $logDir" }
    2 { "A step needs re-planning and is marked [?]. Re-plan it (replan-step), or rerun with -Replan claude|copilot|local. Logs: $logDir" }
    3 { "Stopped: re-planning did not resolve the step. Logs: $logDir" }
}
exit $exitCode
