<#
.SYNOPSIS
    The headless runner the end-to-end tests share: Claude Code (claude -p) or the Copilot CLI (copilot -p) behind one interface, and the facts that differ by tool.

.DESCRIPTION
    Fixture.ps1 dot-sources it. Everything that differs between the two tools lives here, so a scenario is written once and runs under both.
    New-Agent makes the runner for one tool: its CLI, model, budget, time limit, fixture project and work folder, and, for Copilot, its own home folder and the token it runs with, with a warning when that is a general GitHub token rather than COPILOT_GITHUB_TOKEN; it also writes tool.txt in the work folder.
    Get-RunTool gives the tool a run used, from tool.txt, for -CheckOnly without -Tool.
    Get-RunCheckout gives the folder and branch a run works in: its worktree under .claude/worktrees, in every tool.
    Get-CommandFile gives the path of a command's installed copy in the fixture: a .claude command, or a .github skill.
    Invoke-AgentProcess runs a CLI as a process of its own in the fixture project, a .ps1 one in a pwsh of its own, and stops it with its child processes past the runner's -TimeoutMinutes.
    Invoke-ClaudeCli and Invoke-CopilotCli run one headless prompt in the tool and return what it printed, parsed.
    Invoke-Agent runs one prompt in either tool and checks the run returned a session; for Copilot it also checks the project's skill ran and no MCP server loaded.
    Write-AgentSummary prints the cost, as unknown or as at least what it read when a Copilot run's usage file couldn't be read, and how to continue the session by hand.
#>

# Copilot bills in AI credits, 100 to the dollar, and its --max-ai-credits takes no fewer than 30.
$CopilotCreditsPerUsd = 100
$CopilotMinCredits = 30

function New-Agent(
    [ValidateSet('claude', 'copilot')][string]$Tool,
    [string]$Claude = 'claude',
    [string]$Copilot = 'copilot',
    [string]$Model = '',
    [double]$MaxBudgetUsd = 0,
    [double]$TimeoutMinutes = 45,
    [string]$App,
    [string]$Work
) {
    $cli = if ($Tool -eq 'copilot') { $Copilot } else { $Claude }
    if (-not (Get-Command $cli -CommandType Application, ExternalScript -ErrorAction SilentlyContinue)) {
        if ($Tool -eq 'copilot') { throw 'Copilot CLI not found: install it, or pass -Copilot <path>' }
        throw 'Claude Code CLI not found: install it, or pass -Claude <path>'
    }
    $token = ''
    $source = ''
    $copilotHome = ''
    if ($Tool -eq 'copilot') {
        # Read before Use-FixtureEnvironment: it puts the gh stand-in first on PATH and clears the token variables,
        # and Copilot has no other way to find the user's login, so this runner hands it the token for the call only.
        foreach ($n in 'COPILOT_GITHUB_TOKEN', 'GH_TOKEN', 'GITHUB_TOKEN') {
            $value = [Environment]::GetEnvironmentVariable($n)
            if ($value) { $token = $value; $source = $n; break }
        }
        if (-not $token -and (Get-Command gh -ErrorAction SilentlyContinue)) {
            $printed = "$(gh auth token 2>$null)".Trim()
            if ($LASTEXITCODE -eq 0) { $token = $printed; $source = 'gh auth token' }
        }
        if ($token -and $source -ne 'COPILOT_GITHUB_TOKEN') {
            Write-Warning "Copilot runs with the general GitHub token from $source, in a session with --allow-all that reads the fixture's text. Set COPILOT_GITHUB_TOKEN to a fine-grained personal access token with only the Copilot Requests permission, so the session holds no token that can change your repositories."
        }
        $copilotHome = Join-Path $Work 'copilot-home'
        New-Item -ItemType Directory -Force $copilotHome | Out-Null
    }
    New-Item -ItemType Directory -Force $Work | Out-Null
    [IO.File]::WriteAllText((Join-Path $Work 'tool.txt'), "$Tool`n")
    [pscustomobject]@{
        Tool         = $Tool
        Name         = if ($Tool -eq 'copilot') { 'Copilot' } else { 'Claude Code' }
        Cli          = $cli
        Model        = $Model
        MaxBudgetUsd = $MaxBudgetUsd
        TimeoutMinutes = $TimeoutMinutes
        App          = $App
        Work         = $Work
        CopilotHome  = $copilotHome
        Token        = $token
        CostUsd      = 0.0
        Credits      = @{}
        UnreadUsage  = [Collections.Generic.List[int]]::new()
        SessionId    = ''
    }
}

function Get-RunTool([string]$Work, [string]$Tool) {
    $file = Join-Path $Work 'tool.txt'
    if (Test-Path -LiteralPath $file) {
        $text = [IO.File]::ReadAllText($file).Trim()
        if ($text -eq 'claude' -or $text -eq 'copilot') { return $text }
    }
    $Tool
}

