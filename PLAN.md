# Plan: Plan and execute in a Claude Code worktree

## Goal

In Claude Code, each plan gets its own git worktree. A planning command (`/plan-feature`, `/handoff-plan`, …) creates `.claude/worktrees/<name>/` with Claude Code's `EnterWorktree` tool before it researches, then writes and commits `PLAN.md` there. `/orchestrate-plan`, `/execute-step`, `/replan-step` and `/review-plan-diff` move the session into that same worktree before they start. Several Claude Code sessions can then plan and execute different plans on one machine at once without touching each other's files. Copilot (VS Code prompt files and agents, Copilot CLI skills and agents) is unchanged.

## Context for the executor

- Repository: `C:\Users\MarcinPolewski\GitHub\polewskm\project-template`, the Copier project template. Run every command from its root.
- Build: none.
- Test: `.\Test-Template.ps1`, `.\Test-Adoption.ps1` and `.\Test-CommitAttribution.ps1`. Each takes minutes; never run them in a step — the reviewer runs them.
- Conventions:
  - Every file is UTF-8 without BOM, with LF line endings. When writing a file from PowerShell, use `[IO.File]::WriteAllText($fullPath, $text, [Text.UTF8Encoding]::new($false))` with a full path from `(Resolve-Path <path>).Path`: .NET resolves a relative path against the process folder, not the PowerShell location.
  - Markdown: one line per paragraph, list item or table row, never hard-wrapped.
  - PowerShell: 4-space indent, and the style of the file being edited.
  - A "Replace … with …" instruction gives exact text in fenced blocks: find the old text exactly once in the file and replace it with the new text, character for character. If the old text is not in the file exactly once, escalate.
- Gotchas:
  - `Update-Template.ps1` generates every file under `template/.claude/commands`, `template/.claude/agents`, `template/.github/agents`, `template/.github/prompts`, `template/.github/skills` and the same five folders at the repository root. Never edit those by hand; only step 5 regenerates them.
  - The two `workflow/templates/_claude-worktree-*.md` sections end up in Claude Code command files. Claude Code replaces `$ARGUMENTS` and a `$` followed by a digit in them, and runs a shell command written as an exclamation mark followed by a backtick. Write the sections exactly as given: they contain no `$` and no such sequence.
  - `Get-HybridTemplateList` in `workflow/HybridWorkflow.psm1` skips files whose names start with `_`, so the new section files are never listed as prompt templates.
  - Commit nothing; the orchestrator commits each step.

## Decisions

- Claude Code only. The installer adds the worktree sections only to the Claude Code commands (`.claude/commands/`). VS Code prompt files and agents, Copilot CLI skills and agents, both `plan-executor` agents, `New-PlanPrompt.ps1` and `Invoke-PlanSteps.ps1` produce byte-identical output. Copilot has no `EnterWorktree` tool, and the request is for Claude.
- Use Claude Code's own worktrees, not scripted `git worktree add`. The `EnterWorktree` tool creates `.claude/worktrees/<name>/` on the branch `worktree-<name>` (`name`), or switches into an existing one under `.claude/worktrees/` (`path`). While a session is in a worktree, Claude Code blocks edits and commands in the main checkout, for its subagents too. `claude --worktree <name>` reopens an existing worktree at its tip.
- A new optional front-matter field, `worktree: create` or `worktree: join`, selects the section, which lives in `workflow/templates/_claude-worktree-<value>.md`. The templates stay the single source of truth, a new planning template opts in with one line, and an unknown value makes the installer throw.
- `create`: the eight `plan-*` templates and `handoff-plan`, which write a new `PLAN.md`. `join`: `orchestrate-plan`, `execute-step`, `replan-step` and `review-plan-diff`, which work on an existing one. No field: `analyze-architecture`, `analyze-decision` and `review-code`, which never touch `PLAN.md`.
- The installer puts the section before the command's body, followed by a `## Task` heading. The worktree must exist before research or edits begin, so the plan matches the code the executor changes.
- The planner commits `PLAN.md` in the worktree as `Plan: <title>`, the repository's existing convention for plan commits. The branch then carries its plan, `PLAN.md` stays out of the `Plan step 1` commit, and `review-plan-diff`'s default base (the first `Plan step` commit) is unchanged.
- The `plan-executor` subagent gets no section and no `isolation: worktree`. It inherits the orchestrator's worktree, and the orchestrator also passes it the worktree's path; `isolation: worktree` would give it a separate worktree, so plan and execution would no longer share one.
- A join command picks the worktree its arguments name, else the only plan worktree, else a `PLAN.md` in the current checkout, where it is. The last case keeps switching from Copilot to Claude Code working, since a Copilot plan has no worktree. With several plan worktrees and none named, it asks.
- `worktree.baseRef` stays unset, so new worktrees branch from the remote's default branch (Claude Code's default, `"fresh"`). A project that plans on top of unpushed work can set `"head"` in its `.claude/settings.json`.
- `.claude/settings.json` (the template's and this repository's) allows `EnterWorktree`, so creating or entering a worktree under `.claude/worktrees/` doesn't ask. Claude Code still asks before entering any path outside it.
- When a repository doesn't ignore `.claude/worktrees/` (a `-User` install into a repository not made from the template, such as NCode Identity), the create section adds it to `.git/info/exclude`, a local file that is never committed.
- `Test-Template.ps1` and `Test-Adoption.ps1` skip `.claude/worktrees` when they copy this repository into their snapshot; otherwise a run from the main checkout copies every open plan's checkout. This repository gets a root `.gitignore` with the template's Claude Code lines, because it uses its own generated commands.
- Commands never remove a worktree: it holds unpushed commits. The person removes it when Claude Code asks on exit, or with `git worktree remove`.

