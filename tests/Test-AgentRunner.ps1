<#
.SYNOPSIS
    Test that the end-to-end tests' runner, tests\e2e\Agent.ps1, calls Claude Code and the Copilot CLI as it should, with no model.

.DESCRIPTION
    Runs the runner against stand-ins for claude and copilot that record each call and print what the real CLIs print.
    Checks that a missing CLI is refused; that a Claude Code run passes -p, --output-format json, --permission-mode
    bypassPermissions, --strict-mcp-config, the budget and the model in the fixture project, and that a resumed run passes
    --resume with the first run's session; that the runner adds up the cost and prints the command that continues the
    session; that a Copilot run passes its flags, runs with its own home, allow-all and the token for the call only and puts
    them back, and checks the project's skill ran and no MCP server loaded; that a resumed Copilot run passes --resume,
    and that the cost is the last credits of the one session, not the sum of both runs. Also checks that New-Agent warns
    when Copilot's token is a general one, from GH_TOKEN, and not when it is COPILOT_GITHUB_TOKEN. Also checks that
    -MaxBudgetUsd 0.1 gives Copilot --max-ai-credits 30, its least, and that 0 passes no cap to either tool. Prints PASS or
    FAIL per check and exits 1 on any failure.

.PARAMETER Work
    The scratch folder, deleted and recreated. Defaults to project-template-agent-runner-<process ID> in the
    temp folder, the run's own: deleted when every check passes, kept when one fails.

.EXAMPLE
    .\tests\Test-AgentRunner.ps1
#>
[CmdletBinding()]
param([string]$Work = (Join-Path ([IO.Path]::GetTempPath()) "project-template-agent-runner-$PID"))
$ErrorActionPreference = 'Stop'
$ownWork = -not $PSBoundParameters.ContainsKey('Work')
trap { "Kept the work folder: $Work"; break }
$failures = [Collections.Generic.List[string]]::new()
. (Join-Path $PSScriptRoot 'e2e/Fixture.ps1')

function Read-Calls([string]$Path) { @(Get-Content -LiteralPath $Path | ForEach-Object { $_ | ConvertFrom-Json }) }
function Get-FlagValue($CallArgs, [string]$Flag) {
    $i = [array]::IndexOf($CallArgs, $Flag)
    if ($i -ge 0) { $CallArgs[$i + 1] }
}

if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
$bin = Join-Path $Work 'bin'
$app = Join-Path $Work 'app'
New-Item -ItemType Directory -Force $bin, $app | Out-Null

# The stand-in for claude. It records every call in claude-calls.jsonl and prints the JSON claude -p prints.
Write-Text (Join-Path $bin 'claude.ps1') @'
$log = Join-Path $PSScriptRoot 'claude-calls.jsonl'
Add-Content -LiteralPath $log -Value (ConvertTo-Json -Compress -InputObject @{ args = @($args); cwd = (Get-Location).Path })
$i = [array]::IndexOf(@($args), '--resume')
$session = if ($i -ge 0) { $args[$i + 1] } else { 'claude-session-1' }
"{""session_id"":""$session"",""total_cost_usd"":0.25}"
'@

# The stand-in for copilot. It records every call and the environment it ran with in copilot-calls.jsonl, and prints the
# JSONL copilot -p prints. A prompt with no-session gets the authentication error, one with mcp-connected a connected MCP
# server, and one with no-skill no skill request.
Write-Text (Join-Path $bin 'copilot.ps1') @'
$log = Join-Path $PSScriptRoot 'copilot-calls.jsonl'
Add-Content -LiteralPath $log -Value (ConvertTo-Json -Compress -InputObject @{ args = @($args); cwd = (Get-Location).Path; home = $env:COPILOT_HOME; allowAll = $env:COPILOT_ALLOW_ALL; token = $env:COPILOT_GITHUB_TOKEN })
$prompt = "$($args[[array]::IndexOf(@($args), '-p') + 1])"
if ($prompt.Contains('no-session')) { 'Error: No authentication information found.'; exit 1 }
$status = if ($prompt.Contains('mcp-connected')) { 'connected' } else { 'disabled' }
ConvertTo-Json -Compress -Depth 8 -InputObject @{ type = 'session.mcp_servers_loaded'; data = @{ servers = @(@{ name = 'github-mcp-server'; status = $status }) } }
if ($prompt -match '^/([\w-]+)' -and -not $prompt.Contains('no-skill')) {
    ConvertTo-Json -Compress -Depth 8 -InputObject @{ type = 'assistant.message'; data = @{ toolRequests = @(@{ name = 'skill'; arguments = @{ skill = $Matches[1] } }) } }
}
$resume = [array]::IndexOf(@($args), '--resume')
$nano = if ($resume -ge 0) { 4000000000 } else { 2500000000 }
$usageFile = $args[[array]::IndexOf(@($args), '--usage-output-file') + 1]
Set-Content -LiteralPath $usageFile -Value "{""totalNanoAiu"":$nano}"
$session = if ($resume -ge 0) { $args[$resume + 1] } else { 'copilot-session-1' }
"{""type"":""result"",""sessionId"":""$session"",""exitCode"":0}"
'@