function Get-RunCheckout([string]$Tool, [string]$App, [string]$Name) {
    [pscustomobject]@{ Folder = Join-Path $App ".claude/worktrees/$Name"; Branch = "worktree-$Name" }
}

function Get-CommandFile([string]$App, [string]$Tool, [string]$Name) {
    if ($Tool -eq 'copilot') { return Join-Path $App ".github/skills/$Name/SKILL.md" }
    Join-Path $App ".claude/commands/$Name.md"
}

function Invoke-AgentProcess($Agent, [string[]]$Arguments) {
    # A process of its own, not the call operator, so a run past its time limit can be stopped with its child processes.
    $command = Get-Command $Agent.Cli -CommandType Application, ExternalScript | Select-Object -First 1
    $start = [Diagnostics.ProcessStartInfo]::new()
    if ($command.CommandType -eq 'ExternalScript') {
        # A .ps1 CLI, such as npm's shim or a test's stand-in, runs in a pwsh of its own.
        $start.FileName = [Environment]::ProcessPath
        foreach ($a in '-NoProfile', '-File', $command.Source) { $start.ArgumentList.Add($a) }
    }
    else { $start.FileName = $command.Source }
    foreach ($a in $Arguments) { $start.ArgumentList.Add($a) }
    $start.WorkingDirectory = $Agent.App
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $process = [Diagnostics.Process]::Start($start)
    $output = $process.StandardOutput.ReadToEndAsync()
    $errors = $process.StandardError.ReadToEndAsync()
    $limit = if ($Agent.TimeoutMinutes -gt 0) { [int]($Agent.TimeoutMinutes * 60000) } else { -1 }
    $timedOut = -not $process.WaitForExit($limit)
    if ($timedOut) { $process.Kill($true) }
    $process.WaitForExit()
    $null = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($output, $errors), 30000)
    $process.Dispose()
    [pscustomobject]@{
        Output   = if ($output.IsCompletedSuccessfully) { $output.Result } else { '' }
        Errors   = if ($errors.IsCompletedSuccessfully) { $errors.Result } else { '' }
        TimedOut = $timedOut
    }
}

function Invoke-ClaudeCli($Agent, [string]$Prompt, [string]$SessionId, [int]$Index) {
    $arguments = @('-p', $Prompt)
    if ($SessionId) { $arguments += '--resume', $SessionId }
    # --strict-mcp-config with no --mcp-config gives the session none of the user's MCP servers: it posts only through the gh stand-in.
    $arguments += '--output-format', 'json', '--permission-mode', 'bypassPermissions', '--strict-mcp-config'
    if ($Agent.Model) { $arguments += '--model', $Agent.Model }
    if ($Agent.MaxBudgetUsd -gt 0) { $arguments += '--max-budget-usd', "$($Agent.MaxBudgetUsd)" }
    $run = Invoke-AgentProcess $Agent $arguments
    if ($run.Errors) { [Console]::Error.Write($run.Errors) }
    [IO.File]::WriteAllText((Join-Path $Agent.Work "claude-$Index.json"), $run.Output)
    $json = try { $run.Output | ConvertFrom-Json } catch { $null }
    [pscustomobject]@{ Json = $json; TimedOut = $run.TimedOut }
}

