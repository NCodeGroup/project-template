# Shared helpers for the plan-and-execute workflow: read prompt templates, expand includes, fill inputs.
$script:TemplateDir = Join-Path $PSScriptRoot 'templates' | Resolve-Path | Select-Object -ExpandProperty Path

function Get-HybridTemplateDir { $script:TemplateDir }

# Splits a template file into its front-matter fields and body.
function Read-HybridTemplateFile([string]$Path) {
    $raw = [IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
    $meta = [ordered]@{}
    $body = $raw
    $front = ''
    if ($raw -match '(?s)^---\n(.*?)\n---\n(.*)$') {
        $front = $Matches[1]
        $body = $Matches[2]
        foreach ($line in $front -split "`n") {
            if ($line -match '^([A-Za-z-]+):\s*(.*)$') { $meta[$Matches[1]] = $Matches[2].Trim() }
        }
    }
    [pscustomobject]@{ Meta = $meta; Body = $body.Trim() + "`n"; FrontMatter = $front }
}

# Prompt templates are the .md files with a "role" field; excludes agents, the plan format, the example and the README. Targets lists the installer targets a template goes to: its "targets" field, or all three. Command is the name it installs as: its "command" field, or its file name.
function Get-HybridTemplateList {
    $list = @(Get-ChildItem (Get-HybridTemplateDir) -Filter '*.md' -File |
        Where-Object { $_.Name -notlike '*.agent.md' -and $_.Name -notlike '_*' -and $_.Name -notin 'README.md', 'PLAN.example.md' } |
        ForEach-Object {
            $t = Read-HybridTemplateFile $_.FullName
            if ($t.Meta.role) {
                $targets = if ($t.Meta.targets) { @($t.Meta.targets -split '\s*,\s*') } else { @('VSCode', 'Claude', 'CopilotCli') }
                $unknown = @($targets | Where-Object { $_ -notin 'VSCode', 'Claude', 'CopilotCli' })
                if ($unknown) { throw "Template '$($_.BaseName)' has unknown targets: $($unknown -join ', '). Use VSCode, Claude or CopilotCli." }
                [pscustomobject]@{
                    Name         = $_.BaseName
                    Command      = if ($t.Meta.command) { $t.Meta.command } else { $_.BaseName }
                    Role         = $t.Meta.role
                    Description  = $t.Meta.description
                    ArgumentHint = $t.Meta.'argument-hint'
                    AppendFormat = $t.Meta.'append-format' -eq 'true'
                    Worktree     = $t.Meta.worktree
                    Targets      = $targets
                    Body         = $t.Body
                }
            }
        } | Sort-Object Role, Name)
    foreach ($target in 'VSCode', 'Claude', 'CopilotCli') {
        $clash = @($list | Where-Object { $target -in $_.Targets } | Group-Object Command | Where-Object { $_.Count -gt 1 })
        foreach ($c in $clash) {
            throw "Templates $($c.Group.Name -join ' and ') both install as '$($c.Name)' for $target. Give one another command or other targets."
        }
    }
    $list
}

function Get-HybridTemplate([string]$Name) {
    $t = Get-HybridTemplateList | Where-Object Name -EQ $Name
    if (-not $t) { throw "Unknown template '$Name'. Run New-PlanPrompt.ps1 -List to see the templates." }
    $t
}

# Replaces {{PROMPT:name|input}} with that template's body (plus the plan format when it appends one), and {{BODY:name|input}} with its body alone. A fragment's own includes are expanded too.
function Expand-HybridInclude([string]$Text) {
    [regex]::Replace($Text, '\{\{(PROMPT|BODY):([A-Za-z0-9_-]+)(?:\|([^}]*))?\}\}', {
            param($m)
            $kind = $m.Groups[1].Value
            $name = $m.Groups[2].Value
            $inputText = $m.Groups[3].Value
            if ($name.StartsWith('_')) { return (Expand-HybridInclude (Read-HybridTemplateFile (Join-Path (Get-HybridTemplateDir) "$name.md")).Body).Trim() }
            if ($kind -eq 'BODY') { return (Expand-HybridInclude (Get-HybridTemplate $name).Body.Replace('{{INPUT}}', $inputText)).Trim() }
            (Get-HybridPromptText -Name $name -Placeholder $inputText).Trim()
        })
}

# Full prompt text for a template; {{INPUT}} becomes $Placeholder (literal task text, $ARGUMENTS, ${input:...}) and {{STATE_SCRIPT}} becomes the command that runs Get-PlanState.ps1.
function Get-HybridPromptText([string]$Name, [string]$Placeholder, [string]$StateScript = 'pwsh -NoProfile -File .template/Get-PlanState.ps1') {
    $t = Get-HybridTemplate $Name
    $text = $t.Body
    if ($t.AppendFormat) { $text = $text.TrimEnd() + "`n`n" + (Read-HybridTemplateFile (Join-Path (Get-HybridTemplateDir) '_plan-format.md')).Body }
    $text = $text.Replace('{{INPUT}}', $Placeholder)
    (Expand-HybridInclude $text).Replace('{{STATE_SCRIPT}}', $StateScript)
}

Export-ModuleMember -Function Get-HybridTemplateDir, Read-HybridTemplateFile, Get-HybridTemplateList, Get-HybridTemplate, Expand-HybridInclude, Get-HybridPromptText