## Out of scope

- Any change to Copilot files, `New-PlanPrompt.ps1` or `Invoke-PlanSteps.ps1` behavior.
- A `.worktreeinclude` file or a `worktree.baseRef` setting in the template; the docs mention `.worktreeinclude`.
- personal-notes (`plan-and-execute.md`, `configurations.md`) and NCode Identity, which are other repositories.
- Tagging or pushing a template version, and updating projects.
- Hand-editing generated files, or running `Update-Template.ps1` outside step 5.

## Steps

### [x] 1. Write the Claude Code section that creates a plan's worktree
- Files: `workflow/templates/_claude-worktree-create.md` (new)
- Change: Create the file with exactly the content of this block (no front matter), ending with one newline:

  ```markdown
  ## Plan in a worktree of its own

  Each plan lives in its own git worktree, so several Claude Code sessions can plan and execute different plans on this machine at once. Executing, re-planning and reviewing this plan later happen in the same worktree. Set it up before you read any code, so your research matches the code the executor will change:

  1. Run `git rev-parse --show-toplevel`. If the path contains `/.claude/worktrees/`, this session is already in a worktree: use it, unless its `PLAN.md` has a step not yet marked `[x]`. In that case stop, because the worktree holds a plan in progress, and tell me to start the new plan from a new session in the main checkout.
  2. Otherwise, if `git check-ignore -q .claude/worktrees/` exits non-zero, append the line `.claude/worktrees/` to `info/exclude` in the folder that `git rev-parse --path-format=absolute --git-common-dir` prints, so the main checkout doesn't list worktrees as untracked files.
  3. Then name the worktree: two to four lowercase words from the request, joined by hyphens, such as `csv-export`, and not already a folder under `.claude/worktrees/`. Create the worktree and switch into it with the `EnterWorktree` tool and that `name`.
  4. A worktree is a fresh checkout, without ignored files such as installed dependencies. If the build or test command needs a setup step first, such as `npm ci`, run it in the worktree and list it under Context for the executor.

  From here on, the repository root is the worktree's root: read, write and run commands only there, never in the main checkout.

  After writing `PLAN.md`, commit it in the worktree: `git add PLAN.md`, then `git commit -m "Plan: <the plan's title>"`. End your reply with the worktree's name and branch, and how to continue: `/orchestrate-plan` in this session; from a new session, `/orchestrate-plan <name>`; or from a terminal, `claude --worktree <name>` and then `/orchestrate-plan`. If Claude Code asks on exit whether to keep the worktree, keep it.
  ```
- Pattern: `workflow/templates/_plan-format.md`, another section file without front matter.
- Done when: `$p = 'workflow\templates\_claude-worktree-create.md'; $t = if (Test-Path $p) { Get-Content -Raw $p } else { '' }; if ($t.StartsWith('## Plan in a worktree of its own') -and $t.Contains('EnterWorktree') -and $t.Contains('tool and that') -and $t.Contains('git commit -m "Plan: <the plan') -and -not $t.Contains('$')) { exit 0 } else { exit 1 }`

