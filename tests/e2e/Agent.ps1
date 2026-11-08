<#
.SYNOPSIS
    The headless runner the end-to-end tests share: Claude Code (claude -p) or the Copilot CLI (copilot -p) behind one interface, and the facts that differ by tool.

.DESCRIPTION
    Fixture.ps1 dot-sources it. Everything that differs between the two tools lives here, so a scenario is written once and runs under both.
    New-Agent makes the runner for one tool: its CLI, model, budget, fixture project and work folder, and, for Copilot, its own home folder and the token it runs with, with a warning when that is a general GitHub token rather than COPILOT_GITHUB_TOKEN; it also writes tool.txt in the work folder.
    Get-RunTool gives the tool a run used, from tool.txt, for -CheckOnly without -Tool.
    Get-RunCheckout gives the folder and branch a run works in: a Claude Code worktree, or a branch in the main checkout for Copilot.
    Get-CommandFile gives the path of a command's installed copy in the fixture: a .claude command, or a .github skill.
    Invoke-ClaudeCli and Invoke-CopilotCli run one headless prompt in the tool and return what it printed, parsed.
    Invoke-Agent runs one prompt in either tool and checks the run returned a session; for Copilot it also checks the project's skill ran and no MCP server loaded.
    Write-AgentSummary prints the cost and how to continue the session by hand.
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
    [string]$App,
    [string]$Work
) {
    $cli = if ($Tool -eq 'copilot') { $Copilot } else { $Claude }
    if (-not (Get-Command $cli -ErrorAction SilentlyContinue)) {
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
        App          = $App
        Work         = $Work
        CopilotHome  = $copilotHome
        Token        = $token
        CostUsd      = 0.0
        Credits      = @{}
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
    if ($Tool -eq 'copilot') { return [pscustomobject]@{ Folder = $App; Branch = $Name } }
    [pscustomobject]@{ Folder = Join-Path $App ".claude/worktrees/$Name"; Branch = "worktree-$Name" }
}

function Get-CommandFile([string]$App, [string]$Tool, [string]$Name) {
    if ($Tool -eq 'copilot') { return Join-Path $App ".github/skills/$Name/SKILL.md" }
    Join-Path $App ".claude/commands/$Name.md"
}

function Invoke-ClaudeCli($Agent, [string]$Prompt, [string]$SessionId, [int]$Index) {
    $arguments = @('-p', $Prompt)
    if ($SessionId) { $arguments += '--resume', $SessionId }
    # --strict-mcp-config with no --mcp-config gives the session none of the user's MCP servers: it posts only through the gh stand-in.
    $arguments += '--output-format', 'json', '--permission-mode', 'bypassPermissions', '--strict-mcp-config'
    if ($Agent.Model) { $arguments += '--model', $Agent.Model }
    if ($Agent.MaxBudgetUsd -gt 0) { $arguments += '--max-budget-usd', "$($Agent.MaxBudgetUsd)" }
    Push-Location $Agent.App
    try { $output = & $Agent.Cli @arguments | Out-String }
    finally { Pop-Location }
    [IO.File]::WriteAllText((Join-Path $Agent.Work "claude-$Index.json"), $output)
    try { $output | ConvertFrom-Json } catch { $null }
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
    Push-Location $Agent.App
    try {
        # Copilot's own home keeps the user's MCP servers, skills, agents, instructions and memories out, and keeps the sessions for --resume.
        # COPILOT_ALLOW_ALL=true also trusts the working folder, for a resumed session too, so the fixture's skills and agents load.
        [Environment]::SetEnvironmentVariable('COPILOT_HOME', $Agent.CopilotHome)
        [Environment]::SetEnvironmentVariable('COPILOT_ALLOW_ALL', 'true')
        [Environment]::SetEnvironmentVariable('COPILOT_GITHUB_TOKEN', $(if ($Agent.Token) { $Agent.Token } else { $null }))
        $lines = @(& $Agent.Cli @arguments 2>&1 | ForEach-Object { "$_" })
    }
    finally {
        Pop-Location
        foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
    }
    [IO.File]::WriteAllText((Join-Path $Agent.Work "copilot-$Index.jsonl"), (($lines -join "`n") + "`n"))
    $events = @($lines | Where-Object { $_ -like '{*' } | ForEach-Object { try { $_ | ConvertFrom-Json } catch { $null } } | Where-Object { $_ })
    $result = @($events | Where-Object { $_.type -eq 'result' }) | Select-Object -Last 1
    $credits = 0.0
    try { $credits = [double](Get-Content -Raw -LiteralPath $usageFile -ErrorAction Stop | ConvertFrom-Json).totalNanoAiu / 1e9 } catch { $credits = 0.0 }
    [pscustomobject]@{
        SessionId  = if ($result) { "$($result.sessionId)" } else { '' }
        Credits    = $credits
        Skills     = @($events | Where-Object { $_.type -eq 'assistant.message' } | ForEach-Object { $_.data.toolRequests } | Where-Object { $_.name -eq 'skill' } | ForEach-Object { "$($_.arguments.skill)" })
        McpServers = @($events | Where-Object { $_.type -eq 'session.mcp_servers_loaded' } | ForEach-Object { $_.data.servers })
    }
}

function Invoke-Agent($Agent, [string]$Prompt, [string]$SessionId = '', [int]$Index) {
    $session = ''
    $run = $null
    if ($Agent.Tool -eq 'copilot') {
        $run = Invoke-CopilotCli $Agent $Prompt $SessionId $Index
        $session = $run.SessionId
        if ($session) { $Agent.Credits[$session] = $run.Credits }
    }
    else {
        $out = Invoke-ClaudeCli $Agent $Prompt $SessionId $Index
        if ($out) {
            $session = "$($out.session_id)"
            $Agent.CostUsd += [double]$out.total_cost_usd
        }
    }
    $Agent.SessionId = $session
    Check "$($Agent.Name) run $Index returned a session" ([bool]$session) "no session id in the output; see claude-$Index.json (or copilot-$Index.jsonl) in $($Agent.Work)"
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
        "Cost: $([Math]::Round($credits / $CopilotCreditsPerUsd, 2)) USD ($([Math]::Round($credits, 2)) AI credits)"
        "Fixture: $($Agent.App)"
        "Continue the session from $($Agent.App) with: `$env:COPILOT_HOME = '$($Agent.CopilotHome)'; copilot --resume $($Agent.SessionId)"
    }
    else {
        "Cost: $($Agent.CostUsd) USD"
        "Fixture: $($Agent.App)"
        "Continue the session from $($Agent.App) with: claude --resume $($Agent.SessionId)"
    }
}
