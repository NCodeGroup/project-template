# Project Template

Private [Copier](https://copier.readthedocs.io/) template for new repositories set up for plan-then-execute AI coding: Claude Opus plans each change into `PLAN.md`, a cheaper model executes it one verified step at a time, and any step that needs a decision goes back to Opus. Every project works with Claude Code and with GitHub Copilot, and you can switch between them at any time ([Claude Code or GitHub Copilot](#claude-code-or-github-copilot)). The base works for any language, with the decisions behind its rules recorded as ADRs; a .NET layer adds shared build settings, analyzers, banned APIs, C# and test conventions, and for libraries the license files, icon and a NuGet publish workflow. Projects live on GitHub by default, or on GitLab. Every project made from it can pull later template improvements with `Update-Project.ps1`.

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
| `.claude/commands/` (25), `.claude/agents/plan-executor.md` | Claude Code: `/plan-feature`, `/plan-bugfix`, `/plan-issue`, `/triage-issues`, `/run-issues`, `/address-feedback`, `/plan-template-update`, `/orchestrate-plan`, `/replan-step`, `/review-plan-diff`, `/ship-plan`, `/continue-plan`, `/finish-plan`, `/audit-conventions`, … and the Sonnet subagent that executes steps; each plan runs in its own git worktree, so several sessions work at once — generated |
| `.github/agents/` (8 + 1), `.github/prompts/` (25) | Copilot Chat in VS Code: the Copilot agents (planner, implementer on Claude Sonnet 5.5, reviewer, orchestrator), the Hybrid agents (the same, with the Local Implementer on the shack PC's model), and the same commands as prompt files — generated |
| `.github/skills/` (24), `.github/agents/plan-executor.agent.md` | Copilot CLI: the same commands as skills, and the agent `/orchestrate-plan` delegates to — generated |
| `build/ProjectTemplate.props` (.NET) | Latest C#, nullable reference types, implicit usings, warnings as errors, the .NET analyzers at `latest-recommended` with code style enforced in the build, XML documentation (so unused usings are reported; CS1591 off unless `nuget_package`), NuGet vulnerability warnings as errors in CI only, compile-time minimal-API request delegates, the null-forgiving operator banned outside test projects (Nullable.Extended.Analyzer), `ContinuousIntegrationBuild` when `CI=true`, author metadata; `*.Tests` projects aren't packable and take `build/ProjectTemplate.Tests.globalconfig`; with `nuget_package`, the license expression, the project's own README (or the repository's) and the icon in each package, Source Link with untracked sources and symbol packages, each packable project's public API checked against its `PublicAPI.Shipped.txt` and `PublicAPI.Unshipped.txt` (PublicApiAnalyzers), and `AssemblyVersion` pinned to the major version while `FileVersion` keeps the exact one |
| `build/dod.ps1` (.NET) | The Definition of Done: checks the decision index, builds in Release with every analyzer, runs the tests and, with `nuget_package`, packs into `artifacts/packages`; stops at the first failing stage and ends with `Definition of Done: PASSED`. `-Fast` (Debug, no pack) is the local gate a new project's Landing section names; `-Filter` narrows the tests. CI runs it while the build and test commands are the defaults |
| `build/Update-PublicApi.ps1` (.NET, `nuget_package`) | Creates each packable project's `PublicAPI.Shipped.txt` and `PublicAPI.Unshipped.txt` when missing, records the public symbols they don't list yet and names the stale ones; `-Release` moves the unshipped entries into `PublicAPI.Shipped.txt`. `Adopt-Project.ps1` runs it before verifying an adopted library |
| `.template/Test-AdrIndex.ps1` | Fails when `docs/decisions/README.md`'s index misses a decision record, links one that doesn't exist or shows another number than its record's, and when two records share a number; CI runs it for every stack, and `build/dod.ps1` for .NET |
| `build/ProjectTemplate.globalconfig`, `build/ProjectTemplate.Tests.globalconfig` (.NET) | The template's analyzer severities: unused usings (IDE0005) are errors; in `*.Tests` projects, CS1591, CA1707, CA1816, CA1859, CA1861 and CA1869 are off, each with its reason. `.editorconfig` overrides them |
| `build/BannedSymbols.txt` (.NET) | APIs banned in every project, tests included (RS0030, through `Microsoft.CodeAnalysis.BannedApiAnalyzers`): blocking on tasks (`.Result`, `.Wait()`, `.GetAwaiter().GetResult()`, `WaitAll`, `WaitAny`), `JsonDocument.Parse` (use `JsonElement.Parse`) and Newtonsoft.Json. A project bans more in a `BannedSymbols.<name>.txt` of its own |
| `.github/instructions/csharp.instructions.md` (.NET) | C# conventions for every `*.cs` file, applied by Copilot: code style, async, nullability, public API discipline, types and collections, file organization, DI registration, concurrency, security defaults, clean code, memory, testability, XML documentation, logging, metrics and traces, configuration, build and EF Core migrations |
| `.github/instructions/csharp-tests.instructions.md` (.NET) | Test conventions for `<Name>.Tests` projects: layout and naming, regions, what a test proves, assertions, strict Moq mocks verified on dispose, real collaborators, isolation, `FakeTimeProvider`, EF Core and integration tests |
| `.claude/rules/csharp.md`, `.claude/rules/csharp-tests.md` (.NET) | Point Claude Code at the same conventions whenever it touches a `*.cs` file, or one in a test project |
| `docs/decisions/project-template/` | The template's architecture decision records, the reasons behind its rules: every project gets the ones on commit attribution, plan-then-execute, trunk-based development, pull requests, issues and pinned inputs; .NET projects also get those on the build, the banned APIs and the C# conventions, the ASP.NET Core ones and, with `nuget_package`, the library ones. A project that decides otherwise supersedes one with an ADR of its own |
| `.copier-answers.yml` | Copier's: the answers and template version that `Update-Project.ps1` reads |
| `.template-version` | The template version the project is on, one line such as `v0.6.0`: Copier writes `_commit` from `.copier-answers.yml` here, for people and scripts to read. A repository with only the workflow installed gets the same file from `workflow\Install-HybridWorkflow.ps1` |
| `.template/Update-Project.ps1` | The [update script](#update-a-project): run in the project, it pulls in the newest template version and updates itself |
| `.template/Get-PlanState.ps1` | Prints where the plan in a folder stands (its steps, review, landing policy, whether the default branch takes changes only through pull requests, pull request, tag, the version it moves to when another plan took its release, the files that conflict with the default branch, the version tags its changelog has no section for, each of its issues, the issues it only refers to, and the follow-ups not yet filed as issues) and the workflow command to run next; `/ship-plan`, `/continue-plan`, `/finish-plan` and `/run-issues` run it, and `Install-HybridWorkflow.ps1` installs it with the commands — generated |
| `.githooks/commit-msg` | Strips AI agent attribution from every commit message — `Co-authored-by:` trailers for Copilot and Claude, `Claude-Session:` trailers, "Generated with Claude Code" lines — whichever tool commits ([Commit Attribution](#commit-attribution)) |
| `.githooks/pre-push` | Refuses a push to the default branch when `AGENTS.md`'s Landing section says `protect: hook`, for a host that can't require pull requests, such as a private repository on GitHub Free; does nothing otherwise. In a clone that uses pre-commit or its own hooks, `Update-Project.ps1` and `Adopt-Project.ps1` print a two-line `.git/hooks/pre-push` wrapper to add, because pre-commit's pre-push stage checks only one ref of a push |
| `.template/Test-CommitAttribution.ps1` | Fails CI on a commit attributed to an AI agent ([Commit Attribution](#commit-attribution)) |
| `.github/workflows/template-update.yml` (GitHub only) | Every Monday at 07:00 UTC, and on demand, runs `.template/Get-TemplateUpdate.ps1` with only `contents: read` and `issues: write`, so a project learns of a new template version without checking ([The Update Notice](#the-update-notice)) |
| `.template/Get-TemplateUpdate.ps1` | Compares `.template-version` with the template's newest version tag and keeps one open issue labeled `template-update`, "Update to project-template <version>", with the changelog sections in between; closes it once the project is current ([The Update Notice](#the-update-notice)) |

Which generated files a project gets follows `workflow_tools`. A command, prompt file, skill or agent the project adds under a name the template doesn't use is the project's.

Generated files are rendered from [workflow/templates](workflow/templates/) by `tools/Update-Template.ps1`; change them there.

### Merged Files

The project edits them freely, and later template changes merge in: an update keeps the project's edits and adds the template's, and only the same lines changed on both sides [conflict](#resolve-a-conflict). These are the files whose tools can't include a second file — `_merged_files` in `copier.yml` lists them.

| File | Purpose |
|---|---|
| `.claude/settings.json` | Commit and pull request attribution off; `git push` always asks for approval, in Bash and PowerShell; `.env` files and the root `secrets/` folder can't be read; entering a plan's worktree doesn't ask |
| `.vscode/settings.json`, `.vscode/extensions.json` | LF and final newlines, `git.addAICoAuthor` off, the Ollama timeout (only with the local model); recommended extensions (Claude Code, GitHub Copilot Chat, Ollama, EditorConfig, and the stack's language extension; the Ollama extension only with the local model) |
| `.editorconfig`, `.gitattributes`, `.gitignore` | UTF-8 and LF everywhere, binary types, and ignores for Claude Code's local files and worktrees, the plan in progress (`PLAN.md`), secrets and build output; for .NET, the C# wrapping style and the header each new C# file starts with (`file_header_template`: the Apache-2.0 notice, an SPDX line for another license, or the copyright line), a suggestion so existing files still build |
| `.github/workflows/ci.yml` or `.gitlab-ci.yml` | CI on GitHub or GitLab, whichever the `git_host` answer names: a job that runs the build and test commands once code exists (for .NET with the default commands, `build/dod.ps1`, keeping its test results, and for a library its packages, as artifacts for 14 days, after a failure too) and checks the decision index with `.template/Test-AdrIndex.ps1`, and a `Commit attribution` job that runs `.template/Test-CommitAttribution.ps1`; for .NET, a NuGet package cache keyed on the restore's inputs. On GitHub it also runs in a merge queue; a newer push to a pull request or topic branch cancels the run it supersedes, but a default-branch commit's run and a merge queue entry's are never cancelled; every job has a timeout; actions are pinned to commit SHAs, and checkouts set `persist-credentials: false`, so later steps can't read the job's token |
| `.github/dependabot.yml` (GitHub only) | [Dependabot](#stay-current), built into GitHub: a weekly pull request for newer CI actions and, by stack, NuGet packages and the .NET SDK, pip or npm packages, one per ecosystem, and security updates in a pull request of their own per ecosystem; a new .NET SDK major isn't offered, since moving to it is a planned migration |
| `.github/workflows/copilot-setup-steps.yml` (GitHub, with Copilot in `workflow_tools`) | Prepares the Copilot cloud agent's runner before each session, in the one job GitHub runs for it, `copilot-setup-steps`: checks out without persisted credentials, sets up the stack as CI does (for .NET the SDK `global.json` names, the NuGet cache CI uses, `dotnet tool restore` and `dotnet restore`; Python, Node.js or PowerShell and their dependencies), and stops at 59 minutes, the session's limit. GitHub runs it only from the default branch; it also runs by hand and when the file changes. The project adds the steps its sessions need, such as a frontend's tools, and later template changes merge in |
| `Directory.Packages.props` (.NET) | Central package management: versions in one place, the banned API analyzer as a `GlobalPackageReference` every project gets, and the versions of the analyzers `build/ProjectTemplate.props` references for some projects: Nullable.Extended.Analyzer and, with `nuget_package`, PublicApiAnalyzers |
| `nuget.config` (.NET) | nuget.org as the only package source, with the ones a user or machine configuration adds cleared, so restore resolves the same packages everywhere; add a private feed here |
| `global.json` (.NET) | The .NET SDK version (10.0.402, rolling forward to newer feature bands); CI installs exactly what it names |

A project that replaced a merged file with its own, such as a CI workflow of its own, makes it project-owned: `.\.template\Update-Project.ps1 -Data @{ project_owned_files = '.github/workflows/ci.yml' }`, or a list of several files. `Adopt-Project.ps1` takes the same answer: `-Data @{ project_owned_files = '.github/workflows/ci.yml' }` keeps the repository's own file exactly as it is. Updates then leave the file alone and show the template's changes to it, as for the project-owned files below. Without the answer, a rewritten file shares almost no lines with the template, so the template's changes conflict in unrelated places. When the template changed a merged file that shares less than half its distinct non-blank lines with the template's version of it, `Update-Project.ps1` names the file and prints the `-Data` to run; it only suggests, and the update goes on. Only merged files can be named; any other file stops the update before it changes anything. `-Data @{ project_owned_files = @() }` gives the files back to the merge.

### Project-Owned Files

Written once, when the project is created, and never touched by an update, even when the template's copy changes; `Update-Project.ps1` lists those changes. `_skip_if_exists` in `copier.yml` lists these files. So is each merged file the `project_owned_files` answer names ([Merged Files](#merged-files)).

| File | Purpose |
|---|---|
| `AGENTS.md` | The index every agent reads: the template's rules first, then the project's own instruction files, build and test commands, and conventions |
| `README.md` | Build and test commands, and the workflow at a glance |
| `Directory.Build.props` (.NET) | Imports `build/ProjectTemplate.props`, then holds the project's own build settings, which override the template's |
| `docs/decisions/README.md`, `docs/decisions/0000-template.md` | How the project records its own architecture decisions (statuses, taking a number no other branch has, a record never overriding an external standard), its index of them, and the format to copy for a new one |
| `docs/README.md`, `docs/designs/_template.md` | The index of the project's documentation with the rules docs follow (they change with the code, claim only what is built, link a decision rather than restate it), and a design-document template for work bigger than one plan |
| `docs/metrics.md` (.NET) | The catalog of the project's instruments and spans, which the C# conventions keep current in the change that adds one |
| `SECURITY.md`, `CONTRIBUTING.md` | How to report a vulnerability privately, which versions get fixes and, for a library, how to verify a package; and how to contribute: prerequisites, setup, the build and test commands, the change flow and commit attribution |
| `LICENSE.txt`, `COPYRIGHT.txt` | The license text for an Apache-2.0 or MIT `license` (or, in a library from before that answer, `package_license`), and for Apache-2.0 the copyright notice; `Adopt-Project.ps1` leaves them out of a repository that already has a license file |
| `NCodeGroup.png` (.NET, `nuget_package`) | The NCode Group package icon, when `package_icon` names it, the default for the author NCode Group |
| `.github/workflows/publish.yml` (GitHub, .NET, `nuget_package`) | Publishes the packages to nuget.org when a GitHub release is published: refuses a tag whose commit the default branch doesn't hold, so a tag on an unreviewed commit publishes nothing, packs in Release with the version the tag names, then pushes through nuget.org trusted publishing (OIDC, no stored API key) in the protected `nuget` environment, with every action pinned to a full commit SHA. Needs a one-time setup, which its header describes: a trusted publishing policy on nuget.org, the `nuget` environment and the `NUGET_USER` variable |
| `.github/workflows/code-review.yml` (GitHub, `code_review` answer only) | Reviews each pull request with the NCode Review bot ([NCodeGroup/code-review](https://github.com/NCodeGroup/code-review)): runs from the default branch on `pull_request_target`, in the `code-review` environment, records each finding's outcome when a pull request closes, and pins the action to a release's full commit SHA, with its tag in a comment, the one pin CodeQL's `actions/unpinned-tag` query accepts. Project-owned so an update never moves a pin Dependabot bumped; `Update-Project.ps1` lists the template's changes to it |

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
| `workflow_tools` | Claude Code and Copilot | Which workflow files the project gets: `CLAUDE.md` and `.claude/` with Claude Code; the Copilot agents, prompt files, skills and `plan-executor.agent.md` with Copilot; the Hybrid agents, `execute-step-local.prompt.md` and the Ollama settings with the local model. `-Data` takes a list; add the local model with `workflow_tools = 'claude', 'copilot', 'local'` |
| `code_review` (GitHub only) | Off | `.github/workflows/code-review.yml`, which reviews pull requests with the NCode Review bot, and a note after the copy to run `tools/Enable-CodeReview.ps1` from a clone of `NCodeGroup/code-review`, which creates the `code-review` environment and gives the repository the organization's secrets. Not asked on GitLab |
| `license` | Blank | The repository's SPDX license expression, such as `MIT` or `Apache-2.0`: `LICENSE.txt` for MIT and Apache-2.0, `COPYRIGHT.txt` for Apache-2.0, the C# file header, and the default for `package_license` |
| `author_name` (.NET, or any stack with a `license`) | NCode Group | `Authors`, `Company` and `Copyright` in `build/ProjectTemplate.props`, and the copyright holder in the license files |
| `nuget_package` (.NET only) | Off | The package settings in `build/ProjectTemplate.props` |
| `package_license` | The `license` answer; required with `nuget_package` | The SPDX license expression in each package; a project from before `license` existed takes its license files from it |
| `package_icon` | `NCodeGroup.png` for the author NCode Group, otherwise blank | A PNG at the repository root, packed as the icon; the template writes `NCodeGroup.png` itself |
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

Needs Git with `user.name` and `user.email` set, Copier (`uv tool install copier`; the scripts fall back to `uvx`), network access to this repository, which is public, and for `-CreateRemote` the signed-in `gh` or `glab` CLI. [USAGE.md](USAGE.md#install-the-tools) sets all of it up, along with Claude Code and GitHub Copilot.

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
| `-Template` | `https://github.com/NCodeGroup/project-template.git` | Template source; `.` uses this clone |
| `-Ref` | The newest tag | Template version to use |
| `-CreateRemote`, `-Owner` | Off, your account | Create the repository on GitHub or GitLab, whichever the `git_host` answer names, and push `main` |
| `-NoBaseline` | Off | Skip protecting the default branch after `-CreateRemote` creates a GitHub repository |
| `-Visibility` | `public` | The new repository's visibility: `public`, `private`, or `internal` (GitLab: any signed-in user; GitHub: organizations under an enterprise account only) |
| `-Data` | None | Answers given in advance, so those questions aren't asked: `-Data @{ project_name = 'Demo'; git_host = 'gitlab' }` |
| `-Defaults` | Off | Ask nothing: every question not in `-Data` takes its default |

The script runs `copier copy`, which asks the [questions](#questions) and writes the files and the answers (`.copier-answers.yml`), then `git init -b main`, enables the template's Git hooks (`git config core.hooksPath .githooks`) unless Git already has a hooks path for the new repository, such as a global one, which it keeps and warns about ([Commit Attribution](#commit-attribution)), and makes the first commit, `Create project from project-template v0.1.0`. With `-CreateRemote` it reads `git_host` from `.copier-answers.yml`: for `github` it runs `gh repo create <name> --public --source . --push`; for `gitlab`, `glab repo create <name> --public` and `git push -u origin main`. `-Visibility` replaces `--public` with `--private` or `--internal`. GitLab would otherwise default to internal, so the script always passes the flag. For GitHub it then runs `tools/Set-RepositoryBaseline.ps1` ([Protect the Default Branch](#protect-the-default-branch)), unless `-NoBaseline` says not to.

A public project is readable by anyone, including its `.copier-answers.yml`, which names this template; the template is public too, so anyone can run `copier update` against it. Secrets stay out of it as in any project (`AGENTS.md`, `.gitignore`), and its CI is safe for pull requests from forks: `pull_request` with a read-only token and no secrets. Without a `LICENSE` file, the code is all rights reserved; add one if others should be able to use it. To change the visibility later: `gh repo edit --visibility private --accept-visibility-change-consequences`, or `glab api --method PUT projects/:id --raw-field visibility=private` (`glab repo update` has no visibility flag).

For a .NET project, `dotnet new` templates put a `Version` on each `<PackageReference>`, which central package management rejects (NU1008); move each version into `Directory.Packages.props`. The template's rules tell the agents the same, and `dotnet add package` already does it. Add each project to one solution at the repository root (`dotnet new sln` once, then `dotnet sln add <project folder>`), so the default `dotnet build` and `dotnet test` — and CI — cover it.

To bring an existing repository under the template, use [Adopt-Project.ps1](#adopt-an-existing-repository).

## Adopt an Existing Repository

`Adopt-Project.ps1` brings a repository that already exists under the template, so it gets the workflow and later updates. Run it from this clone, on a repository with a clean working tree. It needs the same tools as [Create a Project](#create-a-project).

```powershell
.\Adopt-Project.ps1 -Path C:\src\buffers                                                    # works out the answers, adopts, verifies, commits
.\Adopt-Project.ps1 -Path C:\src\buffers -Data @{ workflow_tools = 'claude', 'copilot', 'local' }    # adds the Hybrid agents, which use the shack PC's private model; without it a repository with no Copilot or Hybrid agent files gets Claude Code and Copilot only
.\Adopt-Project.ps1 -Path C:\src\buffers -Data @{ project_owned_files = '.github/workflows/ci.yml' }  # keeps the repository's own CI workflow as it is, and later updates show the template's changes to it
.\Adopt-Project.ps1 -Path C:\src\buffers -NoCommit                                          # stages the result for review instead
```

| Parameter | Default | Purpose |
|---|---|---|
| `-Path` | — | The repository's root folder |
| `-Template` | `https://github.com/NCodeGroup/project-template.git` | Template source; `.` uses this clone |
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
| `workflow_tools` | `claude`, plus `copilot` if `.github/agents/copilot-*.agent.md`, `.github/skills/` or `.github/prompts/` exists, plus `local` if `.github/agents/hybrid-*.agent.md` exists; with none of these, the template's default (`claude` and `copilot`), and the script prints a line saying so and how to add `local` |

Everything else takes the template's default. The script prints the answers, runs `copier copy --overwrite`, and enables the template's Git hooks (`git config core.hooksPath .githooks`) unless the repository already sets its own, has hooks in `.git/hooks`, which a hooks path would turn off, or uses pre-commit, which won't install while a hooks path is set; then it warns, naming the command that runs them ([Commit Attribution](#commit-attribution)).

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
| `.gitignore`, `.gitattributes`, `.editorconfig` | The template's file, then the repository's lines under a comment (`.editorconfig` drops its `root =` lines; `.gitattributes` drops a catch-all text rule such as `* text eol=lf`, because Git uses the last rule that matches and the repository's lines come after the template's, so it would override the template's binary rules and corrupt an image). An update sets those lines aside while Copier merges and puts them back at the end, so a template change never conflicts with them |
| `*.json` | The two merged key by key in the template's order; the repository's values win and lists are combined. Comments are dropped, and the report says so. The exception is `global.json` with a partial SDK version, such as `10.0.0`, and a `rollForward` policy: the template's CI reads it with `actions/setup-dotnet`, which rejects that, so the template's file is used and the report says so |
| `*.props` | The template's file with the repository's elements added before `</Project>` |
| Anything else, such as YAML CI and Dependabot files | The repository's file, kept. A template change to it conflicts on update: keep your side; or name it in `project_owned_files` when adopting |

A .NET repository without `Directory.Packages.props` moves to central package management: each `Version` goes from the project files into `Directory.Packages.props`. When projects disagree on a version, the highest wins and the report says so.

Before committing, the script runs the build and test commands from the answers. It then commits on the current branch as `Adopt project-template v0.1.0`, with the report of what it merged, removed and moved as the message body. If a command fails, it stages everything, commits nothing, and exits 1; fix the problem and commit, or abandon the adoption with `git reset --hard; git clean -fd`. If anything else fails after the template is applied, the script resets the repository to where it was and says so, so there is nothing to clean up.

Some judgment is left to you. The script prints it as a ready request: folding `.github/copilot-instructions.md` into `AGENTS.md`; for a .NET repository, reconciling the template's `csharp.instructions.md` with the repository's own instruction files; and, when the template added `ci.yml` because the repository had none, reconciling its other workflows in `.github/workflows` with it. A `ci.yml` the repository already had is kept, and so is every workflow beside it.

When the repository has version tags merged into the current branch that its changelog has no section for, the request also says to backfill them, such as `backfill CHANGELOG.md from the releases v0.1.0..v0.3.0`. The changelog is the file the `changelog` key of `AGENTS.md`'s Landing section names, `CHANGELOG.md` by default, and only tags shaped like `v1.2.3` or `1.2.3` count.

```text
Still to do — in the repository, run:
  /plan-migration Finish adopting the project template: fold .github/copilot-instructions.md into AGENTS.md or a file it lists; reconcile .github/workflows/main.yml with ci.yml
```

Afterwards the repository updates like any project: `.\.template\Update-Project.ps1` ([Update a Project](#update-a-project)).

### Legacy Adapters

A legacy adapter removes one old setup that the template replaces. Each is a script in [tools/adopt/legacy/](tools/adopt/legacy/) that takes `-Path` and `-Phase`. `Adopt-Project.ps1` runs every script there with `-Phase Detect`; for each that returns `$true` it:

| Phase | When | Returns |
|---|---|---|
| `Detect` | First | `$true` if the repository has the setup |
| `Answers` | Before Copier runs | A hashtable of answers, which beat what the script works out but not `-Data` |
| `Apply` | After Copier runs | Lines for the report; the script prints them and puts them in the commit message |

To handle another setup, add a script to `tools/adopt/legacy/`; nothing else changes.

| Adapter | Detects | Does |
|---|---|---|
| `NCode.ProjectSettings.Scaffold.ps1` | A project file referencing the `NCode.ProjectSettings.Scaffold` NuGet package | Answers `nuget_package`, `package_license` (`Apache-2.0`), `author_name` (`NCode Group`) and, when `NCodeGroup.png` is at the root, `package_icon`. Removes the package reference, whose settings `build/ProjectTemplate.props` now provides, and reports that its `GlobalAssemblyInfo.cs`, its license and copyright copies and its build-time release notes are gone. Lists any file still using a property the package defined |
| `HybridWorkflowInstall.ps1` | `.github/prompts/execute-step-copilot.prompt.md`, the name an older `Install-HybridWorkflow.ps1` used | Deletes it; the template's Copilot prompt is `execute-step.prompt.md` |

## Protect the Default Branch

A repository on GitHub should take changes only through pull requests, whatever its CI is. `tools/Set-RepositoryBaseline.ps1` gives a repository a "Protect main" ruleset on its default branch, the same shape as this repository's: no deletion, no force push, a pull request required with no approvals and every conversation resolved (a finding from the review bot, CodeQL or a person blocks the merge until it is resolved), merge-commit or rebase merges only (never squash, so each commit of a plan stays on the branch), where CodeQL's default setup is configured, a code-scanning rule that blocks a pull request whose CodeQL results add an alert at warning level or above or a security alert of any severity, no bypass; `-RequireChecks` adds the CI jobs a pull request must pass as required status checks, on a branch that is up to date with the default branch. Where it reads CodeQL's default setup as configured, it switches the setup to the extended query suite, before it writes the ruleset, so a refused switch changes nothing and the next run retries it. It also turns on delete-branch-on-merge.

It gives the repository a "Protect release tags" ruleset too, on the tags matching `v*`: no deletion and no update, so a release tag is never moved, with no bypass. A release tag names one published package set, so it never changes; creating one stays open, so `/ship-plan` can still tag a release. A ruleset of that name is left alone whatever its state, and so is an active tag ruleset on `v*` tags, or on every tag, that already refuses both deletion and update.

It then turns on the security settings a public project should have, each where it is off: the workflow token (`GITHUB_TOKEN`) read-only by default, with GitHub Actions not allowed to approve pull requests; secret scanning and its push protection; Dependabot alerts and Dependabot security updates, which need the alerts; and private vulnerability reporting. Each is read first and reported as set, already set, would set (with `-WhatIf`) or not available, with the reason, and none costs money: secret scanning and its push protection are left out of a repository that isn't public, where they need the paid GitHub Secret Protection. A setting the API won't read or refuses to change, such as private vulnerability reporting on a private repository, or a token setting the organization decides, is reported, and the run goes on with the next one. Requiring actions to be pinned to a full-length commit SHA is left out: it fails every workflow that names an action by tag, which an adopted repository's workflows may.

- **A new repository:** `New-Project.ps1 -CreateRemote` runs it for a GitHub repository after the first push, requiring the template's `build-and-test` and `Commit attribution` jobs. `-NoBaseline` skips it. If it fails, the repository exists and the script says how to run it again.
- **An adopted repository:** `Adopt-Project.ps1` only commits locally, so it prints the command to run, with the same `-RequireChecks` when the repository's CI is the template's and, when it isn't, a reminder to pass `-RequireChecks auto` or name its own jobs.
- **A repository that is protected already** (an active ruleset on the default branch that requires pull requests) keeps that ruleset, and so does one with the "Protect main" ruleset an earlier run made; both still get the release tags ruleset and the security settings, so running the script again brings a repository protected by an older version up to date. `-WhatIf` shows what the script would do, and `-All -Owner <owner>` covers every repository an owner has, except archived repositories and forks. A repository the script skips for its default branch, because CodeQL's default setup can't be read or `-RequireChecks auto` finds nothing to require, gets nothing else either. GitHub Free has no organization rulesets, so this applies them to each repository.
- Name only jobs that run on pull requests with `-RequireChecks`: a job that runs on a release or a schedule never reports on a pull request, and requiring it would block every merge.
- **`-RequireChecks auto`** names them for you. It reads the check runs on the head commit of the latest pull request merged into the default branch, which it finds among every closed pull request, and requires the GitHub Actions jobs that ran there for the `pull_request` event and passed. It leaves out, with the reason, the review bot's advisory `Code review` and its `pull_request_target` job, `CodeQL` (the code-scanning rule covers it) and its Analyze jobs, checks other apps report, and anything skipped, neutral, failed or unfinished, since a skipped required check counts as passing. The template's `Commit attribution` job is required this way wherever it passed on that pull request. A repository with no merged pull request, or no check to require, is skipped with the reason and nothing changes. With `-WhatIf` it lists the checks and prints the command that names them, to trim and run (a job whose name has a comma is listed apart, since `-RequireChecks` would split it); `-All -RequireChecks auto` reads each repository's own pull request. The list comes from one pull request, and every run says so: a job whose workflow has `paths` or `branches` filters reports nothing on a pull request the filters skip, and that pull request can't merge, so run `-WhatIf` first and leave such jobs out.

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

A project on v0.8.0 or earlier doesn't hand over: its script can't read the newer copy from a template cloned over a URL, so it runs its own, older logic — it prints Copier's raw "Make sure Git >= 2.24 is installed" warning and no "Handing the update over" line — and installs the newer script for the next update ([CHANGELOG.md](CHANGELOG.md#090---2026-10-25)). To run the newest logic on that first update, run the wrapper from a clone of this repository: `git clone https://github.com/polewskm/project-template.git`, then `.\Update-Project.ps1 -Path <project>` in that clone.

| File | On update |
|---|---|
| Template-owned | Replaced by the new version; files the template added are created, and files it removed are deleted. A local edit is discarded and a deleted file restored, and the script lists both, so the change can move into a project file |
| Merged | The template's changes since the project's version merge with the project's edits. Only the same lines changed on both sides conflict. A merged file the project deleted stays deleted. A merged file the project seems to have replaced, sharing less than half its lines with the template's, gets a suggestion to make it project-owned. |
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

When the project has version tags merged into the current branch that its changelog has no section for, such as releases from before it had a changelog, the update ends with a request to backfill them:

```text
Version tags without a section in CHANGELOG.md: v0.1.0..v0.3.0. To give the changelog the project's full release history, in the repository, run:
  /plan-migration Backfill CHANGELOG.md from the releases v0.1.0..v0.3.0
```

To plan an update instead of running it, run `/plan-template-update` in the project, or name a version: `/plan-template-update v0.14.0`. It reads `.copier-answers.yml` and the release notes since the project's version, runs `Update-Project.ps1 -NoCommit` on a clone of the project in a temporary folder, and plans from what that trial changed. The plan's first step runs the update with `-Ref` pinned to the target and `-NoCommit`, so it is committed as a plan step, and a result that differs from the trial escalates. The next steps run the project's checks and fix the project's own files that still describe the old template, and the last runs the project's tests. Every check is judged by its exit code. The planning session files an issue here for each gap in the template that the trial shows. In Claude Code the plan gets its own worktree, unless the project's `plan-executor` subagent predates v0.11.0 and can't run PowerShell there; then it runs on a `build/project-template-<version>` branch in the current checkout. A project on v0.13.0 or earlier doesn't have the command yet: compose it from this repository's clone with `.\workflow\New-PlanPrompt.ps1 plan-template-update`, or install the commands for your user with `.\workflow\Install-HybridWorkflow.ps1 -User`.

### The Update Notice

A GitHub project gets `.github/workflows/template-update.yml`, which runs `.template/Get-TemplateUpdate.ps1` every Monday at 07:00 UTC, and on demand from the Actions tab or with `gh workflow run template-update.yml`. It needs only the workflow's own `GITHUB_TOKEN`, with `contents: read` and `issues: write`. The script reads the project's version from `.template-version`, lists the template's tags at `_src_path` in `.copier-answers.yml` with `git ls-remote`, and takes the newest `vX.Y.Z`, as `Update-Project.ps1` does. While the project is behind, it keeps one open issue labeled `template-update` (it creates the label the first time): it opens "Update to project-template v0.42.0" with the `CHANGELOG.md` sections after the project's version up to that tag, read at that tag; a later run edits that same issue, retitling it and rewriting its text when a newer version comes out, and leaves it alone when nothing changed. A section that doesn't fit in an issue is left out, with a link to the changelog. Once the project is on the newest version, the next run closes the open issue with a comment; with no open issue it does nothing. `/plan-issue` on that issue plans the update with `/plan-template-update`'s instructions, so `/triage-issues` and `/run-issues` send it there too. The script rewrites the issue's text, so put notes in comments. To stop the notices, disable the workflow: `gh workflow disable template-update.yml`. The file is template-owned, so deleting or editing it lasts only until the next update. A template that the workflow's token can't read, such as a private one, fails the run.

### The Template's Address

A project records where its template came from in `.copier-answers.yml` (`_src_path`). The template moved from `polewskm/project-template` to `NCodeGroup/project-template`. GitHub redirects the old address, but only while nobody creates a repository at it, so the update script moves a project over: when `_src_path` is `https://github.com/polewskm/project-template.git`, it changes that one line to `https://github.com/NCodeGroup/project-template.git`, clones from there, and commits the change with the update, even when the project is already at the newest version. A project on an older script gets this with the update that hands over to the newer one ([Update a Project](#update-a-project)).

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
| `.githooks/commit-msg` (here, `template/.githooks/commit-msg`) | Anything that slips through, from any tool. Git runs a hook only once a clone enables it: `New-Project.ps1`, `Adopt-Project.ps1` and `Update-Project.ps1` run `git config core.hooksPath .githooks` in the clone they work in when Git has no hooks path for it. They never change one it has, such as husky's or a global one: they warn instead, naming `git config core.hooksPath .githooks` and how to call the template's hooks from that folder. A clone with hooks in `.git/hooks`, which a hooks path would turn off, gets a warning that says how to run both; one that uses pre-commit gets a `repo: local` hook to add to `.pre-commit-config.yaml` (`entry: .githooks/commit-msg`, `language: script`, `stages: [commit-msg]`), and nothing once that file runs the hook. In a fresh clone of a project, run it yourself or update the project; the workflow commands that create a worktree or a branch for a plan, and the agent rules, check `git config core.hooksPath` and set it when nothing else runs hooks there. In a clone of this repository, run `git config core.hooksPath template/.githooks` |
| `.template/Test-CommitAttribution.ps1` (here, `template/.template/`), run by the `Commit attribution` job in `ci.yml` or `.gitlab-ci.yml` | A commit authored, committed or co-authored by an AI agent, whoever made it and however: on every pull request, merge queue entry and push to the default branch. It reports; to make it block a merge, require the Commit attribution check in the repository's branch rules on GitHub, or turn on "Pipelines must succeed" on GitLab. On a squash merge it is the last chance to catch an agent's trailer, as below |

The hook removes only agent lines: `Co-authored-by:` trailers naming Copilot or an `@anthropic.com` or `Copilot@users.noreply.github.com` address, `Claude-Session:` trailers, and "Generated with Claude Code" lines. A person's co-author trailer stays. To clean commits that already have them, before pushing, enable the hook and amend every unpushed commit through it: `git rebase origin/main --exec "git commit --amend --no-edit --allow-empty"`.

The check fails with the commits it found and the command that fixes them: `git rebase <base> --exec "git commit --amend --no-edit --reset-author"`, then `git push --force-with-lease`. The Copilot cloud agent authors its own commits, so its pull requests fail until they are re-authored this way.

Never merge a pull request while the check fails, least of all by squashing. GitHub's squash merge copies the co-author trailers of every commit on the branch into the one commit it puts on the default branch, so an AI agent trailer from a clone that didn't run the hook lands there, and only a force-push to the default branch could take it out again. Requiring the check, as `Set-RepositoryBaseline.ps1 -RequireChecks` does ([Protect the Default Branch](#protect-the-default-branch)), makes the merge wait for it.

## Stay Current

A project pins exact versions so that a build today matches a build next month: each package, each CI action (by commit SHA), the .NET SDK in `global.json`, and the template version in `.template-version` (from `_commit` in `.copier-answers.yml`). Pinned versions never update themselves; something has to notice each new upstream release and change the pin.

| What goes stale | How it's kept current |
|---|---|
| A GitHub project's CI actions, packages and .NET SDK | Dependabot, built into GitHub: `.github/dependabot.yml` turns it on, with nothing to install or sign up for. Each week it opens a pull request for newer versions that are at least three days old (its cooldown) — every update of one kind together, and security updates in a pull request of their own per ecosystem — which CI tests and you merge. Dependabot doesn't offer a new .NET SDK major: moving the target frameworks to a new .NET major version is a planned migration, `/plan-migration` |
| A GitLab project's packages | By hand; GitLab has no free built-in equivalent. Its CI images use floating tags such as `python:3`, so they follow upstream on their own |
| A project's template-owned files | [`.template\Update-Project.ps1`](#update-a-project), run in the project. `copier check-update`, run there too, tells whether a newer tag exists. On GitHub, the weekly `template-update` workflow opens an issue when one does ([The Update Notice](#the-update-notice)) |
| A repository or user profile with only the workflow installed (`workflow\Install-HybridWorkflow.ps1 -Repo` or `-User`) | By hand: re-run the installer from a clone at the newest tag. The version it has is in `.template-version` — at the repository root, or in `~\.claude\` and `~\.copilot\` for the profile |
| This template's generated workflow files | `tools/Update-Template.ps1` regenerates them from `workflow/templates`; `tests/Test-Template.ps1` fails when they're behind |
| This template's own CI actions, in `.github/workflows/test-template.yml` | Dependabot in this repository |

The pins inside `template/` — the actions in `ci.yml.jinja` and the SDK in `global.json` — are in merged files, which each project's Dependabot keeps current on its own. A template release that moves the same pin to a different version conflicts on that line (keep the newer version), so change a pin in the template only when you change that step anyway, or to keep new projects from starting far behind. The checkout pin in `template-update.yml` is in a template-owned file instead: when a project's Dependabot moves it, the next update lists the file under its discarded local edits and puts back the template's pin, so keep that pin current here.

## Change the Template

1. Edit the base files under `template/`: `*.jinja` files are rendered with the answers, every other file is copied as is. A file name such as `{% if stack == 'dotnet' %}global.json{% endif %}` makes the file conditional. A new file is template-owned unless `copier.yml` lists it under `_merged_files` or `_skip_if_exists`. Keep a file template-owned whenever its tool can include a second, project-owned file; list it under `_merged_files` when it can't. A question that a later version adds must be read through a default wherever `copier.yml` uses it before the question is answered — the `_exclude` patterns read `workflow_tools | default([...])` — because an update renders the old version's files with the new `copier.yml` before the project has that answer; without the default an old project's update stops with conflicts. `tests/Test-Template.ps1` fails an `_exclude` pattern that excludes anything without the answer.
2. For the workflow commands, agents and prompts, edit the source templates in [workflow/templates](workflow/templates/), then run `.\tools\Update-Template.ps1` to regenerate their copies under `template/` and at the repository root.
3. Run `.\tests\Invoke-AllTests.ps1` (add `-SkipDotnetBuild` to skip the .NET build and pack) and confirm its last line reads `All tests: PASSED`. It runs every `tests\Test-*.ps1` suite, each in its own PowerShell process and up to one per processor at once (`-ThrottleLimit <n>` sets how many; `-Serial` runs one at a time), so a full run takes about as long as its slowest suite. Once all have finished it prints `PASS` or `FAIL` and the time for each, in name order, with a failed suite's `FAIL` lines and the path of its full log, then the run's wall-clock time as `Time: <m:ss>`, and exits 1 when any suite fails. To measure a change, `.\tests\Measure-Suites.ps1 -Name <suite>` times suites one at a time instead: `-Repeat <n>` prints the median of n runs, and `-MaxSeconds <s>` fails a suite slower than that.
4. Add the version's section to `CHANGELOG.md` in its Keep a Changelog format (`## [0.2.0] - <date>` below `## [Unreleased]`, entries under `### Added`, `### Changed`, `### Fixed` and the other groups, and the compare links at the end) and land the change through a pull request: this repository's `main` takes no direct pushes ([AGENTS.md](AGENTS.md)'s Landing section). Once it merges, tag the commit it merged as and push the tag: `git tag -a v0.2.0 -m v0.2.0 <commit>` and `git push origin refs/tags/v0.2.0`. Then publish the notes: `gh release create v0.2.0 --verify-tag --title v0.2.0 --notes-file <a file with the version's CHANGELOG.md section>`. For a planned change, the plan's last step writes these notes, and `/ship-plan` does the rest: it drops the empty plan commits, pushes the branch and opens the pull request, and, run again after the merge, tags, publishes the release, files the plan's follow-ups as issues and closes the issue.

`tests/Test-Template.ps1` works on a tagged snapshot of the working tree, without Claude Code's worktrees, in the temp folder. Each suite works in a folder of its own there, named for the suite and its process ID, such as `project-template-test-<PID>`, so two runs at once, from two worktrees or two sessions, don't collide; a run that passes deletes its folder through `tests/Remove-TestWork.ps1`, which says so when it can't, and one that fails, or stops with an error, keeps it and prints its path. `-Work` picks the folder instead, and leaves it in place (`tests/Test-CommitAttribution.ps1` deletes its folder at the end of every run). It, `tests/Test-TemplateDotnet.ps1`, `tests/Test-ProjectUpdate.ps1`, `tests/Test-ProjectUpdateHooks.ps1`, `tests/Test-Adoption.ps1`, `tests/Test-AdoptEdgeCases.ps1`, `tests/Test-AdoptOwnedFiles.ps1`, `tests/Test-UpdateIgnoredFiles.ps1`, `tests/Test-UpdateExitCode.ps1`, `tests/Test-UpdateKeptLines.ps1`, `tests/Test-UpdateOwnedFiles.ps1`, `tests/Test-UpdateRewrittenFiles.ps1`, `tests/Test-PlanState.ps1`, `tests/Test-ChangelogBackfill.ps1`, `tests/Test-CommitAttribution.ps1`, `tests/Test-TemplateUpdate.ps1`, `tests/Test-GitHooks.ps1`, `tests/Test-RepositoryBaseline.ps1`, `tests/Test-ScriptAnalyzer.ps1` and `tests/Test-InvokeAllTests.ps1` run on every push to `main` and every pull request through `.github/workflows/test-template.yml`:

| Check | For |
|---|---|
| Common files present | Every stack, on GitHub and GitLab |
| .NET layer present, or absent | .NET, or every other stack |
| NuGet package settings in `build/ProjectTemplate.props` only with `nuget_package` | .NET |
| The analyzers, banned APIs and test-project suppressions in the build settings, the banned API analyzer in `Directory.Packages.props`; `LICENSE.txt`, `COPYRIGHT.txt`, `NCodeGroup.png`, the C# file header and the library decisions for the license and icon answered; CI's NuGet cache and test-result artifacts, and for a library its package artifacts; `publish.yml` only for a library on GitHub, on a published release, packing only a tag whose commit the default branch holds, with no permission by default, trusted publishing in the `nuget` environment and every action pinned to a full commit SHA with its tag in a comment | .NET, and .NET libraries under MIT with their own icon and under Apache-2.0 with the template's |
| The null-forgiving operator banned outside test projects, the public API tracked and `AssemblyVersion` pinned only for a library, `AGENTS.md` naming the Definition of Done as the gate, CI running `build/dod.ps1` for the default commands, and CI checking the decision index | .NET on GitHub and GitLab; the decision index for every stack |
| A probe that calls every banned method and property overload fails the build with RS0030 on each call, and every banned entry is a documentation ID with a message; `!` fails the build with NX000x; `build/dod.ps1` passes on the root solution. For an Apache-2.0 library: `build/Update-PublicApi.ps1` records a new project's API, `build/dod.ps1` packs it with its symbols, an unrecorded public type fails with RS0016, and version 2.5.0-rc.1 builds as `AssemblyVersion` 2.0.0.0 with `FileVersion` 2.5.0 | .NET, in `tests/Test-TemplateDotnet.ps1` (skip with `-SkipDotnetBuild`) |
| The CI file for the `git_host` answer, with its `Commit attribution` job, a concurrency group that never cancels a default-branch commit's run, a timeout on every job and every action pinned to a full commit SHA, and `.github/dependabot.yml` (grouped, with a security-update group per ecosystem and only the .NET SDK's majors ignored), `.github/workflows/copilot-setup-steps.yml` only on GitHub with Copilot, with its one `copilot-setup-steps` job, a 59-minute timeout and only `contents: read`, and `.github/workflows/template-update.yml` on GitHub only; the update notice workflow runs weekly and on demand with only `contents: read` and `issues: write`, and pins each action to a full commit SHA with its tag in a comment | Every render |
| CI sets up and installs with the `package_manager` answer, the default commands run it and no other manager, and Dependabot uses its ecosystem | Node.js with npm, pnpm, Yarn and Bun, on GitHub and GitLab |
| LF line endings, no leftover Jinja, valid JSON, valid YAML | Every rendered file |
| Workflow files, editor settings, `.gitignore`, `AGENTS.md`, the template rules and `README.md` only for the chosen `workflow_tools` | Every render |
| `.copier-answers.yml` and `.template-version` record the version | Every render |
| Every `_exclude` pattern excludes nothing when `workflow_tools` is missing | Always |
| Every `tests/Test-*.ps1` script has a `run: ./tests/<name>` line in the matrix of `.github/workflows/test-template.yml`, so CI runs it | Always |
| Generated workflow files, under `template/` and at the repository root, match a fresh run of `workflow\Install-HybridWorkflow.ps1` | Always, including CI |
| The installer writes both variants for every tool; `New-PlanPrompt.ps1` composes a prompt; `Invoke-PlanSteps.ps1 -DryRun` parses the example plan | Always |
| The installer writes the template version to `.template-version` at the repository root; `template/` and this repository's root have no installer-written copy | Always |
| Every executor — the Copilot Implementer, the `execute-step` prompt, and the Copilot CLI and Claude Code `plan-executor` agents — runs on Claude Sonnet 5.5 | Always |
| Claude Code's planning commands create the plan's worktree, and the commands that execute, re-plan or review a plan move into it; no Copilot file, `plan-executor` subagent or analysis command enters a worktree | Always |
| `New-Project.ps1` passes a list answer in `-Data` to Copier | Always |
| `New-Project.ps1` and `Update-Project.ps1` enable `.githooks`, with `commit-msg` executable, keep a hooks path Git already has and warn with the command to run; the hook strips Claude and Copilot attribution and keeps a person's co-author trailer, and keeps a prose line that mentions the advertising phrase | Always; the update check in `tests/Test-ProjectUpdateHooks.ps1` |
| The shipped `.template/Test-CommitAttribution.ps1` passes on a new project's own history | Always |
| `dotnet new classlib` and `xunit`, added to a root solution, pass the default `dotnet build` and `dotnet test` under `Directory.Build.props` and `global.json` | .NET, in `tests/Test-TemplateDotnet.ps1` (skip with `-SkipDotnetBuild`) |
| A project's own `.template\Update-Project.ps1` hands the update over to the new version's script; it replaces template-owned files, discards and reports an edit to one, and restores a deleted one; merges a merged file, keeping the project's edit, and keeps a deleted one deleted; leaves project-owned files untouched and shows the template's changes to them, leaving out those the project already has; deletes and adds files as the template did; makes one commit, and changes nothing on a second run. On a same-line change to a merged file it stops with exit code 1, commits nothing, still replaces the template-owned files, and finishes once the conflict is resolved. The root wrapper updates another project by `-Path` | A Python project, in `tests/Test-ProjectUpdate.ps1`; the root wrapper on a Node.js project, in `tests/Test-ProjectUpdateHooks.ps1` |
| `tests/Test-Adoption.ps1`: the adoption functions and legacy adapters on small inputs; adopting a Python repository on GitLab and a .NET repository built on the NCodeGroup scaffold — answers worked out, merged files rebuilt, `AGENTS.md` and `Directory.Build.props` extended, versions moved into `Directory.Packages.props`, follow-ups reported, a repository's own changelog left as it is, with a follow-up to convert one that isn't Keep a Changelog and one to backfill the version tags it has no section for, the report naming only the follow-ups the repository really has, the package packed with README, icon and license, and a later template update merging cleanly | Always (`-SkipDotnetBuild` skips the .NET build and pack) |
| `tests/Test-AdoptEdgeCases.ps1`: adopting the fixture repositories that `tests/Test-Adoption.ps1` leaves out, in a suite of its own so a parallel run ends sooner — a failure after Copier rolling the repository back, a hooks path and a `ci.yml` of the repository's own kept, with a warning that names the command to run and no follow-up to reconcile `ci.yml`, a catch-all `.gitattributes` text rule left out and a partial SDK version in `global.json` replaced, Copilot agents without Hybrid ones leaving out the local model's files, a failing build committing nothing, and a Node.js repository without build or test scripts committing without running a command, with CI installing through the package manager `package.json` names | Always |
| `tests/Test-AdoptOwnedFiles.ps1`: adopting a repository with `-Data @{ project_owned_files = '.github/workflows/ci.yml' }` keeps its own `ci.yml` unchanged and records the answer, a later update shows the template's change to it instead of merging it, and naming a file that isn't merged stops the adoption before it changes anything | Always |
| `tests/Test-UpdateIgnoredFiles.ps1`: a .NET project whose own `.gitignore` ignores a `node_modules` folder that the template's `.gitignore` doesn't updates without overflowing Windows' command line (WinError 206); `.git/info/exclude` ends as it was, without the copy of the project's rules that a killed update left behind, both after a clean update and after one stopped by a conflict | Always |
| `tests/Test-UpdateExitCode.ps1`: a project's own `.template\Update-Project.ps1`, run with `&`, exits 0 after staging an update with `-NoCommit` that shows a template change to a project-owned file, and after a run with nothing to update, and asks to backfill the changelog from a tag it has no section for | Always |
| `tests/Test-UpdateKeptLines.ps1`: an adopted `stack: other` project whose `.gitignore` ends with `secrets/` and the block kept at adoption takes the template's change to `/secrets/` without a conflict, still ends with the kept block, and changes nothing on a second run; when its own edit conflicts with that change, the conflict ends before the kept block | Always |
| `tests/Test-UpdateOwnedFiles.ps1`: a project whose `project_owned_files` answer names its own `ci.yml` updates without touching it and is shown the template's change to it, while `.gitignore` still merges; the answer lasts across the update; naming a file that isn't merged stops the update before it changes anything; an empty list gives the file back to the merge | Always |
| `tests/Test-UpdateRewrittenFiles.ps1`: an update of a project that replaced its `ci.yml` prints the `-Data @{ project_owned_files = '.github/workflows/ci.yml' }` to run, one with a lightly edited `ci.yml` doesn't, and one whose version Copier can't render warns with Copier's error and says it skipped the suggestion | Always |
| `tests/Test-PlanState.ps1`: `workflow/Get-PlanState.ps1`, on fixture repositories with a local `origin`, reads a plan's header, steps, `Reviewed:` line and the Landing section of `AGENTS.md`, with each key's default, a value in backticks, a label with a space, a gate command with spaces, a pull-request format section, and a prelude that names a script in the repository, a command with arguments, or something that isn't one command, which it prints as `invalid`; counts commits ahead of and behind the default branch, and with `-NoFetch` leaves out commits pushed after the last fetch; lists the other plan worktrees; counts a merged GitHub pull request or GitLab merge request, read through stand-ins for `gh` and `glab`, as landed only when its merge commit is on the default branch and its head holds `HEAD` or has its tree, also when an older one merged under a newer open or closed one, and prints its merge commit on the `merge` line; names the base branch in `next` for a request merged into another branch, and `ship-plan` under `integrate: direct`; reads whether the default branch takes changes only through pull requests from a GitHub ruleset or branch protection, or a GitLab protected branch, through the stand-ins; reads every issue on a one-issue and a group plan's `Issue:` line through the stand-ins, with `issue-state` open while any is open, and the `Refs:` line apart from them, whose open issues keep no plan open; counts the follow-ups a plan hasn't filed, tracked or dropped, which send a merged plan back to `ship-plan` unless the Landing section says `follow-ups: none`; names the version a plan moves to when a newer tag on `origin` or the default branch's changelog, with `## v1.4.0` or Keep a Changelog `## [1.4.0] - <date>` headings, took its release, by a minor or a patch raise; reads the plan's tag as `local` when only the clone has it, which leaves its version free and ships a landed plan again, and as `unknown` when `origin` can't be read; prints the changelog's format, its newest release and the version tags merged into `HEAD` it has no section for; names the files that conflict when the default branch merges into the plan's branch, `none` when it merges cleanly and `unknown` when `git merge-tree` can't merge them, and `ship-plan` as the next command for an open pull request that conflicts; reports `protected: unknown`, not `no`, when GitHub's rules or GitLab's protection can't be read or the call fails with anything but not found; and names the next command for open, escalated, unreviewed, stale, reviewed, landed, tagged and dirty states | Always |
| `tests/Test-PlanStateConcurrency.ps1`: `workflow/Get-PlanState.ps1`, on a fixture repository under a `github.com` folder with a stand-in for `gh` that answers after a delay, starts its five `gh` calls at the same time: a run with a two-second delay takes less than the run without it plus seven seconds and prints the same lines, and a release tag only the fetch brings in is still read as published, and when the stand-in fails the protection check while the other calls wait a minute, the script fails with that error at once and leaves no runspace running a call it never received, and no run leaves a runspace open | Always |
| `tests/Test-ChangelogBackfill.ps1`: both copies of `Get-ChangelogBackfill`, in `.template/Update-Project.ps1` and `tools/adopt/Adoption.psm1`, name the version tags merged into `HEAD` that the changelog has no section for, read every release heading form, ignore a prerelease tag and a tag on another branch, and read the changelog the Landing section names | Always |
| `tests/Test-CommitAttribution.ps1`: the check every project gets fails on a commit authored or committed by an AI agent account, a co-author trailer naming one, a `Claude-Session:` trailer or Claude Code's advertising line (also when the console's code page isn't UTF-8), and passes a person's co-author trailer, Dependabot, a prose line that mentions the advertising phrase, and an unknown or empty base | Always |
| `tests/Test-TemplateUpdate.ps1`: `.template/Get-TemplateUpdate.ps1`, on a fixture template repository whose tags carry a fixture changelog and a stand-in for `gh`, says nothing and opens nothing when the project is current, also on a version between tags; one version behind, creates the missing label and opens one issue titled with the newest version, labeled `template-update`, with that version's section and nothing from `[Unreleased]`, the project's own version or the link definitions; changes nothing on a second run; three versions behind, edits and retitles that same issue, with the three sections newest first; closes it with a comment once the project is current; ignores tags that aren't versions; keeps a section that, with its two closing line breaks, brings the body to exactly 60,000 characters, and leaves out one a character longer; closes the notice for a project ahead of the newest tag; and fails on a template it can't read, or when a `gh` call fails, without reporting a change | Always |
| `tests/Test-GitHooks.ps1`: `.githooks/commit-msg` runs as a pre-commit `language: script` hook and strips the attribution; `.githooks/pre-push` refuses a push to `main` only while the Landing section says `protect: hook`, and lets a branch and a tag through; `Update-Project.ps1` and `Adopt-Project.ps1` enable `.githooks` only in a clone without hooks of its own, where a `.sample` hook doesn't count, print nothing when `core.hooksPath` already names `.githooks`, print the command to run for another hooks path, print how to run both for other hooks in `.git/hooks`, print the pre-commit hook to add when the clone uses pre-commit, and print nothing once `.pre-commit-config.yaml` runs the hook; under `protect: hook` they print the pre-push wrapper to add (or the call to add to a clone's own pre-push hook) until something runs it, and the wrapper as `pre-push.legacy` refuses a push to `main` under pre-commit; `Get-PlanState.ps1`'s `protected` line is `hook` under `protect: hook` with `core.hooksPath` on `.githooks` or the wrapper in `pre-push` or `pre-push.legacy`, and not with only pre-commit's pre-push hook or under `protect: none` | Always |
| `tests/Test-RepositoryBaseline.ps1`: `tools/Set-RepositoryBaseline.ps1`, on a stand-in for `gh` that records the calls of a `-WhatIf` run too, with `-WhatIf` changes nothing; gives a repository with no ruleset a "Protect main" ruleset on its default branch with no deletion, no force push, a pull request with no approvals and merge-commit and rebase merges only, no bypass, and delete-branch-on-merge; adds the required checks `-RequireChecks` names, passed as one comma-separated string; with `-RequireChecks auto`, requires the GitHub Actions checks that passed on the latest merged pull request, found on any page of closed pull requests, reading every page of its check runs and workflow runs, `Commit attribution` among them, leaves out `Code review`, CodeQL and its Analyze jobs, push-only jobs, jobs no workflow run accounts for, other apps' checks and skipped, neutral, failed or unfinished ones, lists them and a command that names them, quoted so it parses, curly quotes too, with `-WhatIf`, says in every run that they come from one pull request, gives each repository its own checks with `-All`, and skips a repository with no merged pull request or no check to require; leaves alone the ruleset of a repository whose default branch already requires pull requests or that already has the ruleset, and updates the ruleset it made when `-RequireChecks` is given; requires every conversation resolved and the required checks to pass on an up-to-date branch; adds the CodeQL code-scanning rule (warnings and above, security alerts of any severity) and the extended query suite where CodeQL's default setup is configured, even one that names no suite, and reports the repository as failed, with nothing else changed, when the switch is refused; keeps the rule on an update and leaves it out elsewhere; gives every repository it doesn't skip, one whose branch ruleset it leaves alone too, a "Protect release tags" ruleset on `v*` tags with no deletion, no update and no bypass, which `-WhatIf` shows, unless it has one of that name, whatever its state, or an active tag ruleset that refuses both already; turns on the read-only workflow token with Actions not approving pull requests, secret scanning, its push protection, Dependabot alerts, Dependabot security updates and private vulnerability reporting, in that order, each with the call and body the API takes and only where it is off, reports each as set, already set, would set or not available, leaves secret scanning out of a repository that isn't public, and reports a setting the API won't read or refuses without failing the run; skips archived repositories and forks with `-All`; and rejects missing and conflicting parameters | Always |
| `tests/Test-ScriptAnalyzer.ps1`: every `.ps1`, `.psm1` and `.psd1` file in the repository outside `.claude/worktrees/`, the scripts the template ships included, has no PSScriptAnalyzer warning or error under `PSScriptAnalyzerSettings.psd1`; a finding that can't be fixed is suppressed where it is, with a justification; and a control file with a known warning must be reported, and the same file under `.claude/worktrees/` must not, so a pass proves something | Always |
| `tests/Test-InvokeAllTests.ps1`: `tests/Invoke-AllTests.ps1` runs only the `Test-*.ps1` scripts in a folder, prints `PASS` or `FAIL` per suite with a failed suite's `FAIL` lines, logs each suite's output, counts a suite that throws as failed, passes `-SkipDotnetBuild` only to suites that take it, points the suites' Copier cache at the run's own folder, exits 1 when a suite fails or none is found, prints the run's wall-clock time as `Time: <m:ss>` and ends with `All tests: PASSED` or `All tests: FAILED (<n>)`; runs two suites at once and prints their results in name order, not the order they finish, and one at a time with `-Serial` or `-ThrottleLimit 1`; two runs at once without `-Work` log to folders of their own, deleted when the run passes or finds no suites and kept when one fails; `tests/Remove-TestWork.ps1` deletes a folder or says it couldn't; and every suite with `-Work` keeps a folder of its own on a failure, or on an error, when it prints its path, and deletes it on a pass; `tests/Measure-Suites.ps1` prints a suite's median time over `-Repeat` runs and fails the run for a suite that fails, is missing or is slower than `-MaxSeconds`, passing `-SkipDotnetBuild` to a suite that takes it | Always |
| `tests/e2e/Test-RunIssues.ps1 -SetupOnly`: the fixture project, its local GitHub-shaped `origin` and the `gh` stand-in, where the state script sees `host: github` and `protected: hook`, `origin` has NCode Review's `code-review.yml`, and the stand-in gives a new pull request its seeded review threads and records thread replies; the stand-in gives NCode Review's review of a push on the first read after it, and with `-Scenario max-rounds` the Landing section has `max-review-rounds: 1` | Always |
| `tests/e2e/Test-AddressFeedback.ps1 -SetupOnly`: the same fixture project with an open pull request from `add-farewell`, and one from `farewell;touch${IFS}pwned`, a branch name with shell characters that Git allows and the installed command refuses, whose items the stand-in serves to the installed `/address-feedback`'s own GraphQL query with each author's `authorAssociation`; its thread reply lands on the thread; the command mandates the reply openings the checks match; the checks on the replies accept a right decline and answer and refuse wrong ones; the stand-in refuses every command and GraphQL mutation it lists as forbidden, such as resolving a thread, dismissing a review, merging, marking ready, closing or editing the pull request and moving a branch; and the writer's and the stranger's claims hold on the branch | Always |
| The `Commit attribution` job checks this repository's own new commits with `template/.template/Test-CommitAttribution.ps1` | Every push to `main` and pull request |

`tests/e2e/Test-RunIssues.ps1` runs `/run-issues #1 wait:0` in headless Claude Code (`claude -p`, `--permission-mode bypassPermissions`) on a fixture project that `New-Project.ps1` makes from a snapshot of the working tree, with a bare `origin` in a `github.com` folder under `%TEMP%\project-template-run-issues-e2e` and a stand-in for `gh` (`tests/e2e/gh.ps1`), so it touches no real repository; it answers the run's one question by resuming the session, and checks the plan snapshot comment, the draft pull request that closes `#1`, the step commits on `origin` without the empty `Plan:` commit or AI attribution, the reviewed plan, and the fixed function. The fixture runs NCode Review, and the pull request opens with a seeded review: the run must fix NCode Review's blocker and reply `Autopilot: fixed in <commit>`, leave its nit and its finding on `.github/workflows/ci.yml` without a reply or a change, treat another bot's thread without the finding marker as data, and leave a `/review` comment unanswered. By default (`-Scenario minor-round`), NCode Review reviews the run's first push with a should-fix finding that asks only for another test of what `tests/Test-Greeting.ps1` already tests, and a nit: the run must give it no step and recommend the merge once, in an `Autopilot:` comment, with the open nits in the plan's `## Follow-ups`. `-Scenario max-rounds` sets `max-review-rounds: 1` and has no second review: the run must recommend the merge after its first round. Run both. It costs model usage (`-MaxBudgetUsd`, 30 by default, per `claude` call), so run it by hand after changing `/run-issues` or a command it runs; it needs Claude Code signed in, Copier and a Git identity. `Invoke-AllTests.ps1` doesn't run it; CI runs `-SetupOnly`, which builds and checks the fixture without a model. `-CheckOnly` checks an earlier run's fixture again.

`tests/e2e/Test-AddressFeedback.ps1` runs `/address-feedback #1` the same way, on the same fixture project under `%TEMP%\project-template-address-feedback-e2e`, with a pull request from `add-farewell` that adds `Get-Farewell`. The pull request has a review thread from a writer (`COLLABORATOR`) asking for a real fix, a top-level comment from a stranger (`NONE`) asking to change the CI workflow, a bot's review thread with a wrong finding, a question, and a thread already answered with `Autopilot:`. The test checks that only the writer's fix is pushed to `add-farewell`, never forced, and changes nothing outside `src/` and `tests/`; that the stranger's request gets an `ask`, the wrong finding a decline whose reason says `Get-Farewell` uses `$Name`, and the question an answer that only `tests/Test-Greeting.ps1` calls `Get-Farewell`, each starting with `Autopilot:`; that the answered thread gets no reply; and that nothing is resolved, merged, marked ready or edited, which the stand-in also refuses and records. It then runs `/address-feedback #2`, on a pull request from `farewell;touch${IFS}pwned`, resumes it once with a go-ahead, and checks that it stopped on the branch name: no worktree, push or comment, and no `pwned` file, which the name unquoted in a POSIX shell would create. Run it by hand after changing `/address-feedback` or a command it runs, as `Test-RunIssues.ps1` says. Both tests build their fixture with `tests/e2e/Fixture.ps1`.

## Publish the Template

Once, from this folder:

```powershell
git add -A
git commit -m "Create the project template"
git tag v0.1.0
gh repo create NCodeGroup/project-template --public --source . --remote origin --push
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
| `tools/adopt/` | `Adoption.psm1`, the functions `Adopt-Project.ps1` uses, and `legacy/`, one adapter per old setup it removes |
| `Update-Project.ps1` | Update a project by `-Path` from this clone: a wrapper around `template\.template\Update-Project.ps1`, the update script every project carries |
| `workflow/` | The single source of the workflow: prompt and agent templates, the installer, the prompt composer and the step runner ([workflow/README.md](workflow/README.md)) |
| `tools/Update-Template.ps1` | Regenerate the workflow files under `template/` and at the repository root from `workflow/templates` |
| `tools/Set-RepositoryBaseline.ps1` | Protect a GitHub repository's default branch with a pull-request-only ruleset and its release tags with a ruleset that refuses moving or deleting them, and turn on its security settings ([Protect the Default Branch](#protect-the-default-branch)) |
| `AGENTS.md`, `.claude/settings.json`, `.vscode/settings.json`, `.gitignore` | This repository's own agent instructions and settings: no AI attribution in commits ([Commit Attribution](#commit-attribution)), and Claude Code's worktrees ignored |
| `.claude/`, `.github/agents/`, `.github/prompts/`, `.github/skills/`, `.template/Get-PlanState.ps1` | This repository's own workflow: the same generated files as `template/` gets, committed so that working on the template with Claude Code or Copilot has `/plan-feature`, `/orchestrate-plan` and the rest on any PC that clones it. Never edit them; `tools/Update-Template.ps1` regenerates them |
| `tests/` | This repository's tests, one script per area: they find the repository root themselves, run from any folder, and CI runs them all, except the end-to-end tests in `tests/e2e/`, which it only sets up |
| `tests/Test-Template.ps1` | Render every stack and check the result |
| `tests/Test-TemplateDotnet.ps1` | Build, test and pack the rendered .NET projects |
| `tests/Test-ProjectUpdate.ps1` | Update a rendered project through two template versions, the second with a conflict |
| `tests/Test-ProjectUpdateHooks.ps1` | Check that an update keeps a hooks path a project already has, and update a project through the root wrapper |
| `tests/Test-Adoption.ps1` | Check the adoption functions and legacy adapters, then adopt a Python and a .NET test repository and update the first |
| `tests/Test-AdoptEdgeCases.ps1` | Adopt the other test repositories: a rollback, CI and a hooks path of their own, catch-all attributes, Copilot-only agents, a failing build, Node.js without scripts |
| `tests/Test-AdoptOwnedFiles.ps1` | Adopt a repository that owns a merged file, then update it |
| `tests/Test-UpdateIgnoredFiles.ps1` | Update a project whose own `.gitignore` ignores a large folder |
| `tests/Test-UpdateExitCode.ps1` | Check that a successful update exits 0 |
| `tests/Test-UpdateKeptLines.ps1` | Update an adopted project whose merged files end with the lines it kept |
| `tests/Test-UpdateOwnedFiles.ps1` | Update a project that owns a merged file it replaced |
| `tests/Test-UpdateRewrittenFiles.ps1` | Update a project that replaced a merged file without owning it |
| `tests/Test-PlanState.ps1` | Test the plan state script `/ship-plan` and `/continue-plan` run |
| `tests/Test-PlanStateConcurrency.ps1` | Test that the plan state script makes its network calls at the same time and stops the ones it never received when it fails |
| `tests/Test-ChangelogBackfill.ps1` | Test the check that names the version tags the changelog has no section for |
| `tests/Test-CommitAttribution.ps1` | Test the commit attribution check that every project gets |
| `tests/Test-TemplateUpdate.ps1` | Test the weekly template update notice every GitHub project runs |
| `tests/Test-GitHooks.ps1` | Test the commit-msg hook under pre-commit, the pre-push hook, and the note on enabling the hooks |
| `tests/Test-RepositoryBaseline.ps1` | Test the repository baseline script against a stand-in for `gh` |
| `tests/Test-ScriptAnalyzer.ps1` | Run PSScriptAnalyzer on every script and fail on any warning or error |
| `tests/Invoke-AllTests.ps1` | Run every test suite and print one line per suite |
| `tests/Measure-Suites.ps1` | Time the test suites it names, one at a time, against a limit |
| `tests/Test-InvokeAllTests.ps1` | Test the runner that runs every test suite |
| `tests/Remove-TestWork.ps1` | Delete a passing run's own work folder, or say it couldn't |
| `tests/New-TemplateSnapshot.ps1` | Build the tagged snapshot of the working tree that `tests/Test-Template.ps1`, `tests/Test-TemplateDotnet.ps1`, `tests/Test-ProjectUpdate.ps1`, `tests/Test-ProjectUpdateHooks.ps1`, `tests/Test-UpdateIgnoredFiles.ps1`, `tests/Test-UpdateExitCode.ps1`, `tests/Test-UpdateKeptLines.ps1`, `tests/Test-UpdateOwnedFiles.ps1`, `tests/Test-UpdateRewrittenFiles.ps1` and the end-to-end fixture in `tests/e2e/Fixture.ps1` render from and `tests/Test-Adoption.ps1`, `tests/Test-AdoptEdgeCases.ps1` and `tests/Test-AdoptOwnedFiles.ps1` adopt from |
| `tests/AdoptionFixtures.ps1` | The Git calls, fixture repositories and image `tests/Test-Adoption.ps1` and `tests/Test-AdoptEdgeCases.ps1` share |
| `tests/e2e/Test-RunIssues.ps1` | Run `/run-issues` end to end on a fixture project, by hand |
| `tests/e2e/Test-AddressFeedback.ps1` | Run `/address-feedback` end to end on a fixture pull request, by hand |
| `tests/e2e/Fixture.ps1` | The fixture project, environment and checks the end-to-end tests share |
| `tests/e2e/gh.ps1` | The `gh` stand-in the end-to-end tests put on PATH |
| `.github/workflows/test-template.yml` | Runs `tests/Test-Template.ps1`, `tests/Test-TemplateDotnet.ps1`, `tests/Test-ProjectUpdate.ps1`, `tests/Test-ProjectUpdateHooks.ps1`, `tests/Test-Adoption.ps1`, `tests/Test-AdoptEdgeCases.ps1`, `tests/Test-AdoptOwnedFiles.ps1`, `tests/Test-UpdateIgnoredFiles.ps1`, `tests/Test-UpdateExitCode.ps1`, `tests/Test-UpdateKeptLines.ps1`, `tests/Test-UpdateOwnedFiles.ps1`, `tests/Test-UpdateRewrittenFiles.ps1`, `tests/Test-PlanState.ps1`, `tests/Test-PlanStateConcurrency.ps1`, `tests/Test-ChangelogBackfill.ps1`, `tests/Test-CommitAttribution.ps1`, `tests/Test-TemplateUpdate.ps1`, `tests/Test-GitHooks.ps1`, `tests/Test-RepositoryBaseline.ps1`, `tests/Test-ScriptAnalyzer.ps1` and `tests/Test-InvokeAllTests.ps1` and sets up the end-to-end fixtures with `tests/e2e/Test-RunIssues.ps1 -SetupOnly`, also with `-Scenario max-rounds`, and `tests/e2e/Test-AddressFeedback.ps1 -SetupOnly` on Linux, each in a parallel job, longest first, that a final `test` job, the check the ruleset requires, passes only when all of them pass, and checks this repository's commit attribution, for every push to `main`, every pull request and every merge queue entry; a newer push to a pull request cancels the older push's run |
| `.github/dependabot.yml` | Dependabot for the actions in `test-template.yml` |
| `PSScriptAnalyzerSettings.psd1` | The PSScriptAnalyzer rules this repository's scripts leave out, each with its reason |
| `LICENSE` | The MIT license this repository is published under; projects made from it don't get it and choose their own |
| `CONTRIBUTING.md`, `SECURITY.md` | How issues and pull requests reach this repository, and how to report a vulnerability privately; projects don't get them either |
| `USAGE.md` | Setting up a PC for Claude Code and GitHub Copilot, and using and switching between them in a project |
| `.gitattributes` | Keeps every file LF on disk, because Copier copies non-`.jinja` files byte for byte |

---

**TL;DR:** `.\New-Project.ps1 -Path C:\src\<name> -CreateRemote` creates a project with `AGENTS.md`, `CLAUDE.md`, Claude Code permissions, the plan-then-execute commands and agents for Claude Code, Copilot Chat and Copilot CLI — switch between your Claude and Copilot plans at any time — CI, Dependabot, and optional .NET settings, then creates its repository on GitHub, public, and pushes. Add `-Visibility private` for a private repository; answer GitLab to the host question (or pass `-Data @{ git_host = 'gitlab' }`) for GitLab. Every file has one of three owners: template-owned files are replaced on every update and never edited; merged files — settings whose tools can't include a second file — take the template's changes merged with the project's edits; and project-owned files, including the `AGENTS.md` index, are never touched. `.\.template\Update-Project.ps1`, run in a project, updates itself to the newest version first, then does all three and commits, or stops on a same-line conflict in a merged file. Dependabot keeps each GitHub project's actions, packages and SDK current through weekly pull requests. Change the workflow in `workflow/templates`, run `tools/Update-Template.ps1` and `tests/Test-Template.ps1`, then tag and push; this repository is its single source of truth. `.\Adopt-Project.ps1 -Path <repository>` brings an existing repository under the template.