### [x] 2. Write the Claude Code section that moves a session into the plan's worktree
- Files: `workflow/templates/_claude-worktree-join.md` (new)
- Change: Create the file with exactly the content of this block (no front matter), ending with one newline:

  ```markdown
  ## Work in the plan's worktree

  Each plan lives in its own git worktree, so several Claude Code sessions can work on different plans on this machine at once. Before anything else, move this session to the plan:

  1. Run `git rev-parse --show-toplevel`. If the path contains `/.claude/worktrees/` and has a `PLAN.md`, this session is in the plan's worktree: go on with the task.
  2. Otherwise list the plan worktrees: run `git worktree list --porcelain`, keep each `worktree` path under `.claude/worktrees/` that has a `PLAN.md`, and read each plan's title from its first line.
  3. Choose the plan, in this order: the worktree whose folder name the command's arguments give; else the only plan worktree; else, when there is no plan worktree, the `PLAN.md` in the current checkout, worked on where it is — a plan written without a worktree, such as in Copilot. Switch into a chosen worktree with the `EnterWorktree` tool and its `path`. With several plan worktrees and none named, list them with their titles and stop to ask which one. With no plan anywhere, stop and say so.

  From here on, the plan's folder is the repository root: run every command there, Done-when commands included. In a worktree, never edit files or run git in the main checkout. When you delegate to a subagent, give it the folder's absolute path and tell it to work only there.
  ```
- Pattern: step 1's file.
- Done when: `$p = 'workflow\templates\_claude-worktree-join.md'; $t = if (Test-Path $p) { Get-Content -Raw $p } else { '' }; if ($t.StartsWith("## Work in the plan's worktree") -and $t.Contains('git worktree list --porcelain') -and $t.Contains('tool and its') -and -not $t.Contains('$')) { exit 0 } else { exit 1 }`

### [x] 3. Tag each prompt template with its worktree role
- Files: `workflow/HybridWorkflow.psm1` (edit); the 13 templates that the command below edits.
- Change:
  1. In `Get-HybridTemplateList`, in the `[pscustomobject]@{ … }` it builds, add `Worktree     = $t.Meta.worktree` on a new line directly after the `AppendFormat = …` line, aligned like the lines above it.
  2. Run exactly this from the repository root. It inserts `worktree: create` or `worktree: join` after each listed template's `append-format:` line:

  ```powershell
  $kinds = [ordered]@{
      create = 'plan-feature', 'plan-bugfix', 'plan-refactor', 'plan-tests', 'plan-migration', 'plan-performance', 'plan-security', 'plan-docs', 'handoff-plan'
      join   = 'orchestrate-plan', 'execute-step', 'replan-step', 'review-plan-diff'
  }
  foreach ($k in $kinds.Keys) {
      foreach ($n in $kinds[$k]) {
          $f = (Resolve-Path "workflow/templates/$n.md").Path
          $x = [IO.File]::ReadAllText($f)
          if ($x -notmatch '(?m)^append-format: \w+\n') { throw "No append-format line in $f" }
          [IO.File]::WriteAllText($f, ($x -replace '(?m)^(append-format: \w+)\n', ('$1' + "`nworktree: $k`n")), [Text.UTF8Encoding]::new($false))
      }
  }
  ```
- Pattern: the existing `AppendFormat` property in `Get-HybridTemplateList`.
- Done when: `Import-Module ./workflow/HybridWorkflow.psm1 -Force; $l = Get-HybridTemplateList; if (@($l | Where-Object Worktree -EQ 'create').Count -eq 9 -and @($l | Where-Object Worktree -EQ 'join').Count -eq 4 -and (@($l | Where-Object { -not $_.Worktree }).Name -join ',') -eq 'analyze-architecture,analyze-decision,review-code') { exit 0 } else { exit 1 }`

### [x] 4. Put the worktree section into the Claude Code commands
- Files: `workflow/Install-HybridWorkflow.ps1` (edit)
- Change:
  1. Directly before the line that starts `$vscodeModel = @{`, add:

     ```powershell
     # Claude Code only: the section that puts a plan in a worktree of its own (create) or moves the session to it (join).
     function Get-ClaudeWorktreeSection([string]$Kind) {
         $path = Join-Path $templateDir "_claude-worktree-$Kind.md"
         if (-not (Test-Path -LiteralPath $path)) { throw "Unknown worktree value '$Kind'; use create or join." }
         (Read-HybridTemplateFile $path).Body.TrimEnd()
     }
     ```
  2. In the `if ('Claude' -in $Target)` block, directly after the line `$body = Get-HybridPromptText -Name $t.Name -Placeholder '$ARGUMENTS'`, add these three lines at the same indent:

     ```powershell
     $hint = $t.ArgumentHint
     if ($t.Worktree) { $body = (Get-ClaudeWorktreeSection $t.Worktree) + "`n`n## Task`n`n" + $body }
     if ($t.Worktree -eq 'join') { $hint += "; the plan's worktree name when several are open" }
     ```
     In the `$fm = …` line right after them, replace `$(Q "[$($t.ArgumentHint)]")` with `$(Q "[$hint]")`.
  3. In the comment-based help, after the line `                  -User: ~\.copilot\skills, ~\.copilot\agents`, add an empty line and then this line:

     ```text
         Claude Code commands of templates with a "worktree" field start with a section that puts the plan in a git worktree of its own (create) or moves the session into it (join): templates\_claude-worktree-*.md.
     ```