function Invoke-CopilotCli($Agent, [string]$Prompt, [string]$SessionId, [int]$Index) {
    $usageFile = Join-Path $Agent.Work "copilot-$Index-usage.json"
    $arguments = @('-p', $Prompt)
    if ($SessionId) { $arguments += '--resume', $SessionId }
    $arguments += '--allow-all', '--no-ask-user', '--disable-builtin-mcps', '--secret-env-vars=COPILOT_GITHUB_TOKEN'
    $arguments += '--output-format', 'json', '--usage-output-file', $usageFile, '--log-dir', (Join-Path $Agent.Work 'copilot-logs'), '--no-auto-update'
    if ($Agent.Model) { $arguments += '--model', $Agent.Model }
    if ($Agent.MaxBudgetUsd -gt 0) { $arguments += '--max-ai-credits', "$([Math]::Max($CopilotMinCredits, [Math]::Ceiling($Agent.MaxBudgetUsd * $CopilotCreditsPerUsd)))" }
    $names = 'COPILOT_HOME', 'COPILOT_ALLOW_ALL', 'COPILOT_GITHUB_TOKEN'
    $saved = @{}
    foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
    try {
        # Copilot's own home keeps the user's MCP servers, skills, agents, instructions and memories out, and keeps the sessions for --resume.
        # COPILOT_ALLOW_ALL=true also trusts the working folder, for a resumed session too, so the fixture's skills and agents load.
        [Environment]::SetEnvironmentVariable('COPILOT_HOME', $Agent.CopilotHome)
        [Environment]::SetEnvironmentVariable('COPILOT_ALLOW_ALL', 'true')
        [Environment]::SetEnvironmentVariable('COPILOT_GITHUB_TOKEN', $(if ($Agent.Token) { $Agent.Token } else { $null }))
        $run = Invoke-AgentProcess $Agent $arguments
    }
    finally {
        foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
    }
    $lines = @((@($run.Output -split '\r?\n') + @($run.Errors -split '\r?\n')) | Where-Object { $_ })
    [IO.File]::WriteAllText((Join-Path $Agent.Work "copilot-$Index.jsonl"), (($lines -join "`n") + "`n"))
    $events = @($lines | Where-Object { $_ -like '{*' } | ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } | Where-Object { $_ })
    $result = @($events | Where-Object { $_.type -eq 'result' }) | Select-Object -Last 1
    $credits = $null
    try {
        $usage = Get-Content -Raw -LiteralPath $usageFile -ErrorAction Stop | ConvertFrom-Json
        if ($null -eq $usage.totalNanoAiu) { throw 'it has no totalNanoAiu' }
        $credits = [double]$usage.totalNanoAiu / 1e9
    }
    catch { Write-Warning "Copilot run ${Index}: no AI credits read from $usageFile ($($_.Exception.Message)), so its cost is unknown." }
    [pscustomobject]@{
        SessionId  = if ($result) { "$($result.sessionId)" } else { '' }
        Credits    = $credits
        Skills     = @($events | Where-Object { $_.type -eq 'assistant.message' } | ForEach-Object { $_.data.toolRequests } | Where-Object { $_.name -eq 'skill' } | ForEach-Object { "$($_.arguments.skill)" })
        McpServers = @($events | Where-Object { $_.type -eq 'session.mcp_servers_loaded' } | ForEach-Object { $_.data.servers })
        TimedOut   = $run.TimedOut
    }
}

function Invoke-Agent($Agent, [string]$Prompt, [string]$SessionId = '', [int]$Index) {
    $session = ''
    $run = $null
    $timedOut = $false
    if ($Agent.Tool -eq 'copilot') {
        $run = Invoke-CopilotCli $Agent $Prompt $SessionId $Index
        $timedOut = $run.TimedOut
        if (-not $timedOut) { $session = $run.SessionId }
        if ($null -eq $run.Credits) { $Agent.UnreadUsage.Add($Index) }
        elseif ($session) { $Agent.Credits[$session] = $run.Credits }
        else { $Agent.Credits["run-$Index"] = $run.Credits }
    }
    else {
        $out = Invoke-ClaudeCli $Agent $Prompt $SessionId $Index
        $timedOut = $out.TimedOut
        if ($out.Json -and -not $timedOut) {
            $session = "$($out.Json.session_id)"
            $Agent.CostUsd += [double]$out.Json.total_cost_usd
        }
    }
    $Agent.SessionId = $session
    $detail = if ($timedOut) { "stopped after $($Agent.TimeoutMinutes) minutes, the -TimeoutMinutes limit, with its child processes" } else { 'no session id in the output' }
    Check "$($Agent.Name) run $Index returned a session" ([bool]$session) "$detail; see claude-$Index.json (or copilot-$Index.jsonl) in $($Agent.Work)"
    if ($Agent.Tool -eq 'copilot') {
        if (-not $SessionId -and $Prompt -match '^/([\w-]+)') {
            $name = $Matches[1]
            Check "Copilot run $Index ran the project's /$name skill" ($run.Skills -contains $name) "skills: $($run.Skills -join ', ')"
        }
        $loaded = @($run.McpServers | Where-Object { $_.status -ne 'disabled' })
        Check "Copilot run $Index loaded no MCP server" ($loaded.Count -eq 0) "loaded: $(($loaded | ForEach-Object { "$($_.name)=$($_.status)" }) -join ', ')"
    }
}

function Write-AgentSummary($Agent) {
    if ($Agent.Tool -eq 'copilot') {
        $credits = 0.0
        foreach ($value in $Agent.Credits.Values) { $credits += [double]$value }
        $usd = [Math]::Round($credits / $CopilotCreditsPerUsd, 2)
        $read = [Math]::Round($credits, 2)
        $unread = $Agent.UnreadUsage -join ', '
        if ($Agent.UnreadUsage.Count -eq 0) { "Cost: $usd USD ($read AI credits)" }
        elseif ($credits -gt 0) { "Cost: at least $usd USD ($read AI credits; none read for Copilot run $unread)" }
        else { "Cost: unknown (no AI credits read for Copilot run $unread)" }
        "Fixture: $($Agent.App)"
        "Continue the session from $($Agent.App) with: `$env:COPILOT_HOME = '$($Agent.CopilotHome)'; copilot --resume $($Agent.SessionId)"
    }
    else {
        "Cost: $($Agent.CostUsd) USD"
        "Fixture: $($Agent.App)"
        "Continue the session from $($Agent.App) with: claude --resume $($Agent.SessionId)"
    }
}
