# Project Template

Private [Copier](https://copier.readthedocs.io/) template for new repositories set up for plan-then-execute AI coding: Claude Opus plans each change into `PLAN.md`, a cheaper model executes it one verified step at a time, and any step that needs a decision goes back to Opus. The base works for any language; a .NET layer adds shared build settings and C# conventions. Projects live on GitHub by default, or on GitLab. Every project made from it can pull later template improvements with `Update-Project.ps1`.

**Related:** [Configuration G](https://github.com/polewskm/personal-notes/blob/main/ham-radio/shack/shack-pc/local-ai/configuration-g.md) — the accounts, the shack PC, the VS Code tunnel and the daily loop this template is built for. [Plan-and-execute](https://github.com/polewskm/personal-notes/blob/main/ham-radio/shack/shack-pc/local-ai/plan-and-execute.md) — how the workflow works and how to choose between its variants. This repository is the single source of truth for the workflow's templates and scripts ([workflow/](workflow/)); personal-notes and every project consume them.

## Table of Contents

- [What a Project Gets](#what-a-project-gets)
- [Extend or Override the Template](#extend-or-override-the-template)
- [Questions](#questions)
- [Create a Project](#create-a-project)
- [Update a Project](#update-a-project)
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
| `.claude/commands/` (16), `.claude/agents/plan-executor.md` | `/plan-feature`, `/plan-bugfix`, `/orchestrate-plan`, `/replan-step`, `/review-plan-diff`, … and the Sonnet subagent that executes steps — generated |
| `.github/agents/` (4), `.github/prompts/` (16) | VS Code chat agents — the Local Implementer runs steps on the shack PC's model — and prompt files — generated |
| `build/ProjectTemplate.props` (.NET) | Latest C#, nullable reference types, implicit usings, warnings as errors, `ContinuousIntegrationBuild` when `CI=true`, author metadata; `*.Tests` projects aren't packable and skip XML docs |
| `.github/instructions/csharp.instructions.md` (.NET) | C# conventions — test layout and naming, regions, xUnit and Moq, collection expressions, `const`, UTF-8 literals — applied by Copilot to `*.cs` |
| `.claude/rules/csharp.md` (.NET) | Points Claude Code at the same conventions whenever it touches a `*.cs` file |
| `.copier-answers.yml` | Copier's: the answers and template version that `Update-Project.ps1` reads |
| `.template/Update-Project.ps1` | The [update script](#update-a-project): run in the project, it pulls in the newest template version and updates itself |

Generated files are rendered from [workflow/templates](workflow/templates/) by `Update-Template.ps1`; change them there.

### Merged Files

The project edits them freely, and later template changes merge in: an update keeps the project's edits and adds the template's, and only the same lines changed on both sides [conflict](#resolve-a-conflict). These are the files whose tools can't include a second file — `_merged_files` in `copier.yml` lists them.

| File | Purpose |
|---|---|
| `.claude/settings.json` | `git push` always asks for approval, in Bash and PowerShell; `.env` files and `secrets/` can't be read |
| `.vscode/settings.json`, `.vscode/extensions.json` | LF and final newlines, the Ollama timeout; recommended extensions (Claude Code, Ollama, EditorConfig, and the stack's language extension) |
| `.editorconfig`, `.gitattributes`, `.gitignore` | UTF-8 and LF everywhere, binary types, and ignores for Claude Code's local files and worktrees, secrets and build output |
| `.github/workflows/ci.yml` or `.gitlab-ci.yml` | CI on GitHub or GitLab, whichever the `git_host` answer names, that runs the build and test commands once code exists; GitHub Actions pinned to commit SHAs |
| `.github/dependabot.yml` (GitHub only) | [Dependabot](#stay-current), built into GitHub: a weekly pull request for newer CI actions and, by stack, NuGet packages and the .NET SDK, pip or npm packages |
| `Directory.Packages.props` (.NET) | Central package management: versions in one place |
| `global.json` (.NET) | The .NET SDK version (10.0.402, rolling forward to newer feature bands); CI installs exactly what it names |

### Project-Owned Files

Written once, when the project is created, and never touched by an update, even when the template's copy changes; `Update-Project.ps1` lists those changes. `_skip_if_exists` in `copier.yml` lists these files.

| File | Purpose |
|---|---|
| `AGENTS.md` | The index every agent reads: the template's rules first, then the project's own instruction files, build and test commands, and conventions |
| `README.md` | Build and test commands, and the workflow at a glance |
| `Directory.Build.props` (.NET) | Imports `build/ProjectTemplate.props`, then holds the project's own build settings, which override the template's |

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
| `author_name` (.NET only) | Marcin Polewski | `Authors`, `Company` and `Copyright` in `build/ProjectTemplate.props` |
| `build_command`, `test_command` | By stack, below | `AGENTS.md`, `README.md`, and through them every plan's Context for the executor |

| Stack | Build | Test |
|---|---|---|
| .NET | `dotnet build` | `dotnet test` |
| Python | None | `python -m pytest -q` |
| Node.js or TypeScript | `npm run build` | `npm test` |
| PowerShell | `Invoke-ScriptAnalyzer -Path . -Recurse -EnableExit` | `Invoke-Pester -CI` |
| Other | None | None |

## Create a Project

Needs Git with `user.name` and `user.email` set, Copier (`uv tool install copier`; the scripts fall back to `uvx`), access to this private repository (`gh auth setup-git` once per PC), and for `-CreateRemote` the signed-in `gh` or `glab` CLI.

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

The script runs `copier copy`, which asks the [questions](#questions) and writes the files and the answers (`.copier-answers.yml`), then `git init -b main` and the first commit, `Create project from project-template v0.1.0`. With `-CreateRemote` it reads `git_host` from `.copier-answers.yml`: for `github` it runs `gh repo create <name> --public --source . --push`; for `gitlab`, `glab repo create <name> --public` and `git push -u origin main`. `-Visibility` replaces `--public` with `--private` or `--internal`. GitLab would otherwise default to internal, so the script always passes the flag.

A public project is readable by anyone, including its `.copier-answers.yml`, which names this private template; only people with access to the template can run `copier update`. Secrets stay out of it as in any project (`AGENTS.md`, `.gitignore`), and its CI is safe for pull requests from forks: `pull_request` with a read-only token and no secrets. Without a `LICENSE` file, the code is all rights reserved; add one if others should be able to use it. To change the visibility later: `gh repo edit --visibility private --accept-visibility-change-consequences`, or `glab api --method PUT projects/:id --raw-field visibility=private` (`glab repo update` has no visibility flag).

For a .NET project, `dotnet new` templates put a `Version` on each `<PackageReference>`, which central package management rejects (NU1008); move each version into `Directory.Packages.props`. The template's rules tell the agents the same, and `dotnet add package` already does it. Add each project to one solution at the repository root (`dotnet new sln` once, then `dotnet sln add <project folder>`), so the default `dotnet build` and `dotnet test` — and CI — cover it.

To add the template to an existing repository, run `copier copy <template> <repository>` on a clean working tree. Copier keeps the repository's `AGENTS.md`, `README.md` and `Directory.Build.props`, and asks before overwriting any other file it already has: keep the repository's own `.gitignore` and settings files, and later updates merge the template's changes into them. Then add the template's rules to `AGENTS.md` as the first index entry: `- @.github/instructions/project-template.instructions.md — the plan-then-execute workflow and base conventions, from the project template`.

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

The script needs no template clone: it clones the template from the address in `.copier-answers.yml` into a temporary folder, with the Git access Copier needs anyway, and deletes it afterwards. The script is template-owned, so it updates itself: when the target version's copy differs from the running one, it hands the update over to that copy, and the newest update logic always does the update. Every version accepts the same parameters, so any version can hand over to any later one.

| File | On update |
|---|---|
| Template-owned | Replaced by the new version; files the template added are created, and files it removed are deleted. A local edit is discarded and a deleted file restored, and the script lists both, so the change can move into a project file |
| Merged | The template's changes since the project's version merge with the project's edits. Only the same lines changed on both sides conflict. A merged file the project deleted stays deleted |
| Project-owned | Never touched, even if the project deleted it. When the template changed one since the project's version, the script shows the template's change; copy over what you want |
| `.copier-answers.yml` | Records the new version |

Without a conflict the result is one commit, `Update from project-template v0.2.0`:

```text
Handing the update over to the v0.2.0 version of Update-Project.ps1.
Template v0.1.0 -> v0.2.0:
  added     .claude/commands/plan-release.md
  modified  .github/instructions/project-template.instructions.md
  modified  .gitignore
  modified  .template/Update-Project.ps1
  modified  CLAUDE.md

Local edits discarded — these files are the template's; make the change in a project file instead:
  CLAUDE.md

The template changed these project-owned files since v0.1.0. They weren't touched; copy over what you want:

  AGENTS.md, from template/AGENTS.md.jinja:
    @@ -23,3 +23,3 @@ Run from the repository root in PowerShell 7.

    -## Conventions
    +## Conventions and Overrides


Committed "Update from project-template v0.2.0". Review it with: git show --stat
```

The script runs `copier recopy` at the project's current template version, which resets the template-owned files and so shows any local edits, then `copier update --defaults`, which moves to the new version and merges the merged files. If anything else fails, it resets the project to where it was. `copier check-update`, run in a project, tells whether a newer template version exists.
### Resolve a Conflict

When the template and the project changed the same lines of a merged file, the script commits nothing, exits 1, and says how to finish:

```text
Template v0.2.0 -> v0.3.0:
  conflict  .gitignore
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
## Stay Current

A project pins exact versions so that a build today matches a build next month: each package, each CI action (by commit SHA), the .NET SDK in `global.json`, and the template version in `.copier-answers.yml`. Pinned versions never update themselves; something has to notice each new upstream release and change the pin.

| What goes stale | How it's kept current |
|---|---|
| A GitHub project's CI actions, packages and .NET SDK | Dependabot, built into GitHub: `.github/dependabot.yml` turns it on, with nothing to install or sign up for. Each week it opens a pull request for newer versions — minor and patch updates of one kind together — which CI tests and you merge. Moving the target frameworks to a new .NET major version is a planned migration: `/plan-migration` |
| A GitLab project's packages | By hand; GitLab has no free built-in equivalent. Its CI images use floating tags such as `python:3`, so they follow upstream on their own |
| A project's template-owned files | [`.template\Update-Project.ps1`](#update-a-project), run in the project. `copier check-update`, run there too, tells whether a newer tag exists |
| This template's generated workflow files | `Update-Template.ps1` regenerates them from `workflow/templates`; `Test-Template.ps1` fails when they're behind |
| This template's own CI actions, in `.github/workflows/test-template.yml` | Dependabot in this repository |

The pins inside `template/` — the actions in `ci.yml.jinja` and the SDK in `global.json` — are in merged files, which each project's Dependabot keeps current on its own. A template release that moves the same pin to a different version conflicts on that line (keep the newer version), so change a pin in the template only when you change that step anyway, or to keep new projects from starting far behind.

## Change the Template

1. Edit the base files under `template/`: `*.jinja` files are rendered with the answers, every other file is copied as is. A file name such as `{% if stack == 'dotnet' %}global.json{% endif %}` makes the file conditional. A new file is template-owned unless `copier.yml` lists it under `_merged_files` or `_skip_if_exists`. Keep a file template-owned whenever its tool can include a second, project-owned file; list it under `_merged_files` when it can't.
2. For the workflow commands, agents and prompts, edit the source templates in [workflow/templates](workflow/templates/), then run `.\Update-Template.ps1` to regenerate their copies under `template/`.
3. Run `.\Test-Template.ps1` and confirm the last line reads `Template tests: PASSED`.
4. Commit, tag the next version, and push with tags: `git tag v0.2.0` and `git push origin main --tags`.

`Test-Template.ps1` works on a tagged snapshot of the working tree in `%TEMP%`, and runs on every push to `main` and every pull request through `.github/workflows/test-template.yml`:

| Check | For |
|---|---|
| Common files present | Every stack, on GitHub and GitLab |
| .NET layer present, or absent | .NET, or every other stack |
| The CI file for the `git_host` answer, and `.github/dependabot.yml` on GitHub only | Every render |
| LF line endings, no leftover Jinja, valid JSON, valid YAML | Every rendered file |
| `.copier-answers.yml` records the version | Every render |
| Generated workflow files match a fresh run of `workflow\Install-HybridWorkflow.ps1` | Always, including CI |
| The installer writes both variants for every tool; `New-PlanPrompt.ps1` composes a prompt; `Invoke-PlanSteps.ps1 -DryRun` parses the example plan | Always |
| `dotnet new classlib` and `xunit`, added to a root solution, pass the default `dotnet build` and `dotnet test` under `Directory.Build.props` and `global.json` | .NET (skip with `-SkipDotnetBuild`) |
| A project's own `.template\Update-Project.ps1` hands the update over to the new version's script; it replaces template-owned files, discards and reports an edit to one, and restores a deleted one; merges a merged file, keeping the project's edit, and keeps a deleted one deleted; leaves project-owned files untouched and shows the template's changes to them; deletes and adds files as the template did; makes one commit, and changes nothing on a second run. On a same-line change to a merged file it stops with exit code 1, commits nothing, still replaces the template-owned files, and finishes once the conflict is resolved. The root wrapper updates another project by `-Path` | Python and Node.js projects (skip with `-SkipUpdate`) |

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
| `Update-Project.ps1` | Update a project by `-Path` from this clone: a wrapper around `template\.template\Update-Project.ps1`, the update script every project carries |
| `workflow/` | The single source of the workflow: prompt and agent templates, the installer, the prompt composer and the step runner ([workflow/README.md](workflow/README.md)) |
| `Update-Template.ps1` | Regenerate the workflow files under `template/` from `workflow/templates` |
| `Test-Template.ps1` | Render every stack and check the result |
| `.github/workflows/test-template.yml` | Runs `Test-Template.ps1` on Windows for every push to `main` and every pull request |
| `.github/dependabot.yml` | Dependabot for the actions in `test-template.yml` |
| `.gitattributes` | Keeps every file LF on disk, because Copier copies non-`.jinja` files byte for byte |

---

**TL;DR:** `.\New-Project.ps1 -Path C:\src\<name> -CreateRemote` creates a project with `AGENTS.md`, `CLAUDE.md`, Claude Code permissions, the plan-then-execute commands and agents, CI, Dependabot, and optional .NET settings, then creates its repository on GitHub, public, and pushes. Add `-Visibility private` for a private repository; answer GitLab to the host question (or pass `-Data @{ git_host = 'gitlab' }`) for GitLab. Every file has one of three owners: template-owned files are replaced on every update and never edited; merged files — settings whose tools can't include a second file — take the template's changes merged with the project's edits; and project-owned files, including the `AGENTS.md` index, are never touched. `.\.template\Update-Project.ps1`, run in a project, updates itself to the newest version first, then does all three and commits, or stops on a same-line conflict in a merged file. Dependabot keeps each GitHub project's actions, packages and SDK current through weekly pull requests. Change the workflow in `workflow/templates`, run `Update-Template.ps1` and `Test-Template.ps1`, then tag and push; this repository is its single source of truth.