- Pattern: the VS Code prompt loop in the same file, which also builds `$body` and `$fm` per template.
- Done when: `$d = Join-Path $env:TEMP 'wt-install-check'; Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue; $null = & .\workflow\Install-HybridWorkflow.ps1 -Repo (New-Item -ItemType Directory -Force $d).FullName; $c = Get-Content -Raw "$d\.claude\commands\plan-feature.md"; $o = Get-Content -Raw "$d\.claude\commands\orchestrate-plan.md"; $r = Get-Content -Raw "$d\.claude\commands\review-code.md"; $s = Get-Content -Raw "$d\.github\skills\plan-feature\SKILL.md"; $e = Get-Content -Raw "$d\.claude\agents\plan-executor.md"; $ok = $c.Contains('## Plan in a worktree of its own') -and $c -match '(?m)^## Task$' -and $o.Contains("## Work in the plan's worktree") -and $o.Contains("the plan's worktree name when several are open") -and -not $r.Contains('EnterWorktree') -and -not $s.Contains('EnterWorktree') -and -not $e.Contains('EnterWorktree'); Remove-Item $d -Recurse -Force; if ($ok) { exit 0 } else { exit 1 }`

### [x] 5. Regenerate the workflow files
- Files: the generated files under `template/.claude/commands` and `.claude/commands` (regenerated, not hand-edited)
- Change: Run `.\Update-Template.ps1`. Exactly the 13 Claude Code commands that have a `worktree` field change, in both places; every Copilot file and both `plan-executor` agents stay identical. If anything else changes, revert it and escalate.
- Pattern: none.
- Done when: `$gen = @(git status --porcelain -- template/.claude/commands .claude/commands); $other = @(git status --porcelain -- template/.github .github template/.claude/agents .claude/agents); $hits = @(Select-String -LiteralPath template\.claude\commands\plan-feature.md, .claude\commands\orchestrate-plan.md -SimpleMatch 'EnterWorktree' -List); if ($gen.Count -eq 26 -and $other.Count -eq 0 -and $hits.Count -eq 2) { exit 0 } else { exit 1 }`

