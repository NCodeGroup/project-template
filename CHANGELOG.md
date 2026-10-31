# Changelog

What each template version changes for the projects made from it. A project moves to a version with `.\.template\Update-Project.ps1`.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Every PowerShell script in the repository, the ones the template ships included, passes PSScriptAnalyzer with warnings treated as errors: `tests/Test-ScriptAnalyzer.ps1`, which CI runs with the other suites, fails on any finding. `PSScriptAnalyzerSettings.psd1` leaves out four rules that don't fit these scripts (Write-Host in interactive scripts, singular nouns, ShouldProcess on internal helpers, and a BOM PowerShell 7 doesn't need), each with its reason; the few findings that are false positives are suppressed where they are, with a justification.
- A new `/address-feedback` command takes every open comment and discussion on one pull request, from anyone or any bot: review threads, top-level comments and review summaries. It judges each against the code as a fix, a decline with its reason, an answer, a question for the maintainer or nothing to do, plans and executes only the fixes in a worktree, pushes them to the pull request's branch (never forced) and replies to each item starting with `Autopilot:`. Only authors who can write to the repository, bots and authors named with `only:` can make an item a fix; a request from anyone else is answered, declined or put to the maintainer. It never merges, resolves a thread, dismisses an alert or edits the pull request. Claude Code only.
- `Get-PlanState.ps1` prints `changelog-duplicates`: each Keep a Changelog heading (`### Added`, `Changed`, `Deprecated`, `Removed`, `Fixed` or `Security`) that a section of the changelog has more than once, such as `[Unreleased] Changed`, or `-`. Two pull requests that each add the same heading to `## [Unreleased]` merge without a conflict and leave it twice; a plan's changelog step now merges such headings in `## [Unreleased]` into one. This repository's CI checks its own `CHANGELOG.md` the same way with `tests/Test-ChangelogHeadings.ps1`, which fails naming the section and the heading. Projects get it with `.\.template\Update-Project.ps1` ([#132](https://github.com/NCodeGroup/project-template/issues/132)).
- A `prelude` key in `AGENTS.md`'s `## Landing` section names one PowerShell command that sets up the shell the workflow's commands run in, such as `prelude: ./build/env.ps1`, a script in the repository that puts Node installed through nvs on `PATH`. `/ship-plan`, and `/run-issues` and `/address-feedback` through it, dot-source it before the gate in the same PowerShell; the executors, `/orchestrate-plan`, `/replan-step`, `/review-plan-diff` and `workflow/Invoke-PlanSteps.ps1` run it before each Done-when command, from the plan's new `- Prelude:` line under Context for the executor, which the planners write instead of a `PATH` guard in every step. When it fails, they stop and show its error. `Get-PlanState.ps1` prints it on its `landing` line, as `prelude=invalid` when it isn't one command on one line without a `#` comment (a script in the repository, written as `./<path>.ps1`, that exists, or another command with its arguments), and `/ship-plan` stops on it; `workflow/Invoke-PlanSteps.ps1` checks the plan's `- Prelude:` line by the same rule. The default, `prelude: none`, runs nothing ([#138](https://github.com/NCodeGroup/project-template/issues/138)).

### Changed

- The changelog rules that the plans and `/ship-plan` follow say that a section has at most one of each heading: an entry goes under its group's heading when the section already has one, including when a merge combines two sides' changes to the changelog; it never goes under a second heading of the same name ([#132](https://github.com/NCodeGroup/project-template/issues/132)).
- This repository's CI (`test-template.yml`) also runs for merge queue entries, and its commit attribution check reads a merge queue entry's base and head, so its required checks report there too.
- `tools/Set-RepositoryBaseline.ps1` adds a code-scanning rule to the "Protect main" ruleset it creates when CodeQL's default setup is configured for the repository: a pull request whose CodeQL results add an alert at warning level or above, or a security alert of any severity, can't merge. Without CodeQL results every pull request would wait for them, so a repository without the default setup gets no rule, and the script says so. It switches a configured default setup to CodeQL's extended query suite, one that names no suite included, before it writes the ruleset, and reports the repository as failed, with nothing else changed, when the switch is refused, so the next run retries it.
- The "Protect main" ruleset that `tools/Set-RepositoryBaseline.ps1` creates lets nothing merge past feedback or a stale check: every conversation on a pull request must be resolved, and the required checks must pass on a branch that is up to date with the default branch.
- The `code-review.yml` a project gets pins `NCodeGroup/code-review` to the full commit SHA of v0.3.1, with the tag in a comment (it pinned the tag v0.1.0), and no longer checks out the pull request's head: from v0.3.0 the engine fetches the exact commit itself, so CodeQL no longer reports the workflow (two alerts, "checkout of untrusted code in a privileged context" and its TOCTOU variant, on every repository that adopted the bot). Rule checks run on by default, and there is an infrastructure reviewer for OpenTofu and Terraform changes. A SHA is the one pin CodeQL's extended suite accepts, and Dependabot updates the SHA and the comment together. A project that already has the file keeps its own; update it the same way.
- The pre-push rule in `project-template.instructions.md` and the `/run-issues` branch check for Copilot now say that `git ls-remote --exit-code` exits 2 only when the branch is absent, and that any other exit stops, because `origin` could not say. `Update-Project.ps1` notes that its changelog backfill is a deliberate copy of `Get-PlanState.ps1`'s.
- No change for projects made from the template. A new end-to-end test, `tests/e2e/Test-AddressFeedback.ps1`, runs `/address-feedback` in headless Claude Code on a fixture pull request with a writer's request for a real fix, a stranger's request to change the CI workflow, a bot's wrong finding, a question and a thread already answered with `Autopilot:`. It checks that only the writer's fix is pushed, never forced; that the stranger's request becomes an `ask` and the wrong finding a decline with its reason; that the answered thread is left alone; and that nothing is resolved, merged or edited. It costs model usage, so it runs by hand; CI runs its fixture setup with `-SetupOnly`. It shares its fixture with `Test-RunIssues.ps1` through `tests/e2e/Fixture.ps1`, and the `gh` stand-in now serves review threads with each author's `authorAssociation`, records thread replies, and refuses resolving a thread, closing a pull request and the commands a test forbids ([#133](https://github.com/NCodeGroup/project-template/issues/133)).
- The commands that create a plan's worktree or branch (Claude Code's planning commands, `/run-issues` and `/address-feedback`) and `/orchestrate-plan` check `git config core.hooksPath`, and run `git config core.hooksPath .githooks` when nothing runs hooks in the clone; the rules in `project-template.instructions.md` tell every agent to do the same before its first commit in a clone or worktree. The rules, the README and USAGE also say that a squash merge carries the co-author trailers of every commit on the branch into its one commit on the default branch, so the pull request's `Commit attribution` check is the last chance to catch one ([#131](https://github.com/NCodeGroup/project-template/issues/131)).
- The template's `dependabot.yml` gives every entry a three-day cooldown (`cooldown: default-days: 3`), so a version published minutes ago no longer lands in the weekly pull request; Dependabot offers it once it is three days old. New projects get the file as it is; a project that already has it gets the change merged into its own ([#125](https://github.com/NCodeGroup/project-template/issues/125)).

### Fixed

- `Get-PlanState.ps1` reports `protected: unknown`, not `no`, when GitHub's rules or GitLab's protection can't be read, or the call fails with anything but not found (HTTP 404), so a branch that does require pull requests is never reported as unprotected ([#125](https://github.com/NCodeGroup/project-template/issues/125)).
- The scripts the template ships say why they ignore a failure to set the console's encoding, with a verbose message, instead of an empty `catch`; `Update-Project.ps1` and `New-Project.ps1` run `git` before the condition that tests its output, which the analyzer read as a misused redirection when it ran inside it; `Get-PlanState.ps1` no longer keeps a pull request head it never reads.
- `tools/Set-RepositoryBaseline.ps1`: its examples showed a tab where `.\tools\` belongs, and its inner function now declares the `-WhatIf` support it uses.
- `Update-Project.ps1` and `Adopt-Project.ps1` said nothing when a clone already had a hooks path of its own, such as husky's or a global one, so `.githooks/commit-msg` never ran there and an AI agent's co-author trailer could reach a pull request unnoticed. They keep that hooks path and warn, naming `git config core.hooksPath .githooks` and how to call the template's hooks from it, and every note about hooks they can't enable is now a warning. `New-Project.ps1` no longer overrides a global hooks path either, and warns the same way. Projects get it with `.\.template\Update-Project.ps1` ([#131](https://github.com/NCodeGroup/project-template/issues/131)).
- No change for projects made from the template. Two runs of this repository's tests at once, from two worktrees or two sessions, no longer delete each other's work. Each `tests/Test-*.ps1` suite and `tests/Invoke-AllTests.ps1`'s logs default to a folder of the run's own in the temp folder, named for the suite and its process ID (`project-template-test-<PID>` for `Test-Template.ps1`), instead of one fixed folder. A run that passes deletes it through the new `tests/Remove-TestWork.ps1`, which prints the path of a folder it can't delete; one that fails keeps it and prints its path. `-Work` picks the folder as before and leaves it in place ([#130](https://github.com/NCodeGroup/project-template/issues/130)).
- `/ship-plan` passes the titles it takes from `PLAN.md` to `gh` and `glab` from a file, as `(Get-Content -Raw <title file>).Trim()`, instead of in double quotes, where PowerShell expanded `$(...)` and backtick sequences; a title can come from an issue someone else wrote ([#125](https://github.com/NCodeGroup/project-template/issues/125)).
- `.template/Update-Project.ps1` warns, with Copier's error, when Copier can't render a template version, and says it skipped the suggestion of rewritten merged files for `project_owned_files`, instead of reporting none ([#125](https://github.com/NCodeGroup/project-template/issues/125)).
- A project's files call `Adopt-Project.ps1` the template's, since a project has no copy: the changelog-backfill paragraph of every planning command and `project-template.instructions.md`, and a comment in `Update-Project.ps1`, whose comment above `Get-ChangelogBackfill` also names `.template/Get-PlanState.ps1`, where a project has it ([#125](https://github.com/NCodeGroup/project-template/issues/125)).

## [0.41.1] - 2026-10-30

### Fixed

- `Adopt-Project.ps1` no longer lets a repository's catch-all text rule in `.gitattributes`, such as `* text eol=lf`, override the template's binary rules. The repository's lines are appended after the template's, and Git uses the last rule that matches, so such a rule turned an image into text and the adoption commit rewrote its CRLF header byte, corrupting it. The adoption leaves those rules out of the lines it keeps and says so in its report.
- `Adopt-Project.ps1` replaces a `global.json` whose SDK version is partial, such as `10.0.0`, and that sets `rollForward`, with the template's. The template's CI reads `global.json` with `actions/setup-dotnet`, which rejects that combination ("a full SDK version is required"), so the adopted repository's first `build-and-test` run failed although the adoption's own build and test passed. The report says when it did.
- `Adopt-Project.ps1` no longer asks to reconcile `.github/workflows/code-review.yml` with `ci.yml`. The review workflow is separate from CI by design.

### Changed

- The template's `dependabot.yml` groups every update of an ecosystem, major ones included, in one pull request, instead of only minor and patch updates. Each major update used to open a pull request of its own, so a repository that adopted the template got ten or more at once, as Dependabot began to run on merge. New projects get the file as it is; a project that already has it keeps its own, as a merged file, and can drop the `update-types` lines.

## [0.41.0] - 2026-10-30

### Added

- A `code_review` question, asked only for a GitHub project and off by default. Answering yes adds `.github/workflows/code-review.yml`, which reviews each pull request with the NCode Review bot ([NCodeGroup/code-review](https://github.com/NCodeGroup/code-review)): it runs from the default branch on `pull_request_target`, in the `code-review` environment, with no permissions by default and `persist-credentials: false` on both checkouts, and it pins the action to an exact release tag. The file is project-owned, so an update shows its changes but never moves back a pin Dependabot bumped, and the template's `github-actions` Dependabot entry opens each bump. A project asked on GitLab, or given `code_review` in `-Data` there, gets no file. A note after the copy says to run `tools/Enable-CodeReview.ps1` from a clone of `NCodeGroup/code-review` once for the repository, which creates the `code-review` environment and gives it the organization's secrets.
- `tools/Set-RepositoryBaseline.ps1` gives a GitHub repository a "Protect main" ruleset on its default branch, so changes reach it only through pull requests: no deletion, no force push, a pull request with no approvals, merge-commit or rebase merges only (never squash), no bypass, and optionally required status checks (`-RequireChecks`, as one comma-separated string of jobs that run on pull requests). It also turns on delete-branch-on-merge. A repository that already requires pull requests on its default branch is left alone; `-WhatIf` shows what it would do, and `-All -Owner <owner>` covers every repository of an owner except archived ones and forks.
- `New-Project.ps1 -CreateRemote` runs the script for a new GitHub repository, requiring the template's `build-and-test` and `Commit attribution` jobs; `-NoBaseline` skips it, and a failure warns and prints the command to run again. `Adopt-Project.ps1` only commits locally, so for a GitHub `origin` it prints the command to run.

### Changed

- The template's address is `https://github.com/NCodeGroup/project-template.git`. The `-Template` default of `New-Project.ps1` and `Adopt-Project.ps1` and the README name it. `.template/Update-Project.ps1` changes a project's recorded `_src_path` from `https://github.com/polewskm/project-template.git` to the new address before it clones, and commits that line with the update, also for a project already at the newest version, so a project stops depending on GitHub's redirect with its next update. No other answer changes.
- New projects default to `author_name` NCode Group and to `workflow_tools` Claude Code and Copilot, without the local model. Projects keep the answers they recorded, so only new ones change; add the Hybrid agents with `-Data @{ workflow_tools = 'claude', 'copilot', 'local' }`. `Adopt-Project.ps1` says it left the local model out when the repository has no agent files, and how to add it.

## [0.40.4] - 2026-10-30

### Fixed

- `/ship-plan` now files a plan's follow-ups also after its pull request merged without it. The state script that `/ship-plan`, `/continue-plan`, `/finish-plan` and `/run-issues` run prints a new `unfiled` line, the follow-ups in `PLAN.md` not yet filed, tracked or dropped, and names `ship-plan` instead of `finish-plan` for a landed plan while any is left, unless the Landing section says `follow-ups: none`; `/finish-plan` stops before it deletes `PLAN.md` while any is left. A pull request merged with no release left to tag, whose merge closed its issues, sent the plan straight to `/finish-plan`, which deleted `PLAN.md` with the follow-ups only in it. Projects get it with `.\.template\Update-Project.ps1`.

## [0.40.3] - 2026-10-30

### Fixed

- The state script that `/ship-plan`, `/continue-plan`, `/finish-plan` and `/run-issues` run reads the plan's release tag from `origin` instead of the clone. A version tag only the clone had, such as one an older `/ship-plan` left after a failed push, read as `tag: present`, so `/ship-plan` moved the plan to the next version, never pushed the tag, or, under `release: tag`, called a landed plan finished. Such a tag now reads as `tag: local`, and one `origin` can't be asked about as `tag: unknown`; `/ship-plan` stops on either and says to delete a local tag with `git tag -d <version>`, and the next free version, `renumber`, counts only the tags on `origin`. Projects get it with `.\.template\Update-Project.ps1`.
- The plan commands take a new plan's `Release:` version from the newest version tag on `origin`, with `git ls-remote --tags`, instead of the clone's tags, so a tag only the clone has no longer makes a plan skip a version. Projects get it with `.\.template\Update-Project.ps1`.

## [0.40.2] - 2026-10-28

### Fixed

- `/ship-plan` no longer leaves a release tag in the clone when the push that should carry it fails. Under `integrate: direct` it tags the commit and pushes the commits and the tag together with `git push --atomic`; after a pull request merges, it tags the merge commit and pushes the tag. When either push fails, such as when the default branch moved, it now deletes the tag it made unless `origin` has it. The tag it left behind made the next run take the version for one another plan had released and move the plan to the next version, stop because the tag pointed at a commit that never landed, or never push the tag. Projects get it with `.\.template\Update-Project.ps1`.
- The project rules list what a push sends with `git log --stat origin/<branch>..`, or `git log --stat origin/<default branch>..` before a branch's first push, instead of `git log --stat @{u}..`. That failed on a plan branch with no upstream, such as one `/run-issues` makes, and listed commits already pushed on a branch that tracks the default branch. Projects get it with `.\.template\Update-Project.ps1`.

## [0.40.1] - 2026-10-28

### Fixed

- The plan executor runs each step's Done-when command in a child `pwsh` that prints `exit=<code>`, judges the step by that line alone, and quotes it in its report. Claude Code's PowerShell tool shows nothing for a command that passes, so executors took an empty output as a pass or checked the condition their own way. It applies to Claude Code's `plan-executor` subagent and `/execute-step`, the Copilot implementer agents and `execute-step` prompt files in VS Code, and the Copilot CLI `plan-executor` agent and `execute-step` skill. Projects get it with `.\.template\Update-Project.ps1`.

## [0.40.0] - 2026-10-28

### Added

- Plans can name issues they relate to without resolving them, on a `Refs:` line after `Issue:` and `Release:`. The planning commands put an issue there when the request marks it as related, such as `refs owner/repo#90`, and post no snapshot to it. `/ship-plan` ends the pull request description with one `Refs <reference>` line per reference, after the `Closes` lines, and never comments on or closes those issues. `.template/Get-PlanState.ps1` prints them on a new `refs` line, and `/continue-plan` shows them. Projects get it with `.\.template\Update-Project.ps1`.

### Changed

- `/ship-plan` under `integrate: direct` no longer stops when the default branch has moved since the plan branched. Because the push to the default branch must fast-forward, it adds a step that merges the default branch in, never by rebasing, with a sentence for each file that conflicts saying how to combine the two sides, and stops. The plan lands once that step is executed and reviewed. Projects get it with `.\.template\Update-Project.ps1`.

### Fixed

- `/ship-plan` drops the empty `Plan:` and `Re-plan step` commits whenever `origin` doesn't have the plan's branch yet. It used to test whether the branch had an upstream, and a branch made from `origin/<default>` tracks it before its first push, so the empty commits reached the pull request and the default branch. `/run-issues` also makes each worktree's branch with `git worktree add --no-track`, so it has no upstream until `/ship-plan` pushes it. Projects get it with `.\.template\Update-Project.ps1`.

## [0.39.0] - 2026-10-28

### Added

- `.template/Get-PlanState.ps1` prints a new line, `conflicts`. It names the files that conflict when the default branch on `origin` merges into the plan's branch, joined by `, `, found with `git merge-tree` without touching the index or the working tree. It is `none` when the merge is clean, `unknown` when Git can't say, such as Git older than 2.38, and `-` on the default branch or once the plan has landed. While a pull request is open and `conflicts` names files, `next` is `ship-plan`. Projects get it with `.\.template\Update-Project.ps1`.

### Changed

- `/ship-plan` no longer pushes a branch, or opens or updates a pull request, that conflicts with the default branch. It adds a step that merges the default branch in, never by rebasing, with a sentence for each file that conflicts saying how to combine the two sides, and stops. The plan lands once that step is executed and reviewed, and an open pull request then gets the step pushed to it and merges with a merge commit. A branch that merges cleanly isn't merged in: the pull request merges it. Projects get it with `.\.template\Update-Project.ps1`.
- The renumber step resolves the files that conflict besides the changelog the same way, instead of stopping to escalate them. Projects get it with `.\.template\Update-Project.ps1`.
- `/run-issues` handles a waiting draft pull request that another pull request left conflicting as it handles one whose release was taken, and `/continue-plan` shows the files that conflict. Projects get it with `.\.template\Update-Project.ps1`.

## [0.38.0] - 2026-10-28

### Added

- `.template/Get-PlanState.ps1` prints a new line, `changelog-backfill`. It names the version tags merged into `HEAD` that the changelog has no section for, as `<oldest>..<newest>`, as the tag alone when there is one, or as `-` when there is none. Projects get it with `.\.template\Update-Project.ps1`.
- `.\.template\Update-Project.ps1` and `Adopt-Project.ps1` print a request to backfill the changelog when the project has version tags it has no section for, such as `/plan-migration Backfill CHANGELOG.md from the releases v0.1.0..v0.3.0`. A project whose changelog started after its first releases can then get its full history.
- Every planning command lists that backfill under the plan's Follow-ups until it lands. It also says how a backfill plan writes the sections: one per tag, dated with the tag's date, with entries from the tag's release notes, or from its commits when it has no release, and compare links. Projects get it with `.\.template\Update-Project.ps1`.

### Changed

- No change for projects made from the template. A new test suite, `tests/Test-ChangelogBackfill.ps1`, checks both copies of the backfill check, in `.template/Update-Project.ps1` and `tools/adopt/Adoption.psm1`.

## [0.37.1] - 2026-10-28

### Changed

- No change for projects made from the template. This repository's `CHANGELOG.md` now covers every version: it has sections for v0.1.0 to v0.7.0, written from their commits, with their tags' dates and compare links.

## [0.37.0] - 2026-10-28

### Added

- Changelogs follow [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/): `## [Unreleased]` first, then one `## [1.4.0] - <date>` section per release with its entries under `### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed` and `### Security`, and compare links at the end. Every plan's last step now writes the changelog the Landing section names. A plan without a `Release:` line adds its entries under `## [Unreleased]`. A plan with one moves them into its new version's section and updates the links. The first such step creates `CHANGELOG.md` when the project has none. Projects get it with `.\.template\Update-Project.ps1`.
- `.template/Get-PlanState.ps1` prints two new lines. `changelog-format` is `keep-a-changelog`, `other` or `missing`. `changelog-version` is the changelog's newest release, written with the plan's `v` prefix. The script reads `## [1.4.0] - <date>` headings, `[YANKED]` ones included, as well as `## v1.4.0`, and does so for `renumber` too. Projects get it with `.\.template\Update-Project.ps1`.

### Changed

- `/ship-plan` checks `changelog-version` against the plan's `Release:` version instead of the changelog's first `## ` heading. It takes the release notes from a `## [1.4.0] - <date>` section, up to the next section or the links. Its renumber step re-dates a Keep a Changelog section and moves its links. Projects get it with `.\.template\Update-Project.ps1`.
- A changelog in another format, such as one an adopted project already had, is left as it is. Plans with a `Release:` line keep adding sections in its own style, and plans without one don't touch it. `Adopt-Project.ps1` lists a `/plan-migration` follow-up to convert a `CHANGELOG.md` that isn't Keep a Changelog. To convert the changelog of a project adopted earlier, run `/plan-migration Convert CHANGELOG.md to Keep a Changelog 1.1.0`.
- No change for projects made from the template. This repository's own `CHANGELOG.md` now follows Keep a Changelog: each version has its tag's date, its entries are grouped by type, and the file ends with compare links.

## [0.36.2] - 2026-10-28

### Changed

- No change for projects made from the template. This repository's CI now runs on Linux, each test suite in a parallel job, and a run takes a few minutes instead of about 18. A final `test` job, the check the ruleset requires, passes only when every suite passes, and every `tests/Test-*.ps1` script still needs a `run: ./tests/<name>` entry in the matrix of `.github/workflows/test-template.yml`. The tests now default their scratch folders to the system temp folder instead of `%TEMP%`, and `tests/Test-GitHooks.ps1` uses the system `sh`, `awk` and `grep` outside Windows. `workflow/Install-HybridWorkflow.ps1` and `workflow/Invoke-PlanSteps.ps1` build their paths with forward slashes and no longer need `%TEMP%` or `%LOCALAPPDATA%`, so they also run on Linux and macOS.

## [0.36.1] - 2026-10-28

### Changed

- No change for projects made from the template. A new end-to-end test, `tests/e2e/Test-RunIssues.ps1`, runs `/run-issues` in headless Claude Code on a fixture project made from the template, with a local `origin` and a stand-in for `gh`, and checks the plan snapshot comment, the draft pull request, the step commits and the reviewed plan it leaves. It costs model usage, so it runs by hand; CI runs its fixture setup with `-SetupOnly`.

## [0.36.0] - 2026-10-28

### Added

- `/run-issues` now runs in Copilot Chat and Copilot CLI too, from a new template, `run-issues-copilot`: it takes the same requests, plans, executes and reviews each entry, opens a draft pull request, answers your review threads and comments, and lands it once you merge. It works in the open folder instead of worktrees, one entry after another, each on a branch `issue-<number>`, without running one ahead, and a stop after an entry's plan is written ends the run, leaving it for `/continue-plan`. Run it in a Local session in Copilot Chat, or a Copilot CLI session started on Opus, without approval prompts (Bypass Approvals or Autopilot; `/allow-all`). Projects get it with `.\.template\Update-Project.ps1`.
- A workflow template's new `command` field names the command, prompt file and skill it installs as, so two templates can give different tools the same command; `Install-HybridWorkflow.ps1` stops when two templates install the same command for one tool.

## [0.35.2] - 2026-10-27

### Fixed

- `/ship-plan` made the follow-up label with `gh label create --force`, which on GitHub rewrote an existing label's color and description to `FBCA04` and "Work a plan found and did not do" on every landing that filed a follow-up, such as when `follow-up-label` names a label the project already uses or the project recolored `follow-up`. It now creates the label only when it is missing and leaves an existing one as it is, as it already did on GitLab. Projects get it with `.\.template\Update-Project.ps1`.

## [0.35.1] - 2026-10-27

### Changed

- No change for projects made from the template. This repository's `adopt/` folder, which holds `Adoption.psm1` and the `legacy/` adapters that only `Adopt-Project.ps1` uses, moved to `tools/adopt/`, beside `tools/Update-Template.ps1`. Add a new legacy adapter to `tools/adopt/legacy/`. `Adopt-Project.ps1` takes the same parameters and works as before.

## [0.35.0] - 2026-10-27

### Changed

- `/run-issues` now runs `.template/Get-PlanState.ps1` at each check of a draft pull request it waits on, so when a pull request outside the run lands that entry's `Release:` version, it renumbers the entry right away through `/ship-plan` (the `Release:` line and the renumber step), executes and reviews the step, pushes it to the draft pull request, and comments that the pull request must now merge with a merge commit, not by rebasing. Projects get it with `.\.template\Update-Project.ps1`.

## [0.34.0] - 2026-10-27

### Changed

- When another plan takes a plan's `Release:` version while its pull request is open, `/ship-plan` now renumbers it as it does before a pull request opens: it changes the `Release:` line and adds the renumber step, and once that step is reviewed the next `/ship-plan` pushes it to the open pull request, which then merges with a merge commit, not by rebasing. `.template/Get-PlanState.ps1` names `ship-plan` as `next`, not `wait`, while the pull request is open and `renumber` isn't `-`. Projects get it with `.\.template\Update-Project.ps1`.

## [0.33.0] - 2026-10-27

### Added

- A plan's `Release:` version now holds only until another plan lands it, or a later one, first: `.template/Get-PlanState.ps1` prints a new `renumber` line with the next free version, from the newest tag or the default branch's changelog, raised as the plan's version was; `/ship-plan` then changes the `Release:` line and adds a step that merges in the default branch and moves the changelog section, and lands after that step's review; such a pull request merges with a merge commit, not by rebasing; `/review-plan-diff` now diffs from the merge base with the default branch, so merged-in commits aren't reviewed as the plan's. Projects get it with `.\.template\Update-Project.ps1`.

### Changed

- `/run-issues` runs one entry ahead: while a draft pull request waits for review, it plans, executes and reviews the next entry in its own worktree, and opens that entry's pull request only once the one before has landed, so entries still land in queue order. Projects get it with `.\.template\Update-Project.ps1`.

## [0.32.0] - 2026-10-27

### Added

- `- pr-format: <file>#<heading>` in the Landing section, such as `AGENTS.md#Pull requests`, makes `/ship-plan` write the pull request's title and description as that section says, such as a conventional-commit title or required headings, still ending with its `Closes` lines. `/run-issues` refreshes descriptions the same way, and `/ship-plan` stops before pushing when the file or heading is missing. The `landing` line of `.template/Get-PlanState.ps1` prints `pr-format`, `none` by default, which keeps the plan's title and a short summary. Template updates don't change a project's `AGENTS.md`, so a project adds the key to its own Landing section. Projects get it with `.\.template\Update-Project.ps1`.
- The Copilot and Hybrid reviewer agents in VS Code have two more buttons: Land the plan, which puts `/ship-plan` in the chat box to send, and Show where the plan stands, which runs `/continue-plan`. Projects get it with `.\.template\Update-Project.ps1`.

## [0.31.0] - 2026-10-27

### Added

- `- gate: <command>` in the Landing section, such as `./build/dod.ps1 -Fast -Affected`, makes `/ship-plan` run that command from the repository root before it pushes, judged by its exit code, and stop when it fails or changes a file. `/run-issues` runs it before the pushes it makes after review rounds. The `landing` line of `.template/Get-PlanState.ps1` prints `gate`, `none` by default. Template updates don't change a project's `AGENTS.md`, so a project adds the key to its own Landing section. Projects get it with `.\.template\Update-Project.ps1`.
- `.template/Get-PlanState.ps1` prints a new `protected` line: `host` when GitHub or GitLab requires pull requests into the default branch, `hook` under `protect: hook` with the `pre-push` hook enabled, else `no`, `unknown` or `-`. The `landing` line now also gives `protect`. `/run-issues` reads `protected` instead of calling `gh api` and `glab api` itself, and `/ship-plan` reads `protect` from the `landing` line. Projects get it with `.\.template\Update-Project.ps1`.

## [0.30.0] - 2026-10-27

### Added

- `Adopt-Project.ps1` takes the `project_owned_files` answer: `-Data @{ project_owned_files = '.github/workflows/ci.yml' }` keeps the named merged files exactly as the repository has them instead of rebuilding them, records the answer in `.copier-answers.yml`, and so later updates show the template's changes to them instead of merging. A name that isn't a merged file stops the adoption before it changes anything, and the report lists each kept file as `Owned`. Projects get it with `.\.template\Update-Project.ps1`.
- `Update-Project.ps1` suggests `project_owned_files` for a merged file the project seems to have replaced: when the template changed a merged file that shares less than half its distinct non-blank lines with the template's version (lines an adopted file keeps under its "Kept from" comment don't count), it names the file and prints the `-Data` to run, after a commit or a conflict alike. It doesn't stop the update. Projects get it with `.\.template\Update-Project.ps1`.

## [0.29.0] - 2026-10-27

### Changed

- `/run-issues` now reads your top-level pull request comments and review summaries, not only review threads, fixes what they ask for, and answers each with a top-level comment that starts with `Autopilot:` and names the comment's link. A top-level comment counts as answered once such a comment names it, and a new comment from you starts a new round. Projects get it with `.\.template\Update-Project.ps1`.
- After a review round adds fix steps and pushes them, `/run-issues` rewrites the pull request description the way `/ship-plan` writes it, a short summary of the plan's steps and Decisions and a `Closes` line per issue, so it matches the plan that lands. Projects get it with `.\.template\Update-Project.ps1`.
- `/run-issues` waits for each merge for up to 24 hours with nothing to answer, counted again from each check that finds a comment of yours, then stops the entry and keeps its worktree and draft pull request for `/continue-plan`. `wait:<hours>` in the request, such as `/run-issues #42 wait:72`, changes the limit. Projects get it with `.\.template\Update-Project.ps1`.

## [0.28.0] - 2026-10-27

### Added

- `/ship-plan` now opens the pull request as a draft when the Landing section of `AGENTS.md` says `- draft: yes`, as `/ship-plan draft` does. `.template/Get-PlanState.ps1`'s `landing` line now gives every Landing key the workflow reads, with its default, and prints a value with a space in double quotes. Template updates don't change a project's `AGENTS.md`, so a project adds the keys to its Landing section itself; without them it lands as before. Projects get it with `.\.template\Update-Project.ps1`.
- `- follow-ups: issues` (the default), `- follow-ups: <owner/repo>` or `- follow-ups: none` in the Landing section says where `/ship-plan` files a plan's follow-ups. With `none` it files nothing and lists them for you to record, and `/run-issues` says the same in its summary. Projects get it with `.\.template\Update-Project.ps1`.
- `- follow-up-label: <name>` in the Landing section sets the label filed follow-ups get, `follow-up` by default; a name may contain spaces. Projects get it with `.\.template\Update-Project.ps1`.

## [0.27.1] - 2026-10-27

### Added

- A new `merge` line prints the commit the merged pull request merged as, and `/ship-plan` tags that commit instead of asking `gh pr view` or `glab mr view` for it. Projects get it with `.\.template\Update-Project.ps1`.

### Changed

- For a merged pull request that doesn't hold the branch's `HEAD`, `next` now names the base branch when the pull request merged into another branch than the default (a stacked pull request), and is `ship-plan` under `integrate: direct`, where a plan lands by a push; `/ship-plan`'s stop for a merged pull request says the same. Projects get it with `.\.template\Update-Project.ps1`.

### Fixed

- `.template/Get-PlanState.ps1` read only the newest pull request or merge request from a plan's branch, so when a newer one was open or closed but an older one had merged with the branch's `HEAD`, `landed` was `no` and `/finish-plan` stopped to ask. It now reads all of them, counts the branch as landed when any merged one holds `HEAD` or its tree, and its `pr` line names that one. Projects get it with `.\.template\Update-Project.ps1`.

## [0.27.0] - 2026-10-27

### Added

- A plan may now cover a small group of related issues, up to three: `/plan-issue #25 #24 #26` writes one plan whose `Issue:` line lists them, with its steps grouped by issue and the largest version raise among them, in one worktree named after the first issue, one pull request with a `Closes` line per issue and one release. The plan snapshot and re-plan comments go to each issue, and `/ship-plan` comments on and closes each issue still open. `.template/Get-PlanState.ps1` has a new `issue-states` line, and its `issue-state` is `OPEN` while any issue is open. `/triage-issues` groups ready issues that overlap, at most three (`group:<n>` changes it), and prints one `/plan-issue` line per group. `/run-issues` runs each group as one queue entry, and a group stops together. A plan with one issue works as before. Projects get it with `.\.template\Update-Project.ps1`.

## [0.26.0] - 2026-10-27

### Changed

- No change for projects made from the template. `tests/Invoke-AllTests.ps1` runs every `tests/Test-*.ps1` suite, prints `PASS` or `FAIL` and the time per suite, writes each suite's output to a log, and exits 1 when any suite fails, so the README's "Change the Template" step is one command instead of nine. `tests/Test-InvokeAllTests.ps1` tests it, and CI runs that test.

## [0.25.4] - 2026-10-27

### Changed

- The first `PLAN.md` rule in `.github/instructions/project-template.instructions.md` now names the optional `Release:` and `Reviewed:` lines under a plan's title and the optional `## Follow-ups` section at its end, which the planning commands, `/review-plan-diff` and `.template/Get-PlanState.ps1` already use; it listed only the `Issue:` line before. Projects get it with `.\.template\Update-Project.ps1`.

## [0.25.3] - 2026-10-27

### Changed

- No change for projects made from the template. `tests/Test-Template.ps1` now fails, naming the script, when a `tests/Test-*.ps1` script has no `run: ./tests/<name>` step in `.github/workflows/test-template.yml`, so a new test script can't be left out of CI unnoticed.

## [0.25.2] - 2026-10-27

### Fixed

- `.template/Test-CommitAttribution.ps1` let a commit with Claude Code's "Generated with [Claude Code]" line through when PowerShell's console code page wasn't UTF-8, such as a Windows console on its default code page or a PowerShell job, because it read Git's output in that code page. It now reads Git's output as UTF-8 whatever the code page. Projects get it with `.\.template\Update-Project.ps1`.

## [0.25.1] - 2026-10-27

### Changed

- No change for projects made from the template. `USAGE.md` now says that `/finish-plan` reads the `landed` value of `.template/Get-PlanState.ps1`, which asks the host with `gh` or `glab` for a merged pull request whose head holds the plan's branch or has its tree; since v0.22.0 the command no longer asks the host itself.

## [0.25.0] - 2026-10-27

### Added

- `/ship-plan` and `/run-issues` now file a plan's follow-ups as issues labelled `follow-up` once the plan has landed, unless you drop them (`/ship-plan`: name them in the landing summary; `/run-issues`: answer at the start that you want none filed). Before, `/run-issues` only listed them in the issue's closing comment, which a pull request that closes the issue skips, so they were easy to lose. `/ship-plan` skips a follow-up an open issue already covers, and the closing comment, or a short comment when the pull request closed the issue, lists the filed numbers. Plans and reviews now list only work worth its own issue, one line each as `<short title>: <what, where, why>`; nits go in the planner's reply. Projects get it with `.\.template\Update-Project.ps1`.

## [0.24.4] - 2026-10-27

### Fixed

- `.githooks/commit-msg` used to keep the AI agent attribution and let the commit through, saying nothing clear, when `grep` was missing from `PATH`. It now refuses the commit when `grep` is missing or fails. Projects get it with `.\.template\Update-Project.ps1`.

## [0.24.3] - 2026-10-27

### Fixed

- With `protect: hook`, `/run-issues` accepted any `pre-push` hook as protection, so in a pre-commit clone pre-commit's own `pre-push` hook passed its check although nothing ran `.githooks/pre-push`. It now runs only when `core.hooksPath` names the `.githooks` folder, or the clone's `pre-push` or `pre-push.legacy` calls `.githooks/pre-push`, and says how to add the wrapper otherwise. Projects get it with `.\.template\Update-Project.ps1`.

## [0.24.2] - 2026-10-27

### Fixed

- In a clone that uses pre-commit or has hooks of its own, `Update-Project.ps1` and `Adopt-Project.ps1` left `.githooks/pre-push` unrun and said nothing, so `protect: hook` protected nothing. Under `protect: hook` they now print a two-line wrapper to save as `.git/hooks/pre-push` (or `pre-push.legacy` when pre-commit installed its pre-push hook), or say to call it from the clone's own pre-push hook. A pre-commit `stages: [pre-push]` hook isn't enough, because pre-commit's pre-push stage checks only one ref of a push. Projects get it with `.\.template\Update-Project.ps1`.

## [0.24.1] - 2026-10-27

### Fixed

- With `protect: hook`, `.githooks/pre-push` used to let every push through when `awk` or `tr` was missing from `PATH`. It now needs only `awk` and refuses the push when `awk` is missing or fails. Projects get it with `.\.template\Update-Project.ps1`.

## [0.24.0] - 2026-10-27

### Changed

- No change for projects made from the template. `workflow/New-PlanPrompt.ps1 -List` now shows each template's targets, the installer targets its `targets` field names (all three without it), so Claude Code-only templates such as `run-issues` stand out.

## [0.23.2] - 2026-10-27

### Changed

- No change for projects made from the template. This repository's `AGENTS.md` no longer gives a project whose `main` takes changes only through pull requests as one that squashes plan step commits: since v0.23.0 this repository lands through pull requests and keeps them, by merge commit or rebase.

## [0.23.1] - 2026-10-27

### Changed

- No change for projects made from the template. The help of `workflow/Install-HybridWorkflow.ps1` now names `tools\Update-Template.ps1`, where v0.22.1 moved the script, as the one that passes `-NoVersionMarker`.

## [0.23.0] - 2026-10-27

### Added

- `/run-issues` (Claude Code only) takes the issues a request names, or the ready ones a filter finds through `/triage-issues`, from plan to landing in one session, up to five, one at a time: it plans each issue, executes and reviews it, opens a draft pull request, fixes what each review thread you start asks for and replies with `Autopilot:` (you resolve the thread), and once you mark the pull request ready and it merges, tags, releases, closes and finishes it before starting the next. It asks once, at the start, never merges, marks ready, turns on auto-merge or resolves a thread, and stops an issue that needs a decision, keeping its worktree for `/continue-plan`.
- `/run-issues` runs only when `AGENTS.md`'s Landing section says `integrate: pull-request` and the default branch takes changes through pull requests alone: a GitHub ruleset or branch protection rule that requires them, a GitLab protected branch nobody pushes to, or the new `protect: hook`.
- New Landing key `protect`: `hook` turns on the new `.githooks/pre-push`, which refuses any push to the default branch, for a host that can't require pull requests, such as a private repository on GitHub Free. A project without the key sees no change. New projects get `- protect: none`. `New-Project.ps1`, `Adopt-Project.ps1` and `Update-Project.ps1` mark the hook executable. Projects get it with `.\.template\Update-Project.ps1`.
- `/ship-plan` opens a draft pull request when its extra instructions say `draft`, and stops when `protect: hook` is set with `integrate: direct`.

### Changed

- This repository now lands through pull requests, guarded by `protect: hook`: run `git config core.hooksPath template/.githooks` in each clone. `Install-HybridWorkflow.ps1` reads a new template field, `targets`, that limits a template to the tools it names.

## [0.22.1] - 2026-10-26

### Changed

- No change for projects made from the template. This repository's own scripts moved: the nine `Test-*.ps1` tests into `tests/` and `Update-Template.ps1` into `tools/`, so the root holds only `New-Project.ps1`, `Adopt-Project.ps1` and `Update-Project.ps1`, the scripts people run. Run them as `.\tests\Test-Template.ps1` and `.\tools\Update-Template.ps1`. The scripts, their checks and CI are otherwise the same.

## [0.22.0] - 2026-10-26

### Changed

- `/finish-plan` now runs `.template/Get-PlanState.ps1` and reads `landed`, `dirty` and `steps` from it instead of running its own git, `gh` and `glab` checks, so the script is the one tested copy of the "is the work upstream" rule.

### Fixed

- The script's `landed` now counts a merged pull request or merge request only when its merge commit is on the default branch and its head holds the branch's `HEAD` or has the same tree. Before, any merged pull request counted, so `/ship-plan` and `/continue-plan` could call a branch landed after commits were added to it once its pull request merged. Such a branch's `next` now says to land those commits from a new branch, and `/ship-plan` stops on it. Projects get it with `.\.template\Update-Project.ps1`.

## [0.21.0] - 2026-10-26

### Added

- New answer `project_owned_files`: the merged files a project owns. `Update-Project.ps1` leaves them alone and shows the template's changes to them, rendered with the project's answers and leaving out what the file already has, as it does for project-owned files. A project that replaced a merged file, such as its own `.github/workflows/ci.yml`, sets it in an update to v0.21.0 or later: `.\.template\Update-Project.ps1 -Data @{ project_owned_files = '.github/workflows/ci.yml' }`. Before, the rewritten file shared almost no lines with the template, so Copier's merge paired the template's changed lines with unrelated project lines, and taking the template's side broke the workflow. Only merged files can be named; any other file stops the update before it changes anything. `-Data @{ project_owned_files = @() }` gives them back to the merge (Copier records the empty list as `project_owned_files: []`, which means no owned files). New projects aren't asked.

## [0.20.0] - 2026-10-26

### Changed

- `/continue-plan` now fetches `origin` once instead of once per plan worktree. `.template/Get-PlanState.ps1` has a new `-NoFetch` switch that skips its fetch and reads `ahead`, `behind` and `landed` from the remote refs the last fetch left. `/continue-plan` passes it to its calls for the other worktrees, which share the first call's remote refs. `/ship-plan` still fetches.

## [0.19.0] - 2026-10-26

### Added

- `/ship-plan` lands a reviewed plan by the new `## Landing` section of `AGENTS.md`: `integrate` (`pull-request`, the default, or `direct`), `release` (`none`, the default, `tag` or `tag+release`) and `changelog` (default `CHANGELOG.md`). It shows what it will push, tag, publish, post and file, and asks once. It drops the empty `Plan:` and `Re-plan step` commits from a branch that was never pushed, pushes the commits and tag atomically or opens the pull request with `Closes`, publishes the release from the changelog section, comments on and closes the issue, and files the follow-ups you pick. Every stage skips what's already done, so it can run again after a pull request merges. A project without a Landing section keeps today's behavior: a pull request and no release. New projects get the section with those defaults, and a project adds it to its own `AGENTS.md` to change them.
- `/continue-plan` shows where each open plan stands (steps, review, landing, pull request) and the one command to run next. Both commands run `.template/Get-PlanState.ps1`, a new template-owned script that `Install-HybridWorkflow.ps1` also installs with the commands, in `.template\` with `-Repo` or in `~\.claude\` and `~\.copilot\` with `-User`.
- Plans gain a `Release:` line, which the planner sets from the kind of plan when the Landing section releases (a patch for bugfix, docs, tests and refactor plans, a minor for others), with a last step that writes that version's changelog section, and a `## Follow-ups` section. A clean `/review-plan-diff` records the commit it reviewed on a `Reviewed:` line, and `/ship-plan` lands only work that matches it. `/orchestrate-plan` and `/review-plan-diff` end with the exact next command.

## [0.18.3] - 2026-10-26

### Fixed

- `Update-Project.ps1` sets aside the lines an adopted project kept from its own `.gitignore`, `.gitattributes` or `.editorconfig` (the block under `# Kept from this repository's own <file> when it adopted the project template`, which `Adopt-Project.ps1` puts at the end of the file) while Copier merges, then puts them back at the end. Before, a template change to the file's last line, such as v0.15.0's `secrets/` → `/secrets/` in a `stack: other` project, stopped the update with a conflict that held the project's whole kept block, so taking the template's side deleted every rule the project kept. A conflict in the template's lines now ends before the kept block. A project gets the fix with its update to this version or later, because its current script hands the update over to this version's script. An update pinned with `-Ref` to an earlier version runs that version's script and still conflicts: see v0.15.0.

## [0.18.2] - 2026-10-26

### Fixed

- `Update-Project.ps1` exits 0 when an update succeeds, with `-NoCommit` too. Before, run with `&` (as `/plan-template-update`'s trial run and its first step do), a `-NoCommit` update that showed a template change to a project-owned file left `$LASTEXITCODE` at 1, from the git commands that show the change, so a caller or plan step that judged the run by its exit code saw a failure. `pwsh -File` and committing updates weren't affected. A project gets the fix with its update to this version, because its current script hands the update over to this version's script and passes on its exit code.

## [0.18.1] - 2026-10-26

### Fixed

- `Adopt-Project.ps1` answers `stack: other` for an OpenTofu or Terraform repository (a `.tf`, `.tofu` or `.tftest.hcl` file within two folders of the root), even when it has PowerShell scripts. PowerShell files under the root's `build/`, `eng/`, `scripts/`, `tools/`, `.github/` and `.gitlab/` folders no longer make a repository `powershell`. Before, such a repository got `Invoke-ScriptAnalyzer` and `Invoke-Pester` as its build and test commands, and the adoption stopped staged, not committed, when those modules weren't installed. A PowerShell project whose only PowerShell files are in those folders now gets `other`, so pass `-Data @{ stack = 'powershell' }`. A project adopted before this release with the wrong stack corrects `stack`, `build_command` and `test_command` in `.copier-answers.yml` and runs `.\.template\Update-Project.ps1`.

## [0.18.0] - 2026-10-26

### Changed

- `Adopt-Project.ps1` works out `workflow_tools` from the repository's own files instead of always taking the default: `claude`, plus `copilot` when it has `.github/agents/copilot-*.agent.md`, `.github/skills/` or `.github/prompts/`, plus `local` only when it has `.github/agents/hybrid-*.agent.md`. `-Data` still wins. Before, a repository with only Copilot agents got the Hybrid agents and `local-implementer.agent.md`, which use the shack PC's private model, `.github/prompts/execute-step-local.prompt.md`, the only prompt file without a matching skill, and `"ollama.inferenceTimeoutMinutes"` in `.vscode/settings.json`. A repository with none of these files still gets the default, and the script prints a line saying it included `local` and how to leave it out. A project adopted before this release that shouldn't have the local model's files removes them with `.\.template\Update-Project.ps1 -Data @{ workflow_tools = 'claude', 'copilot' }`.

## [0.17.0] - 2026-10-26

### Fixed

- `.githooks/commit-msg` starts with `#!/usr/bin/env sh` instead of `#!/bin/sh`, so pre-commit on Windows can run it as a `language: script` hook. Before, it failed with "Executable `/bin/sh` not found". Git runs it through `core.hooksPath` as before.
- `Update-Project.ps1` and `Adopt-Project.ps1` no longer set `core.hooksPath` in a clone that uses pre-commit (its hooks in `.git/hooks` are pre-commit's, or it has `.pre-commit-config.yaml`), because `pre-commit install` refuses to run while `core.hooksPath` is set. They print a `repo: local` hook to add to `.pre-commit-config.yaml` and `pre-commit install --hook-type commit-msg`, and print nothing once that file runs `.githooks/commit-msg`. A clone where an earlier update or adoption set `core.hooksPath` keeps it: run `git config --unset core.hooksPath` before `pre-commit install`.

## [0.16.0] - 2026-10-26

### Security

- Both `actions/checkout` steps in `.github/workflows/ci.yml` set `persist-credentials: false`, so the job's `GITHUB_TOKEN` is no longer written to `.git/config`, where later steps could read it (zizmor's `artipacked` finding). Neither job pushes. In a project whose Dependabot has moved the `actions/checkout` pin, `Update-Project.ps1` stops with a conflict on these lines: keep the project's pin and add the new `with:` and `persist-credentials: false` lines. A project whose build or test steps run git commands that need the token, such as a push, sets `persist-credentials: true` on that checkout in its own `ci.yml`, which is a merged file, so later updates keep it. A project that replaced `ci.yml` with its own workflow gets different conflicts, whose "after updating" side holds the template's job lines: keep the project's side ("before updating") of each and add `persist-credentials: false` under each of its own `actions/checkout` steps. From v0.21.0, `-Data @{ project_owned_files = '.github/workflows/ci.yml' }` in the update avoids the conflict.

## [0.15.0] - 2026-10-26

### Fixed

- `.gitignore` ignores only the `secrets/` folder at the repository root (`/secrets/`), and `.claude/settings.json` denies Claude Code reading only that folder (`Read(/secrets/**)`). Before, both matched a `secrets/` folder at any depth, and on Windows also `Secrets/`, so new source files in a folder such as `src/App/Endpoints/Secrets/` were silently left out of commits and agents couldn't read them. `.env` files are still ignored and denied at any depth. Both files are merged on update. A project that keeps secret files in a nested `secrets/` folder should move them to the root `secrets/` folder, or add that folder's path to `.gitignore`, before updating, because the update stops ignoring it. An adopted `stack: other` project's `.gitignore` ends with `secrets/` followed by the block kept at adoption (`# Kept from this repository's own .gitignore when it adopted the project template`). Its update to a version from v0.15.0 through v0.18.2 stops on a conflict in `.gitignore`. To resolve it, change `secrets/` to `/secrets/` and keep the whole kept block below it; taking the template's side ("after updating") deletes every rule the project kept. Updating to v0.18.3 or later doesn't conflict.

## [0.14.1] - 2026-10-26

### Fixed

- `Adopt-Project.ps1` no longer names a project after the Claude Code worktree it runs in. Without a single solution, `project_name` is the `origin` remote's repository name, else the main checkout's folder name, else the folder name. A project adopted from a plan worktree before this release has the worktree's name in `.copier-answers.yml`; correct it there and run `.\.template\Update-Project.ps1`.

## [0.14.0] - 2026-10-26

### Added

- A new `/plan-template-update` command plans a project's update to the newest template version, or to one it names (`/plan-template-update v0.14.0`), and can change an answer on the way. It reads the release notes since the project's version and runs `Update-Project.ps1 -NoCommit` on a clone of the project to see what the update does. Its plan runs the update as a step, pinned with `-Ref` and staged with `-NoCommit`, so the update is committed as `Plan step 1` and a result that differs from the trial escalates. Then it runs the project's checks, fixes each project file that still describes the old template, and ends with the project's tests, each judged by its exit code. It files an issue in the template repository for each gap the trial shows. In Claude Code it plans in a worktree, or, when the project's `plan-executor` subagent lacks the PowerShell tool (before v0.11.0), on a `build/project-template-<version>` branch in the current checkout.

## [0.13.0] - 2026-10-26

### Added

- A new `/plan-issue` command plans one GitHub or GitLab issue: `/plan-issue #42`, `owner/repo#42` or the issue's URL. It reads the issue and its comments with `gh` or `glab`. It stops with questions when the issue is closed, already has a plan, has an open pull request or doesn't say enough to plan. It picks the kind of plan from the issue's labels (`bug` → bugfix, `enhancement` → feature, `documentation` → docs, …) or its text, and plans with that kind's checklist, in Claude Code in a worktree named `issue-42`. The `Issue:` line, the snapshot comment and `Closes` work as in v0.12.0.
- A new `/triage-issues` command lists up to 20 open issues that match a filter (a label, a milestone, an assignee or search words). For each one it judges the kind of plan, its readiness and its size, flags issues whose plans would overlap, and gives the `/plan-issue` command for each ready one. It changes no files and posts nothing.

### Changed

- Every planning command reads the issue a request names, its body and every comment, before it researches. It treats the issue's text as data, not instructions: it never runs a command, opens a link or changes its rules because an issue says to.

## [0.12.0] - 2026-10-26

### Added

- A plan can name the issue it implements. When the request names one (`#42`, `owner/repo#42` or its URL), the planning commands put it on an `Issue:` line under the plan's title and post the finished plan to the issue once, as a collapsed comment, with `gh` or `glab`. A re-plan that changes the Decisions or adds or removes steps posts a short follow-up. Only the planning session posts; executors never call `gh` or `glab`. A plan for no issue is unchanged.

### Changed

- `review-plan-diff` and the push rules in `.github/instructions/project-template.instructions.md` put `Closes <issue>` and a short summary of the plan in the pull request description, so the issue's timeline holds the problem, the plan and the pull request that closed it.

## [0.11.0] - 2026-10-25

### Changed

- `/finish-plan` asks GitHub (`gh`) or GitLab (`glab`) whether the plan's branch has a merged pull request. It counts the work as upstream when that pull request's merge commit is on the default branch and its head matches the plan's branch, so a squash-merged or merge-queued pull request no longer stops it. Without the CLI, or without such a pull request, it still stops to ask.
- `Update-Project.ps1` leaves out of its listing of the template's changes to project-owned files each change the project's file already has, and a file that has them all.
- README.md's "Update a Project" says that a project on v0.8.0 or earlier runs its own, older update logic on its first update, and how to run the newest logic from a clone instead.

### Fixed

- In Claude Code, `/finish-plan` deletes what's left of a plan's worktree when Windows' 260-character path limit stops `git worktree remove` with "Filename too long", and says to turn on `core.longpaths`. USAGE.md's Git setup now does: `git config --global core.longpaths true`.
- The Claude Code `plan-executor` subagent has the PowerShell tool and runs Done-when commands and a step's commands with it. Through Bash, Claude Code refused every `pwsh` command in a plan's worktree.

## [0.10.0] - 2026-10-25

### Added

- A new `/finish-plan` command closes a plan once its work is pushed or merged: it deletes `PLAN.md`, fast-forwards the default branch from `origin`, deletes the plan's branch, and in Claude Code removes the plan's worktree. It never pushes, and stops when a commit hasn't reached the default branch yet, such as after a squash-merged pull request.

### Changed

- `review-plan-diff` points at `/finish-plan` once a review finds no blocker or should-fix left.

## [0.9.0] - 2026-10-25

**Update twice, or once from a clone.**

Every earlier version of `.template\Update-Project.ps1` fails to hand an update over to the newer script when the template is cloned over a URL, as it is from GitHub, and runs its own, older update logic instead. It read the newer script with `git checkout` from a blob-filtered clone, which doesn't fetch the file. v0.9.0 fixes this, but the fix reaches a project only on its second update after this release: the first update to v0.9.0 still runs the project's old script, which installs the fixed one. That first run also commits on whatever branch is checked out, so switch to a branch of its own first.

To run the v0.9.0 logic on the first update instead, run the wrapper from a clone of this repository at v0.9.0: `git clone --branch v0.9.0 https://github.com/polewskm/project-template.git`, then `.\Update-Project.ps1 -Path <project>` in that clone.

### Added

- `Adopt-Project.ps1` asks to re-admit `Directory.Build.props` and `build/ProjectTemplate.props` in each `.dockerignore` and in each CI file that lists `Directory.Build.props`.

### Changed

- `Update-Project.ps1` refuses to commit on the default branch (the branch `origin/HEAD` names). Run it on a branch of its own, such as `git switch -c build/project-template-v0.9.0`, or pass `-NoCommit`.
- `Update-Project.ps1` replaces Copier's "Make sure Git >= 2.24 is installed" warning, a false alarm with Git 2.55 and later, with what it means (copier-org/copier#2759).
- `Update-Project.ps1` shows the template's changes to project-owned files rendered with the project's answers, not as Jinja, and leaves out a change the project's answers don't reach.
- The plan executor reports a Done-when command it couldn't run and leaves the check to the coordinator, instead of reporting a check of its own.

### Fixed

- `Update-Project.ps1` reads the target version's copy of itself with `git show` and hands the update over to it, and clones the template in full.
- `Update-Project.ps1` and `Adopt-Project.ps1` no longer set `core.hooksPath` in a clone that has hooks in `.git/hooks`, which a hooks path turns off. They say how to run both.
- `CLAUDE.md`, `.template/Update-Project.ps1` and `Directory.Build.props` end with a newline.

## [0.8.0] - 2026-10-25

### Changed

- An agent asked to push deletes a finished `PLAN.md` first, once every step, the review's fix steps included, is marked `[x]`; with a step still open it keeps the plan and says which steps remain.

## [0.7.0] - 2026-10-25

### Added

- Every project has a `.template-version` file: one line with the template version the project is on, such as `v0.7.0`, which Copier writes from `_commit` in `.copier-answers.yml`, for people and scripts to read. It is template-owned, so `Update-Project.ps1` records each new version in it.
- `workflow\Install-HybridWorkflow.ps1` records the template version it installed in `.template-version`: at the repository root with `-Repo`, or in `~\.claude\` and `~\.copilot\` with `-User`. `-NoVersionMarker` skips it.

## [0.6.0] - 2026-10-25

### Changed

- `PLAN.md` is a local working file, never committed or pushed. The template's `.gitignore` ignores it, and a planning command adds it to `.git/info/exclude` in a repository whose `.gitignore` doesn't.
- A finished step is committed as `Plan step N: <title>` with only the files the step lists staged, never with `git add -A` or `PLAN.md`. A re-planned step is recorded as an empty commit, `Re-plan step N: <title>`, and in Claude Code a new plan's worktree gets an empty `Plan: <title>` commit. `workflow\Invoke-PlanSteps.ps1` never stages the plan either.
- Before a push it was asked for, an agent lists what the unpushed commits contain (`git log --stat @{u}..`) and stops on anything unexpected, such as `PLAN.md`, secrets or large files.

## [0.5.0] - 2026-10-25

### Added

- A `package_manager` question for Node.js projects: npm (the default), pnpm, Yarn or Bun. CI installs dependencies with it: pnpm and Yarn through Corepack, Bun through `oven-sh/setup-bun` on GitHub and the `oven/bun` image on GitLab. It also sets Dependabot's ecosystem (`bun` for Bun, else `npm`) and the default build and test commands, such as `pnpm run build` and `pnpm run test`.

### Fixed

- CI installed a Node.js project's dependencies only with `npm ci`, so a pnpm, Yarn or Bun project ran its build and test commands with nothing installed.
- `Adopt-Project.ps1` works out a Node.js repository's package manager (the `packageManager` field in `package.json`, else its lockfile, else npm) and its build and test commands from the scripts in `package.json`. It leaves a command blank when there is no such script or the `test` script is the failing placeholder `npm init` writes, so adopting a repository without a build script no longer fails its verification.

## [0.4.0] - 2026-10-25

### Fixed

- `Update-Project.ps1` no longer fails on Windows with `[WinError 206] The filename or extension is too long` when the project's own `.gitignore` ignores a large folder that the template's `.gitignore` doesn't, such as `node_modules/` in a .NET project with a frontend. While Copier updates, it keeps the project's ignore rules in force through `.git/info/exclude`, and it restores that file afterwards. A run also removes the copy of the rules that a killed update left there.

## [0.3.0] - 2026-10-25

### Added

- In Claude Code, each plan lives in its own git worktree, so several sessions can plan and execute different plans on one machine at once. The planning commands (the `/plan-*` commands and `/handoff-plan`) create `.claude/worktrees/<name>/` on the branch `worktree-<name>` before they research, and commit `PLAN.md` there as `Plan: <title>`. `/orchestrate-plan`, `/execute-step`, `/replan-step` and `/review-plan-diff` move the session into the plan's worktree first; with several plans open, name one: `/orchestrate-plan <name>`. Copilot is unchanged: to continue a plan there, open the worktree's folder.

### Changed

- `.claude/settings.json` allows Claude Code's `EnterWorktree` tool, so creating or entering a plan's worktree doesn't ask.

## [0.2.0] - 2026-10-25

### Added

- Every project works with Claude Code and with GitHub Copilot, and you can switch between them at any time: besides the Claude Code commands and `plan-executor` subagent, it gets the Copilot agents and prompt files for Copilot Chat in VS Code, and the same commands as Copilot CLI skills with a `plan-executor` agent. `PLAN.md` is the only state they share. This repository's `USAGE.md` covers setting up and switching between them.
- A `workflow_tools` question chooses which of Claude Code (`claude`), Copilot (`copilot`) and the shack PC's local model (`local`) a project gets workflow files, editor settings and recommended extensions for; the default is all three. `New-Project.ps1` and `Update-Project.ps1` pass a list given in `-Data` to Copier: `-Data @{ workflow_tools = 'claude', 'copilot' }`.
- A `nuget_package` question (.NET) turns on NuGet packaging in `build/ProjectTemplate.props`: the license expression from the required `package_license`, the root `README.md` and an optional `package_icon` in each package, Source Link with untracked sources, symbol packages and XML documentation.
- `Adopt-Project.ps1` brings an existing repository under the template without asking questions. It works out the answers, runs Copier, rebuilds each merged file as the template's file plus the repository's own content, extends `AGENTS.md` and `Directory.Build.props`, moves a .NET repository's package versions into `Directory.Packages.props`, and removes legacy setups through legacy adapters. It runs the build and test commands before it commits, and rolls the repository back when a later step fails.
- AI agent attribution stays out of commits. `.claude/settings.json` turns Claude Code's attribution off, `.vscode/settings.json` sets `git.addAICoAuthor` to off, and the template's rules tell agents not to add it. A `.githooks/commit-msg` hook, which `New-Project.ps1` and `Update-Project.ps1` enable, strips Copilot and Claude `Co-authored-by:` trailers, `Claude-Session:` trailers and "Generated with Claude Code" lines, and keeps a person's co-author trailer.
- `.template/Test-CommitAttribution.ps1`, run by a `Commit attribution` job in `ci.yml` or `.gitlab-ci.yml`, fails on a commit authored, committed or co-authored by an AI agent, on pull requests, in a GitHub merge queue and on pushes to the default branch.

### Changed

- The plan executor runs on Claude Sonnet 5.5 in every tool: the Copilot agents in VS Code, Copilot CLI and `workflow\Invoke-PlanSteps.ps1`, instead of Copilot's Auto, which picked a different model from run to run, and Claude Code's `plan-executor` subagent, pinned to `claude-sonnet-5-5`.
- Copilot's step prompt is `execute-step.prompt.md`, like its `execute-step` skill; with the local model too, the local model's is `execute-step-local.prompt.md`. `Adopt-Project.ps1` deletes an older `execute-step-copilot.prompt.md`.
- When `Update-Project.ps1` can't read the template, it says that updating needs read access to it, and that the project still works without it.

## [0.1.0] - 2026-10-24

### Added

- The first release: a Copier template for repositories set up for plan-then-execute AI coding. Claude Opus plans each change into `PLAN.md`, a cheaper model executes it one verified step at a time, and any step that needs a decision goes back to Opus. The base works for any language, a .NET layer adds shared build settings and C# conventions, and projects live on GitHub (the default) or GitLab.
- `New-Project.ps1` asks the questions (`project_name`, `project_description`, `stack`, `git_host`, `author_name` for .NET, `build_command` and `test_command`), creates the project and makes its first commit. With `-CreateRemote` it also creates the repository, public unless `-Visibility` says otherwise, and pushes.
- Every file has one owner. Template-owned files are replaced on update. Merged files, the settings whose tools can't include a second file, take the template's changes merged with the project's edits. Project-owned files, `AGENTS.md`, `README.md` and, for .NET, `Directory.Build.props`, are never touched.
- `.template/Update-Project.ps1`, in every project, updates it to the newest template version, handing the update over to that version's copy of itself.
- The workflow: Claude Code commands (`/plan-feature`, `/plan-bugfix`, `/orchestrate-plan`, `/replan-step`, `/review-plan-diff`, …) with a `plan-executor` subagent, VS Code agents and prompt files whose Local Implementer runs steps on the shack PC's model, and the template's rules in `.github/instructions/project-template.instructions.md`, which `AGENTS.md` imports.
- The .NET layer: `build/ProjectTemplate.props` (latest C#, nullable reference types, implicit usings, warnings as errors, `ContinuousIntegrationBuild` when `CI=true`, author metadata), central package management in `Directory.Packages.props`, the SDK in `global.json`, and C# conventions for Copilot and Claude Code.
- CI on GitHub or GitLab that runs the build and test commands, with GitHub Actions pinned to commit SHAs, and on GitHub, Dependabot for the CI actions and, by stack, packages and the .NET SDK.

[unreleased]: https://github.com/NCodeGroup/project-template/compare/v0.41.1...HEAD
[0.41.1]: https://github.com/NCodeGroup/project-template/compare/v0.41.0...v0.41.1
[0.41.0]: https://github.com/NCodeGroup/project-template/compare/v0.40.4...v0.41.0
[0.40.4]: https://github.com/NCodeGroup/project-template/compare/v0.40.3...v0.40.4
[0.40.3]: https://github.com/NCodeGroup/project-template/compare/v0.40.2...v0.40.3
[0.40.2]: https://github.com/NCodeGroup/project-template/compare/v0.40.1...v0.40.2
[0.40.1]: https://github.com/NCodeGroup/project-template/compare/v0.40.0...v0.40.1
[0.40.0]: https://github.com/NCodeGroup/project-template/compare/v0.39.0...v0.40.0
[0.39.0]: https://github.com/NCodeGroup/project-template/compare/v0.38.0...v0.39.0
[0.38.0]: https://github.com/NCodeGroup/project-template/compare/v0.37.1...v0.38.0
[0.37.1]: https://github.com/NCodeGroup/project-template/compare/v0.37.0...v0.37.1
[0.37.0]: https://github.com/NCodeGroup/project-template/compare/v0.36.2...v0.37.0
[0.36.2]: https://github.com/NCodeGroup/project-template/compare/v0.36.1...v0.36.2
[0.36.1]: https://github.com/NCodeGroup/project-template/compare/v0.36.0...v0.36.1
[0.36.0]: https://github.com/NCodeGroup/project-template/compare/v0.35.2...v0.36.0
[0.35.2]: https://github.com/NCodeGroup/project-template/compare/v0.35.1...v0.35.2
[0.35.1]: https://github.com/NCodeGroup/project-template/compare/v0.35.0...v0.35.1
[0.35.0]: https://github.com/NCodeGroup/project-template/compare/v0.34.0...v0.35.0
[0.34.0]: https://github.com/NCodeGroup/project-template/compare/v0.33.0...v0.34.0
[0.33.0]: https://github.com/NCodeGroup/project-template/compare/v0.32.0...v0.33.0
[0.32.0]: https://github.com/NCodeGroup/project-template/compare/v0.31.0...v0.32.0
[0.31.0]: https://github.com/NCodeGroup/project-template/compare/v0.30.0...v0.31.0
[0.30.0]: https://github.com/NCodeGroup/project-template/compare/v0.29.0...v0.30.0
[0.29.0]: https://github.com/NCodeGroup/project-template/compare/v0.28.0...v0.29.0
[0.28.0]: https://github.com/NCodeGroup/project-template/compare/v0.27.1...v0.28.0
[0.27.1]: https://github.com/NCodeGroup/project-template/compare/v0.27.0...v0.27.1
[0.27.0]: https://github.com/NCodeGroup/project-template/compare/v0.26.0...v0.27.0
[0.26.0]: https://github.com/NCodeGroup/project-template/compare/v0.25.4...v0.26.0
[0.25.4]: https://github.com/NCodeGroup/project-template/compare/v0.25.3...v0.25.4
[0.25.3]: https://github.com/NCodeGroup/project-template/compare/v0.25.2...v0.25.3
[0.25.2]: https://github.com/NCodeGroup/project-template/compare/v0.25.1...v0.25.2
[0.25.1]: https://github.com/NCodeGroup/project-template/compare/v0.25.0...v0.25.1
[0.25.0]: https://github.com/NCodeGroup/project-template/compare/v0.24.4...v0.25.0
[0.24.4]: https://github.com/NCodeGroup/project-template/compare/v0.24.3...v0.24.4
[0.24.3]: https://github.com/NCodeGroup/project-template/compare/v0.24.2...v0.24.3
[0.24.2]: https://github.com/NCodeGroup/project-template/compare/v0.24.1...v0.24.2
[0.24.1]: https://github.com/NCodeGroup/project-template/compare/v0.24.0...v0.24.1
[0.24.0]: https://github.com/NCodeGroup/project-template/compare/v0.23.2...v0.24.0
[0.23.2]: https://github.com/NCodeGroup/project-template/compare/v0.23.1...v0.23.2
[0.23.1]: https://github.com/NCodeGroup/project-template/compare/v0.23.0...v0.23.1
[0.23.0]: https://github.com/NCodeGroup/project-template/compare/v0.22.1...v0.23.0
[0.22.1]: https://github.com/NCodeGroup/project-template/compare/v0.22.0...v0.22.1
[0.22.0]: https://github.com/NCodeGroup/project-template/compare/v0.21.0...v0.22.0
[0.21.0]: https://github.com/NCodeGroup/project-template/compare/v0.20.0...v0.21.0
[0.20.0]: https://github.com/NCodeGroup/project-template/compare/v0.19.0...v0.20.0
[0.19.0]: https://github.com/NCodeGroup/project-template/compare/v0.18.3...v0.19.0
[0.18.3]: https://github.com/NCodeGroup/project-template/compare/v0.18.2...v0.18.3
[0.18.2]: https://github.com/NCodeGroup/project-template/compare/v0.18.1...v0.18.2
[0.18.1]: https://github.com/NCodeGroup/project-template/compare/v0.18.0...v0.18.1
[0.18.0]: https://github.com/NCodeGroup/project-template/compare/v0.17.0...v0.18.0
[0.17.0]: https://github.com/NCodeGroup/project-template/compare/v0.16.0...v0.17.0
[0.16.0]: https://github.com/NCodeGroup/project-template/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/NCodeGroup/project-template/compare/v0.14.1...v0.15.0
[0.14.1]: https://github.com/NCodeGroup/project-template/compare/v0.14.0...v0.14.1
[0.14.0]: https://github.com/NCodeGroup/project-template/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/NCodeGroup/project-template/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/NCodeGroup/project-template/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/NCodeGroup/project-template/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/NCodeGroup/project-template/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/NCodeGroup/project-template/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/NCodeGroup/project-template/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/NCodeGroup/project-template/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/NCodeGroup/project-template/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/NCodeGroup/project-template/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/NCodeGroup/project-template/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/NCodeGroup/project-template/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/NCodeGroup/project-template/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/NCodeGroup/project-template/releases/tag/v0.1.0
