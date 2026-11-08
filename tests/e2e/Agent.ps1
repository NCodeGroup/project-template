<#
.SYNOPSIS
    The headless runner the end-to-end tests share: Claude Code (claude -p) or the Copilot CLI (copilot -p) behind one interface, and the facts that differ by tool.

.DESCRIPTION
    Fixture.ps1 dot-sources it. Everything that differs between the two tools lives here, so a scenario is written once and runs under both.
    New-Agent makes the runner for one tool: its CLI, model, budget, fixture project and work folder, and, for Copilot, its own home folder and the token it runs with; it also writes tool.txt in the work folder.
    Get-RunTool gives the tool a run used, from tool.txt, for -CheckOnly without -Tool.
    Get-RunCheckout gives the folder and branch a run works in: a Claude Code worktree, or a branch in the main checkout for Copilot.
    Get-CommandFile gives the path of a command's installed copy in the fixture: a .claude command, or a .github skill.
    Invoke-ClaudeCli and Invoke-CopilotCli run one headless prompt in the tool and return what it printed, parsed.
    Invoke-Agent runs one prompt in either tool and checks the run returned a session; for Copilot it also checks the project's skill ran and no MCP server loaded.
    Write-AgentSummary prints the cost and how to continue the session by hand.
#>

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
    $copilotHome = ''
    if ($Tool -eq 'copilot') {
        # Read before Use-FixtureEnvironment: it puts the gh stand-in first on PATH and clears the token variables,
        # and Copilot has no other way to find the user's login, so this runner hands it the token for the call only.
        foreach ($n in 'COPILOT_GITHUB_TOKEN', 'GH_TOKEN', 'GITHUB_TOKEN') {
            $value = [Environment]::GetEnvironmentVariable($n)
            if ($value) { $token = $value; break }
        }
        if (-not $token -and (Get-Command gh -ErrorAction SilentlyContinue)) {
            $printed = "$(gh auth token 2>$null)".Trim()
            if ($LASTEXITCODE -eq 0) { $token = $printed }
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