### [x] 6. Check the worktree sections in Test-Template.ps1
- Files: `Test-Template.ps1` (edit)
- Change:
  1. Directly after the line that starts `Check 'workflow: every executor runs on Claude Sonnet 5.5'`, and before `$both = Join-Path $Work 'installed-both'`, add:

     ```powershell
     $worktreeKinds = [ordered]@{
         create = 'plan-feature', 'plan-bugfix', 'plan-refactor', 'plan-tests', 'plan-migration', 'plan-performance', 'plan-security', 'plan-docs', 'handoff-plan'
         join   = 'orchestrate-plan', 'execute-step', 'replan-step', 'review-plan-diff'
     }
     $worktreeMissing = @(
         foreach ($kind in $worktreeKinds.Keys) {
             $section = [IO.File]::ReadAllText((Join-Path $workflow "templates\_claude-worktree-$kind.md")).Replace("`r`n", "`n").Trim()
             $worktreeKinds[$kind] | Where-Object { -not [IO.File]::ReadAllText((Join-Path $PSScriptRoot "template\.claude\commands\$_.md")).Contains($section) }
         }
     )
     $worktreeLeaked = @(
         Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'template\.github'), (Join-Path $PSScriptRoot 'template\.claude\agents') -Recurse -File |
             Where-Object { $text = [IO.File]::ReadAllText($_.FullName); $text.Contains('EnterWorktree') -or $text -match '(?m)^isolation:' } | ForEach-Object Name
         'analyze-architecture', 'analyze-decision', 'review-code' | Where-Object { [IO.File]::ReadAllText((Join-Path $PSScriptRoot "template\.claude\commands\$_.md")).Contains('EnterWorktree') }
     )
     Check 'workflow: Claude Code planning commands create the plan''s worktree, and the commands that work on a plan move into it' (-not $worktreeMissing) ($worktreeMissing -join ', ')
     Check 'workflow: no Copilot file, plan-executor subagent or analysis command enters a worktree' (-not $worktreeLeaked) ($worktreeLeaked -join ', ')
     ```
  2. In the help's `.DESCRIPTION` paragraph, replace `and that the workflow scripts run.` with `that the Claude Code commands, and no Copilot file, carry the plan-worktree sections, and that the workflow scripts run.`

  Every existing line other than the `.DESCRIPTION` line stays byte-identical; in particular, the line `$both = Join-Path $Work 'installed-both'` keeps its spaces. `git diff --numstat -- Test-Template.ps1` shows `18	1`: 17 inserted lines plus the changed `.DESCRIPTION` line.
- Pattern: the `$executorChecks` check just above the insertion point.
- Done when: `$e = $null; $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Test-Template.ps1).Path, [ref]$null, [ref]$e); $t = Get-Content -Raw .\Test-Template.ps1; if (-not $e -and (git diff --numstat -- Test-Template.ps1) -match '^18\s+1\s' -and $t.Contains('$both = Join-Path $Work ''installed-both''') -and $t.Contains("Check 'workflow: Claude Code planning commands create the plan''s worktree, and the commands that work on a plan move into it'") -and $t.Contains("Check 'workflow: no Copilot file, plan-executor subagent or analysis command enters a worktree'") -and $t.Contains('carry the plan-worktree sections')) { exit 0 } else { exit 1 }`

### [x] 7. Keep plan worktrees out of the test snapshots
- Files: `Test-Template.ps1` (edit), `Test-Adoption.ps1` (edit)
- Change: In each file, replace this line (in `Test-Adoption.ps1` it is indented by 4 spaces inside `if (-not $UnitOnly) {`; keep that indent on every new line):

  ```powershell
  Get-ChildItem -LiteralPath $PSScriptRoot -Force | Where-Object Name -NE '.git' | Copy-Item -Destination $tpl -Recurse -Force
  ```
  with these four lines:

  ```powershell
  Get-ChildItem -LiteralPath $PSScriptRoot -Force | Where-Object Name -NotIn '.git', '.claude' | Copy-Item -Destination $tpl -Recurse -Force
  # Claude Code's plan worktrees are other checkouts, not part of the snapshot.
  $claudeCopy = New-Item -ItemType Directory -Force (Join-Path $tpl '.claude')
  Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '.claude') -Force | Where-Object Name -NE 'worktrees' | Copy-Item -Destination $claudeCopy.FullName -Recurse -Force
  ```
- Pattern: the replaced line.
- Done when: `$ok = $true; foreach ($f in '.\Test-Template.ps1', '.\Test-Adoption.ps1') { $e = $null; $null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f).Path, [ref]$null, [ref]$e); $t = Get-Content -Raw $f; if ($e -or -not $t.Contains("Where-Object Name -NE 'worktrees'") -or $t.Contains("Where-Object Name -NE '.git' | Copy-Item")) { $ok = $false } }; if ($ok) { exit 0 } else { exit 1 }`

### [x] 8. Allow entering a worktree, and ignore worktrees in this repository
- Files: `template/.claude/settings.json` (edit), `.claude/settings.json` (edit), `.gitignore` (new)
- Change:
  1. `template/.claude/settings.json`: in `permissions`, add an `allow` list holding `"EnterWorktree"` as the first key, before `"ask"`, formatted like the `ask` list: `"allow": [`, then `"EnterWorktree"` on its own line, then `],`.
  2. `.claude/settings.json` (this repository's own): add a comma after the closing `}` of `attribution`, then a `permissions` object holding only that same `allow` list, in the same formatting.
  3. Create `.gitignore` at the repository root with exactly these four lines:

     ```gitignore
     # Claude Code: personal settings and worktrees
     .claude/settings.local.json
     .claude/worktrees/
     CLAUDE.local.md
     ```
- Pattern: the `# Claude Code` section of `template/.gitignore.jinja`; the `ask` list in `template/.claude/settings.json`.
- Done when: `$a = Get-Content -Raw template\.claude\settings.json | ConvertFrom-Json; $b = Get-Content -Raw .claude\settings.json | ConvertFrom-Json; git check-ignore -q .claude/worktrees/x; if ($LASTEXITCODE -eq 0 -and $a.permissions.allow -contains 'EnterWorktree' -and @($a.permissions.ask).Count -eq 4 -and @($a.permissions.deny).Count -eq 3 -and $b.permissions.allow -contains 'EnterWorktree' -and $b.attribution.sessionUrl -eq $false) { exit 0 } else { exit 1 }`

