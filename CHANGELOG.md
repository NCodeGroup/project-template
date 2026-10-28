# Changelog

What each template version changes for the projects made from it. A project moves to a version with `.\.template\Update-Project.ps1`.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[unreleased]: https://github.com/polewskm/project-template/compare/v0.37.0...HEAD
[0.37.0]: https://github.com/polewskm/project-template/compare/v0.36.2...v0.37.0
[0.36.2]: https://github.com/polewskm/project-template/compare/v0.36.1...v0.36.2
[0.36.1]: https://github.com/polewskm/project-template/compare/v0.36.0...v0.36.1
[0.36.0]: https://github.com/polewskm/project-template/compare/v0.35.2...v0.36.0
[0.35.2]: https://github.com/polewskm/project-template/compare/v0.35.1...v0.35.2
[0.35.1]: https://github.com/polewskm/project-template/compare/v0.35.0...v0.35.1
[0.35.0]: https://github.com/polewskm/project-template/compare/v0.34.0...v0.35.0
[0.34.0]: https://github.com/polewskm/project-template/compare/v0.33.0...v0.34.0
[0.33.0]: https://github.com/polewskm/project-template/compare/v0.32.0...v0.33.0
[0.32.0]: https://github.com/polewskm/project-template/compare/v0.31.0...v0.32.0
[0.31.0]: https://github.com/polewskm/project-template/compare/v0.30.0...v0.31.0
[0.30.0]: https://github.com/polewskm/project-template/compare/v0.29.0...v0.30.0
[0.29.0]: https://github.com/polewskm/project-template/compare/v0.28.0...v0.29.0
[0.28.0]: https://github.com/polewskm/project-template/compare/v0.27.1...v0.28.0
[0.27.1]: https://github.com/polewskm/project-template/compare/v0.27.0...v0.27.1
[0.27.0]: https://github.com/polewskm/project-template/compare/v0.26.0...v0.27.0
[0.26.0]: https://github.com/polewskm/project-template/compare/v0.25.4...v0.26.0
[0.25.4]: https://github.com/polewskm/project-template/compare/v0.25.3...v0.25.4
[0.25.3]: https://github.com/polewskm/project-template/compare/v0.25.2...v0.25.3
[0.25.2]: https://github.com/polewskm/project-template/compare/v0.25.1...v0.25.2
[0.25.1]: https://github.com/polewskm/project-template/compare/v0.25.0...v0.25.1
[0.25.0]: https://github.com/polewskm/project-template/compare/v0.24.4...v0.25.0
[0.24.4]: https://github.com/polewskm/project-template/compare/v0.24.3...v0.24.4
[0.24.3]: https://github.com/polewskm/project-template/compare/v0.24.2...v0.24.3
[0.24.2]: https://github.com/polewskm/project-template/compare/v0.24.1...v0.24.2
[0.24.1]: https://github.com/polewskm/project-template/compare/v0.24.0...v0.24.1
[0.24.0]: https://github.com/polewskm/project-template/compare/v0.23.2...v0.24.0
[0.23.2]: https://github.com/polewskm/project-template/compare/v0.23.1...v0.23.2
[0.23.1]: https://github.com/polewskm/project-template/compare/v0.23.0...v0.23.1
[0.23.0]: https://github.com/polewskm/project-template/compare/v0.22.1...v0.23.0
[0.22.1]: https://github.com/polewskm/project-template/compare/v0.22.0...v0.22.1
[0.22.0]: https://github.com/polewskm/project-template/compare/v0.21.0...v0.22.0
[0.21.0]: https://github.com/polewskm/project-template/compare/v0.20.0...v0.21.0
[0.20.0]: https://github.com/polewskm/project-template/compare/v0.19.0...v0.20.0
[0.19.0]: https://github.com/polewskm/project-template/compare/v0.18.3...v0.19.0
[0.18.3]: https://github.com/polewskm/project-template/compare/v0.18.2...v0.18.3
[0.18.2]: https://github.com/polewskm/project-template/compare/v0.18.1...v0.18.2
[0.18.1]: https://github.com/polewskm/project-template/compare/v0.18.0...v0.18.1
[0.18.0]: https://github.com/polewskm/project-template/compare/v0.17.0...v0.18.0
[0.17.0]: https://github.com/polewskm/project-template/compare/v0.16.0...v0.17.0
[0.16.0]: https://github.com/polewskm/project-template/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/polewskm/project-template/compare/v0.14.1...v0.15.0
[0.14.1]: https://github.com/polewskm/project-template/compare/v0.14.0...v0.14.1
[0.14.0]: https://github.com/polewskm/project-template/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/polewskm/project-template/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/polewskm/project-template/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/polewskm/project-template/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/polewskm/project-template/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/polewskm/project-template/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/polewskm/project-template/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/polewskm/project-template/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/polewskm/project-template/compare/v0.5.0...v0.6.0
