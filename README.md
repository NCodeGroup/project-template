# Project Template

Private [Copier](https://copier.readthedocs.io/) template for new repositories set up for plan-then-execute AI coding: Claude Opus plans each change into `PLAN.md`, a cheaper model executes it one verified step at a time, and any step that needs a decision goes back to Opus. Every project works with Claude Code and with GitHub Copilot, and you can switch between them at any time ([Claude Code or GitHub Copilot](#claude-code-or-github-copilot)). The base works for any language; a .NET layer adds shared build settings and C# conventions. Projects live on GitHub by default, or on GitLab. Every project made from it can pull later template improvements with `Update-Project.ps1`.

**Related:** [Configuration G](https://github.com/polewskm/personal-notes/blob/main/ham-radio/shack/shack-pc/local-ai/configuration-g.md) — the accounts, the shack PC, the VS Code tunnel and the daily loop this template is built for. [Plan-and-execute](https://github.com/polewskm/personal-notes/blob/main/ham-radio/shack/shack-pc/local-ai/plan-and-execute.md) — how the workflow works and how to choose between its variants. This repository is the single source of truth for the workflow's templates and scripts ([workflow/](workflow/)); personal-notes and every project consume them. [USAGE.md](USAGE.md) — setting up a PC for Claude Code and GitHub Copilot, and using and switching between them.

## Table of Contents

- [What a Project Gets](#what-a-project-gets)
- [Claude Code or GitHub Copilot](#claude-code-or-github-copilot)
- [Extend or Override the Template](#extend-or-override-the-template)
- [Questions](#questions)
- [Create a Project](#create-a-project)
- [Adopt an Existing Repository](#adopt-an-existing-repository)
  - [Legacy Adapters](#legacy-adapters)
- [Update a Project](#update-a-project)
- [Commit Attribution](#commit-attribution)
- [Stay Current](#stay-current)
- [Change the Template](#change-the-template)
- [Publish the Template](#publish-the-template)
- [Repository Layout](#repository-layout)

## What a Project Gets

Every file has one of three owners, listed in `copier.yml`:

| Owner | Files | On [update](#update-a-project) |
|---|---|---|
| Template | The workflow machinery | Replaced; an edit in the project is discarded |
| Template and project, merged | Settings files whose tools can't include a second file | The template's changes merge with the project's edits, like a Git merge |
| Project | `AGENTS.md`, `README.md` and, for .NET, `Directory.Build.props` | Never touched |

Where a tool can include a second file, the template's part and the project's part are separate files, so the project changes the template's behavior without editing it ([Extend or Override the Template](#extend-or-override-the-template)).

### Template-Owned Files

Replaced on every update. A project never edits them; an edit is discarded by the next update.

| File | Purpose |
|---|---|
| `.github/instructions/project-template.instructions.md` | The plan-then-execute rules and base conventions, for every agent: Copilot loads it on its own; Claude Code imports it through the first entry in `AGENTS.md` |
| `CLAUDE.md` | Imports `AGENTS.md` for Claude Code and adds Claude-specific notes |
| `.claude/commands/` (23), `.claude/agents/plan-executor.md` | Claude Code: `/plan-feature`, `/plan-bugfix`, `/plan-issue`, `/triage-issues`, `/run-issues`, `/plan-template-update`, `/orchestrate-plan`, `/replan-step`, `/review-plan-diff`, `/ship-plan`, `/continue-plan`, `/finish-plan`, … and the Sonnet subagent that executes steps; each plan runs in its own git worktree, so several sessions work at once — generated |
| `.github/agents/` (8 + 1), `.github/prompts/` (23) | Copilot Chat in VS Code: the Copilot agents (planner, implementer on Claude Sonnet 5.5, reviewer, orchestrator), the Hybrid agents (the same, with the Local Implementer on the shack PC's model), and the same commands as prompt files — generated |
| `.github/skills/` (22), `.github/agents/plan-executor.agent.md` | Copilot CLI: the same commands as skills, and the agent `/orchestrate-plan` delegates to — generated |
| `build/ProjectTemplate.props` (.NET) | Latest C#, nullable reference types, implicit usings, warnings as errors, `ContinuousIntegrationBuild` when `CI=true`, author metadata; `*.Tests` projects aren't packable and skip XML docs; with `nuget_package`, the license expression, README and icon in each package, Source Link with untracked sources, symbol packages and XML documentation |
| `.github/instructions/csharp.instructions.md` (.NET) | C# conventions — test layout and naming, regions, xUnit and Moq, collection expressions, `const`, UTF-8 literals — applied by Copilot to `*.cs` |
| `.claude/rules/csharp.md` (.NET) | Points Claude Code at the same conventions whenever it touches a `*.cs` file |
| `.copier-answers.yml` | Copier's: the answers and template version that `Update-Project.ps1` reads |
| `.template-version` | The template version the project is on, one line such as `v0.6.0`: Copier writes `_commit` from `.copier-answers.yml` here, for people and scripts to read. A repository with only the workflow installed gets the same file from `workflow\Install-HybridWorkflow.ps1` |
| `.template/Update-Project.ps1` | The [update script](#update-a-project): run in the project, it pulls in the newest template version and updates itself |
| `.template/Get-PlanState.ps1` | Prints where the plan in a folder stands (its steps, review, landing policy, pull request, tag and each of its issues) and the workflow command to run next; `/ship-plan`, `/continue-plan` and `/finish-plan` run it, and `Install-HybridWorkflow.ps1` installs it with the commands — generated |
| `.githooks/commit-msg` | Strips AI agent attribution from every commit message — `Co-authored-by:` trailers for Copilot and Claude, `Claude-Session:` trailers, "Generated with Claude Code" lines — whichever tool commits ([Commit Attribution](#commit-attribution)) |
| `.githooks/pre-push` | Refuses a push to the default branch when `AGENTS.md`'s Landing section says `protect: hook`, for a host that can't require pull requests, such as a private repository on GitHub Free; does nothing otherwise. In a clone that uses pre-commit or its own hooks, `Update-Project.ps1` and `Adopt-Project.ps1` print a two-line `.git/hooks/pre-push` wrapper to add, because pre-commit's pre-push stage checks only one ref of a push |
| `.template/Test-CommitAttribution.ps1` | Fails CI on a commit attributed to an AI agent ([Commit Attribution](#commit-attribution)) |

Which generated files a project gets follows `workflow_tools`. A command, prompt file, skill or agent the project adds under a name the template doesn't use is the project's.

Generated files are rendered from [workflow/templates](workflow/templates/) by `tools/Update-Template.ps1`; change them there.

### Merged Files

The project edits them freely, and later template changes merge in: an update keeps the project's edits and adds the template's, and only the same lines changed on both sides [conflict](#resolve-a-conflict). These are the files whose tools can't include a second file — `_merged_files` in `copier.yml` lists them.

| File | Purpose |
|---|---|
| `.claude/settings.json` | Commit and pull request attribution off; `git push` always asks for approval, in Bash and PowerShell; `.env` files and the root `secrets/` folder can't be read; entering a plan's worktree doesn't ask |
| `.vscode/settings.json`, `.vscode/extensions.json` | LF and final newlines, `git.addAICoAuthor` off, the Ollama timeout (only with the local model); recommended extensions (Claude Code, GitHub Copilot Chat, Ollama, EditorConfig, and the stack's language extension; the Ollama extension only with the local model) |
| `.editorconfig`, `.gitattributes`, `.gitignore` | UTF-8 and LF everywhere, binary types, and ignores for Claude Code's local files and worktrees, the plan in progress (`PLAN.md`), secrets and build output |
| `.github/workflows/ci.yml` or `.gitlab-ci.yml` | CI on GitHub or GitLab, whichever the `git_host` answer names: a job that runs the build and test commands once code exists, and a `Commit attribution` job that runs `.template/Test-CommitAttribution.ps1`; on GitHub it also runs in a merge queue, with actions pinned to commit SHAs and checkouts that set `persist-credentials: false`, so later steps can't read the job's token |
| `.github/dependabot.yml` (GitHub only) | [Dependabot](#stay-current), built into GitHub: a weekly pull request for newer CI actions and, by stack, NuGet packages and the .NET SDK, pip or npm packages |
| `Directory.Packages.props` (.NET) | Central package management: versions in one place |
| `global.json` (.NET) | The .NET SDK version (10.0.402, rolling forward to newer feature bands); CI installs exactly what it names |

A project that replaced a merged file with its own, such as a CI workflow of its own, makes it project-owned: `.\.template\Update-Project.ps1 -Data @{ project_owned_files = '.github/workflows/ci.yml' }`, or a list of several files. `Adopt-Project.ps1` takes the same answer: `-Data @{ project_owned_files = '.github/workflows/ci.yml' }` keeps the repository's own file exactly as it is. Updates then leave the file alone and show the template's changes to it, as for the project-owned files below. Without the answer, a rewritten file shares almost no lines with the template, so the template's changes conflict in unrelated places. Only merged files can be named; any other file stops the update before it changes anything. `-Data @{ project_owned_files = @() }` gives the files back to the merge.

### Project-Owned Files

Written once, when the project is created, and never touched by an update, even when the template's copy changes; `Update-Project.ps1` lists those changes. `_skip_if_exists` in `copier.yml` lists these files. So is each merged file the `project_owned_files` answer names ([Merged Files](#merged-files)).

| File | Purpose |
|---|---|
| `AGENTS.md` | The index every agent reads: the template's rules first, then the project's own instruction files, build and test commands, and conventions |
| `README.md` | Build and test commands, and the workflow at a glance |
| `Directory.Build.props` (.NET) | Imports `build/ProjectTemplate.props`, then holds the project's own build settings, which override the template's |

## Claude Code or GitHub Copilot

Every project carries the same workflow for both, so you can work on it with your Claude plan or your Copilot plan, and switch whenever you like: open the other panel in VS Code, or run `claude` or `copilot` in a terminal. Nothing in the project needs to change. `PLAN.md` is the only state the tools share, so one can plan and another execute, re-plan or review. In Claude Code each plan lives in its own git worktree, so several sessions can work on different plans at once; open that folder to continue the plan in Copilot. Each request bills the plan of the tool that makes it.

[USAGE.md](USAGE.md) is the guide: the tools to install, signing in to each, the commands per tool, switching mid-plan, and troubleshooting.
## Extend or Override the Template

A project never edits a template-owned file. It adds to the template and overrides it with files of its own, which win where they differ.

`AGENTS.md` is the project's index. Its first entry imports the template's rules; every entry after it is the project's:

```markdown
## Instructions

- @.github/instructions/project-template.instructions.md — the plan-then-execute workflow and base conventions, from the project template. …
- @.github/instructions/api.instructions.md — how this project designs its HTTP API
- @docs/agents/releases.md — how to cut a release
```

| To | Add | Picked up by |
|---|---|---|
| Add an instruction, or override one of the template's, for every agent | A line under Conventions in `AGENTS.md`, or a file listed in its index as `@<path> — what it covers`. A `.github/instructions/<name>.instructions.md` file with an `applyTo` glob also reaches Copilot automatically | Claude Code imports each `@` entry; Copilot reads `AGENTS.md` and loads every `.github/instructions/` file; other agents follow the index |
| Add a command, skill or agent | A file with a new name in `.claude/commands/`, `.github/prompts/`, `.github/skills/<name>/` or `.github/agents/` | The tool; updates leave it alone |
| Add an instruction for Claude Code only | `.claude/rules/<name>.md` | Claude Code loads every file there |
| Override a .NET build setting | A property in `Directory.Build.props`, after its import of `build/ProjectTemplate.props` | MSBuild: the later value wins |
| Change a merged file — `.gitignore`, CI, editor settings, permissions | Edit the file; later template changes merge into it | — |

An instruction override is the project's word against the template's, so say it plainly — "Ignore the template's rule on X; here, do Y" — and the agents follow the project.

## Questions

`New-Project.ps1` runs `copier copy`, which asks these questions in the terminal, in this order. Each shows its default; press Enter to accept it. A question answered in advance with `-Data` isn't asked, and `-Defaults` takes the default for every other question without asking. Project-owned files take the answers once, when the project is created; template-owned and merged files follow a later change made with `Update-Project.ps1 -Data`.

| Question | Default | Affects |
|---|---|---|
| `project_name` | None; required, so `-Defaults` needs it in `-Data` | Headings in `AGENTS.md` and `README.md` |
| `project_description` | Blank | The line under each heading |
| `stack` | .NET | The .NET layer, default commands, CI setup steps, `.gitignore` section, recommended extension |
| `git_host` | GitHub | The CI file (`.github/workflows/ci.yml` or `.gitlab-ci.yml`) and, on GitHub, `.github/dependabot.yml`; the pull-request command in the template's rules; with `-CreateRemote`, where the repository is created: `gh` on GitHub, `glab` on GitLab |
| `workflow_tools` | Claude Code, Copilot and the local model | Which workflow files the project gets: `CLAUDE.md` and `.claude/` with Claude Code; the Copilot agents, prompt files, skills and `plan-executor.agent.md` with Copilot; the Hybrid agents, `execute-step-local.prompt.md` and the Ollama settings with the local model. `-Data` takes a list: `workflow_tools = 'claude', 'copilot'` |
| `author_name` (.NET only) | Marcin Polewski | `Authors`, `Company` and `Copyright` in `build/ProjectTemplate.props` |
| `nuget_package` (.NET only) | Off | The package settings in `build/ProjectTemplate.props` |
| `package_license` | None; required with `nuget_package` | The SPDX license expression |
| `package_icon` | Blank | A PNG at the repository root, packed as the icon |
| `package_manager` (Node.js only) | npm | How CI installs dependencies — `npm ci`; pnpm and Yarn through Corepack, which runs the version `package.json`'s `packageManager` field names; Bun through `oven-sh/setup-bun` on GitHub and the `oven/bun` image on GitLab — Dependabot's ecosystem (`bun` for Bun, else `npm`), and the default build and test commands |
| `build_command`, `test_command` | By stack, below | `AGENTS.md`, `README.md`, and through them every plan's Context for the executor |
| `project_owned_files` | None; not asked, set with `Update-Project.ps1 -Data` | Merged files the project owns: updates leave them alone and show the template's changes to them ([Merged Files](#merged-files)) |

| Stack | Build | Test |
|---|---|---|
| .NET | `dotnet build` | `dotnet test` |
| Python | None | `python -m pytest -q` |
| Node.js or TypeScript | `<package_manager> run build`, such as `npm run build` | `<package_manager> run test` |
| PowerShell | `Invoke-ScriptAnalyzer -Path . -Recurse -EnableExit` | `Invoke-Pester -CI` |
| Other | None | None |

## Create a Project

Needs Git with `user.name` and `user.email` set, Copier (`uv tool install copier`; the scripts fall back to `uvx`), access to this private repository (`gh auth setup-git` once per PC), and for `-CreateRemote` the signed-in `gh` or `glab` CLI. [USAGE.md](USAGE.md#install-the-tools) sets all of it up, along with Claude Code and GitHub Copilot.

```powershell
.\New-Project.ps1 -Path C:\src\qso-viewer                                # asks the questions, then git init and the first commit
.\New-Project.ps1 -Path C:\src\qso-viewer -CreateRemote                  # also creates the repository, public, on the host you answer (GitHub by default), and pushes
.\New-Project.ps1 -Path C:\src\qso-viewer -CreateRemote -Visibility private                # the same, but private
.\New-Project.ps1 -Path C:\src\qso-viewer -CreateRemote -Data @{ git_host = 'gitlab' }     # on GitLab instead of GitHub, without asking that question
.\New-Project.ps1 -Path C:\src\qso-viewer -CreateRemote -Owner bixbots   # under a GitHub org or GitLab group
.\New-Project.ps1 -Path C:\src\qso-viewer -CreateRemote -Defaults -Data @{ project_name = 'QSO Viewer'; stack = 'python' }   # asks nothing: GitHub, public
```

| Parameter | Default | Purpose |
|---|---|---|
| `-Path` | — | New, empty project folder; its name becomes the repository name |
| `-Template` | `https://github.com/polewskm/project-template.git` | Template source; `.` uses this clone |
| `-Ref` | The newest tag | Template version to use |
| `-CreateRemote`, `-Owner` | Off, your account | Create the repository on GitHub or GitLab, whichever the `git_host` answer names, and push `main` |
| `-Visibility` | `public` | The new repository's visibility: `public`, `private`, or `internal` (GitLab: any signed-in user; GitHub: organizations under an enterprise account only) |
| `-Data` | None | Answers given in advance, so those questions aren't asked: `-Data @{ project_name = 'Demo'; git_host = 'gitlab' }` |
| `-Defaults` | Off | Ask nothing: every question not in `-Data` takes its default |

The script runs `copier copy`, which asks the [questions](#questions) and writes the files and the answers (`.copier-answers.yml`), then `git init -b main`, enables the template's Git hooks (`git config core.hooksPath .githooks`), and makes the first commit, `Create project from project-template v0.1.0`. With `-CreateRemote` it reads `git_host` from `.copier-answers.yml`: for `github` it runs `gh repo create <name> --public --source . --push`; for `gitlab`, `glab repo create <name> --public` and `git push -u origin main`. `-Visibility` replaces `--public` with `--private` or `--internal`. GitLab would otherwise default to internal, so the script always passes the flag.

A public project is readable by anyone, including its `.copier-answers.yml`, which names this private template; only people with access to the template can run `copier update`. Secrets stay out of it as in any project (`AGENTS.md`, `.gitignore`), and its CI is safe for pull requests from forks: `pull_request` with a read-only token and no secrets. Without a `LICENSE` file, the code is all rights reserved; add one if others should be able to use it. To change the visibility later: `gh repo edit --visibility private --accept-visibility-change-consequences`, or `glab api --method PUT projects/:id --raw-field visibility=private` (`glab repo update` has no visibility flag).

For a .NET project, `dotnet new` templates put a `Version` on each `<PackageReference>`, which central package management rejects (NU1008); move each version into `Directory.Packages.props`. The template's rules tell the agents the same, and `dotnet add package` already does it. Add each project to one solution at the repository root (`dotnet new sln` once, then `dotnet sln add <project folder>`), so the default `dotnet build` and `dotnet test` — and CI — cover it.

To bring an existing repository under the template, use [Adopt-Project.ps1](#adopt-an-existing-repository).

## Adopt an Existing Repository

`Adopt-Project.ps1` brings a repository that already exists under the template, so it gets the workflow and later updates. Run it from this clone, on a repository with a clean working tree. It needs the same tools as [Create a Project](#create-a-project).

```powershell
.\Adopt-Project.ps1 -Path C:\src\buffers                                                    # works out the answers, adopts, verifies, commits
.\Adopt-Project.ps1 -Path C:\src\buffers -Data @{ workflow_tools = 'claude', 'copilot' }    # for a public or shared repository with no Copilot or Hybrid agent files: no Hybrid agents, which use the shack PC's private model
.\Adopt-Project.ps1 -Path C:\src\buffers -Data @{ project_owned_files = '.github/workflows/ci.yml' }  # keeps the repository's own CI workflow as it is, and later updates show the template's changes to it
.\Adopt-Project.ps1 -Path C:\src\buffers -NoCommit                                          # stages the result for review instead
```

| Parameter | Default | Purpose |
|---|---|---|
| `-Path` | — | The repository's root folder |
| `-Template` | `https://github.com/polewskm/project-template.git` | Template source; `.` uses this clone |
| `-Ref` | The newest tag | Template version to use |
| `-Data` | None | Answers that win over everything the script works out: `-Data @{ stack = 'node' }` |
| `-NoVerify` | Off | Skip the build and test commands before the commit |
| `-NoCommit` | Off | Stage the result instead of committing it; it still verifies unless `-NoVerify` is also given |

The script refuses a folder that isn't the root of a Git repository, has uncommitted changes, has no commits yet, already has `.copier-answers.yml` (use `Update-Project.ps1` instead), or has no Git `user.name` or `user.email`.

### How it works

It never asks a question. Each answer comes from the first of these that has it:

1. `-Data`.
2. A [legacy adapter](#legacy-adapters).
3. What the script works out from the repository.
4. The template's default.

The script works out these answers:

| Answer | Worked out from |
|---|---|
| `stack` | `dotnet` if there is a solution or a C#, F# or VB project within two folders of the root; else `node` if `package.json` is at the root; else `python` if `pyproject.toml`, `requirements.txt` or `setup.py` is; else `other` if there is an OpenTofu or Terraform file (`.tf`, `.tofu` or `.tftest.hcl`) within two folders of the root; else `powershell` if there is a `.ps1`, `.psm1` or `.psd1` file outside the `build`, `eng`, `scripts`, `tools`, `.github` and `.gitlab` folders at the root; else `other` |
| `project_name` | The only solution's name, else the `origin` remote's repository name, else the main checkout's folder name, so a Claude Code worktree doesn't name the project after itself |
| `git_host` | `gitlab` if the `origin` remote names GitLab, else `github` |
| `author_name` (.NET) | `Authors`, else `Company`, in the root `Directory.Build.props` |
| `build_command`, `test_command` (.NET) | `dotnet build <solution>` and `dotnet test <solution>`, when the only solution isn't at the root |
| `package_manager` (Node.js) | The one the `packageManager` field in `package.json` names, else the one whose lockfile is at the root (`pnpm-lock.yaml`, `yarn.lock`, `bun.lock` or `bun.lockb`), else npm |
| `build_command`, `test_command` (Node.js) | `<package_manager> run build` and `<package_manager> run test`, each only when `package.json` has that script and the `test` script isn't the failing placeholder `npm init` writes; else blank |
| `workflow_tools` | `claude`, plus `copilot` if `.github/agents/copilot-*.agent.md`, `.github/skills/` or `.github/prompts/` exists, plus `local` if `.github/agents/hybrid-*.agent.md` exists; with none of these, the template's default, and the script prints a line saying it included `local` and how to leave it out |

Everything else takes the template's default. The script prints the answers, runs `copier copy --overwrite`, and enables the template's Git hooks (`git config core.hooksPath .githooks`) unless the repository already sets its own, has hooks in `.git/hooks`, which a hooks path would turn off, or uses pre-commit, which won't install while a hooks path is set ([Commit Attribution](#commit-attribution)).

What it does with a file the repository already has depends on the file's owner ([What a Project Gets](#what-a-project-gets)):

| Owner | What happens |
|---|---|
| Template | Replaced by the template's file; the repository's copy is discarded |
| Merged | Rebuilt as the template's file plus the repository's own content, so a later update merges the repository's content like any project's edits (below) |
| Project | Kept. `AGENTS.md` gains the template's rules as an index entry: first under its `## Instructions` heading, else in a new `## Project Template` section before its first section, else at the end. `Directory.Build.props` gains the import of `build/ProjectTemplate.props` as its first element, so its own settings override the template's |

A merged file is rebuilt by type:

| File | Rebuilt as |
|---|---|
| A file the `project_owned_files` answer names, such as `-Data @{ project_owned_files = '.github/workflows/ci.yml' }` | The repository's file, exactly as it is; Copier doesn't touch it, and a file the repository lacks isn't created. Later updates leave it alone and show the template's changes to it ([Merged Files](#merged-files)). Only merged files can be named; any other file stops the adoption before it changes anything |
| `.gitignore`, `.gitattributes`, `.editorconfig` | The template's file, then the repository's lines under a comment (`.editorconfig` drops its `root =` lines). An update sets those lines aside while Copier merges and puts them back at the end, so a template change never conflicts with them |
| `*.json` | The two merged key by key in the template's order; the repository's values win and lists are combined. Comments are dropped, and the report says so |
| `*.props` | The template's file with the repository's elements added before `</Project>` |
| Anything else, such as YAML CI and Dependabot files | The repository's file, kept. A template change to it conflicts on update: keep your side; or name it in `project_owned_files` when adopting |

A .NET repository without `Directory.Packages.props` moves to central package management: each `Version` goes from the project files into `Directory.Packages.props`. When projects disagree on a version, the highest wins and the report says so.

Before committing, the script runs the build and test commands from the answers. It then commits on the current branch as `Adopt project-template v0.1.0`, with the report of what it merged, removed and moved as the message body. If a command fails, it stages everything, commits nothing, and exits 1; fix the problem and commit, or abandon the adoption with `git reset --hard; git clean -fd`. If anything else fails after the template is applied, the script resets the repository to where it was and says so, so there is nothing to clean up.

Some judgment is left to you. The script prints it as a ready request: folding `.github/copilot-instructions.md` into `AGENTS.md`; for a .NET repository, reconciling the template's `csharp.instructions.md` with the repository's own instruction files; and, when the template added `ci.yml` because the repository had none, reconciling its other workflows in `.github/workflows` with it. A `ci.yml` the repository already had is kept, and so is every workflow beside it.

```text
Still to do — in the repository, run:
  /plan-migration Finish adopting the project template: fold .github/copilot-instructions.md into AGENTS.md or a file it lists; reconcile .github/workflows/main.yml with ci.yml
```

Afterwards the repository updates like any project: `.\.template\Update-Project.ps1` ([Update a Project](#update-a-project)).

### Legacy Adapters

A legacy adapter removes one old setup that the template replaces. Each is a script in [adopt/legacy/](adopt/legacy/) that takes `-Path` and `-Phase`. `Adopt-Project.ps1` runs every script there with `-Phase Detect`; for each that returns `$true` it:

| Phase | When | Returns |
|---|---|---|
| `Detect` | First | `$true` if the repository has the setup |
| `Answers` | Before Copier runs | A hashtable of answers, which beat what the script works out but not `-Data` |
| `Apply` | After Copier runs | Lines for the report; the script prints them and puts them in the commit message |

To handle another setup, add a script to `adopt/legacy/`; nothing else changes.

| Adapter | Detects | Does |
|---|---|---|
| `NCode.ProjectSettings.Scaffold.ps1` | A project file referencing the `NCode.ProjectSettings.Scaffold` NuGet package | Answers `nuget_package`, `package_license` (`Apache-2.0`), `author_name` (`NCode Group`) and, when `NCodeGroup.png` is at the root, `package_icon`. Removes the package reference, whose settings `build/ProjectTemplate.props` now provides, and reports that its `GlobalAssemblyInfo.cs`, its license and copyright copies and its build-time release notes are gone. Lists any file still using a property the package defined |
| `HybridWorkflowInstall.ps1` | `.github/prompts/execute-step-copilot.prompt.md`, the name an older `Install-HybridWorkflow.ps1` used | Deletes it; the template's Copilot prompt is `execute-step.prompt.md` |

## Update a Project

Every project carries its update script as `.template\Update-Project.ps1`. Run it in the project:

```powershell
cd C:\src\qso-viewer
.\.template\Update-Project.ps1                # newest template tag; commits the update
.\.template\Update-Project.ps1 -NoCommit      # stages it for review instead
.\.template\Update-Project.ps1 -Ref v0.3.0    # a specific template version
```

From this repository's clone, `.\Update-Project.ps1 -Path C:\src\qso-viewer` does the same: it's a wrapper that runs `template\.template\Update-Project.ps1`, the script's single source.

| Parameter | Default | Purpose |
|---|---|---|
| `-Path` | The project the script sits in | The project; it must have no uncommitted changes |
| `-Ref` | The newest tag | Template version to update to |
| `-Data` | None | Answers to change: `-Data @{ author_name = 'K0MTP' }`. Template-owned and merged files follow the new answer; project-owned files don't |
| `-NoCommit` | Off | Stage the update instead of committing it |

The script needs no template clone: it clones the template from the address in `.copier-answers.yml` into a temporary folder, with the Git access Copier needs anyway, and deletes it afterwards. The script is template-owned, so it updates itself: when the target version's copy differs from the running one, it hands the update over to that copy, and the newest update logic always does the update. Every version accepts the same parameters, so any version can hand over to any later one. It refuses to run on the default branch (the branch `origin/HEAD` names), because it commits: run it on a branch of its own, such as `git switch -c build/project-template-v0.2.0`, or pass `-NoCommit`.

A project on v0.8.0 or earlier doesn't hand over: its script can't read the newer copy from a template cloned over a URL, so it runs its own, older logic — it prints Copier's raw "Make sure Git >= 2.24 is installed" warning and no "Handing the update over" line — and installs the newer script for the next update ([CHANGELOG.md](CHANGELOG.md#v090)). To run the newest logic on that first update, run the wrapper from a clone of this repository: `git clone https://github.com/polewskm/project-template.git`, then `.\Update-Project.ps1 -Path <project>` in that clone.

| File | On update |
|---|---|
| Template-owned | Replaced by the new version; files the template added are created, and files it removed are deleted. A local edit is discarded and a deleted file restored, and the script lists both, so the change can move into a project file |
| Merged | The template's changes since the project's version merge with the project's edits. Only the same lines changed on both sides conflict. A merged file the project deleted stays deleted |
| Project-owned | Including each merged file the `project_owned_files` answer names. Never touched, even if the project deleted it. When the template changed one since the project's version, the script shows the template's change, rendered with the project's answers and leaving out what the project's file already has; copy over what you want |
| `.copier-answers.yml`, `.template-version` | Record the new version |

Without a conflict the result is one commit, `Update from project-template v0.2.0`:

```text
Handing the update over to the v0.2.0 version of Update-Project.ps1.
Template v0.1.0 -> v0.2.0:
  added     .claude/commands/plan-release.md
  modified  .github/instructions/project-template.instructions.md
  modified  .gitignore
  modified  .template-version
  modified  .template/Update-Project.ps1
  modified  CLAUDE.md

Local edits discarded — these files are the template's; make the change in a project file instead:
  CLAUDE.md

The template changed these project-owned files since v0.1.0. They weren't touched; copy over what you want:

  AGENTS.md:
    @@ -23,3 +23,3 @@ Run from the repository root in PowerShell 7.

    -## Conventions
    +## Conventions and Overrides


Committed "Update from project-template v0.2.0". Review it with: git show --stat
```

The script runs `copier recopy` at the project's current template version, which resets the template-owned files and so shows any local edits, then `copier update --defaults`, which moves to the new version and merges the merged files. If anything else fails, it resets the project to where it was. `copier check-update`, run in a project, tells whether a newer template version exists.

To plan an update instead of running it, run `/plan-template-update` in the project, or name a version: `/plan-template-update v0.14.0`. It reads `.copier-answers.yml` and the release notes since the project's version, runs `Update-Project.ps1 -NoCommit` on a clone of the project in a temporary folder, and plans from what that trial changed. The plan's first step runs the update with `-Ref` pinned to the target and `-NoCommit`, so it is committed as a plan step, and a result that differs from the trial escalates. The next steps run the project's checks and fix the project's own files that still describe the old template, and the last runs the project's tests. Every check is judged by its exit code. The planning session files an issue here for each gap in the template that the trial shows. In Claude Code the plan gets its own worktree, unless the project's `plan-executor` subagent predates v0.11.0 and can't run PowerShell there; then it runs on a `build/project-template-<version>` branch in the current checkout. A project on v0.13.0 or earlier doesn't have the command yet: compose it from this repository's clone with `.\workflow\New-PlanPrompt.ps1 plan-template-update`, or install the commands for your user with `.\workflow\Install-HybridWorkflow.ps1 -User`.

### Resolve a Conflict

When the template and the project changed the same lines of a merged file, the script commits nothing, exits 1, and says how to finish:

```text
Template v0.2.0 -> v0.3.0:
  conflict  .gitignore
  modified  .template-version
  modified  CLAUDE.md

1 file(s) conflict: the template and this project changed the same lines. In each, keep the right lines and delete the <<<<<<<, ======= and >>>>>>> marker lines. Then:
  git add -A
  git diff --cached --check     # prints any marker you missed
  git commit -m "Update from project-template v0.3.0"
To abandon the update instead: git reset --hard; git clean -fd
```

The rest of the update is already in place; only the conflicting lines wait for you. In the file, the top half is the project's version and the bottom half the template's:

```text
<<<<<<< before updating
Thumbs.db # project
=======
Thumbs.db # template
>>>>>>> after updating
```

VS Code lists the file under Merge Changes in Source Control and calls the halves Current and Incoming, with Accept buttons above each block. Git won't commit while a file is still unmerged, but `git add` marks it resolved even with markers left in it, so run `git diff --cached --check` before committing.
## Commit Attribution

A commit records the people who wrote it. AI tools add their own attribution by default — Claude Code a `Co-Authored-By: Claude <noreply@anthropic.com>` trailer and a `Claude-Session:` trailer, Copilot a `Co-authored-by: Copilot` trailer — and GitHub then lists the agent as a contributor, which only rewriting published history undoes. Every project, and this repository, turns it off in layers that travel with the repository, so they work on any PC that clones it:

| Layer | Stops |
|---|---|
| `attribution` in `.claude/settings.json`: `commit` and `pr` empty, `sessionUrl` off | Claude Code's trailers and pull request text |
| `git.addAICoAuthor` off in `.vscode/settings.json` | VS Code's own Copilot trailer when you commit from Source Control |
| The rule in `.github/instructions/project-template.instructions.md` (here, `AGENTS.md`) | Agents that write the commit message themselves, such as Copilot's |
| `.githooks/commit-msg` (here, `template/.githooks/commit-msg`) | Anything that slips through, from any tool. Git runs a hook only once a clone enables it: `New-Project.ps1` and `Update-Project.ps1` run `git config core.hooksPath .githooks` unless the clone already has hooks in `.git/hooks`, which a hooks path would turn off, and then say how to run both; in a clone that uses pre-commit, they print a `repo: local` hook to add to `.pre-commit-config.yaml` (`entry: .githooks/commit-msg`, `language: script`, `stages: [commit-msg]`), and nothing once that file runs the hook; in a fresh clone of a project, run it yourself or update the project. In a clone of this repository, run `git config core.hooksPath template/.githooks` |
| `.template/Test-CommitAttribution.ps1` (here, `template/.template/`), run by the `Commit attribution` job in `ci.yml` or `.gitlab-ci.yml` | A commit authored, committed or co-authored by an AI agent, whoever made it and however: on every pull request, merge queue entry and push to the default branch. It reports; to make it block a merge, require the Commit attribution check in the repository's branch rules on GitHub, or turn on "Pipelines must succeed" on GitLab |

The hook removes only agent lines: `Co-authored-by:` trailers naming Copilot or an `@anthropic.com` or `Copilot@users.noreply.github.com` address, `Claude-Session:` trailers, and "Generated with Claude Code" lines. A person's co-author trailer stays. To clean commits that already have them, before pushing, enable the hook and amend every unpushed commit through it: `git rebase origin/main --exec "git commit --amend --no-edit --allow-empty"`.

The check fails with the commits it found and the command that fixes them: `git rebase <base> --exec "git commit --amend --no-edit --reset-author"`, then `git push --force-with-lease`. The Copilot cloud agent authors its own commits, so its pull requests fail until they are re-authored this way.

## Stay Current

A project pins exact versions so that a build today matches a build next month: each package, each CI action (by commit SHA), the .NET SDK in `global.json`, and the template version in `.template-version` (from `_commit` in `.copier-answers.yml`). Pinned versions never update themselves; something has to notice each new upstream release and change the pin.

| What goes stale | How it's kept current |
|---|---|
| A GitHub project's CI actions, packages and .NET SDK | Dependabot, built into GitHub: `.github/dependabot.yml` turns it on, with nothing to install or sign up for. Each week it opens a pull request for newer versions — minor and patch updates of one kind together — which CI tests and you merge. Moving the target frameworks to a new .NET major version is a planned migration: `/plan-migration` |
| A GitLab project's packages | By hand; GitLab has no free built-in equivalent. Its CI images use floating tags such as `python:3`, so they follow upstream on their own |
| A project's template-owned files | [`.template\Update-Project.ps1`](#update-a-project), run in the project. `copier check-update`, run there too, tells whether a newer tag exists |
| A repository or user profile with only the workflow installed (`workflow\Install-HybridWorkflow.ps1 -Repo` or `-User`) | By hand: re-run the installer from a clone at the newest tag. The version it has is in `.template-version` — at the repository root, or in `~\.claude\` and `~\.copilot\` for the profile |
| This template's generated workflow files | `tools/Update-Template.ps1` regenerates them from `workflow/templates`; `tests/Test-Template.ps1` fails when they're behind |
| This template's own CI actions, in `.github/workflows/test-template.yml` | Dependabot in this repository |

The pins inside `template/` — the actions in `ci.yml.jinja` and the SDK in `global.json` — are in merged files, which each project's Dependabot keeps current on its own. A template release that moves the same pin to a different version conflicts on that line (keep the newer version), so change a pin in the template only when you change that step anyway, or to keep new projects from starting far behind.

## Change the Template

1. Edit the base files under `template/`: `*.jinja` files are rendered with the answers, every other file is copied as is. A file name such as `{% if stack == 'dotnet' %}global.json{% endif %}` makes the file conditional. A new file is template-owned unless `copier.yml` lists it under `_merged_files` or `_skip_if_exists`. Keep a file template-owned whenever its tool can include a second, project-owned file; list it under `_merged_files` when it can't. A question that a later version adds must be read through a default wherever `copier.yml` uses it before the question is answered — the `_exclude` patterns read `workflow_tools | default([...])` — because an update renders the old version's files with the new `copier.yml` before the project has that answer; without the default an old project's update stops with conflicts. `tests/Test-Template.ps1` fails an `_exclude` pattern that excludes anything without the answer.
2. For the workflow commands, agents and prompts, edit the source templates in [workflow/templates](workflow/templates/), then run `.\tools\Update-Template.ps1` to regenerate their copies under `template/` and at the repository root.
3. Run `.\tests\Invoke-AllTests.ps1` (add `-SkipDotnetBuild` to skip the .NET build and pack) and confirm its last line reads `All tests: PASSED`. It runs every `tests\Test-*.ps1` suite in turn and prints `PASS` or `FAIL` and the time for each, with a failed suite's `FAIL` lines and the path of its full log, and exits 1 when any suite fails.
4. Add the version's notes to `CHANGELOG.md` and land the change through a pull request: this repository's `main` takes no direct pushes ([AGENTS.md](AGENTS.md)'s Landing section). Once it merges, tag the commit it merged as and push the tag: `git tag -a v0.2.0 -m v0.2.0 <commit>` and `git push origin refs/tags/v0.2.0`. Then publish the notes: `gh release create v0.2.0 --verify-tag --title v0.2.0 --notes-file <a file with the version's CHANGELOG.md section>`. For a planned change, the plan's last step writes these notes, and `/ship-plan` does the rest: it drops the empty plan commits, pushes the branch and opens the pull request, and, run again after the merge, tags, publishes the release, files the plan's follow-ups as issues and closes the issue.

`tests/Test-Template.ps1` works on a tagged snapshot of the working tree, without Claude Code's worktrees, in `%TEMP%`. It, `tests/Test-Adoption.ps1`, `tests/Test-AdoptOwnedFiles.ps1`, `tests/Test-UpdateIgnoredFiles.ps1`, `tests/Test-UpdateExitCode.ps1`, `tests/Test-UpdateKeptLines.ps1`, `tests/Test-UpdateOwnedFiles.ps1`, `tests/Test-PlanState.ps1`, `tests/Test-CommitAttribution.ps1`, `tests/Test-GitHooks.ps1` and `tests/Test-InvokeAllTests.ps1` run on every push to `main` and every pull request through `.github/workflows/test-template.yml`:

| Check | For |
|---|---|
| Common files present | Every stack, on GitHub and GitLab |
| .NET layer present, or absent | .NET, or every other stack |
| NuGet package settings in `build/ProjectTemplate.props` only with `nuget_package` | .NET |
| The CI file for the `git_host` answer, with its `Commit attribution` job, and `.github/dependabot.yml` on GitHub only | Every render |
| CI sets up and installs with the `package_manager` answer, the default commands run it and no other manager, and Dependabot uses its ecosystem | Node.js with npm, pnpm, Yarn and Bun, on GitHub and GitLab |
| LF line endings, no leftover Jinja, valid JSON, valid YAML | Every rendered file |
| Workflow files, editor settings, `.gitignore`, `AGENTS.md`, the template rules and `README.md` only for the chosen `workflow_tools` | Every render |
| `.copier-answers.yml` and `.template-version` record the version | Every render |
| Every `_exclude` pattern excludes nothing when `workflow_tools` is missing | Always |
| Every `tests/Test-*.ps1` script has a `run: ./tests/<name>` step in `.github/workflows/test-template.yml`, so CI runs it | Always |
| Generated workflow files, under `template/` and at the repository root, match a fresh run of `workflow\Install-HybridWorkflow.ps1` | Always, including CI |
| The installer writes both variants for every tool; `New-PlanPrompt.ps1` composes a prompt; `Invoke-PlanSteps.ps1 -DryRun` parses the example plan | Always |
| The installer writes the template version to `.template-version` at the repository root; `template/` and this repository's root have no installer-written copy | Always |
| Every executor — the Copilot Implementer, the `execute-step` prompt, and the Copilot CLI and Claude Code `plan-executor` agents — runs on Claude Sonnet 5.5 | Always |
| Claude Code's planning commands create the plan's worktree, and the commands that execute, re-plan or review a plan move into it; no Copilot file, `plan-executor` subagent or analysis command enters a worktree | Always |
| `New-Project.ps1` passes a list answer in `-Data` to Copier | Always |
| `New-Project.ps1` and `Update-Project.ps1` enable `.githooks`, with `commit-msg` executable; the hook strips Claude and Copilot attribution and keeps a person's co-author trailer, and keeps a prose line that mentions the advertising phrase | Always; the update check with the update tests |
| The shipped `.template/Test-CommitAttribution.ps1` passes on a new project's own history | Always |
| `dotnet new classlib` and `xunit`, added to a root solution, pass the default `dotnet build` and `dotnet test` under `Directory.Build.props` and `global.json` | .NET (skip with `-SkipDotnetBuild`) |
| A project's own `.template\Update-Project.ps1` hands the update over to the new version's script; it replaces template-owned files, discards and reports an edit to one, and restores a deleted one; merges a merged file, keeping the project's edit, and keeps a deleted one deleted; leaves project-owned files untouched and shows the template's changes to them, leaving out those the project already has; deletes and adds files as the template did; makes one commit, and changes nothing on a second run. On a same-line change to a merged file it stops with exit code 1, commits nothing, still replaces the template-owned files, and finishes once the conflict is resolved. The root wrapper updates another project by `-Path` | Python and Node.js projects (skip with `-SkipUpdate`) |
| `tests/Test-Adoption.ps1`: the adoption functions and legacy adapters on small inputs; adopting a Python repository on GitLab and a .NET repository built on the NCodeGroup scaffold — answers worked out, merged files rebuilt, `AGENTS.md` and `Directory.Build.props` extended, versions moved into `Directory.Packages.props`, follow-ups reported, a failing build committing nothing, a Node.js repository without build or test scripts committing without running a command, with CI installing through the package manager `package.json` names, a failure after Copier rolling the repository back, the report naming only the follow-ups the repository really has, the package packed with README, icon and license, and a later template update merging cleanly | Always (`-SkipDotnetBuild` skips the .NET build and pack) |
| `tests/Test-AdoptOwnedFiles.ps1`: adopting a repository with `-Data @{ project_owned_files = '.github/workflows/ci.yml' }` keeps its own `ci.yml` unchanged and records the answer, a later update shows the template's change to it instead of merging it, and naming a file that isn't merged stops the adoption before it changes anything | Always |
| `tests/Test-UpdateIgnoredFiles.ps1`: a .NET project whose own `.gitignore` ignores a `node_modules` folder that the template's `.gitignore` doesn't updates without overflowing Windows' command line (WinError 206); `.git/info/exclude` ends as it was, without the copy of the project's rules that a killed update left behind, both after a clean update and after one stopped by a conflict | Always |
| `tests/Test-UpdateExitCode.ps1`: a project's own `.template\Update-Project.ps1`, run with `&`, exits 0 after staging an update with `-NoCommit` that shows a template change to a project-owned file, and after a run with nothing to update | Always |
| `tests/Test-UpdateKeptLines.ps1`: an adopted `stack: other` project whose `.gitignore` ends with `secrets/` and the block kept at adoption takes the template's change to `/secrets/` without a conflict, still ends with the kept block, and changes nothing on a second run; when its own edit conflicts with that change, the conflict ends before the kept block | Always |
| `tests/Test-UpdateOwnedFiles.ps1`: a project whose `project_owned_files` answer names its own `ci.yml` updates without touching it and is shown the template's change to it, while `.gitignore` still merges; the answer lasts across the update; naming a file that isn't merged stops the update before it changes anything; an empty list gives the file back to the merge | Always |
| `tests/Test-PlanState.ps1`: `workflow/Get-PlanState.ps1`, on fixture repositories with a local `origin`, reads a plan's header, steps, `Reviewed:` line and the Landing section of `AGENTS.md`, with each key's default, a value in backticks and a label with a space; counts commits ahead of and behind the default branch, and with `-NoFetch` leaves out commits pushed after the last fetch; lists the other plan worktrees; counts a merged GitHub pull request or GitLab merge request, read through stand-ins for `gh` and `glab`, as landed only when its merge commit is on the default branch and its head holds `HEAD` or has its tree, also when an older one merged under a newer open or closed one, and prints its merge commit on the `merge` line; names the base branch in `next` for a request merged into another branch, and `ship-plan` under `integrate: direct`; reads every issue on a one-issue and a group plan's `Issue:` line through the stand-ins, with `issue-state` open while any is open; and names the next command for open, escalated, unreviewed, stale, reviewed, landed, tagged and dirty states | Always |
| `tests/Test-CommitAttribution.ps1`: the check every project gets fails on a commit authored or committed by an AI agent account, a co-author trailer naming one, a `Claude-Session:` trailer or Claude Code's advertising line (also when the console's code page isn't UTF-8), and passes a person's co-author trailer, Dependabot, a prose line that mentions the advertising phrase, and an unknown or empty base | Always |
| `tests/Test-GitHooks.ps1`: `.githooks/commit-msg` runs as a pre-commit `language: script` hook and strips the attribution; `.githooks/pre-push` refuses a push to `main` only while the Landing section says `protect: hook`, and lets a branch and a tag through; `Update-Project.ps1` and `Adopt-Project.ps1` enable `.githooks` only in a clone without hooks of its own, print how to run both for other hooks in `.git/hooks`, print the pre-commit hook to add when the clone uses pre-commit, and print nothing once `.pre-commit-config.yaml` runs the hook; under `protect: hook` they print the pre-push wrapper to add (or the call to add to a clone's own pre-push hook) until something runs it, and the wrapper as `pre-push.legacy` refuses a push to `main` under pre-commit; `/run-issues`'s `protect: hook` check passes with `core.hooksPath` on `.githooks` or the wrapper in `pre-push` or `pre-push.legacy`, and fails with only pre-commit's pre-push hook | Always |
| `tests/Test-InvokeAllTests.ps1`: `tests/Invoke-AllTests.ps1` runs only the `Test-*.ps1` scripts in a folder, prints `PASS` or `FAIL` per suite with a failed suite's `FAIL` lines, logs each suite's output, counts a suite that throws as failed, passes `-SkipDotnetBuild` only to suites that take it, exits 1 when a suite fails or none is found, and ends with `All tests: PASSED` or `All tests: FAILED (<n>)` | Always |
| The `Commit attribution` job checks this repository's own new commits with `template/.template/Test-CommitAttribution.ps1` | Every push to `main` and pull request |

## Publish the Template

Once, from this folder:

```powershell
git add -A
git commit -m "Create the project template"
git tag v0.1.0
gh repo create polewskm/project-template --private --source . --remote origin --push
git push origin v0.1.0
```

Copier picks the newest tag, so a change reaches projects only once it is tagged and pushed.

## Repository Layout

| Path | Purpose |
|---|---|
| `copier.yml` | Questions and Copier settings: `_subdirectory: template` keeps everything else out of projects; `_merged_files` and `_skip_if_exists` list the merged and project-owned files |
| `template/` | The files a project gets |
| `New-Project.ps1` | Create a project, its first commit and optionally its remote |
| `Adopt-Project.ps1` | Bring an existing repository under the template, with no questions asked |
| `adopt/` | `Adoption.psm1`, the functions `Adopt-Project.ps1` uses, and `legacy/`, one adapter per old setup it removes |
| `Update-Project.ps1` | Update a project by `-Path` from this clone: a wrapper around `template\.template\Update-Project.ps1`, the update script every project carries |
| `workflow/` | The single source of the workflow: prompt and agent templates, the installer, the prompt composer and the step runner ([workflow/README.md](workflow/README.md)) |
| `tools/Update-Template.ps1` | Regenerate the workflow files under `template/` and at the repository root from `workflow/templates` |
| `AGENTS.md`, `.claude/settings.json`, `.vscode/settings.json`, `.gitignore` | This repository's own agent instructions and settings: no AI attribution in commits ([Commit Attribution](#commit-attribution)), and Claude Code's worktrees ignored |
| `.claude/`, `.github/agents/`, `.github/prompts/`, `.github/skills/`, `.template/Get-PlanState.ps1` | This repository's own workflow: the same generated files as `template/` gets, committed so that working on the template with Claude Code or Copilot has `/plan-feature`, `/orchestrate-plan` and the rest on any PC that clones it. Never edit them; `tools/Update-Template.ps1` regenerates them |
| `tests/` | This repository's tests, one script per area: they find the repository root themselves, run from any folder, and CI runs them all |
| `tests/Test-Template.ps1` | Render every stack and check the result |
| `tests/Test-Adoption.ps1` | Check the adoption functions and legacy adapters, then adopt small test repositories |
| `tests/Test-AdoptOwnedFiles.ps1` | Adopt a repository that owns a merged file, then update it |
| `tests/Test-UpdateIgnoredFiles.ps1` | Update a project whose own `.gitignore` ignores a large folder |
| `tests/Test-UpdateExitCode.ps1` | Check that a successful update exits 0 |
| `tests/Test-UpdateKeptLines.ps1` | Update an adopted project whose merged files end with the lines it kept |
| `tests/Test-UpdateOwnedFiles.ps1` | Update a project that owns a merged file it replaced |
| `tests/Test-PlanState.ps1` | Test the plan state script `/ship-plan` and `/continue-plan` run |
| `tests/Test-CommitAttribution.ps1` | Test the commit attribution check that every project gets |
| `tests/Test-GitHooks.ps1` | Test the commit-msg hook under pre-commit, the pre-push hook, and the note on enabling the hooks |
| `tests/Invoke-AllTests.ps1` | Run every test suite and print one line per suite |
| `tests/Test-InvokeAllTests.ps1` | Test the runner that runs every test suite |
| `.github/workflows/test-template.yml` | Runs `tests/Test-Template.ps1`, `tests/Test-Adoption.ps1`, `tests/Test-AdoptOwnedFiles.ps1`, `tests/Test-UpdateIgnoredFiles.ps1`, `tests/Test-UpdateExitCode.ps1`, `tests/Test-UpdateKeptLines.ps1`, `tests/Test-UpdateOwnedFiles.ps1`, `tests/Test-PlanState.ps1`, `tests/Test-CommitAttribution.ps1`, `tests/Test-GitHooks.ps1` and `tests/Test-InvokeAllTests.ps1` on Windows, and checks this repository's commit attribution, for every push to `main` and every pull request |
| `.github/dependabot.yml` | Dependabot for the actions in `test-template.yml` |
| `USAGE.md` | Setting up a PC for Claude Code and GitHub Copilot, and using and switching between them in a project |
| `.gitattributes` | Keeps every file LF on disk, because Copier copies non-`.jinja` files byte for byte |

---

**TL;DR:** `.\New-Project.ps1 -Path C:\src\<name> -CreateRemote` creates a project with `AGENTS.md`, `CLAUDE.md`, Claude Code permissions, the plan-then-execute commands and agents for Claude Code, Copilot Chat and Copilot CLI — switch between your Claude and Copilot plans at any time — CI, Dependabot, and optional .NET settings, then creates its repository on GitHub, public, and pushes. Add `-Visibility private` for a private repository; answer GitLab to the host question (or pass `-Data @{ git_host = 'gitlab' }`) for GitLab. Every file has one of three owners: template-owned files are replaced on every update and never edited; merged files — settings whose tools can't include a second file — take the template's changes merged with the project's edits; and project-owned files, including the `AGENTS.md` index, are never touched. `.\.template\Update-Project.ps1`, run in a project, updates itself to the newest version first, then does all three and commits, or stops on a same-line conflict in a merged file. Dependabot keeps each GitHub project's actions, packages and SDK current through weekly pull requests. Change the workflow in `workflow/templates`, run `tools/Update-Template.ps1` and `tests/Test-Template.ps1`, then tag and push; this repository is its single source of truth. `.\Adopt-Project.ps1 -Path <repository>` brings an existing repository under the template.