### [x] 9. Describe plan worktrees in a project's CLAUDE.md and README
- Files: `template/CLAUDE.md` (edit), `template/README.md.jinja` (edit)
- Change:
  1. In `template/CLAUDE.md`, replace:

     ```markdown
     - Run Done-when commands and other `PLAN.md` commands with the PowerShell tool, from the repository root.
     ```
     with:

     ```markdown
     - Each plan lives in its own git worktree, so several sessions can work on different plans at once. A planning command (`/plan-feature`, `/handoff-plan`, …) creates `.claude/worktrees/<name>/` on the branch `worktree-<name>` and commits `PLAN.md` there; `/orchestrate-plan`, `/execute-step`, `/replan-step` and `/review-plan-diff` move the session into that worktree first. With several plans open, name the one you mean: `/orchestrate-plan <name>`.
     - Run Done-when commands and other `PLAN.md` commands with the PowerShell tool, from the root of the plan's worktree.
     ```
  2. In `template/README.md.jinja`, replace `In Claude Code, plan in Accept edits mode and execute in Auto.` with:

     ```markdown
     In Claude Code, plan in Accept edits mode and execute in Auto. Each plan gets its own git worktree under `.claude/worktrees/`, so several sessions can work on different plans at once.
     ```
- Pattern: the neighboring bullets and sentences.
- Done when: `$c = Get-Content -Raw template\CLAUDE.md; $m = Get-Content -Raw template\README.md.jinja; if ($c.Contains('.claude/worktrees/<name>/') -and $c.Contains("from the root of the plan's worktree") -and -not $c.Contains('PowerShell tool, from the repository root') -and $m.Contains('Each plan gets its own git worktree under')) { exit 0 } else { exit 1 }`

### [x] 10. Describe plan worktrees in the template's rules
- Files: `template/.github/instructions/project-template.instructions.md.jinja` (edit)
- Change: Directly after the line that starts ``- `PLAN.md` at the repository root is the handoff between them.``, insert these three lines:

  ```jinja
  {%- if 'claude' in workflow_tools %}
  - In Claude Code, each plan lives in its own git worktree, so several sessions can work on different plans at once: the planning command creates `.claude/worktrees/<name>/` on the branch `worktree-<name>` and commits `PLAN.md` there, and the commands that execute, re-plan or review the plan work in that worktree. Its root is the plan's repository root. To continue the plan in another tool, open that folder.
  {%- endif %}
  ```
- Pattern: the `{%- if git_host == 'github' %}` … `{%- endif %}` bullet further down the same section.
- Done when: `$r = Get-Content -Raw template\.github\instructions\project-template.instructions.md.jinja; if ($r -match '(?m)^\{%- if ''claude'' in workflow_tools %\}\n- In Claude Code, each plan lives in its own git worktree[^\n]*\n\{%- endif %\}$') { exit 0 } else { exit 1 }`

### [x] 11. Document the worktree field in the templates README
- Files: `workflow/templates/README.md` (edit)
- Change:
  1. Replace ``(`description`, `argument-hint`, `role`, `append-format`)`` with ``(`description`, `argument-hint`, `role`, `append-format`, and optionally `worktree`)``.
  2. Directly before the line `## Agent Templates`, insert these lines, followed by one empty line:

     ```markdown
     ### Claude Code Plan Worktrees

     In Claude Code only, each plan lives in its own git worktree, so several sessions can work on different plans on one machine at once. A template's `worktree` field says what its Claude Code command does with the plan's worktree. The installer puts the matching section before the command's body, followed by a `## Task` heading:

     | `worktree` | Section | Templates | The command |
     |---|---|---|---|
     | `create` | [_claude-worktree-create.md](_claude-worktree-create.md) | The `plan-*` templates and `handoff-plan` | Creates `.claude/worktrees/<name>/` with the `EnterWorktree` tool before it researches, plans there, and commits `PLAN.md` as `Plan: <title>` |
     | `join` | [_claude-worktree-join.md](_claude-worktree-join.md) | `orchestrate-plan`, `execute-step`, `replan-step`, `review-plan-diff` | Moves the session into the plan's worktree — the one its arguments name, or the only one — before it starts; with no plan worktree, works on a `PLAN.md` in the current checkout |

     A command without the field works where the session is. VS Code prompt files, Copilot CLI skills, the agents and `New-PlanPrompt.ps1` never get a section. The `plan-executor` subagent inherits the orchestrator's worktree; `isolation: worktree` would give it a worktree of its own instead.
     ```
- Pattern: the existing tables in the same file.
- Done when: `$t = Get-Content -Raw workflow\templates\README.md; if ($t.Contains('and optionally') -and $t -match '(?s)### Claude Code Plan Worktrees.*\[_claude-worktree-join\.md\]\(_claude-worktree-join\.md\).*## Agent Templates') { exit 0 } else { exit 1 }`

### [x] 12. List the worktree sections in the workflow READMEs
- Files: `workflow/templates/README.md` (edit), `workflow/README.md` (edit)
- Change:
  1. In `workflow/templates/README.md`, in the `## Other Files` table, directly after the row that starts `| [PLAN.example.md](PLAN.example.md) |`, insert this row:

     ```markdown
     | [_claude-worktree-create.md](_claude-worktree-create.md), [_claude-worktree-join.md](_claude-worktree-join.md) | The Claude Code plan-worktree sections ([Claude Code Plan Worktrees](#claude-code-plan-worktrees)) |
     ```
  2. In `workflow/templates/README.md`, replace ``with the same four header fields;`` with ``with the same four header fields, plus `worktree: create` when its Claude Code command writes a new `PLAN.md` or `worktree: join` when it works on one;``.
  3. In `workflow/README.md`, replace ``the `plan-executor` subagent templates, the `PLAN.md` format`` with ``the `plan-executor` subagent templates, the Claude Code plan-worktree sections, the `PLAN.md` format``.