$envNames = 'COPILOT_GITHUB_TOKEN', 'GH_TOKEN', 'GITHUB_TOKEN', 'COPILOT_HOME', 'COPILOT_ALLOW_ALL'
$savedEnv = @{}
foreach ($n in $envNames) { $savedEnv[$n] = [Environment]::GetEnvironmentVariable($n) }
try {
    $thrown = try { New-Agent -Tool claude -Claude (Join-Path $bin 'no-such-cli') -App $app -Work $Work | Out-Null; '' } catch { "$_" }
    Check 'claude: New-Agent refuses a missing CLI' ($thrown -like 'Claude Code CLI not found*') $thrown

    $agent = New-Agent -Tool claude -Claude (Join-Path $bin 'claude.ps1') -Model fixture-model -MaxBudgetUsd 30 -App $app -Work $Work
    $out1 = @(Invoke-Agent $agent -Prompt '/address-feedback #1' -Index 1)
    $out1
    $calls = Read-Calls (Join-Path $bin 'claude-calls.jsonl')
    $c = $calls[0]
    Check 'claude: a run passes -p, --output-format json, --permission-mode bypassPermissions, --strict-mcp-config, --max-budget-usd 30 and --model in the fixture project' ((Get-FlagValue $c.args '-p') -eq '/address-feedback #1' -and (Get-FlagValue $c.args '--output-format') -eq 'json' -and (Get-FlagValue $c.args '--permission-mode') -eq 'bypassPermissions' -and $c.args -contains '--strict-mcp-config' -and (Get-FlagValue $c.args '--max-budget-usd') -eq '30' -and (Get-FlagValue $c.args '--model') -eq 'fixture-model' -and $c.cwd -eq $app -and $c.args -notcontains '--resume') ($c | ConvertTo-Json -Compress)

    $first = $agent.SessionId
    $out2 = @(Invoke-Agent $agent -Prompt 'go ahead' -SessionId $first -Index 2)
    $out2
    $calls = Read-Calls (Join-Path $bin 'claude-calls.jsonl')
    Check 'claude: the resumed run passes --resume with the first run''s session' ($calls.Count -eq 2 -and $first -eq 'claude-session-1' -and (Get-FlagValue $calls[1].args '--resume') -eq $first) ($calls | ConvertTo-Json -Compress)

    $summary = @(Write-AgentSummary $agent) -join ' '
    Check 'claude: the runner adds up the cost and prints the command that continues the session' ($agent.CostUsd -eq 0.5 -and $summary.Contains('Cost: 0.5 USD') -and $summary.Contains('claude --resume claude-session-1') -and (Test-Path -LiteralPath (Join-Path $Work 'claude-1.json'))) "$($agent.CostUsd) $summary"

    [Environment]::SetEnvironmentVariable('COPILOT_GITHUB_TOKEN', 'fixture-token')
    $captured = @(New-Agent -Tool copilot -Copilot (Join-Path $bin 'copilot.ps1') -Model fixture-model -MaxBudgetUsd 30 -App $app -Work $Work 3>&1)
    $agent = $captured | Where-Object { $_ -isnot [Management.Automation.WarningRecord] } | Select-Object -First 1
    $warned = @($captured | Where-Object { $_ -is [Management.Automation.WarningRecord] })
    Check 'copilot: New-Agent takes COPILOT_GITHUB_TOKEN with no warning' ($agent.Token -eq 'fixture-token' -and $warned.Count -eq 0) "warnings: $($warned -join '; ')"
    [Environment]::SetEnvironmentVariable('COPILOT_GITHUB_TOKEN', $null)
    [Environment]::SetEnvironmentVariable('COPILOT_HOME', 'outer-home')
    [Environment]::SetEnvironmentVariable('COPILOT_ALLOW_ALL', $null)
    $out1 = @(Invoke-Agent $agent -Prompt '/address-feedback #1' -Index 1)
    $out1
    $after = @{}
    foreach ($n in 'COPILOT_HOME', 'COPILOT_ALLOW_ALL', 'COPILOT_GITHUB_TOKEN') { $after[$n] = [Environment]::GetEnvironmentVariable($n) }
    $calls = Read-Calls (Join-Path $bin 'copilot-calls.jsonl')
    $c = $calls[0]
    $flags = '--allow-all', '--no-ask-user', '--disable-builtin-mcps', '--secret-env-vars=COPILOT_GITHUB_TOKEN', '--no-auto-update'
    $hasFlags = @($flags | Where-Object { $c.args -notcontains $_ }).Count -eq 0
    Check 'copilot: a run passes -p, --allow-all, --no-ask-user, --disable-builtin-mcps, --secret-env-vars, --output-format json, --no-auto-update, --usage-output-file, --max-ai-credits 3000 and --model, with its own home, allow-all and the token, in the fixture project' ((Get-FlagValue $c.args '-p') -eq '/address-feedback #1' -and $hasFlags -and (Get-FlagValue $c.args '--output-format') -eq 'json' -and (Get-FlagValue $c.args '--usage-output-file') -eq (Join-Path $Work 'copilot-1-usage.json') -and (Get-FlagValue $c.args '--max-ai-credits') -eq '3000' -and (Get-FlagValue $c.args '--model') -eq 'fixture-model' -and $c.args -notcontains '--resume' -and $c.home -eq (Join-Path $Work 'copilot-home') -and $c.allowAll -eq 'true' -and $c.token -eq 'fixture-token' -and $c.cwd -eq $app) ($c | ConvertTo-Json -Compress)
    Check 'copilot: the runner puts COPILOT_HOME, COPILOT_ALLOW_ALL and COPILOT_GITHUB_TOKEN back after the run' ($after.COPILOT_HOME -eq 'outer-home' -and -not $after.COPILOT_ALLOW_ALL -and -not $after.COPILOT_GITHUB_TOKEN) ($after | ConvertTo-Json -Compress)
    Check 'copilot: a run checks that the project''s skill ran and no MCP server loaded' ($out1 -contains 'PASS  Copilot run 1 ran the project''s /address-feedback skill' -and $out1 -contains 'PASS  Copilot run 1 loaded no MCP server') ($out1 -join '; ')

    $first = $agent.SessionId
    $out2 = @(Invoke-Agent $agent -Prompt 'go ahead' -SessionId $first -Index 2)
    $out2
    $calls = Read-Calls (Join-Path $bin 'copilot-calls.jsonl')
    Check 'copilot: the resumed run passes --resume with the first run''s session' ($calls.Count -eq 2 -and $first -eq 'copilot-session-1' -and (Get-FlagValue $calls[1].args '--resume') -eq $first -and $agent.SessionId -eq $first) ($calls | ConvertTo-Json -Compress)

    $summary = @(Write-AgentSummary $agent) -join ' '
    Check 'copilot: the runner keeps the last credits of the session, not the sum of both runs, and prints the command that continues it' ($summary.Contains('Cost: 0.04 USD (4 AI credits)') -and $summary.Contains('copilot --resume copilot-session-1') -and (Get-RunTool $Work 'claude') -eq 'copilot') $summary

    # The failing cases run in their own scope, so their FAIL lines don't fail the suite.
    $out3 = @(& { Set-Variable failures ([Collections.Generic.List[string]]::new()); Invoke-Agent $agent -Prompt 'no-session' -Index 3 })
    Check 'copilot: a run that prints no result fails its session check and clears the session' (@($out3 | Where-Object { $_ -like 'FAIL  Copilot run 3 returned a session*' }).Count -gt 0 -and $agent.SessionId -eq '') ($out3 -join '; ')

    $out4 = @(& { Set-Variable failures ([Collections.Generic.List[string]]::new()); Invoke-Agent $agent -Prompt '/address-feedback mcp-connected' -Index 4 })
    Check 'copilot: a run that loads an MCP server fails its MCP check' (@($out4 | Where-Object { $_ -like 'FAIL  Copilot run 4 loaded no MCP server*' }).Count -gt 0) ($out4 -join '; ')

    $out5 = @(& { Set-Variable failures ([Collections.Generic.List[string]]::new()); Invoke-Agent $agent -Prompt '/address-feedback no-skill' -Index 5 })
    Check 'copilot: a run that runs no skill for its slash command fails its skill check' (@($out5 | Where-Object { $_ -like 'FAIL  Copilot run 5 ran the project''s /address-feedback skill*' }).Count -gt 0) ($out5 -join '; ')

    $thrown = try { New-Agent -Tool copilot -Copilot (Join-Path $bin 'no-such-cli') -App $app -Work $Work | Out-Null; '' } catch { "$_" }
    Check 'copilot: New-Agent refuses a missing CLI' ($thrown -like 'Copilot CLI not found*') $thrown

    [Environment]::SetEnvironmentVariable('COPILOT_GITHUB_TOKEN', $null)
    [Environment]::SetEnvironmentVariable('GH_TOKEN', 'gh-env-token')
    $captured = @(New-Agent -Tool copilot -Copilot (Join-Path $bin 'copilot.ps1') -App $app -Work $Work 3>&1)
    $ghAgent = $captured | Where-Object { $_ -isnot [Management.Automation.WarningRecord] } | Select-Object -First 1
    $warned = @($captured | Where-Object { $_ -is [Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
    Check 'copilot: New-Agent takes GH_TOKEN when COPILOT_GITHUB_TOKEN is unset, and warns that a general token is in use' ($ghAgent.Token -eq 'gh-env-token' -and $warned.Count -eq 1 -and $warned[0].Contains('GH_TOKEN') -and $warned[0].Contains('COPILOT_GITHUB_TOKEN') -and $warned[0].Contains('Copilot Requests')) "$($ghAgent.Token); warnings: $($warned -join '; ')"
    # The runs below take the fixture token, with no warning, and never the token the real gh auth token prints.
    [Environment]::SetEnvironmentVariable('GH_TOKEN', $null)
    [Environment]::SetEnvironmentVariable('COPILOT_GITHUB_TOKEN', 'fixture-token')

    $emptyWork = Join-Path $Work 'empty-run'
    New-Item -ItemType Directory -Force $emptyWork | Out-Null
    Check 'Get-RunTool reads the tool tool.txt names, and falls back without it' ((Get-RunTool $Work 'claude') -eq 'copilot' -and (Get-RunTool $emptyWork 'claude') -eq 'claude') "$(Get-RunTool $Work 'claude') $(Get-RunTool $emptyWork 'claude')"

    $r = Get-RunCheckout copilot $app feedback-1
    $c = Get-RunCheckout claude $app issue-1
    Check 'Get-RunCheckout and Get-CommandFile name each tool''s run checkout and installed command' ($r.Folder -eq $app -and $r.Branch -eq 'feedback-1' -and $c.Branch -eq 'worktree-issue-1' -and $c.Folder -eq (Join-Path $app '.claude/worktrees/issue-1') -and (Get-CommandFile $app copilot run-issues) -eq (Join-Path $app '.github/skills/run-issues/SKILL.md') -and (Get-CommandFile $app claude run-issues) -eq (Join-Path $app '.claude/commands/run-issues.md')) "$($r | ConvertTo-Json -Compress) $($c | ConvertTo-Json -Compress)"

    $budgetWork = Join-Path $Work 'budget'
    $low = New-Agent -Tool copilot -Copilot (Join-Path $bin 'copilot.ps1') -MaxBudgetUsd 0.1 -App $app -Work $budgetWork
    Invoke-Agent $low -Prompt 'budget' -Index 1
    $none = New-Agent -Tool copilot -Copilot (Join-Path $bin 'copilot.ps1') -MaxBudgetUsd 0 -App $app -Work $budgetWork
    Invoke-Agent $none -Prompt 'budget' -Index 2
    $noClaude = New-Agent -Tool claude -Claude (Join-Path $bin 'claude.ps1') -MaxBudgetUsd 0 -App $app -Work $budgetWork
    Invoke-Agent $noClaude -Prompt 'budget' -Index 1
    $copilotCalls = Read-Calls (Join-Path $bin 'copilot-calls.jsonl')
    $claudeCalls = Read-Calls (Join-Path $bin 'claude-calls.jsonl')
    Check 'budget: -MaxBudgetUsd 0.1 gives Copilot --max-ai-credits 30, its least, and 0 passes neither --max-ai-credits nor --max-budget-usd' ((Get-FlagValue $copilotCalls[-2].args '--max-ai-credits') -eq '30' -and $copilotCalls[-1].args -notcontains '--max-ai-credits' -and $claudeCalls[-1].args -notcontains '--max-budget-usd') "$($copilotCalls[-2] | ConvertTo-Json -Compress) $($copilotCalls[-1] | ConvertTo-Json -Compress) $($claudeCalls[-1] | ConvertTo-Json -Compress)"
}
finally {
    foreach ($n in $envNames) { [Environment]::SetEnvironmentVariable($n, $savedEnv[$n]) }
}

if ($failures.Count) { "Kept the work folder: $Work"; "Agent runner: FAILED ($($failures.Count))"; exit 1 }
if ($ownWork) { & (Join-Path $PSScriptRoot 'Remove-TestWork.ps1') $Work }
'Agent runner: PASSED'
exit 0