- Pattern: the neighboring rows.
- Done when: `$t = Get-Content -Raw workflow\templates\README.md; $w = Get-Content -Raw workflow\README.md; if ($t.Contains('The Claude Code plan-worktree sections ([Claude Code Plan Worktrees](#claude-code-plan-worktrees))') -and $t.Contains('when it works on one;') -and $w.Contains('the Claude Code plan-worktree sections, the')) { exit 0 } else { exit 1 }`

### [x] 13. Document plan worktrees in USAGE.md: the tools and daily work
- Files: `USAGE.md` (edit)
- Change:
  1. In the `## How the Two Tools Fit` table, directly after the row that starts `| Executes plan steps on |`, insert:

     ```markdown
     | Where a plan lives | Its own git worktree, `.claude/worktrees/<name>/`, so several sessions can work on different plans at once | The folder that's open, usually the main checkout |
     ```
  2. Replace ``whichever one started the plan.`` with ``whichever one started the plan. To continue a Claude Code plan in Copilot, open its worktree's folder.``
  3. Replace ``checks it, and re-plans what comes back.`` with:

     ```markdown
     checks it, and re-plans what comes back. Each planning command creates a worktree for its plan, commits `PLAN.md` there and names it in its reply; `/orchestrate-plan`, `/execute-step`, `/replan-step` and `/review-plan-diff` move into it, so run one session per plan. With several plans open, name the one you mean, `/orchestrate-plan <name>`, or start a terminal session in it with `claude --worktree <name>`. A worktree is a fresh checkout: to copy gitignored files such as `.env` into each new one, list them in a `.worktreeinclude` file at the repository root.
     ```
  4. Replace ``keep it as the record of the change.`` with:

     ```markdown
     keep it as the record of the change. In Claude Code the commits are on the worktree's branch, `worktree-<name>`: push it and open a pull request, or merge it into your branch, then remove the worktree — choose remove when Claude Code asks on exit, or run `git worktree remove .claude/worktrees/<name>` and `git branch -d worktree-<name>`.
     ```
- Pattern: the neighboring rows and sentences.
- Done when: `$t = Get-Content -Raw USAGE.md; if ($t.Contains('| Where a plan lives |') -and $t.Contains("open its worktree's folder.") -and $t.Contains('so run one session per plan') -and $t.Contains('git worktree remove .claude/worktrees/<name>')) { exit 0 } else { exit 1 }`

### [x] 14. Document plan worktrees in USAGE.md: switching and troubleshooting
- Files: `USAGE.md` (edit)
- Change:
  1. Replace ``the commits carry the work across; chat history doesn't.`` with:

     ```markdown
     the commits carry the work across; chat history doesn't. A Claude Code plan is in its worktree: to continue it in Copilot, open `.claude/worktrees/<name>` in VS Code, or `cd` there for Copilot CLI.
     ```
  2. Replace ``| A plan written in Claude Code | Copilot Chat:`` with ``| A plan written in Claude Code | Open its worktree's folder, `.claude/worktrees/<name>`. Copilot Chat:``
  3. Replace ``or `/execute-step` for one step |`` with ``or `/execute-step` for one step; with no plan worktree open, they work on `PLAN.md` where it is |``
  4. Directly after the row that starts `| Claude Code stops with a limit message |`, insert:

     ```markdown
     | `/orchestrate-plan` lists plans and asks which one | Several plan worktrees are open | Name the plan's worktree: `/orchestrate-plan <name>`; `git worktree list` shows them |
     ```
  5. Replace ``so switch whenever you like by using the other panel or command.`` with ``so switch whenever you like by using the other panel or command. In Claude Code each plan has its own git worktree, so several sessions work on different plans at once.``
- Pattern: the neighboring rows and sentences.
- Done when: `$t = Get-Content -Raw USAGE.md; if ($t.Contains('A Claude Code plan is in its worktree') -and $t.Contains("| A plan written in Claude Code | Open its worktree's folder") -and $t.Contains('with no plan worktree open, they work on') -and $t.Contains('lists plans and asks which one') -and $t.Contains('In Claude Code each plan has its own git worktree')) { exit 0 } else { exit 1 }`

### [x] 15. Document plan worktrees in README.md
- Files: `README.md` (edit)
- Change:
  1. Replace ``and the Sonnet subagent that executes steps — generated |`` with ``and the Sonnet subagent that executes steps; each plan runs in its own git worktree, so several sessions work at once — generated |``
  2. Replace ``and `secrets/` can't be read |`` with ``and `secrets/` can't be read; entering a plan's worktree doesn't ask |``
  3. Replace ``so one can plan and another execute, re-plan or review.`` with ``so one can plan and another execute, re-plan or review. In Claude Code each plan lives in its own git worktree, so several sessions can work on different plans at once; open that folder to continue the plan in Copilot.``
  4. Directly after the row that starts `| Every executor —`, insert:

     ```markdown
     | Claude Code's planning commands create the plan's worktree, and the commands that execute, re-plan or review a plan move into it; no Copilot file, `plan-executor` subagent or analysis command enters a worktree | Always |
     ```
  5. Replace ``works on a tagged snapshot of the working tree in `%TEMP%`.`` with ``works on a tagged snapshot of the working tree, without Claude Code's worktrees, in `%TEMP%`.``
  6. Replace ``| `AGENTS.md`, `.claude/settings.json`, `.vscode/settings.json` | This repository's own agent instructions and settings: no AI attribution in commits ([Commit Attribution](#commit-attribution)) |`` with ``| `AGENTS.md`, `.claude/settings.json`, `.vscode/settings.json`, `.gitignore` | This repository's own agent instructions and settings: no AI attribution in commits ([Commit Attribution](#commit-attribution)), and Claude Code's worktrees ignored |``
- Pattern: the neighboring rows and sentences.
- Done when: `$t = Get-Content -Raw README.md; if ($t.Contains('each plan runs in its own git worktree, so several sessions work at once') -and $t.Contains("entering a plan's worktree doesn't ask") -and $t.Contains('open that folder to continue the plan in Copilot') -and $t.Contains("Claude Code's planning commands create the plan's worktree") -and $t.Contains("without Claude Code's worktrees") -and $t.Contains("and Claude Code's worktrees ignored |")) { exit 0 } else { exit 1 }`

## Review checklist

- `.\Test-Template.ps1` with no switches, `.\Test-Adoption.ps1` and `.\Test-CommitAttribution.ps1` pass: their last lines read `Template tests: PASSED`, `Adoption tests: PASSED` and `Commit attribution tests: PASSED`. Test-Template took 2 min 14 s even with `-SkipDotnetBuild -SkipUpdate` before this change, so give it a long timeout. Its two new `workflow:` checks print PASS.
- Copilot is untouched: the diff against the plan's base changes no file under `template/.github/agents`, `template/.github/prompts`, `template/.github/skills`, the same folders at the root, or either `plan-executor` agent.
- Read `template/.claude/commands/plan-feature.md`, `orchestrate-plan.md` and `execute-step.md` end to end. The section, the `## Task` heading and the body read as one coherent prompt; the join commands' `argument-hint` ends with `; the plan's worktree name when several are open`; neither section contains a `$`.
- Render a project with `workflow_tools = 'copilot'` and one with `'claude', 'copilot'`. The worktree bullet in `.github/instructions/project-template.instructions.md` is absent from the first and appears once, as its own bullet, in the second; the worktree sentence in `README.md` likewise.
- Running `.\Update-Template.ps1` again leaves `git status` clean, so the generated files are current.
- Smoke test in Claude Code, in a scratch project made with `.\New-Project.ps1 -Template . -Path <scratch> -Defaults -Data @{ project_name = 'Worktree Smoke' }` after committing the change: two sessions run `/plan-feature` at once and get two worktrees, each with a `Plan: …` commit; a third session's `/orchestrate-plan <name>` enters the right one; the `plan-executor` subagent's edits land in that worktree; `git status` in the main checkout stays clean. If the reviewer can't run Claude Code, record this as remaining work instead of passing it.
