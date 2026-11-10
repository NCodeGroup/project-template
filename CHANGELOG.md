# Changelog

What each template version changes for the projects made from it. A project moves to a version with `.\.template\Update-Project.ps1`.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.84.1] - 2026-11-10

### Changed

- No change for projects made from the template. CI also sets up the run-feedback end-to-end fixture with `-Scenario review-with-footer`, so a change that breaks that scenario's `footer.txt` setup fails the pull request, and `tests/Invoke-AllTests.ps1` runs that setup too ([#342](https://github.com/NCodeGroup/project-template/issues/342)).

### Fixed

- `.template/Update-Project.ps1`, when it stops on a conflict, stages every change outside the conflicting files, deletions included, as it does without a conflict. It left the files the template changed or deleted unstaged, so a `/plan-template-update` plan, whose update step runs `git add` only on the files that still exist, committed the update without its deletions. `/plan-template-update` also leaves a deletion an older target's script left unstaged unmarked, so its commit note stages it ([#339](https://github.com/NCodeGroup/project-template/issues/339)).
- `.template/Update-Project.ps1` leaves a catch-all text rule, such as `* text eol=lf`, out of the lines an adopted project's `.gitattributes` kept at adoption, as `Adopt-Project.ps1` has since 0.41.1, and says so. A project adopted before then kept the rule through every update, and because Git uses the last rule that matches, it overrode the template's binary rules: `git add` dropped the CR of each CR LF pair in an `.ico` or `.pdf` file it staged, corrupting it ([#340](https://github.com/NCodeGroup/project-template/issues/340)).

## [0.84.0] - 2026-11-10

### Changed

- No change for projects made from the template. `tests/Invoke-AllTests.ps1` also runs each end-to-end fixture setup that `.github/workflows/test-template.yml` runs, every `run: ./tests/e2e/<script>.ps1 -SetupOnly` line with its arguments, each with a `-Work` folder of its own in the run's folder, and prints their results after the suites', in the workflow's order, so a change that breaks a fixture setup fails the local run as it fails CI ([#338](https://github.com/NCodeGroup/project-template/issues/338)).

## [0.83.1] - 2026-11-10

### Changed

- No change for projects made from the template. `tests/e2e/Test-RunIssues.ps1` and `tests/e2e/Test-RunFeedback.ps1` rename `-Scenario session-footer` to `-Scenario review-with-footer`, for what it checks: that a `/review` comment the run posts with a Claude Code cloud session's footer still asks NCode Review for a review and stays as posted. The README, CONTRIBUTING and the CI job that sets up its fixture use the new name ([#337](https://github.com/NCodeGroup/project-template/issues/337)).

## [0.83.0] - 2026-11-10

### Added

- `.template/Update-Project.ps1`, when its update removes the Commit attribution check, says to drop a required `Commit attribution` check from the default branch's ruleset or branch protection, and names a `.pre-commit-config.yaml` or Git hook that still calls the removed `.githooks/commit-msg` ([ADR-0018](template/docs/decisions/project-template/0018-agent-attribution-is-avoided-not-enforced.md)).

### Changed

- **Breaking:** Agent attribution is avoided, not enforced: the settings, the rules and `/ship-plan` and `/run-issues`, which delete attribution lines from the pull request title and description they write, still keep it out, but nothing checks for it or fails a commit, push, pull request or pipeline over it. A repository whose ruleset or branch protection requires a `Commit attribution` check must drop it from the required checks, or every pull request waits for a check no workflow reports; on GitHub, run `tools/Set-RepositoryBaseline.ps1 -Repo <name> -RequireChecks 'build-and-test'` from the template's clone for a ruleset it made, or edit the ruleset ([ADR-0018](template/docs/decisions/project-template/0018-agent-attribution-is-avoided-not-enforced.md)).
- On GitLab, the always-on CI job that checks the decision index is named `decision-index`.
- New projects and adoptions require only the `build-and-test` check, and the template's GitHub CI no longer runs again when a pull request's title or description is edited.

### Removed

- `.githooks/commit-msg`, which stripped agent attribution from commit messages, and the pre-commit hook `Update-Project.ps1` and `Adopt-Project.ps1` suggested for it.
- `.template/Test-CommitAttribution.ps1` and the `Commit attribution` CI job on GitHub and GitLab.
- The workflow commands' read-back of each pull request, issue, comment and note they post, which edited out a session's attribution footer and listed what it couldn't remove.

## [0.82.0] - 2026-11-10

### Added

- `brand/`, the NCode Group logo kit: the `{N}` mark redrawn as a vector on a 64-unit grid, with a pixel-fitted drawing of its own for each of 16, 20, 24, 32, 40 and 48 pixels, in NCode Blue (`#0033CC`) for light backgrounds, a light blue for dark ones, and on blue, white and navy tiles, exported as the PNG and ICO files that NuGet, a website's favicon, GitHub, GitLab, My Apps, profile pictures, badges and social cards each ask for. `brand/build.py` draws every file and stops when one breaks its platform's limit, and `brand/README.md` says which file is for what. No change for projects made from the template.

### Changed

- `NCodeGroup.png`, the package icon a new NCode Group library gets, is the redrawn `{N}` mark in white on a blue tile at 128 by 128 pixels, the size NuGet recommends. It was a 64 by 64 picture of the mark in blue on a transparent background, which a dark theme all but hides: a contrast of 1.9 to 1 on `#1E1E1E`. The file is project-owned, so a project that already has it keeps its own; copy this version's `template/NCodeGroup.png` over it to take the new icon.

## [0.81.0] - 2026-11-10

### Added

- `/run-issues` offers at its start to fix the follow-ups in the same pull request before merge, beside filing them as issues and filing none: each entry turns its plan's own follow-ups into fix steps before its draft pull request opens, and, while its rounds of review feedback stay below `max-review-rounds`, every NCode Review finding that holds, nits, minor findings and changes outside the issue included, into fix steps pushed to the draft pull request, replying `Autopilot: fixed in <commit>` and never `Autopilot: left as a follow-up`. A follow-up it can't fix there, because its fix would edit a protected path, lies in another repository or the issue excludes it, or one found after the last round, is still filed and listed in the report, with a reply that says why ([#332](https://github.com/NCodeGroup/project-template/issues/332)).
- `/ship-plan` offers to fix follow-ups in the plan's pull request before merge, beside filing them, acting on them next and dropping them, while the plan hasn't landed: each one named becomes an escalated step of the plan, which `/replan-step` plans, and nothing is filed for it ([#332](https://github.com/NCodeGroup/project-template/issues/332)).

### Changed

- `/run-issues` words its follow-up answers by where the work lands: file them as issues; fix them in the same pull request before merge; file them and run each as a new entry of this run, which is 0.79.0's "complete them immediately" and works as before; or file none. With `follow-ups: none`, it offers to fix them in the same pull request or to list them in the report ([#332](https://github.com/NCodeGroup/project-template/issues/332)).
- `tests/e2e/Test-RunIssues.ps1 -Scenario fix-now` answers the run's question with fixing the follow-ups in the same pull request, and checks that the run fixes NCode Review's out-of-scope blocker and its nit in the draft pull request, never replies `Autopilot: left as a follow-up`, and leaves neither in the plan's `## Follow-ups`; CI runs its fixture setup. No change for projects made from the template ([#332](https://github.com/NCodeGroup/project-template/issues/332)).

## [0.80.1] - 2026-11-09

### Changed

- No change for projects made from the template. `tests/e2e/Test-RunIssues.ps1 -Scenario push-branch` runs `/run-issues` with a `push-branch:<name>` word on an `origin` whose push branch still holds the head of a pull request merged by squashing, which the `gh` stand-in serves, and checks that the run records the push branch, restarts it from its plan, pushes its commits and its fix round there, never pushes the plan's own branch, and opens its draft pull request from it; the stand-in's `gh pr view <branch>` picks a branch's open pull request over a merged one, and `gh pr list` without `--state` lists only open ones, as `gh` does; CI runs the scenario's fixture setup ([#327](https://github.com/NCodeGroup/project-template/issues/327)).

### Fixed

- `.template/Get-PlanState.ps1` no longer reads a new plan as landed right after an earlier plan's pull request from the same branch, such as a session's push branch, merged: the new plan's empty `Plan:` commit has that pull request's tree, so the script printed `landed: yes`, that pull request on its `pr` line and `next: finish-plan` until the plan's first step changed a file. A merged pull request or merge request whose head doesn't hold `HEAD` now counts by its tree only when `HEAD` changes a file since it left the default branch. Projects get it with `.\.template\Update-Project.ps1` ([#327](https://github.com/NCodeGroup/project-template/issues/327)).

## [0.80.0] - 2026-11-09

### Added

- `tools/Set-RepositoryBaseline.ps1` allows, in the event policy "Allow pull_request_target for code review", every event the code-review workflows' top-level `on:` keys name, besides `pull_request_target` and `issue_comment`, so a trigger a project adds to its `.github/workflows/code-review.yml`, such as `workflow_dispatch`, isn't blocked by the policy. Another active policy, the repository's or the organization's, counts as already allowing them only when it allows every one of those events for both files, so one that allows only `pull_request_target` no longer stops the script from creating its own; `-OrganizationPolicy` checks an organization's other policies for `pull_request_target` and `issue_comment` the same way. A file whose content it can't read, such as one over 1 MB, is named in the policy's line. A project that adds one reruns `tools/Set-RepositoryBaseline.ps1 -Repo <name>` from a clone of the template, which updates the policy ([#323](https://github.com/NCodeGroup/project-template/issues/323)).

### Fixed

- `tools/Set-RepositoryBaseline.ps1` updates its own event policy, "Allow pull_request_target for code review", in place when it is disabled or in evaluate mode, doesn't allow an event the code-review workflows start on, or doesn't cover both workflows, keeping any other event it allows, and says what was wrong, also when GitHub refuses the update. It left such a policy alone and reported "left alone", so a disabled one kept a public repository's automatic reviews blocked from December 2, 2026. One that does its job is reported as already set, and `-OrganizationPolicy` does the same for the organization's policy of that name, which must also cover every repository ([#324](https://github.com/NCodeGroup/project-template/issues/324)).
- `tools/Set-RepositoryBaseline.ps1` says in a repository's event policy line when it couldn't read the organization's Actions policies for a reason other than HTTP 403 or 404, such as a server error, no response or an answer that isn't JSON. It took every such failure for "no organization policy" and created a repository policy without saying why ([#325](https://github.com/NCodeGroup/project-template/issues/325)).

## [0.79.1] - 2026-11-09

### Fixed

- `tools/Set-RepositoryBaseline.ps1 -OrganizationPolicy` says that organization event policies need GitHub Team or above, and to run the script for each repository instead, with `-Repo <name>`, or with `-All` once its `-WhatIf` looks right, when GitHub refuses the organization's policies for its plan, such as with `HTTP 403: Upgrade to GitHub Team to enable this feature.` on GitHub Free. It asked for an organization owner with the `admin:org` scope instead, which the owner running it already was. A repository's own policy, which `-Repo` and `-All` create, works on every plan, so a public project on GitHub Free that answers `code_review` runs `tools/Set-RepositoryBaseline.ps1 -Repo <name>` from a clone of the template before December 2, 2026. Any other refusal still names the owner role and the `admin:org` scope, and the run still exits 1 ([#329](https://github.com/NCodeGroup/project-template/issues/329)).

## [0.79.0] - 2026-11-09

### Added

- `/run-issues` offers a third answer for the follow-ups at its start, complete them immediately, beside filing them and filing none, as `/ship-plan` offers to act on them next: each landed entry's follow-ups are filed marked ` — next`, and once `/finish-plan` has run for the entry, each filed issue joins the run's queue as an entry of its own and lands like any other, while the run has taken fewer than five entries; the report names the rest with the commands that plan them. It is offered with `follow-ups: issues` ([#321](https://github.com/NCodeGroup/project-template/issues/321)).

## [0.78.0] - 2026-11-09

### Added

- A session whose host made a branch for it and limits its pushes to that branch, such as a Claude Code cloud session's `claude/<words>-<id>` branch, lands plans through it: `/ship-plan` pushes the plan's own branch to it with `git push -u origin "HEAD:refs/heads/<branch>"` and opens the pull request from it, `/run-issues` lands its entries through it one open pull request at a time, and `/address-feedback` and `/run-feedback` work only on a pull request from it. Plans keep their own branch names, `worktree-<name>`, `worktree-issue-<number>` and `issue-<number>`, which stay the default. The session takes the branch from its own instructions or from a `push-branch:<name>` word in the request, never from a branch's name or a `claude/` prefix, and records it in the clone's Git config as `plan.pushBranch`; `push-branch:none` clears it ([#320](https://github.com/NCodeGroup/project-template/issues/320), [ADR-0004](template/docs/decisions/project-template/0004-trunk-based-development-on-the-default-branch.md)).
- `.template/Get-PlanState.ps1` prints `push-branch`, the clone's `plan.pushBranch` setting or `invalid`; `pr-branch`, the branch on `origin` the plan's pull request comes from: its upstream once pushed, else the push branch, else the plan's branch; and `pr-branch-state`, which says whether that branch can take the plan: `new`, `ours`, `landed`, `busy <number>`, `other` or `unknown` ([#320](https://github.com/NCodeGroup/project-template/issues/320)).

### Changed

- `.template/Get-PlanState.ps1` reads the plan's pull request from the branch it was pushed to, not only from the local branch's name, so `/ship-plan`, `/continue-plan` and `/finish-plan` find it after a push to a push branch, and leaves out the pull requests other plans opened from that branch ([#320](https://github.com/NCodeGroup/project-template/issues/320)).
- When a push branch on `origin` still holds a merged pull request's work, because the host didn't delete it, `/ship-plan` deletes it there before it pushes the next plan, so each pull request starts from the default branch; it stops, pushing nothing, when the branch carries another open pull request or work that hasn't landed, and under `integrate: direct`. `/finish-plan` never deletes the session's push branch ([#320](https://github.com/NCodeGroup/project-template/issues/320), [ADR-0004](template/docs/decisions/project-template/0004-trunk-based-development-on-the-default-branch.md)).

## [0.77.0] - 2026-11-09

### Added

- `tools/Set-RepositoryBaseline.ps1` gives a public repository that has `.github/workflows/code-review.yml` or `code-review-auto-merge.yml` the Actions event policy "Allow pull_request_target for code review", which allows `pull_request_target` and `issue_comment` for those two workflows alone, unless a policy of the repository or its organization allows the event already. From December 2, 2026, GitHub's default policy blocks `pull_request_target` in a public repository without one, which would stop every automatic review and every NCode Review pin bump's auto-merge. `-OrganizationPolicy -Owner <organization>`, run once by an organization owner with the `admin:org` scope, creates the same policy for every repository of the organization instead, and `-WhatIf` prints the policy it would post. A public project that answers `code_review` reruns `tools/Set-RepositoryBaseline.ps1 -Repo <name>` from a clone of the template, has an organization owner run `-OrganizationPolicy`, or allows `pull_request_target` for the two workflows by hand, before December 2, 2026 ([#317](https://github.com/NCodeGroup/project-template/issues/317)).

## [0.76.1] - 2026-11-09

### Added

- `.template/install-nvs.sh`, for a project that answers `uses_node`, is the one nvs installer outside Windows: it clones nvs at the v1.7.1 tag and checks its commit, does nothing when nvs is already there, and edits no profile. `Initialize-Nvs.ps1`, GitLab CI and `.claude/hooks/ensure-nvs.sh` run it, in place of the three pinned clones and the unpinned install command they carried ([#307](https://github.com/NCodeGroup/project-template/issues/307), [ADR-0200](template/docs/decisions/project-template/0200-nodejs-comes-from-nvs-and-a-node-version-file.md)).

### Changed

- `.template/Use-Node.ps1`, the `prelude` of a project that uses Node.js, and `.template/use-node.sh` check the `node` on `PATH` first and accept it when `node --version`, without its leading `v`, is the version `.node-version` names or starts with it and a dot, so `26` accepts 26.1.0 and `26.1` accepts 26.1.4 but not 26.10.0. Only otherwise do they select it through nvs, and when that fails too they stop with one message naming `Initialize-Nvs.ps1`. `Initialize-Nvs.ps1` installs nvs through `install-nvs.sh` on Linux and macOS, and on Windows names `winget install --id jasongin.nvs -e --version 1.7.1`, as `USAGE.md` now does. `.claude/hooks/ensure-nvs.sh` installs nvs only when the session's Node.js is another release, and GitLab CI only when the job image's is. ADR-0200 and the Node.js rules say that every environment installs the `.node-version` release its own way and the selector checks it ([#307](https://github.com/NCodeGroup/project-template/issues/307), [ADR-0200](template/docs/decisions/project-template/0200-nodejs-comes-from-nvs-and-a-node-version-file.md)).

### Fixed

- The prelude no longer stops every Done-when command and gate in Copilot's cloud agent, which installs Node.js with `actions/setup-node` and has no nvs: `Use-Node.ps1` threw "nvs is not installed" even when the `.node-version` release was on `PATH`. `Use-Node.ps1` reports an empty `.node-version` as such instead of "You cannot call a method on a null-valued expression", and `use-node.sh` no longer ends a `set -eo pipefail` shell, such as GitHub Actions' bash, before it prints why it stopped. `tests/Test-NodeSetup.ps1` runs both selectors against stub nvs and node binaries with a `PATH` of the system folders alone ([#307](https://github.com/NCodeGroup/project-template/issues/307)).

## [0.76.0] - 2026-11-09

### Added

- A project decides which tools its Claude Code cloud sessions bootstrap, through scripts in `.claude/hooks/`: the `SessionStart` hook in `.claude/settings.json` runs `.claude/hooks/session-start.sh`, with a timeout of 600 seconds, which in a cloud session runs every `.claude/hooks/ensure-*.sh` in name order, each for at most `ENSURE_SCRIPT_TIMEOUT` seconds (240 by default), goes on past one that fails or times out and names it, and never fails the session. A project adds a tool by adding `.claude/hooks/ensure-<tool>.sh`, which template updates leave alone. The template ships `ensure-pwsh.sh`, as before, and, for a project that answers `uses_node`, `ensure-nvs.sh`, which clones nvs pinned to the v1.7.1 tag's commit, installs and links the `.node-version` Node.js, and puts it first on `PATH` for the session's later commands, so the `Use-Node.ps1` prelude selects it there as on a developer's PC. `tests/Test-EnsureTools.ps1` checks both scripts with stand-ins. Projects get them with `.\.template\Update-Project.ps1`, which merges the new hook command into the project's `.claude/settings.json` ([ADR-0017](template/docs/decisions/project-template/0017-cloud-sessions-bootstrap-their-tools-through-ensure-scripts.md)).

## [0.75.6] - 2026-11-09

### Changed

- No change for projects made from the template. Every file and folder name under `template/` is plain: the 79 names that held a Copier condition, such as `{% if stack == 'dotnet' %}global.json{% endif %}`, lost it, and their conditions are `_exclude` entries in `copier.yml`, so a project gets exactly the files it got before, and an update from an earlier version changes nothing it didn't. No path in the repository holds a Jinja tag, and the longest is 141 characters instead of 200, so the repository checks out the same on Windows, Linux and macOS, with no setting such as `core.longpaths`. `tests/Test-WindowsFileNames.ps1` fails a path that holds a Jinja tag or is longer than 160 characters, and the new `tests/Compare-Renders.ps1 -Base <commit>` checks that the working tree's template renders, and updates a project, exactly as the template at that commit does.

## [0.75.5] - 2026-11-09

### Fixed

- `.github/instructions/project-template.instructions.md` no longer says that `git push` always asks for approval; `.claude/settings.json` has let it run without asking since v0.69.0. It now says not to count on an approval prompt to stop a push, because `git push` can run without one, so the check of the unpushed commits is what catches an unexpected push. `/ship-plan`, `/run-issues` and Copilot's `/address-feedback` no longer say that `git push` may still ask for its own approval: they say that after the yes to their summary, no prompt stops a push. `tests/Test-Template.ps1` fails when a rule or command says again that `git push` asks, and its check that a prelude command that writes an error ends the output with `prelude failed` no longer fails now and then: it reads that last line from the child PowerShell's standard output alone, because the error on its standard error could arrive after it ([#308](https://github.com/NCodeGroup/project-template/issues/308)).

## [0.75.4] - 2026-11-09

### Changed

- On GitHub, the template's `.github/workflows/tag-release.yml` is named Tag and publish release instead of Release, so the Actions tab no longer lists it beside a project's own workflow of that name. A first job with only `contents: read`, whose checkout keeps no token, reads `release` from `AGENTS.md`'s Landing section through the new `-Policy` switch of `.template/Publish-Release.ps1`, and the job that tags and publishes, with `contents: write` and `actions: write`, runs only with `release: tag` or `tag+release`; with `release: none`, no job holds a write permission ([#309](https://github.com/NCodeGroup/project-template/issues/309), [ADR-0016](template/docs/decisions/project-template/0016-releases-are-tagged-and-published-when-their-pull-request-merges.md.jinja)).

### Fixed

- A project's decision records cite only records it has: ADR-0016 names ADR-0137 only in a .NET library on GitHub, and says for every project that the release script starts its `.github/workflows/publish.yml` through `workflow_dispatch`; ADR-0008, ADR-0015, ADR-0100, ADR-0116, ADR-0117 and ADR-0136 cite ADR-0108, ADR-0130, ADR-0131, ADR-0135, ADR-0136, ADR-0143 and ADR-0200 only in the projects that have them; and the decision index and ADR-0012 use ADR-0004, which every project has, as their example. The warning `Update-Project.ps1` and `Adopt-Project.ps1` print for a `publish.yml` without a `workflow_dispatch` trigger names ADR-0137 as the template's, which a .NET library on GitHub has ([#311](https://github.com/NCodeGroup/project-template/issues/311)).

## [0.75.3] - 2026-11-09

### Changed

- No change for projects made from the template. The help text of `tests/Test-WindowsFileNames.ps1` wraps its description at 100 characters instead of uneven widths past 120, and its `Get-WindowsNameProblem` names `Test-WindowsName` in `template/.template/Update-Project.ps1` as the copy of its rules to change with it; `Test-WindowsName` already pointed back to it ([#306](https://github.com/NCodeGroup/project-template/issues/306)).

## [0.75.2] - 2026-11-09

### Fixed

- On Windows, `Update-Project.ps1` stops before it changes anything when the project is on a template version Git for Windows can't check out, such as v0.69.0 to v0.75.0, whose `uses_node` file names held a `|`: it names the path and says to update once from Linux, macOS or WSL, instead of failing in `copier recopy` with Copier's `invalid path` error. A project on v0.69.0 to v0.75.0 gets the stop when it updates to v0.75.2 or later, because its own script hands the update over to that version's ([#305](https://github.com/NCodeGroup/project-template/issues/305)).

## [0.75.1] - 2026-11-09

### Fixed

- A project can be made, updated and adopted on Windows again: from v0.69.0 the template's names for the five files a project that answers `uses_node` gets, `.node-version`, `.template/Initialize-Nvs.ps1`, `.template/Use-Node.ps1`, `.template/use-node.sh` and ADR-0200, held a `|`, a character Windows forbids in file names, so Git for Windows refused to check the template out and `New-Project.ps1`, `Update-Project.ps1` and `Adopt-Project.ps1` stopped before changing anything. The files and what they hold are unchanged, and this repository's CI now fails any path Windows can't check out, through `tests/Test-WindowsFileNames.ps1`. A project on v0.69.0 to v0.75.0 still can't update on Windows, because the update checks out the project's own version first: update it once from Linux, macOS or WSL ([#302](https://github.com/NCodeGroup/project-template/issues/302)).

## [0.75.0] - 2026-11-09

### Changed

- GitLab CI for a PowerShell project runs in the `mcr.microsoft.com/dotnet/sdk:10.0` image, which the `Commit attribution` job also uses and which has a supported PowerShell, Git and curl, instead of `mcr.microsoft.com/powershell:lts`, last built with PowerShell 7.2, past its end of support; with `uses_node` it installs nothing with `apt-get` before nvs ([#297](https://github.com/NCodeGroup/project-template/issues/297), [ADR-0200](template/docs/decisions/project-template/0200-nodejs-comes-from-nvs-and-a-node-version-file.md)).

- GitLab CI for the `other` stack with `uses_node` runs in the `node:lts` image instead of `alpine:3`, installs nvs v1.7.1, pinned to its commit, and selects the Node.js `.node-version` names before the build, as for every other stack; without `uses_node` it keeps `alpine:3` ([#298](https://github.com/NCodeGroup/project-template/issues/298), [ADR-0200](template/docs/decisions/project-template/0200-nodejs-comes-from-nvs-and-a-node-version-file.md)).

- The warning `Update-Project.ps1` and `Adopt-Project.ps1` print for a `.github/workflows/publish.yml` without a `workflow_dispatch` trigger points at the `publish.yml` the template gives a .NET library on GitHub and at ADR-0137, not at one release's changelog section ([#299](https://github.com/NCodeGroup/project-template/issues/299)).

## [0.74.0] - 2026-11-08

### Added

- `/ship-plan` offers a third answer for a plan's follow-ups, act on them next, beside filing them for later and dropping them: each follow-up you name, or all of them, is still filed as an issue and marked ` — next` in `PLAN.md`, and `/finish-plan` then ends with `/plan-issue #<number>` for each, and `/run-issues` with all of them when the project lands through pull requests, so the work starts while the plan's context is fresh. It is offered with `follow-ups: issues`; the Landing section gains no new value ([#295](https://github.com/NCodeGroup/project-template/issues/295)).

## [0.73.0] - 2026-11-08

### Added

- `Adopt-Project.ps1` warns, word for word as `Update-Project.ps1` does, when the repository keeps its own `.github/workflows/publish.yml` without a `workflow_dispatch` trigger: the Release workflow, `tag-release.yml`, starts `publish.yml` through that trigger, so until it has one, a release ships no packages ([#294](https://github.com/NCodeGroup/project-template/issues/294)).

### Changed

- GitLab CI for a .NET, Python or PowerShell project that answers `uses_node` installs nvs v1.7.1, pinned to its commit, and selects the Node.js `.node-version` names before the build, as for a Node.js project; in the PowerShell image, which has neither, it installs Git and curl first ([#290](https://github.com/NCodeGroup/project-template/issues/290), [ADR-0200](template/docs/decisions/project-template/0200-nodejs-comes-from-nvs-and-a-node-version-file.md)).

## [0.72.0] - 2026-11-08

### Added

- A GitHub project gets `.github/workflows/tag-release.yml`, template-owned, which runs `.template/Publish-Release.ps1` on each push to `main`: with `release: tag` or `tag+release` in `AGENTS.md`'s Landing section, it tags the commit a pull request merged as with the plan's version and, with `tag+release`, publishes the GitHub release through GitHub's REST API, so a plan landed from a Claude Code cloud session needs nobody to run anything after the merge. The version is the changelog's newest release section or, in a pre-release project, whose changelog has none, the `Release:` line of the merged pull request's description, with `## [Unreleased]` as the release notes; a `Release:` line that disagrees with the changelog fails the run. It never moves a tag or changes a release, and a failed run is retried with Re-run failed jobs in the Actions tab ([#292](https://github.com/NCodeGroup/project-template/issues/292), [ADR-0016](template/docs/decisions/project-template/0016-releases-are-tagged-and-published-when-their-pull-request-merges.md)).

### Changed

- **Breaking:** A .NET library's `publish.yml` must also run on `workflow_dispatch`: the Release workflow publishes each release with the workflow's token, which starts no other workflow, and then starts `publish.yml` through `workflow_dispatch`. Until an existing project adds the trigger, the Release workflow publishes the release, then fails and names the change, and no package ships. `publish.yml` is the project's, so updates never change it: add `workflow_dispatch:` with a required string input `tag` to its `on:` section, set the `TAG` of the step that reads the version to `${{ github.event.release.tag_name || inputs.tag }}` and write `"tag=$env:TAG" >> $env:GITHUB_OUTPUT` there, and give the checkout `ref: refs/tags/${{ steps.version.outputs.tag }}`, as the template's `publish.yml` does. `Update-Project.ps1` shows the template's change to it and warns while the trigger is missing ([#292](https://github.com/NCodeGroup/project-template/issues/292), [ADR-0137](template/docs/decisions/project-template/0137-the-release-workflow-starts-package-publishing.md)).

- `/ship-plan` writes the plan's version into the pull request description as a `Release: <version>` line, and sets that line again on the open pull request after a renumber; run after the merge, it finds the tag and the release the Release workflow made and only closes the plan's issues and files its follow-ups ([#292](https://github.com/NCodeGroup/project-template/issues/292)).

## [0.71.0] - 2026-11-08

### Added

- `Adopt-Project.ps1` answers `uses_node` for a .NET, Python or other repository with a `package.json` within two folders of the root, or a `.nvmrc` or `.node-version` at the root, and gives `.node-version` the version a `.nvmrc` names when the repository has no `.node-version`; an existing `.node-version` is kept ([#287](https://github.com/NCodeGroup/project-template/issues/287), [ADR-0200](template/docs/decisions/project-template/0200-nodejs-comes-from-nvs-and-a-node-version-file.md)).

### Changed

- CI and the Copilot setup workflow on GitHub set up the Node.js `.node-version` names for every stack that answers `uses_node`, not only Node.js, and the setup workflow runs when `.node-version` changes ([#286](https://github.com/NCodeGroup/project-template/issues/286)).

- GitLab CI for a Node.js project installs nvs v1.7.1, pinned to its commit, and selects the Node.js `.node-version` names, so CI and developers' PCs run the same version; a Bun project keeps the `oven/bun:1` image ([#285](https://github.com/NCodeGroup/project-template/issues/285), [ADR-0200](template/docs/decisions/project-template/0200-nodejs-comes-from-nvs-and-a-node-version-file.md)).

### Fixed

- `Update-Project.ps1` renders the template's changes to project-owned files with `pre-release: tracked` unless the project's `AGENTS.md` says `pre-release: untracked`, so a released project is no longer shown pre-release wording to copy ([#281](https://github.com/NCodeGroup/project-template/issues/281)).

## [0.70.0] - 2026-11-08

### Added

- A `SessionStart` hook in `.claude/settings.json` runs `.claude/hooks/ensure-pwsh.sh`, so a Claude Code cloud session has `pwsh` without stopping to ask to install it. In a cloud session (`CLAUDE_CODE_REMOTE=true`) whose container lacks `pwsh`, the script installs the pinned PowerShell package from Microsoft's apt repository, which a cloud session's default network reaches, after checking its SHA-256; it supports Ubuntu 24.04 x86_64 and elsewhere prints one line and exits 0. It does nothing on a developer's own machine or when `pwsh` is already there, such as after a cloud environment's setup script installed it, and it never fails the session. `tests/Test-EnsurePwsh.ps1` checks the script's paths and the hook's entry in both settings files. Projects get them with `.\.template\Update-Project.ps1`, which merges the hook into the project's `.claude/settings.json`.

## [0.69.0] - 2026-11-08

### Added

- A new `uses_node` answer, asked for every stack and yes by default for Node.js, decides the Node.js setup on the PC and in the repository, so a .NET or Python project with a frontend gets the same `.node-version`, scripts, agent rules and prelude as a Node.js project. CI sets up Node.js only for Node.js projects so far.

- `.node-version`, a project-owned file holding the Node.js major version, `26`, which nvs, `actions/setup-node` and the scripts below read, so one file names the version everywhere.

- `.template/Initialize-Nvs.ps1` sets nvs up once per PC in `~/.bashrc` and the PowerShell profile, is safe to run again, and installs the `.node-version` release.

- `.template/Use-Node.ps1` and `.template/use-node.sh` put the `.node-version` Node.js on `PATH` in a shell that loads no profile, which is why agents no longer find `node` missing.

- The Node.js rules in `.github/instructions/project-template.instructions.md` tell an agent how to get `node` on `PATH` and which scripts to run.

- ADR-0200 records the standard: nvs, `.node-version` and the scripts.

- A new project's `AGENTS.md` sets `prelude: ./.template/Use-Node.ps1`, so Node.js is on `PATH` before every gate and Done-when command.

### Changed

- GitHub CI and `copilot-setup-steps.yml` of a Node.js project read `.node-version` instead of `lts/*`, and the setup workflow's path filters list it.

- No change for projects made from the template. `tests/Test-NodeSetup.ps1` checks the Node.js scripts against stand-ins for nvs, and `tests/Test-Template.ps1` has new checks for the `uses_node` answer and the files it adds.

- `.claude/settings.json`, a merged file, allows every Bash and PowerShell command without asking, so a session no longer stops on each command. The default stance is allow everything, with a deny list for the exceptions: `git push`, `git tag` and `gh release create` run without asking too, and the template's `ask` rules for `git push` are removed. The `deny` rules for `.env` and `secrets/` still apply, because they take precedence over an allow rule. Because `deny` covers the Read tool only, new `ask` rules make any Bash or PowerShell command that mentions `.env` or `secrets`, such as `cat .env` or `ls .\secrets`, ask for approval first. The rules match the command's text, so they slow a careless read but do not block a determined one; a sandbox or a PreToolUse hook enforces.

- An existing project is asked `uses_node` on update, yes by default for a Node.js project. `AGENTS.md` and `.node-version` are project-owned, so add `.node-version` (one line, the Node.js major version, such as `26`) and set `prelude: ./.template/Use-Node.ps1` in the Landing section of `AGENTS.md` yourself, then run `./.template/Initialize-Nvs.ps1` once per PC.

## [0.68.4] - 2026-11-08

### Changed

- `/run-issues` and `/run-feedback`, in Claude Code and Copilot, post `/review` as a top-level comment after each push of fix steps and leave it as posted, with whatever footer the session's tooling appends, such as a Claude Code cloud session's `---` line and `_Generated by [Claude Code](…)_`: NCode Review v1.1.2, which `code-review.yml` pins, reads the command from the comment's first line and sets aside everything from a `---` line on. The read-back that removes agent attribution from every other description, issue and comment leaves a `/review` comment alone, no command deletes a `/review` comment or asks the maintainer to post one, and the header of `code-review.yml`, the README, USAGE and ADR-0002 say so. The `-Scenario session-footer` runs of `tests/e2e/Test-RunIssues.ps1` and `Test-RunFeedback.ps1` check that each `/review` comment keeps its footer and still starts the review, and the `gh` stand-in refuses a comment's delete and an edit of a `/review` comment ([#279](https://github.com/NCodeGroup/project-template/issues/279)).

## [0.68.3] - 2026-11-08

### Fixed

- `.template/Update-Project.ps1` stages only what an update changes: the tracked files with `git add -u` and each file the update adds by name, never with `git add -A`. From the reset of the template-owned files to the end of the run, `.git/info/exclude` holds a copy of the project's whole `.gitignore`, an adopted project's kept lines included, so a folder only those lines ignore, such as `node_modules/`, `.turbo/` or `dist/` in a checkout with a frontend installed and built, is never staged or committed, and the update doesn't stall staging it. A file the project ignored when the update started stays unstaged when the updated `.gitignore` doesn't ignore it. An update that stops on a conflict stages the files it added and says to finish with `git add -u`. The update to this version runs it, because a project's script hands the update over to the target version's copy ([#275](https://github.com/NCodeGroup/project-template/issues/275)).

## [0.68.2] - 2026-11-08

### Fixed

- The Entity Framework Core rule in `.github/instructions/csharp.instructions.md` and item 8 of ADR-0143 (.NET) keep a pre-release project's `InitialCreate` migration for each context in `Migrations/<Name>`, the context's class name without its `DbContext` or `Context` suffix, such as `Migrations/OpenId` for `OpenIdDbContext`, and regenerate it with `dotnet ef migrations add InitialCreate --context <Context> --output-dir Migrations/<Name>`. A folder named for the class becomes a namespace segment that hides the class from the scaffolded code, which then fails to compile with CS0118. A project whose migrations are in `Migrations/<Context>` deletes that folder and runs the command. Projects get them with `.\.template\Update-Project.ps1` ([#273](https://github.com/NCodeGroup/project-template/issues/273)).

- `.github/workflows/copilot-setup-steps.yml` (GitHub, with Copilot) runs on a push to `main` or a pull request that changes it or a file its steps run, for .NET the `.github/actions/install-dotnet` action and `build/Get-TestRuntimes.ps1`, so a change to the .NET setup, such as a Dependabot bump of the action's `actions/setup-dotnet` pins, shows whether the Copilot setup still works before a session needs it. Its header says that a step that runs a file of the repository adds that file to both `paths` lists, and the action's header says that a workflow whose triggers list `paths` lists the action and the script. Projects get them with `.\.template\Update-Project.ps1`, which merges them with the project's own edits ([#274](https://github.com/NCodeGroup/project-template/issues/274)).

## [0.68.1] - 2026-11-07

### Changed

- No change for projects made from the template. Every end-to-end test, `tests/e2e/Test-AddressFeedback.ps1`, `Test-AddressFeedbackGitLab.ps1`, `Test-RunFeedback.ps1` and `Test-RunIssues.ps1`, takes `-Tool copilot` to run its prompts in the Copilot CLI (`copilot -p`) instead of Claude Code, on the same fixture and with the same checks, so a model runs the Copilot copies of `/address-feedback`, `/run-feedback` and `/run-issues`; `Test-AddressFeedback.ps1 -Tool copilot -Scenario resume-claude` has Copilot move a Claude Code run's worktree into the main checkout and finish it, and `-Scenario resume-claude` names the scenario whose stopped run Claude Code left. The runner, `tests/e2e/Agent.ps1`, gives a Copilot session a `COPILOT_HOME` of its own, no GitHub MCP server and the token it reads before the `gh` stand-in shadows `gh`, and checks that the session ran the project's skill; `-Model` picks either tool's model, `-MaxBudgetUsd` also caps a Copilot session, in AI credits, `-TimeoutMinutes` (45 by default) stops a `claude` or `copilot` call that runs longer, with its child processes, and `tests/Test-AgentRunner.ps1` checks the runner against stand-ins for both CLIs. The fixture project has both tools' commands, and each `-SetupOnly` checks that both copies hold what its checks read. The check that `/address-feedback #2` stopped on its branch name also requires no `feedback-2` or `worktree-feedback-2` branch, the main checkout on `main` and no `PLAN.md`, so a Copilot run that stopped on a leftover checkout fails it ([#270](https://github.com/NCodeGroup/project-template/issues/270)).

## [0.68.0] - 2026-11-07

### Added

- `/address-feedback <number>` finishes a run on that pull request that the other tool stopped. Claude Code moves a Copilot run's `feedback-<number>` branch, with its `PLAN.md`, into the worktree `.claude/worktrees/feedback-<number>` and switches the folder it was checked out in to the default branch; Copilot moves a Claude Code run's `worktree-feedback-<number>` branch, with its `PLAN.md`, into the open folder as `feedback-<number>` and removes the worktree, never by force. Each stops when the run's checkout has uncommitted changes or holds another pull request's plan, and the move changes none of the run's commits and no line of its plan, so switching tools in the middle of a run strands nothing. `/run-feedback <number>` does the same in its first pass. Projects get it with `.\.template\Update-Project.ps1` ([#267](https://github.com/NCodeGroup/project-template/issues/267)).

### Changed

- No change for projects made from the template. `tests/e2e/Test-AddressFeedback.ps1 -Scenario resume` runs `/address-feedback #1` on a run that stopped once its plan was reviewed, and `-Scenario resume-copilot` on the same run left on Copilot's `feedback-1` branch in the main checkout; each checks that the run pushes the stopped run's step as it was, names that commit in the writer's reply, answers the plan's other items and leaves no checkout behind. CI sets up both fixtures, and every setup checks that the state script still sends a stopped run to `/address-feedback 1` once each tool's resume has moved it ([#266](https://github.com/NCodeGroup/project-template/issues/266), [#267](https://github.com/NCodeGroup/project-template/issues/267)).

## [0.67.0] - 2026-11-07

### Added

- `.github/actions/install-dotnet` (.NET, GitHub), a composite action, installs the SDK `global.json` selects and then the runtimes `build/Get-TestRuntimes.ps1` names with `actions/setup-dotnet`. `ci.yml`, `copilot-setup-steps.yml` and a library's `publish.yml` call it right after their checkout, and a project's own workflows that build or test call it the same way, so the .NET setup lives in one place. It is a merged file, and for .NET `.github/dependabot.yml`'s `github-actions` entry reads `.github/actions/*` beside the workflows, so the project's Dependabot moves the action's `actions/setup-dotnet` pins. Projects get it with `.\.template\Update-Project.ps1`, which lists the template's change to a library's own `publish.yml` ([#263](https://github.com/NCodeGroup/project-template/issues/263)).

### Changed

- ADR-0008, `build/Get-TestRuntimes.ps1`'s help and `build/Install-Dotnet.ps1`'s help say the `.github/actions/install-dotnet` action installs the SDK and the test runtimes on GitHub, and that the project's Dependabot moves the pins in it as in the CI workflow. Projects get them with `.\.template\Update-Project.ps1` ([#263](https://github.com/NCodeGroup/project-template/issues/263)).

- `build/Install-Dotnet.ps1` (.NET) gives up on a request after 30 seconds without an answer, or 60 seconds without more of a download, so a download that stalls partway fails, and tries a failed request twice more, after 5 and then 10 seconds, or after the `Retry-After` a 429 or 503 gives, up to 60 seconds, each plus up to a second at random so that clients that failed together don't retry together; a client error other than 408 or 429 fails at once. The script names these limits once, at its top. It needs PowerShell 7.4 or later, and `tests/Test-TemplateDotnet.ps1` checks the timeouts, the retries and how it finds the installation against its offline stand-ins. Projects get it with `.\.template\Update-Project.ps1` ([#263](https://github.com/NCodeGroup/project-template/issues/263), [#264](https://github.com/NCodeGroup/project-template/pull/264)).

## [0.66.0] - 2026-11-07

### Added

- `/address-feedback <number>` finishes a run on that pull request that stopped, such as on a question for you or a step that needs re-planning: it resumes the run's worktree in Claude Code, or its `feedback-<number>` branch in Copilot, with its commits and `PLAN.md`, carries on from the stage where the run stopped, pushes to the pull request's branch and replies to the items the plan's `## Feedback` section names. Once the pull request is merged or closed, it offers to discard the run instead. `/run-feedback <number>` resumes it the same way in its first pass. Each tool finishes its own runs. Projects get it with `.\.template\Update-Project.ps1` ([#259](https://github.com/NCodeGroup/project-template/issues/259)).

### Changed

- No change for projects made from the template. `tests/Test-PlanState.ps1` checks a feedback plan's state on GitHub and GitLab, `tests/Test-Template.ps1` checks the resume and the redirects in every copy, and the end-to-end setups `tests/e2e/Test-AddressFeedback.ps1 -SetupOnly` and `tests/e2e/Test-AddressFeedbackGitLab.ps1 -SetupOnly` check that the state script sends a stopped run's reviewed plan back to `/address-feedback` ([#259](https://github.com/NCodeGroup/project-template/issues/259)).

### Fixed

- A plan that `/address-feedback` writes names its pull request on a `Pull request:` line and the commit the run started from on a `Start:` line. `.template/Get-PlanState.ps1` prints that number as `feedback`, reads that pull request's state by its number on the `pr` line, prints `conflicts: -` for it, and names `address-feedback <number>` as `next` once its steps are done and reviewed, never `ship-plan`, or a `none` that says `address-feedback <number>` discards the run once the pull request is merged or closed. `/continue-plan` names `/address-feedback <number>` for such a plan, and `/ship-plan`, `/finish-plan` and `/review-plan-diff` send it there, so a stopped run's fixes reach the reviewed pull request's branch with a reply on each item, never a pull request of their own. Projects get it with `.\.template\Update-Project.ps1` ([#259](https://github.com/NCodeGroup/project-template/issues/259)).

- `/address-feedback` fetches the pull request's branch before it compares the run's commits with it, so its protected-file check and its check for someone else's push see the branch as it is on `origin`, and it fetches again right before the push. When someone pushed to that branch during the run, it stops and says how to go on: merge `origin/<head>` into the run's checkout, never by a rebase or a force-push, then run `/address-feedback <number>` again. A resumed run whose `next` is one the run stops on, such as `none the plan has no steps`, stops before it asks to go ahead. Projects get it with `.\.template\Update-Project.ps1` ([#259](https://github.com/NCodeGroup/project-template/issues/259)).

## [0.65.0] - 2026-11-07

### Added

- `build/Install-Dotnet.ps1` (.NET) installs the SDK `global.json` selects, honouring its `rollForward` policy as `actions/setup-dotnet` does, then the runtimes `build/Get-TestRuntimes.ps1` names, taking each from Microsoft's release metadata and only once its download matches the SHA-512 that metadata gives. `.gitlab-ci.yml` runs it before the build, so a GitLab project builds with the SDK a GitHub one does, and a test project that targets an older .NET runs there too ([#255](https://github.com/NCodeGroup/project-template/issues/255), [#260](https://github.com/NCodeGroup/project-template/issues/260)).

### Changed

- ADR-0008 says CI installs the SDK `global.json` selects under its `rollForward` policy, with `actions/setup-dotnet` on GitHub and `build/Install-Dotnet.ps1` on GitLab, and that the SDK under `latestFeature`, the test runtimes and GitLab's `mcr.microsoft.com/dotnet/sdk:10.0` image, which supplies git and PowerShell, follow their newest release. `CONTRIBUTING.md` points at `build/Install-Dotnet.ps1` to install the SDK and runtimes locally ([#255](https://github.com/NCodeGroup/project-template/issues/255), [#260](https://github.com/NCodeGroup/project-template/issues/260)).

## [0.64.1] - 2026-11-07

### Changed

- ADR-0143 and the Entity Framework Core section of `csharp.instructions.md` (.NET) name a pre-release project's one initial migration per database context `InitialCreate`, the name EF Core's documentation gives a project's first migration, keep it in the context's own folder `Migrations/<Context>`, and regenerate it on each model change with `dotnet ef migrations add InitialCreate --context <Context> --output-dir Migrations/<Context>`, which works as written with one context or several. Projects get them with `.\.template\Update-Project.ps1` ([#262](https://github.com/NCodeGroup/project-template/issues/262)).

## [0.64.0] - 2026-11-07

### Added

- `/address-feedback` and `/run-feedback` run in Copilot Chat and Copilot CLI too, from two new templates, `address-feedback-copilot` and `run-feedback-copilot`: they take the same requests, judge each open review thread, top-level comment and review summary against the code, push the fixes to the pull request's branch, never forced, and reply to each item starting with `Autopilot:`. A pass works in the open folder instead of a worktree: it needs a clean working tree and no `PLAN.md`, works on a branch `feedback-<number>` made from the pull request's branch, and once its fixes are pushed switches back to the branch you had checked out and deletes `feedback-<number>`; a stop after its plan is written leaves that branch checked out for `/continue-plan`. `/run-feedback` waits between passes with a foreground sleep. Run them in a Local session in Copilot Chat, or a Copilot CLI session started on Opus, without approval prompts (Bypass Approvals or Autopilot; `/allow-all`). Projects get them with `.\.template\Update-Project.ps1` ([#254](https://github.com/NCodeGroup/project-template/issues/254)).

### Changed

- `/address-feedback` keeps what differs between Claude Code and Copilot, how the run's worktree or branch is made, left and cleaned up, in a `## Checkout` section at its end; in Claude Code it also stops while a Copilot run on the same pull request is open on its branch `feedback-<number>`, and `/continue-plan` offers `/address-feedback <number>` in every tool. Projects get it with `.\.template\Update-Project.ps1` ([#254](https://github.com/NCodeGroup/project-template/issues/254)).
- The project instructions, and a new project's `AGENTS.md` Landing section, name `/address-feedback` and `/run-feedback` among the commands that run `prelude` and `gate` before each push, and `USAGE.md` says each feedback pass runs the gate. Projects get the instructions with `.\.template\Update-Project.ps1`; an existing project's `AGENTS.md` is its own, so a project that sets `gate` or `prelude` may add the two commands to its Landing section's description itself ([#254](https://github.com/NCodeGroup/project-template/issues/254)).
- No change for projects made from the template. The Claude Code and Copilot variants of `address-feedback` and `run-feedback` share their text through `workflow/templates/_address-feedback-body.md` and `_run-feedback-body.md`, and the orchestrating commands share how each tool runs a stage through `_claude-stages.md` and `_copilot-stages.md`, so each rule is written once; `tests/Test-Template.ps1` checks the Copilot copies and that every copy holds its body partial's whole text ([#254](https://github.com/NCodeGroup/project-template/issues/254)).

## [0.63.1] - 2026-11-07

### Changed

- ADR-0014, "Every pull request discussion is remediated and replied to before it merges", states its context and consequences in the present tense: an agent that replies only to the threads it acts on leaves the person who resolves them to read the code again, every nit thread gets a reply, and `tools/Set-RepositoryBaseline.ps1` turns on conversation resolution in a ruleset an owner shaped and changes nothing else in it. Projects get it with `.\.template\Update-Project.ps1` ([#256](https://github.com/NCodeGroup/project-template/issues/256)).
- No change for projects made from the template. The `gh` stand-in in `tests/Test-PlanState.ps1` and the end-to-end stand-ins `tests/e2e/gh.ps1` and `tests/e2e/glab.ps1` append to their logs one call at a time, through a named mutex, so the calls `workflow/Get-PlanState.ps1` makes at the same time are each logged and answered, and `tests/Test-PlanState.ps1` passes on a loaded machine ([#257](https://github.com/NCodeGroup/project-template/issues/257)).

## [0.63.0] - 2026-11-07

### Added

- `build/Get-TestRuntimes.ps1` (.NET) names the .NET runtimes the `<Name>.Tests` projects in the root solution target besides the SDK's own, and `ci.yml`, `copilot-setup-steps.yml` and a library's `publish.yml` install them, so a test project that targets an older .NET runs in CI, in the Copilot cloud agent's session and at release. Projects get it with `.\.template\Update-Project.ps1`, which shows the change to the project-owned `publish.yml` to copy ([#248](https://github.com/NCodeGroup/project-template/issues/248)).
- For a .NET library whose current major has a release built with a higher assembly version than the `<major>.0.0.0` that `build/ProjectTemplate.props` pins, `Update-Project.ps1` and `Adopt-Project.ps1`'s follow-up request name the `AssemblyVersion` to set in `Directory.Build.props` until the next major, as ADR-0136 says ([#248](https://github.com/NCodeGroup/project-template/issues/248)).
- `Update-Project.ps1` and `Adopt-Project.ps1` leave `.github/workflows/publish.yml` out of a library whose own workflow already runs `nuget push`, so a published release runs one publisher, and the update warns when both exist ([#248](https://github.com/NCodeGroup/project-template/issues/248)).

### Changed

- The `license` answer is the license of the repository and of every package: `PackageLicenseExpression` in `build/ProjectTemplate.props`, the C# file header in `.editorconfig`, `LICENSE.txt`, `COPYRIGHT.txt`, `README.md` and `CONTRIBUTING.md` follow it, a NuGet library requires it, `Update-Project.ps1` stops before it changes anything when a library's answers give none and prints the `-Data` that gives one, and `Adopt-Project.ps1` works it out from `Directory.Build.props`'s `PackageLicenseExpression` or the repository's license file ([#248](https://github.com/NCodeGroup/project-template/issues/248)).
- `code-review.yml` takes NCode Review v1.1.2's caller: both jobs pin v1.1.2, and the review job's concurrency group puts only a comment whose first line is exactly `/review` in the pull request's group, so a `/review` followed by more lines, such as an agent's `---` footer, reviews instead of cancelling a review in progress. The file is project-owned: `Update-Project.ps1` shows the change ([#248](https://github.com/NCodeGroup/project-template/issues/248)).
- `SECURITY.md` says packages reach nuget.org only through `publish.yml` once its one-time setup is done, and carries no hidden maintainer note: `tools/Set-RepositoryBaseline.ps1` turns on private vulnerability reporting, which its Report a Vulnerability button needs ([#248](https://github.com/NCodeGroup/project-template/issues/248)).
- `CONTRIBUTING.md` points at `AGENTS.md` and `.github/instructions/project-template.instructions.md` for the AI-assisted workflow, and lists the runtimes `build/Get-TestRuntimes.ps1` names among a .NET project's prerequisites ([#248](https://github.com/NCodeGroup/project-template/issues/248)).
- `docs/metrics.md` and `docs/decisions/README.md` say above each table what an empty table means ([#248](https://github.com/NCodeGroup/project-template/issues/248)).
- `/address-feedback` and `/run-feedback` say in their descriptions that they run in Claude Code only ([#248](https://github.com/NCodeGroup/project-template/issues/248)).
- ADR-0109, ADR-0112 and ADR-0143 say whom they apply to inside Context, as the other records do; ADR-0126 describes ADR-0144 by its title; ADR-0131 names the template's adoption without naming its script ([#248](https://github.com/NCodeGroup/project-template/issues/248)).

### Removed

- The `package_license` answer: a library's packages carry the `license` answer ([#248](https://github.com/NCodeGroup/project-template/issues/248)).

### Fixed

- A library's `publish.yml` counts only a 404 from nuget.org as a package with no published version; any other failed lookup stops the publish job instead of skipping the already-published check and miscounting the summary ([#248](https://github.com/NCodeGroup/project-template/issues/248)).

## [0.62.0] - 2026-11-07

### Added

- A pre-release posture for a project that has shipped nothing: `- pre-release: untracked` in `AGENTS.md`'s Landing section, which a new project starts with, keeps the project pre-release until a version tag of 1.0.0 or later. Every text then describes the product as it is, the changelog's `## [Unreleased]` is a catalog of what the product does under `### Added` and `### Security` that each plan's last step edits in place, a release's notes are that catalog, and a breaking change needs no deprecation, compatibility shim, migration path or `**Breaking:**` label. The plan that releases the first stable version moves the catalog into that version's section. `- pre-release: tracked`, the default for a missing line, tracks every change from the first release. The template writes the line from the Copier answer `pre_release`, which is never asked or recorded: a new project gets `untracked`, an `AGENTS.md` that `Adopt-Project.ps1` has the template write gets `tracked`, and `New-Project.ps1 -Data @{ pre_release = 'tracked' }` starts a project tracked. ADR-0015 records the decision ([#249](https://github.com/NCodeGroup/project-template/issues/249)).
- `.template/Get-PlanState.ps1` prints `pre-release: yes` or `no`, and the Landing key on its `landing` line; its `changelog-backfill`, `Update-Project.ps1` and `Adopt-Project.ps1` need no changelog section for a pre-release project's tags below 1.0.0 ([#249](https://github.com/NCodeGroup/project-template/issues/249)).

### Changed

- In a pre-release project, `/ship-plan` publishes a release from `## [Unreleased]`, moves a plan whose version another plan took by its `Release:` line alone, and hands a plan back to `/replan-step` when the first stable release lands before it; `/review-plan-diff` checks that the plan's texts describe the product as it is; planners keep the version below 1.0.0 until a request asks for the first stable release ([#249](https://github.com/NCodeGroup/project-template/issues/249)).
- ADR-0108: a .NET project's serializer refuses a stored document that isn't an envelope with a descriptive `JsonException`, and only a project that adopts the envelope over documents it already stored reads a document without `$ver` as version 1. Before a pre-release project's first stable release, a payload changes in place at version 1, with no upcaster. In a pre-release project, ADR-0143 keeps one `Initial` migration per database context, regenerated on each model change, and ADR-0131, ADR-0136 and `csharp.instructions.md` let the public API change in place ([#250](https://github.com/NCodeGroup/project-template/issues/250)).

## [0.61.2] - 2026-11-03

### Changed

- No change for projects made from the template. The end-to-end `gh` stand-in, `tests/e2e/gh.ps1`, serves the REST routes `workflow/templates/_github-rest.md` maps `gh` commands to (a pull request, its `ccr/review_threads`, review comments, top-level comments and reviews, a thread reply and a comment post), and with a new `graphql-refused.txt` it refuses `gh api graphql` and the `gh pr`, `gh issue`, `gh release` and `gh repo` commands as a Claude Code cloud session's proxy does. `tests/e2e/Test-AddressFeedback.ps1 -Scenario rest` runs `/address-feedback` that way and checks that every thread gets its `Autopilot:` reply through `pulls/<number>/comments/<id>/replies`; CI runs its fixture setup ([#245](https://github.com/NCodeGroup/project-template/issues/245)).

## [0.61.1] - 2026-11-03

### Changed

- No change for projects made from the template. A `glab` stand-in, `tests/e2e/glab.ps1`, serves merge requests, discussions and notes with the `gh` stand-in's `footer.txt` option, and a new end-to-end test, `tests/e2e/Test-AddressFeedbackGitLab.ps1`, runs `/address-feedback` on a GitLab fixture merge request whose notes come back with a Claude Code cloud session's footer, and checks that its discussion reply and top-level note are read back and edited through `glab api --method PUT`; CI runs its fixture setup ([#241](https://github.com/NCodeGroup/project-template/issues/241)).
- No change for projects made from the template. `tests/e2e/Test-RunIssues.ps1 -Scenario session-footer` runs `/run-issues` with the footer and two fix rounds, and checks that after the second push the run asks the maintainer for `/review` in an `Autopilot:` comment and posts no `/review` comment; the `gh` stand-in's new `delete-fails.txt` makes the run's `/review` comment stay, and its new `footer-pr-only.txt` keeps the footer off the plan snapshot, so the `/review` comment is the first post that comes back with it, and the test checks the run never answers it; CI runs its fixture setup ([#242](https://github.com/NCodeGroup/project-template/issues/242), [#243](https://github.com/NCodeGroup/project-template/issues/243)).

### Fixed

- `/run-issues`, Copilot's `run-issues`, `/address-feedback` and `/run-feedback` test whether a comment is only a slash command after setting aside the agent attribution at its end, so a `/review` comment whose delete failed after it came back with a session footer stays only a slash command, and a later check no longer answers the run's own comment as the maintainer's. Projects get it with `.\.template\Update-Project.ps1` ([#243](https://github.com/NCodeGroup/project-template/issues/243)).

## [0.61.0] - 2026-11-03

### Added

- The workflow commands that run `gh` (`/run-issues`, `/address-feedback`, `/run-feedback`, `/continue-plan`, `/ship-plan`, `/orchestrate-plan`, `/replan-step`, `/triage-issues`, the planning commands and Copilot's `run-issues`) now work in a session that refuses GitHub's GraphQL API, as a Claude Code cloud session's proxy does, where `gh api graphql` and every `gh pr`, `gh issue` and `gh release` command fail. Once a `gh` command fails that way, the command runs each of them in its REST form through `gh api` for the rest of the run: a pull request's review threads come from the proxy's `pulls/<number>/ccr/review_threads` route, or the GitHub MCP `pull_request_read` tool, and a thread reply goes through `pulls/<number>/comments/<id>/replies`; without a route that says whether a thread is resolved, the command stops and says why. A local session's commands don't change. The forms are in one new rule, `workflow/templates/_github-rest.md`. Projects get it with `.\.template\Update-Project.ps1` ([#240](https://github.com/NCodeGroup/project-template/issues/240)).

### Changed

- `.template/Get-PlanState.ps1` reads a plan's pull requests, issues and release through `gh api` REST paths instead of `gh pr list`, `gh issue view` and `gh release view`, so its `pr`, `merge`, `landed`, `issue-state` and `published` lines are right in a Claude Code cloud session too. Projects get it with `.\.template\Update-Project.ps1` ([#240](https://github.com/NCodeGroup/project-template/issues/240)).
- No change for projects made from the template. `tests/Test-PlanState.ps1` runs the state script with a `gh` stand-in that refuses GitHub's GraphQL API as the cloud proxy does, and checks a published release; the end-to-end `gh` stand-in, `tests/e2e/gh.ps1`, answers the state script's REST calls; and `tests/Test-Template.ps1` checks that every generated command that runs `gh pr`, `gh issue`, `gh release` or `gh api graphql` has the REST forms ([#240](https://github.com/NCodeGroup/project-template/issues/240)).

## [0.60.0] - 2026-11-02

### Changed

- The workflow commands that post to GitHub or GitLab (`/ship-plan`, `/run-issues`, `/address-feedback`, `/run-feedback`, `/orchestrate-plan`, `/replan-step` and the planning commands' plan snapshot) read back each pull request or merge request description, issue, top-level comment and note they create or edit, and remove any agent attribution a session's tooling appended at its end, whichever AI agent or model runs it: a line that says the text was generated, written or created with or by an AI tool, such as the `---` line and `_Generated by [Claude Code](…)_` footer a Claude Code cloud session appends, or a line that holds only a link to an agent's session or task, such as one from Codex, Cursor, Devin or Jules. They remove it through a route that doesn't append it again: on GitHub the GitHub MCP tools (`update_pull_request`, `issue_write`, `update_issue_comment`) where the session has them, since a Claude Code cloud session's edit through `gh` appends the footer again, else `gh`; on GitLab `glab`. What a second read-back still shows, such as a GitHub review-thread reply a cloud session can't edit without the footer, is still posted and listed in the report. `gh` or `glab` in a local session appends nothing, so nothing changes there. Projects get it with `.\.template\Update-Project.ps1` ([#238](https://github.com/NCodeGroup/project-template/issues/238)).
- `/run-issues` and `/run-feedback` read their `/review` comment back. NCode Review starts only on a comment that is exactly `/review` when it is created, so when the session's tooling appended anything to it, the run deletes it, posts no other `/review` in that run, and asks the maintainer in an `Autopilot:` comment to comment `/review`, instead of posting one that silently starts nothing; `/run-feedback` then awaits the review that comment starts, for up to an hour, before it recommends the merge ([#238](https://github.com/NCodeGroup/project-template/issues/238)).
- No change for projects made from the template. The end-to-end tests' `gh` stand-in, `tests/e2e/gh.ps1`, answers a comment read back, edited or deleted by its id, as the commands now do after posting one, and with a `footer.txt` in its host folder saves each comment and thread reply with a Claude Code cloud session's footer, which `tests/e2e/Test-RunFeedback.ps1 -Scenario session-footer` uses to check that `/run-feedback` deletes its `/review` comment, asks the maintainer for one and removes the footer from its other comments, `tests/Test-Template.ps1` checks that each command that posts to GitHub or GitLab has the read-back, and `tests/AttributionFixtures.psd1` holds one or more attribution lines and accounts per agent family, and the people and prose that must pass, which `tests/Test-CommitAttribution.ps1` and `tests/Test-GitHooks.ps1` both use. `tests/Test-Template.ps1` builds the list of files that must have the read-back from every workflow template whose text includes it, the planning commands and agents included, and checks each decision of the `/review` read-back in every generated `/run-issues` and `/run-feedback`. The end-to-end tests run `claude` with `--strict-mcp-config`, so a session has none of your MCP servers ([#238](https://github.com/NCodeGroup/project-template/issues/238)).

### Fixed

- `.template/Test-CommitAttribution.ps1`, the `Commit attribution` check, now fails attribution from any AI agent or model, not only Copilot and Claude: a commit authored or committed by an agent's app or bot account, such as Codex's, Cursor's, Devin's, Jules's, Gemini's, Grok's or Amazon Q's, by an address only an agent uses, or by a name aider marks with " (aider)"; a `Co-authored-by:` line that names an agent or model or uses an agent's address, such as `noreply@openai.com`, `cursoragent@cursor.com`, `noreply@x.ai`, `aider@aider.chat`, `noreply@pi.dev` or a GitLab Duo address; a `Claude-Session:`, `Agent-Logs-Url:` or `Amp-Thread-ID:` trailer, or a `Made-with:`, `Assisted-by:` or `Generated-by:` trailer that names an AI tool; a line that starts, after any symbols or underscores, with "Generated with", "Generated by", "Created by", "Made with" or the like and then an AI tool or model, such as GitHub Copilot, Claude Opus 4.5, GPT-5 or Qwen3, or a cloud session's `_Generated by [Claude Code](…)_` footer, which it let through because it matched only "Generated with" after symbols other than `_`; and a line that holds only a link to an agent's session or task, such as `claude.ai/code/session_…` or `chatgpt.com/codex/tasks/…`. A name an agent shares with people, such as Claude, Devin, Jules, Cline or Amp, counts only with an agent's address, a model's name or, in an `Assisted-by:` trailer, an `<agent>:` prefix, so a person's co-author or `Assisted-by:` trailer still passes. `.githooks/commit-msg` strips the same lines from a commit message, with the same patterns. Projects get both with `.\.template\Update-Project.ps1` ([#238](https://github.com/NCodeGroup/project-template/issues/238)).
- The `Commit attribution` check's remedy for a commit message with agent attribution now runs the project's `commit-msg` hook: `git rebase <base> --exec "git -c core.hooksPath=.githooks commit --amend --no-edit"`, which strips those lines. The remedy it printed before, `git commit --amend --no-edit --reset-author`, keeps the message as it is, so it removed them only in a clone where the hook runs. The check adds `--reset-author` only when an agent account authored or committed a commit, so a person's commit keeps its author, and `CONTRIBUTING.md`, the Copilot instructions and ADR-0002 say the same. Projects get it with `.\.template\Update-Project.ps1` ([#238](https://github.com/NCodeGroup/project-template/issues/238)).

## [0.59.2] - 2026-11-02

### Changed

- `/run-feedback` says that each pass follows `address-feedback` "with the changes listed under Each Pass below", instead of "with the changes Each Pass makes", which read as an unfinished clause. A comment in `.template/Update-Project.ps1` now says why an update that stops on a conflict stages only the files its reset changed: `git add -A` would mark the conflicted files resolved, conflict markers and all. Neither changes behavior. Projects get them with `.\.template\Update-Project.ps1` ([#235](https://github.com/NCodeGroup/project-template/issues/235)).
- No change for projects made from the template. `tests/Test-UpdateSkipPatterns.ps1` also checks an update whose project's version Copier can't render with its answers: the update warns with Copier's error that it skipped refreshing `docs/decisions/project-template/README.md`, lists nothing under Refreshed, keeps the index's local line and still reaches the target version ([#236](https://github.com/NCodeGroup/project-template/issues/236)).

## [0.59.1] - 2026-11-02

### Fixed

- `.\.template\Update-Project.ps1` now updates `docs/decisions/project-template/README.md`, the index of the template's decision records, like the rest of that template-owned folder. `copier.yml` listed `README.md` under `_skip_if_exists`, which Copier reads like a `.gitignore` pattern, so it also matched the index, and Copier wrote it once and never again. Every `_skip_if_exists` entry now starts with `/`, so it names one file from the project's root, and the update reads the entries as Copier does, also for the files it and `Adopt-Project.ps1` exclude. The first update to this version resets an index that earlier versions left out of date and lists it under `Refreshed`, which says that a local edit to it is discarded. Projects get it with `.\.template\Update-Project.ps1` ([#233](https://github.com/NCodeGroup/project-template/issues/233)).

## [0.59.0] - 2026-11-02

### Added

- `tools/Set-GitLabBaseline.ps1` sets a GitLab project's "Squash commits when merging" to "Do not allow" (`squash_option` `never`), so a plan's step commits stay on the default branch, as ADR-0013 records, and lets no one push to its default branch ("Allowed to push and merge" set to "No one"), so a change reaches it only through a merge request, as ADR-0005 records, and `.template/Get-PlanState.ps1` reports `protected: host`. Each is read first, changed only where it isn't so already, and reported as set, already set, would set (`-WhatIf`) or not available. GitLab Free can't change a protected branch's access levels in place, so the script removes a protection made only of roles and protects the branch again with its own merge, unprotect and force-push settings, restoring the earlier protection when that fails and failing the run only when the branch is left unprotected; a protection that names users, groups, deploy keys or code owners is reported and left to change in Settings > Repository > Protected branches, and an unprotected default branch is protected. Run it again for each GitLab project made from the template before 0.59.0 ([#228](https://github.com/NCodeGroup/project-template/issues/228), [#229](https://github.com/NCodeGroup/project-template/issues/229)).
- No change for projects made from the template. A new suite, `tests/Test-NewProjectRemote.ps1`, runs `New-Project.ps1 -CreateRemote` against stand-ins for `copier`, `gh`, `glab` and the two baseline scripts, and checks the GitHub and GitLab baseline calls, their `-NoBaseline` gate and their warning on failure; CI runs it ([#230](https://github.com/NCodeGroup/project-template/issues/230)).

### Changed

- ADR-0005 and ADR-0013 name `tools/Set-GitLabBaseline.ps1` as what lets no one push to a GitLab project's default branch and forbids squash merges there. Projects get them with `.\.template\Update-Project.ps1` ([#228](https://github.com/NCodeGroup/project-template/issues/228), [#229](https://github.com/NCodeGroup/project-template/issues/229)).

### Fixed

- `New-Project.ps1 -CreateRemote` no longer stops with "You cannot call a method on a null-valued expression" after creating a GitHub repository when `gh` can't read the signed-in user: it warns with the command that runs `tools/Set-RepositoryBaseline.ps1` again, with `<owner>` to fill in ([#230](https://github.com/NCodeGroup/project-template/issues/230)).

## [0.58.2] - 2026-11-02

### Fixed

- A .NET project whose `author_name` holds a `;` or `#`, such as `C# Tools; Inc.`, gets no `file_header_template` in `.editorconfig`, and a comment there that says why, instead of a header Roslyn cut short at that character: IDE0073 flagged every file carrying the whole copyright line, and its fix inserted the cut-off line. `author_name` keeps its exact text everywhere else. Projects get it with `.\.template\Update-Project.ps1` ([#227](https://github.com/NCodeGroup/project-template/issues/227)).

## [0.58.1] - 2026-11-01

### Added

- No change for projects made from the template. A new end-to-end test, `tests/e2e/Test-RunFeedback.ps1`, runs `/run-feedback #1 wait:0` in headless Claude Code on a fixture pull request with a writer's fix request, and checks that the run pushes the fix, never forced, comments `/review` after the push, sees NCode Review's `Code review` check run complete on the pushed commit, answers the bot's nit once and recommends the merge once, and never resolves a thread or merges. The end-to-end tests' `gh` stand-in answers the check-runs call `/run-feedback` makes, and CI runs the test's fixture check with `-SetupOnly` ([#221](https://github.com/NCodeGroup/project-template/issues/221)).

### Changed

- No change for projects made from the template. `tests/Test-UpdateConflictStaging.ps1` also checks that an update that stops on a conflict leaves a conflicted file with a non-ASCII name, one the update's reset changed, unmerged, so a restage that read its unmerged list without `core.quotePath=false` fails a test ([#217](https://github.com/NCodeGroup/project-template/issues/217)).

## [0.58.0] - 2026-11-01

### Added

- `tools/Set-GitLabBaseline.ps1` turns on a GitLab project's "All threads must be resolved" and "Pipelines must succeed" merge checks, which the decision records named but nothing enforced: each is read first, turned on only where it is off, and reported as set, already set, would set (`-WhatIf`) or not available, with the reason. Name the project with `-Project <group/name>` and `-Hostname`, or `-Path`, a clone whose `origin` remote names it. `New-Project.ps1 -CreateRemote` runs it for a new GitLab project unless `-NoBaseline` says not to, and `Adopt-Project.ps1` prints the command for a repository on GitLab. Run it once for each GitLab project made from the template before 0.58.0 ([#223](https://github.com/NCodeGroup/project-template/issues/223)).

### Changed

- ADR-0005 and ADR-0014 name `tools/Set-GitLabBaseline.ps1` as what turns on GitLab's "Pipelines must succeed" and "All threads must be resolved". Projects get it with `.\.template\Update-Project.ps1` ([#223](https://github.com/NCodeGroup/project-template/issues/223)).

## [0.57.1] - 2026-11-01

### Fixed

- A .NET project's `.editorconfig` sets `file_header_template` to the copyright line and `SPDX-License-Identifier: Apache-2.0` for an Apache-2.0 `license`, as it already did for other licenses, instead of the Apache-2.0 notice. Roslyn ends an `.editorconfig` value at its first `;` or `#`, so it read the notice only up to `(the "License")`: IDE0073 flagged every file carrying the whole notice, and its fix inserted the cut-off lines. Projects get it with `.\.template\Update-Project.ps1`; a project that raises IDE0073 above `suggestion` replaces each file's notice with the two lines ([#215](https://github.com/NCodeGroup/project-template/issues/215)).

## [0.57.0] - 2026-11-01

### Added

- A new decision record, ADR-0014, "Every pull request discussion is remediated and replied to before it merges": every review thread, and every top-level comment or review summary that asks for something, is fixed in a commit or answered with why nothing changed, and replied to, before the pull request merges; an agent replies starting with `Autopilot:` and never resolves a thread, and the person who merges resolves it. The agent instructions state it for every agent. Projects get it with `.\.template\Update-Project.ps1`.

### Changed

- `tools/Set-RepositoryBaseline.ps1` turns on "require conversation resolution" in every default-branch ruleset that already requires pull requests, its own "Protect main" from an older version or one someone else shaped, where it is off, sending only that ruleset's rules with the one parameter changed; `-WhatIf` shows it, and a refusal, or a pull request rule that came without parameters, is reported without failing the run. Run it again, such as `.\tools\Set-RepositoryBaseline.ps1 -All -Owner NCodeGroup -WhatIf` and then without `-WhatIf`, to enforce it in every repository.
- `/address-feedback`, `/run-feedback` and `/run-issues` reply to every unresolved review thread they read: a thread whose verdict is nothing to change gets `Autopilot: nothing to change` and why, NCode Review's nits and findings on protected paths get one reply each instead of none, `/run-issues` replies to threads someone else started without acting on them, and still at most twice on a thread a bot or someone else started. `/address-feedback` re-reads the threads after replying and lists any that still await a reply, such as one its 40-item limit left out, which gets no reply so the next run takes it, and every merge recommendation lists the threads still unresolved for you to resolve. In Claude Code, and for `/run-issues` in Copilot Chat and Copilot CLI too.
- `/continue-plan` lists every unresolved thread on a waiting pull request, not only NCode Review's findings, and says whether each awaits a reply or only your resolution.
- No change for projects made from the template. `tests/e2e/Test-RunIssues.ps1` now expects the replies `/run-issues` gives the threads it used to leave without one: `Autopilot: left as a follow-up` on NCode Review's nits, `Autopilot: left for you` on its finding on a protected path, and `Autopilot: not acted on` on another bot's thread without the finding marker.

## [0.56.0] - 2026-11-01

### Added

- A new `/run-feedback` command, the looping counterpart of `/address-feedback`, for any open pull request in the repository: every five minutes it runs an `/address-feedback` pass, which fixes what holds, pushes and replies with `Autopilot:`, until the pull request merges or closes. Like `/address-feedback`, it can start in the session that shipped a plan, leaving the plan's worktree and keeping it. After each push, when the project runs NCode Review, it comments `/review` and waits up to an hour for the bot's `Code review` check run on the pushed commit to complete. It keeps `/run-issues`' limits: the wait limit, 24 hours with nothing to answer unless `wait:<hours>` sets it, the Landing section's `max-review-rounds`, only NCode Review's `blocker` and `should-fix` findings, at most two `Autopilot:` replies per bot thread, and one merge recommendation once a pass finds nothing to fix or the rounds run out. It never merges, marks a pull request ready, resolves a thread or force-pushes. Claude Code only ([#218](https://github.com/NCodeGroup/project-template/issues/218)).

### Changed

- `/run-issues` comments `/review` on its draft pull request after it pushes a round's fix steps, when the project runs NCode Review, so the bot reviews the new commits. `code-review.yml` reviews a pull request when it opens or is marked ready, and again only when a writer comments `/review`, so before, NCode Review never saw the fix commits and the merge recommendation rested on findings about an older commit. In Claude Code, Copilot Chat and Copilot CLI ([#218](https://github.com/NCodeGroup/project-template/issues/218)).
- No change for projects made from the template. The end-to-end tests' `gh` stand-in gives NCode Review's review of a push only after a `/review` comment that follows the push, as `code-review.yml` does, so `tests/e2e/Test-RunIssues.ps1` checks that `/run-issues` asks for it ([#218](https://github.com/NCodeGroup/project-template/issues/218)).

## [0.55.0] - 2026-11-01

### Changed

- `/address-feedback` and `/run-issues`, run in a worktree the session entered with the `EnterWorktree` tool, such as a plan's worktree after `/ship-plan`, leave it with the `ExitWorktree` tool and `action: "keep"`, say so, and go on from the main checkout, so `/address-feedback <pr>` runs in the session that shipped the plan. The worktree, its branch and its `PLAN.md` stay as they were, for `/ship-plan` and `/finish-plan`. Both still stop and say to start a new session in the main checkout when the session can't leave, such as one started with `claude --worktree <name>` ([#214](https://github.com/NCodeGroup/project-template/issues/214)).

## [0.54.1] - 2026-11-01

### Fixed

- When `Update-Project.ps1` stops on a conflict, it stages each file it reset or set lines aside in as the update left it, so every file without a conflict is either unstaged or staged as it is in the working tree. Before, the index kept the version the update started from, such as an adopted project's `.gitignore` without the lines kept at adoption: the file was listed as `modified` even when the update left it as it was, and a commit that didn't stage it again, such as one that stages a list of files without it, dropped the project's lines. The update hands over to the new version's script, so this applies from the update to this version on ([#212](https://github.com/NCodeGroup/project-template/issues/212)).

## [0.54.0] - 2026-11-01

### Changed

- `/run-issues` gives an NCode Review finding that holds but asks for behavior the issue doesn't ask for, because the default branch already behaves that way and the issue doesn't name it or because the plan's `## Out of scope` excludes it, no fix step: it replies `Autopilot: left as a follow-up` and adds the finding to the plan's `## Follow-ups`, which `/ship-plan` files once the pull request has merged. It used to reply `Autopilot: not changed` to such a finding, which says a claim doesn't hold, and file nothing, or fix it in some runs and not others. A round whose findings are only such changes, test gaps, style and repeats leads to the merge recommendation ([#159](https://github.com/NCodeGroup/project-template/issues/159)).
- No change for projects made from the template. Both end-to-end tests have now run against a real model. The `gh` stand-in fails `gh pr view <branch>` for a branch without a pull request as `gh` does, because Claude Code itself looks up the current branch's pull request that way. `tests/e2e/Test-RunIssues.ps1` seeds a review thread of the owner's, which drives the run's fix round in both scenarios, and checks that NCode Review's blocker on behavior `main` already had becomes a follow-up ([#159](https://github.com/NCodeGroup/project-template/issues/159)).

## [0.53.0] - 2026-11-01

### Added

- When `Update-Project.ps1` stops on a conflict in a file the version it moves to owns, such as a `build/dod.ps1` of the project's own that the template now adds, it names the file and prints the `.\.template\Update-Project.ps1 -Data @{ project_owned_files = ... }` to run after abandoning the update, so the project keeps its copy. The command also names the files the answer already lists and any merged file the project seems to have replaced. The update hands over to the new version's script, so this applies from the update to this version on ([#207](https://github.com/NCodeGroup/project-template/issues/207)).
- `.template/Test-AdrIndex.ps1` fails a new project decision record numbered below 1000, the range the template's own records use: one whose number no record in `docs/decisions/` had at the merge base with the default branch (`origin/HEAD`, else `origin/main` or `origin/master`, or the commit the new `-Base` parameter names). Records a project already had below 1000 still pass, also under a new title; renumber a new one from 1000. Without a merge base, as in a shallow clone or a clone without `origin`, it skips that check and says so. So that CI can run it, `ci.yml`'s `build-and-test` job checks out the full history (`fetch-depth: 0`), and `.gitlab-ci.yml` passes the merge request's base with `-Base "$CI_MERGE_REQUEST_DIFF_BASE_SHA"`. Both files are merged, so an update brings this in; a project that owns its CI file makes that change itself ([#206](https://github.com/NCodeGroup/project-template/issues/206)).

## [0.52.0] - 2026-11-01

### Changed

- `/ship-plan` and `/run-issues` read the title and description they write for a pull request and delete each line of agent attribution, a `Co-authored-by:` line naming an AI agent, a `Claude-Session:` line or a "Generated with" line, before `gh pr create`, `gh pr edit`, `glab mr create` or `glab mr update` sends them, so the `Commit attribution` check no longer fails a pull request on text an agent wrote itself. The sentence lives in one shared fragment, `workflow/templates/_pr-attribution.md` ([#209](https://github.com/NCodeGroup/project-template/issues/209)).
- No change for projects made from the template. This repository's own `Commit attribution` job passes a pull request's title and description to `template/.template/Test-CommitAttribution.ps1` through the environment and runs again when the pull request is edited, as every project's GitHub CI has since v0.51.1, and `tests/Test-Template.ps1` fails when it doesn't ([#208](https://github.com/NCodeGroup/project-template/issues/208)).

## [0.51.1] - 2026-11-01

### Fixed

- The `Commit attribution` check also reads a pull request's title and description, which GitHub's squash merge, with the repository's commit message set to "Pull request title and description", makes the message of the commit on the default branch: a `Co-authored-by:` line naming an AI agent, a `Claude-Session:` line or a "Generated with Claude Code" line there fails the pull request, where it used to pass and fail only on the push to the default branch. `.template/Test-CommitAttribution.ps1` takes them as `-PullRequestTitle` and `-PullRequestBody`, and such a finding says to edit them, not to rebase. `ci.yml` passes them through the environment and also runs when a pull request is edited, so a description changed after the last push is checked again; `.gitlab-ci.yml` passes the merge request's, though GitLab gives CI only the first 2700 characters of the description and starts no pipeline on an edit. ADR-0002, the project instructions, `CONTRIBUTING.md` and the README say so ([#201](https://github.com/NCodeGroup/project-template/issues/201)).

### Changed

- The merge method has a decision record of its own, ADR-0013, "Pull requests merge with a merge commit or by rebasing". It keeps a merge commit or a rebase as the default, and ADR-0004, ADR-0005 and ADR-0006 refer to it instead of each stating it, so a project that squash-merges, such as through a merge queue, supersedes ADR-0013 alone; the record names the required `Commit attribution` check as the guard such a project needs. ADR-0005 accepts a merge queue's run on the merged result in place of a branch up to date with the default branch ([#200](https://github.com/NCodeGroup/project-template/issues/200), [ADR-0013](template/docs/decisions/project-template/0013-pull-requests-merge-with-a-merge-commit-or-by-rebasing.md)).

## [0.51.0] - 2026-11-01

### Changed

- The `project_owned_files` answer can name any file the template renders, not only merged files: a template-owned one too, such as a `build/dod.ps1` the project had before the template added its own. An update leaves each file the answer names out of its reset of the template-owned files, so it never overwrites the project's copy, and shows the template's changes to it instead, as it does for an owned merged file. A project keeps its own Definition of Done with `.\.template\Update-Project.ps1 -Data @{ project_owned_files = 'build/dod.ps1' }`, naming the files the answer already lists too, and `Adopt-Project.ps1` takes the same answer. Only the update's own files, `.copier-answers.yml`, `.template-version` and those in `.template/`, can't be named, and a name that the version the update moves to doesn't render stops the update before it changes anything ([#198](https://github.com/NCodeGroup/project-template/issues/198)).

### Fixed

- `Update-Project.ps1` checks the `project_owned_files` answer against the version it updates to, not the version the project is on, so a project can own a file from the same update that first adds or merges it, such as `.github/workflows/copilot-setup-steps.yml`. The update hands over to the new version's script before it checks, so this applies from the update to this version on. It also names a merged file once when the template renamed its source, such as `Directory.Packages.props` when it became a rendered file, both in the note about files the project seems to have replaced and in the `-Data` it suggests, and shows the template's change to a project-owned file once ([#199](https://github.com/NCodeGroup/project-template/issues/199)).

## [0.50.2] - 2026-11-01

### Added

- Template decision ADR-0012, "The template's decision records are numbered below 1000, a project's from 1000", in `docs/decisions/project-template/`: the template's records keep their numbers below 1000 (0001–0099 for every project, from 0100 for a stack's or an option's), and a project numbers its own from 1000, so a bare number such as "ADR-0102" names one record and a template update never brings a number the project already uses.

### Changed

- `/analyze-decision` gives a project's next decision record the next number above its highest record numbered 1000 or more, or 1000 for the first, and `.github/instructions/project-template.instructions.md` says project records are numbered from 1000; a new project's `docs/decisions/README.md` says to start from `1000`. Records a project already has below 1000 keep their numbers, and `.template/Test-AdrIndex.ps1` still accepts them. `docs/decisions/README.md` is project-owned, so a project made from an earlier version keeps its own: `Update-Project.ps1` shows the template's change to it, and you make it by hand, changing "starting from `0001`" to "starting from `1000`" and "the highest record" to "the highest record numbered 1000 or more". The changelog example in the planning commands cites a project record as `ADR-1007`.

## [0.50.1] - 2026-11-01

### Fixed

- `.github/instructions/project-template.instructions.md` lists "Secrets never enter the repository or a prompt" as a `## Conventions` item of its own again: since v0.45.0 it was joined to the end of the "Done" item, on the same line. `tests/Test-Template.ps1` now fails when a rendered Markdown line joins two list items ([#197](https://github.com/NCodeGroup/project-template/issues/197)).
- `.github/workflows/code-review-auto-merge.yml` no longer always asks for a merge commit, which a repository that allows only squash merges, or whose default branch's ruleset requires linear history or allows only other methods, refused, failing the run on every NCode Review bump. It turns on auto-merge with the first method that both the repository's settings and the active rules of the pull request's base branch allow: a merge commit, else a rebase, else a squash; when none is left, the run fails and says so. Classic branch protection's "Require linear history" can't be read with the workflow's token: a repository that sets it there should turn merge commits off in its settings, or require linear history in a ruleset instead ([#195](https://github.com/NCodeGroup/project-template/issues/195)).

## [0.50.0] - 2026-11-01

### Added

- `tools/Set-RepositoryBaseline.ps1` prints a notice for a repository whose "Protect main" ruleset already has a code-scanning rule, such as one an older version of the script made, when its CodeQL default setup runs a query suite other than `extended`, also with `-WhatIf`: it says so and gives the command that switches it by hand, `gh api -X PATCH repos/<owner>/<repo>/code-scanning/default-setup -f query_suite=extended`, which can start blocking merges on the new alerts the extended suite raises. It never switches such a repository's suite or raises its rule's alert thresholds itself, and a setup it can't read is reported while the run goes on ([#167](https://github.com/NCodeGroup/project-template/issues/167)).

### Changed

- The protected paths that `/run-issues` and `/address-feedback` never let a bot's finding change say that a `scripts` folder is deliberately not one: it usually holds ordinary code a fix may need, the CI files that run its scripts are protected already, and the pull request, its review loop and the person who merges it remain the gate ([#156](https://github.com/NCodeGroup/project-template/issues/156)).
- `/ship-plan`'s `draft` Landing setting keeps defaulting to `no`, so no template update changes how an existing project lands. `/ship-plan`, the Landing section of a new project's `AGENTS.md` and USAGE.md now say so, and that a project opts in to draft pull requests with `- draft: yes`; `/run-issues` opens its pull requests as drafts either way ([#157](https://github.com/NCodeGroup/project-template/issues/157)).

## [0.49.0] - 2026-11-01

### Added

- A GitHub project gets `.github/workflows/code-review-auto-merge.yml`, a template-owned workflow that turns on auto-merge, with a merge commit, for a Dependabot pull request that only moves the NCode Review pin in `.github/workflows/code-review.yml` to a newer minor or patch release, so the bump merges itself once the checks the default branch requires pass. It runs from the default branch on `pull_request_target` for Dependabot's pull requests from the repository itself, with only `contents: write` and `pull-requests: write`, and checks nothing out: it reads the update with `dependabot/fetch-metadata`, pinned by commit SHA, which must name `NCodeGroup/code-review` alone; checks through the API that every changed line is in a `.github/workflows/*.yml` file and is that action's `uses:` line, pinned to a full commit SHA with its `# vX.Y.Z` tag; and runs `gh pr merge --auto --merge` for the commit it checked. A major release, a pull request that updates other dependencies too and any other change wait for a person. A project without `code-review.yml` gets no such pull request, so the workflow merges nothing there. `.github/dependabot.yml` gives `NCodeGroup/code-review` a group of its own, `ncode-review`, before the catch-all `github-actions` group, so its bump comes in a pull request of its own instead of with the week's other action updates. ADR-0006, "A person merges every pull request; an agent never does", records the workflow as its one exception, with its scope and why the rule's reason doesn't apply to a pin bump to a release that was itself reviewed. `Adopt-Project.ps1` doesn't ask to reconcile it with `ci.yml` ([NCodeGroup/code-review#33](https://github.com/NCodeGroup/code-review/issues/33)).

### Changed

- The `code-review.yml` a project gets pins `NCodeGroup/code-review` to the full commit SHA of v1.0.0, with the tag in a comment (it pinned v0.4.0), and splits in two jobs, as v1.0.0 asks of its callers: the `review` job no longer runs when a pull request closes, nor for a plain `/review` comment on a closed pull request (`/review explain` and `/review teach` still answer there), so it can't cancel or displace the outcomes run in their shared concurrency group, and it cancels a superseded review; a new `outcomes` job records each posted finding's outcome when a pull request closes, merged or not, whoever closed it. The `outcomes` job makes no model call and needs no environment, since the app's key is an organization secret and the `code-review` environment holds none, only letting Anthropic's federation rule trust the review job. So it runs outside it, with no `id-token: write`, checkout or Bedrock key, only the app's private key and `contents: read` and `pull-requests: read`, in the review's concurrency group without cancelling a review in progress. Its setup note now says `tools/Enable-CodeReview.ps1` gives the repository, not the environment, access to the organization's two secrets. This repository's own `code-review.yml` gets the same change. The file is project-owned, so a project that already has it keeps its own and `Update-Project.ps1` only shows this change: make it by hand, moving to the v1.0.0 pin and the two jobs together. Dependabot's bump to v1.0.0 changes only the pin, so `code-review-auto-merge.yml` leaves it to a person, as it does every major release: apply the whole change on that pull request, or close it and make the change in one of your own ([NCodeGroup/code-review#97](https://github.com/NCodeGroup/code-review/issues/97)).
- `tools/Set-RepositoryBaseline.ps1` also allows auto-merge where it is off, which the code review auto-merge workflow needs, read first and reported as set, already set, would set or not available like the security settings, on a repository whose branch ruleset it leaves alone too. Run it again, such as `.\tools\Set-RepositoryBaseline.ps1 -All -Owner NCodeGroup`, to allow it in the repositories it protected before ([NCodeGroup/code-review#33](https://github.com/NCodeGroup/code-review/issues/33)).

## [0.48.4] - 2026-11-01

### Fixed

- No change for projects made from the template. `tests/Test-GitHooks.ps1` runs pre-commit at the version `tests/requirements.txt` pins, `pre-commit==4.7.0`, through `uvx --from`, instead of the pre-commit on `PATH` or the newest release `uvx` resolved on every run, CI included, so Dependabot's `pip` entry for `/tests` moves it in a pull request CI has tested. A new check fails when the version it runs isn't the pin, and the suite stops with an error when the pin is missing or `uvx` isn't installed ([#192](https://github.com/NCodeGroup/project-template/issues/192)).

## [0.48.3] - 2026-11-01

### Fixed

- No change for projects made from the template. `tests/Test-Template.ps1` runs its YAML and `_exclude` checks with the PyYAML and Jinja2 versions `tests/requirements.txt` pins, `pyyaml==6.0.3` and `jinja2==3.1.6`, instead of resolving the newest releases through uv on every run, so Dependabot's `pip` entry for `/tests` moves them in a pull request CI has tested, and CI's Copier install runs on the same versions. The suite stops with an error when either pin is missing ([#187](https://github.com/NCodeGroup/project-template/issues/187)).
- No change for projects made from the template. This repository's Dependabot `github-actions` entry waits three days before it offers a new action version and gives security updates a pull request of their own, as its `pip` entry and every project's entries do, so a just-released action no longer reaches CI the day it is published. `tests/Test-Template.ps1` fails when an entry in `.github/dependabot.yml` lacks the cooldown or the security group ([#188](https://github.com/NCodeGroup/project-template/issues/188)).

## [0.48.2] - 2026-11-01

### Added

- No change for projects made from the template. `tests/Test-PlanStateConcurrency.ps1` also checks that `workflow/Get-PlanState.ps1`, when a step fails after its network calls have started, fails at once with that error and leaves no runspace running a call it never received, through a stand-in for `gh` that fails the branch protection check while its other calls wait ([#186](https://github.com/NCodeGroup/project-template/issues/186)).

### Fixed

- `Get-PlanState.ps1` closes the runspace of each network call it starts. Since v0.48.0 it left one open per call, which built up in a PowerShell session that runs the script many times, such as a test suite. Projects get it with `.\.template\Update-Project.ps1` ([#186](https://github.com/NCodeGroup/project-template/issues/186)).

## [0.48.1] - 2026-11-01

### Changed

- No change for projects made from the template. This repository's CI installs Copier at the exact version `tests/requirements.txt` pins, `copier==9.19.1`, instead of the newest release, and a Dependabot `pip` entry for `/tests` moves the pin in a pull request three days after a release, so a new Copier version, such as the 9.19 that failed a `main` run, reaches the tests only through a pull request CI has tested. `tests/Test-Template.ps1` fails when the pin, the install from it or the Dependabot entry is missing ([#180](https://github.com/NCodeGroup/project-template/issues/180)).

### Fixed

- No change for projects made from the template. Every suite that builds a template snapshot, and the end-to-end fixture, keeps Copier's mirrors in a `copier-cache` folder in its work folder when it runs on its own, as `tests/Test-TemplateDotnet.ps1` does, instead of the user's Copier cache: `tests/Test-ProjectUpdate.ps1` and `tests/Test-ProjectUpdateHooks.ps1` left a new mirror there on every run, and `tests/Test-UpdateExitCode.ps1` refreshed the user's mirror of the template's GitHub address with the snapshot. `tests/Test-InvokeAllTests.ps1` fails a snapshot suite that doesn't ([#182](https://github.com/NCodeGroup/project-template/issues/182)).

## [0.48.0] - 2026-10-31

### Added

- No change for projects made from the template. `tests/Test-PlanStateConcurrency.ps1`, which CI runs as a job of its own, checks that `workflow/Get-PlanState.ps1` makes its `gh` calls at the same time, through a stand-in for `gh` that answers after a delay ([#181](https://github.com/NCodeGroup/project-template/issues/181)).

### Changed

- `Get-PlanState.ps1` starts its calls that wait on the network at the same time instead of one after another: the fetch of `origin`, `git ls-remote` for origin's tags, and, through `gh` or `glab`, the pull request or merge request list, the branch protection, each issue's state and the release. It prints the same lines, in about 1.7 seconds instead of 4 on this repository, so `/ship-plan`, `/continue-plan`, `/finish-plan`, `/run-issues` and `/address-feedback` wait less each time they run it. Projects get it with `.\.template\Update-Project.ps1` ([#181](https://github.com/NCodeGroup/project-template/issues/181)).

## [0.47.0] - 2026-10-31

### Added

- No change for projects made from the template. `tests/Measure-Suites.ps1` times the test suites it names, one at a time, prints each one's median over `-Repeat` runs and fails a suite that fails or takes longer than `-MaxSeconds`, so a change to the tests can be measured against a baseline ([#177](https://github.com/NCodeGroup/project-template/issues/177)).

### Changed

- No change for projects made from the template. The .NET build checks move from `tests/Test-Template.ps1` into a new suite, `tests/Test-TemplateDotnet.ps1`, which CI runs as a job of its own, and `tests/Test-PlanState.ps1` runs `workflow/Get-PlanState.ps1` in a runspace of its own process instead of starting PowerShell for each of its 88 calls, so CI's two longest jobs end sooner. CI lists its suites longest first and cancels a pull request's run when a newer push replaces it ([#177](https://github.com/NCodeGroup/project-template/issues/177)).

### Fixed

- No change for projects made from the template. `tests/Test-Template.ps1` gives each of its parallel renders a Copier cache of its own, since Copier 9.19 refreshes one shared mirror per template URL without a lock and a render failed on it; `tests/Invoke-AllTests.ps1` keeps the suites' Copier mirrors in its own work folder, deleted with it, instead of leaving one per suite in the user's cache on every run; and `tests/Test-ScriptAnalyzer.ps1` leaves out `.claude/worktrees/`, where it analyzed, and failed on, other plans' checkouts ([#177](https://github.com/NCodeGroup/project-template/issues/177)).

## [0.46.2] - 2026-10-31

### Changed

- No change for projects made from the template. `tests/Test-UpdateExitCode.ps1`, `tests/Test-UpdateIgnoredFiles.ps1`, `tests/Test-UpdateKeptLines.ps1`, `tests/Test-UpdateOwnedFiles.ps1`, `tests/Test-UpdateRewrittenFiles.ps1` and the end-to-end fixture in `tests/e2e/Fixture.ps1` build the snapshot of the working tree they render from with `tests/New-TemplateSnapshot.ps1` instead of copying, committing and tagging it themselves, so what the snapshot leaves out is set in one place. Its new `-BeforeCommit` script block changes the snapshot before it is committed, as `tests/Test-UpdateKeptLines.ps1` does to start from an older `.gitignore` ([#176](https://github.com/NCodeGroup/project-template/issues/176)).

## [0.46.1] - 2026-10-31

### Changed

- No change for projects made from the template. `tests/Test-Adoption.ps1` and `tests/Test-AdoptOwnedFiles.ps1` build the snapshot of the working tree they adopt from with `tests/New-TemplateSnapshot.ps1`, as `tests/Test-AdoptEdgeCases.ps1` does, instead of copying, committing and tagging it themselves, so what the snapshot leaves out is set in one place ([#174](https://github.com/NCodeGroup/project-template/issues/174)).

## [0.46.0] - 2026-10-31

### Changed

- No change for projects made from the template. The six adoption fixtures after `plain` and `scaffold` — a rollback, a repository's own CI and hooks path, catch-all attributes and a partial SDK version, Copilot-only agents, a failing build, and Node.js without build or test scripts — move from `tests/Test-Adoption.ps1` into a new suite, `tests/Test-AdoptEdgeCases.ps1`, which CI runs as a job of its own, so the longest suite of a parallel `tests/Invoke-AllTests.ps1` run is shorter and the run ends sooner ([#171](https://github.com/NCodeGroup/project-template/issues/171)).

## [0.45.0] - 2026-10-31

### Added

- Every project gets architecture decision records. `docs/decisions/project-template/`, which the template owns and updates replace, records the decisions behind the template's rules: commits attributed to people, plan-then-execute, trunk-based development, pull requests into the default branch, a person merging every pull request, issues for pending work, pinned inputs and the dependency cooldown. A .NET project also gets the decisions on its build (warnings as errors, central package management, banned APIs), on C# design (services, strategies and mediators, `InternalsVisibleTo`, `DefaultFoo`, strict configuration, filtering in the database, versioned stored documents, concurrency races, read-modify-write, failure codes, buffers, metrics, traces, logging to standard output), on ASP.NET Core apps (compile-time request delegates, a strict Content Security Policy, HSTS, opaque resource ids, keyset pagination, `412` on a lost write race) and, with `nuget_package`, on libraries (Source Link, the public API, abstractions packages, evolving parameters, publishing). The project's own decisions go in `docs/decisions/`, from its `README.md` and `0000-template.md`, which the project owns; one of them supersedes a template decision the project overrides. They come from the NCode.Identity repository, keeping only what holds for every project.
- A .NET project's build enforces more of its conventions. `build/ProjectTemplate.props` runs the .NET analyzers at `latest-recommended` with code style enforced in the build, reports unused usings as errors, in test projects too (through XML documentation, which test projects now generate as well, with CS1591 off in them and unless `nuget_package`, and the new template-owned `build/ProjectTemplate.globalconfig`), keeps NuGet vulnerability warnings errors in CI but not in a local build, and turns on the minimal-API Request Delegate Generator. `*.Tests` projects turn off CS1591, CA1707, CA1816, CA1859, CA1861 and CA1869, which are noise in tests, in the new template-owned `build/ProjectTemplate.Tests.globalconfig`, where `.editorconfig` can turn one back on. `Directory.Packages.props` references `Microsoft.CodeAnalysis.BannedApiAnalyzers` 5.6.0 as a `GlobalPackageReference`, and the new template-owned `build/BannedSymbols.txt` bans blocking on tasks, `JsonDocument.Parse` and Newtonsoft.Json in every project, each overload by its full documentation ID: a bare `M:Type.Method` entry matches only the overload without parameters. A project bans more in a `BannedSymbols.<name>.txt` of its own.
- `.github/instructions/csharp-tests.instructions.md` and `.claude/rules/csharp-tests.md`, template-owned, hold the test conventions for `<Name>.Tests` projects: what a test proves, strict Moq mocks verified when the test class is disposed (through `IDisposable`, since xUnit v2 never calls a test class's `DisposeAsync`), real collaborators, isolation, `FakeTimeProvider`, EF Core and integration tests.
- A .NET library gets the shared files the retired NCode.ProjectSettings.Scaffold package used to copy in: `LICENSE.txt` for an Apache-2.0 or MIT `package_license`, `COPYRIGHT.txt` for Apache-2.0, and `NCodeGroup.png`, which `package_icon` now defaults to for the author NCode Group, all project-owned; `Adopt-Project.ps1` leaves the license files out of a repository that already has a license. `.editorconfig` sets the header each new C# file starts with (`file_header_template`): the scaffold's Apache-2.0 notice, an SPDX line for another license, or the copyright line, as a suggestion so files without it still build. Each package takes its project's own `README.md` as its readme, or the repository's when it has none. A .NET project also gets a merged `nuget.config` that clears inherited package sources down to nuget.org.
- A .NET project gets a Definition of Done, the template-owned `build/dod.ps1`: it restores local tools, checks the decision index, builds in Release with every analyzer, runs the tests and, for a library, packs into `artifacts/packages`, stopping at the first stage that fails and ending with `Definition of Done: PASSED`. CI's build job runs it while the build and test commands are the defaults (`dotnet build`, `dotnet test`), on GitHub and GitLab, and a new .NET project's `AGENTS.md` names it under Commands and sets `gate: ./build/dod.ps1 -Fast` (Debug, no pack) in its Landing section, which `/ship-plan` runs before each push.
- A .NET library's public API is tracked: every packable project references `Microsoft.CodeAnalysis.PublicApiAnalyzers` 5.6.0 and keeps `PublicAPI.Shipped.txt` and `PublicAPI.Unshipped.txt`, so a public change they don't record fails the build (RS0016, RS0017). The new template-owned `build/Update-PublicApi.ps1` creates the files, records the new symbols and names the stale ones, and with `-Release` moves the unshipped entries into `PublicAPI.Shipped.txt`; `Adopt-Project.ps1` runs it before verifying an adopted library, so its API at adoption is the baseline. `AssemblyVersion` moves only with the major version (2.5.0-rc.1 builds as 2.0.0.0), while `FileVersion` and `InformationalVersion` keep the exact one. The C# conventions add the compatibility rules (add rather than change, nullability is part of the signature, append enum members, never share a type across packages that version apart) and a review checklist for a public change.
- The null-forgiving operator (`!`) fails the build outside test projects, through `Nullable.Extended.Analyzer` 1.17.0, which `build/ProjectTemplate.props` references for every project but `*.Tests` and `Directory.Packages.props` versions. The conventions state the one exception: `null!` in a test, to pass a deliberate null.
- Every project gets `.template/Test-AdrIndex.ps1`, which fails when `docs/decisions/README.md`'s index misses a decision record or links one that doesn't exist; CI runs it on GitHub and GitLab, and `build/dod.ps1` for .NET. The template's rules add change control: a change consumers can observe starts as an issue, and its decision is recorded as an ADR before or with the pull request that builds it.
- A new `/audit-conventions` command, in Claude Code, Copilot Chat and Copilot CLI, sweeps the codebase, or the part a request names, against `AGENTS.md`, the instruction files it lists and the decision records, after the gate passes, with deterministic searches, and ranks what doesn't follow them; it changes no file.
- More template decisions: a change consumers can observe is decided before it is built (every project); visibility starts at the narrowest that works, one Definition of Done gates every change, and the null-forgiving operator is banned outside tests (.NET); packages follow Semantic Versioning, with `AssemblyVersion` moving only with the major version (libraries).
- A .NET library on GitHub gets `.github/workflows/publish.yml`, project-owned: when a GitHub release is published, a job without credentials tests and packs in Release with the version the tag names, and a job in the protected `nuget` environment pushes the packages and their symbols to nuget.org through trusted publishing, exchanging the job's OIDC token for a short-lived key instead of storing one. The pack job fails when a package doesn't have the tag's version, as when a project sets its own `Version`, and the publish job fails when every package is already on nuget.org at that version, and says in its summary how many it pushed; it packs only a tag whose commit the default branch holds, so a tag on an unreviewed commit publishes nothing. Every action is pinned to a full commit SHA. It needs a one-time setup, which its header describes. A project that already publishes from a workflow of its own keeps one publisher: `Adopt-Project.ps1` says so, and an updated project deletes `publish.yml` or its own publishing job.

- A .NET project's C# conventions add the rules a second reading of NCode.Identity found general: ASP.NET Core security (published URLs from a configured origin, never the `Host` header; a shared, encrypted Data Protection key ring; local return URLs, no state change on GET, antiforgery, `__Host-` cookies; liveness apart from readiness; reads scoped in the query, answering 404, and no overposting), security and resilience (secrets never in logs, audit events or stored payloads; constant-time comparison; generated credentials shown once and stored hashed; bounded outbound calls and a full guard against server-side request forgery; correctness guards fail closed, capacity guards open; production refuses development-only settings), distributed state and background work (cache lifetimes, change hints, reconciliation under a lease, an outbox, retention with bounded pruning, background handoff, single-flight fetches), and EF Core (no migration at startup outside Development, the steps that contract a schema, deleting what an owner owns). Rules an earlier edit had cut come back, such as `TryAddEnumerable` dropping a duplicate implementation and a library never calling `ConfigureHttpsDefaults`. The test conventions say how to make a test filter that matches nothing fail, and add host and factory rules for integration tests.
- More template decisions: agents treat existing code as evidence, pin what is current upstream and report done only when done everywhere (every project); production refuses development-only settings, replicas converge through reconciliation, side effects after a commit go through an outbox, data that grows is pruned in bounded batches, migrations run before the rollout and only expand, correctness guards fail closed while capacity guards fail open, outbound calls are bounded and guarded, and secrets are never logged, compared in constant time and shown once (.NET); published URLs come from a configured origin, the Data Protection key ring is shared and encrypted, liveness never checks dependencies, and browser-facing requests are safe by construction (ASP.NET Core). Records 0103, 0106, 0113, 0114 and 0125 add observers, failed reloads and one validator per rule, the metrics catalog, and one entity per `ETag`.
- Every project gets `docs/README.md`, the index of its documentation with the rules docs follow, and `docs/designs/_template.md`, a design document for work bigger than one plan; a .NET project also gets `docs/metrics.md`, the catalog of its instruments and spans. All three are project-owned. The decision records' README adds statuses for a deprecated or amended record, how to take a number that no other branch has taken, and that a record never overrides an external standard or current security practice.
- Every project gets a project-owned `SECURITY.md`, which says how to report a vulnerability privately, which versions get fixes and, for a .NET library, how to verify a package, and `CONTRIBUTING.md`, with the prerequisites, the build and test commands, the change flow and commit attribution; the project's `README.md` links them, the changelog, the decisions and the license.
- A new `license` answer, asked for every stack, names the repository's SPDX license: `LICENSE.txt` for MIT or Apache-2.0, `COPYRIGHT.txt` for Apache-2.0, the C# file header, and the default for `package_license`. A library from before the answer keeps the license files its `package_license` gave it.
- A .NET project names its `Product`, and a library's package points its project page and release notes at the repository and its changelog, from the remote Source Link reads, unless the project sets them. `global.json` refuses a preview SDK, `.gitignore` adds the common .NET user and secret files, and `.editorconfig` treats EF Core migrations as generated code.
- `tools/Set-RepositoryBaseline.ps1` gives a repository a "Protect release tags" ruleset beside "Protect main": no `v*` tag can be deleted or updated (moved), with no bypass, since a release tag names one published package set. A ruleset of that name is left alone, and so is an active tag ruleset that already refuses both. It also turns on, where each is off, a read-only workflow token with GitHub Actions not allowed to approve pull requests, secret scanning and its push protection, Dependabot alerts and security updates, and private vulnerability reporting, and reports each as set, already set or not available, with the reason: secret scanning is left out of a repository that isn't public, where it is paid, and a setting the API refuses doesn't fail the run. A repository whose default branch ruleset it leaves alone still gets both, so running it again brings an already protected repository up to date. `-WhatIf` lists them all and changes nothing.
- A GitHub project that uses Copilot gets `.github/workflows/copilot-setup-steps.yml`, a merged file, which prepares the Copilot cloud agent's runner before each session: in the one job GitHub runs for it, `copilot-setup-steps`, it checks out without persisted credentials and sets up the stack as CI does — for .NET the SDK `global.json` names, CI's NuGet cache, `dotnet tool restore` and `dotnet restore`; for Python, Node.js and PowerShell the runtime and the dependencies — and stops at 59 minutes, the session's limit. The template's rules say how to fit a cloud agent session into its 59 minutes: push each finished item from the clone, one chain of issues per session, and re-author the agent's commits before merging.
- .NET CI keeps the Definition of Done's TRX test results as an artifact for 14 days, after a failure too, and for a library the packages a release would publish, on GitHub and GitLab, and caches NuGet packages, keyed on `Directory.Packages.props`, `global.json`, `.config/dotnet-tools.json` and the project files on GitHub, and on `Directory.Packages.props` and `global.json` on GitLab.
- Dependabot gives security updates a group of their own in each ecosystem (`applies-to: security-updates`), so one advisory run is one pull request; groups otherwise apply only to version updates.
### Changed

- **Breaking:** A .NET project's build checks more after this update, so an existing project's build can fail until it catches up: the .NET analyzers run at `latest-recommended` with code style and unused usings enforced, the null-forgiving operator fails the build outside test projects, `build/BannedSymbols.txt` bans blocking on tasks, `JsonDocument.Parse` and Newtonsoft.Json (a project that bans the same APIs in a list of its own removes its copies), and a library's build fails on a public symbol its `PublicAPI.Shipped.txt` and `PublicAPI.Unshipped.txt` don't record: `./build/Update-PublicApi.ps1` records the API as it is. CI runs `build/dod.ps1` while the build and test commands are the defaults. A library that already publishes from a workflow of its own keeps one publisher, deleting `publish.yml` or its own publishing job. `/plan-template-update` plans the fixes from a trial run of the update.
- `.github/instructions/csharp.instructions.md` holds the C# conventions for every `*.cs` file, from NCode.Identity's, kept where they hold for any project: async and cancellation, no null-forgiving operator, public API discipline, sealed data types and owned immutable collections, one type per file and `DefaultFoo`, a composition-only `Program.cs`, `TryAdd*` registration, atomic shared-state updates, security defaults, clean code, memory, testability through `TimeProvider` and interfaces, XML documentation, `[LoggerMessage]` logging, bounded metrics and traces, strict options validated at startup, and EF Core migrations that keep the previous release working. Its test rules moved to `csharp-tests.instructions.md`. The template's rules list the new template-owned files, and a new project's `AGENTS.md` lists the test conventions and `docs/decisions/`.
- `/analyze-decision` reads the decisions a choice touches, in `docs/decisions/` and the template's in `docs/decisions/project-template/`, and writes the new record in `docs/decisions/` with the sections of `0000-template.md`, adds it to the index, and marks one that overrides a template decision as superseding it. It no longer falls back to `docs/adr/`.
- `Adopt-Project.ps1`, for a repository built on NCode.ProjectSettings.Scaffold, also reports what the package left behind: `project.props` files nothing imports any more, a `Microsoft.SourceLink.GitHub` reference the SDK builds in, the scaffold's `DocumentationFile` path, its `.sln.DotSettings` file header and a second workflow that pushes packages. It no longer asks to reconcile `csharp-tests.instructions.md` or `publish.yml`, which are the template's.
- GitHub CI cancels a run when a newer push to the same pull request or topic branch supersedes it, but never a default-branch commit's run or a merge queue entry's: their concurrency group holds the commit SHA, because `cancel-in-progress: false` alone still lets a newer run cancel a pending one, leaving a commit without a verdict. The build job stops after 30 minutes instead of GitHub's 6 hours.
- Dependabot no longer offers a new .NET SDK major, which is a planned migration (`/plan-migration`), as a new target framework is.
- The template's rules add how agents work: existing code is evidence of intent, not a constraint; current secure practice is the default rather than a question; a version is pinned from the upstream release after the cooldown; and "done" is one fact everywhere. They also say how to handle a failing Dependabot pull request, and that a .NET project keeps production projects in `src/` and tests in `tests/`. The changelog rules a plan follows mark a breaking entry `**Breaking:**`, link each entry's issue and decision record, and name the advisory a security update closes.
- `build/dod.ps1` fails on a NuGet vulnerability advisory in its full gate, as CI does, writes TRX test results to `artifacts/test-results`, and fails a `-Filter` run that matches no test; the plan format tells the planner to make a Done-when test filter fail when it matches nothing. `.template/Test-AdrIndex.ps1` also fails on two records that share a number and on an index row that shows another number than its record's.
### Fixed

- Python CI fails the install step when `pip install` fails; it used to check only the step's last command.
- The `gate` example in a new project's `AGENTS.md` and in the template's rules no longer names `-Affected`, which `build/dod.ps1` doesn't take.

## [0.44.0] - 2026-10-31

### Changed

- `tests/Invoke-AllTests.ps1` runs the suites in parallel, up to one per processor (`-ThrottleLimit <n>` sets how many, `-Serial` runs one at a time), prints each suite's result line in name order once all have finished, and ends with the run's wall-clock time as `Time: <m:ss>`. `tests/Test-Template.ps1` renders its answer sets in parallel, and the project update runs it made move into two new suites, `tests/Test-ProjectUpdate.ps1` and `tests/Test-ProjectUpdateHooks.ps1`, which CI runs as jobs of their own; its `-SkipUpdate` switch is gone. A full local run now takes about as long as its slowest suite instead of all of them added up ([#168](https://github.com/NCodeGroup/project-template/issues/168)).

## [0.43.1] - 2026-10-31

### Changed

- `/replan-step` and `/review-plan-diff` run the plan's `- Prelude:` command in the same wrapper as the executors, and stop when it fails: when the output ends with `prelude failed`, the check never ran, so they show the prelude's error and say to fix the Landing section's `prelude` and the plan's `- Prelude:` line, instead of re-planning the step or adding fix steps for it. `/ship-plan`'s landing summary says the prelude runs in the gate's command ([#155](https://github.com/NCodeGroup/project-template/issues/155)).
- No change for projects made from the template. `workflow/Invoke-PlanSteps.ps1`'s help says how a failed prelude ends a run: with an error that names it, so PowerShell exits 1. `tests/Test-Template.ps1` runs a prelude command that isn't a script, and a Done-when command that prints `prelude failed` without a prelude, through the runner, and runs the runner's loop with a stand-in `copilot` whose planner completes a step, which the loop re-checks after the plan's prelude ([#155](https://github.com/NCodeGroup/project-template/issues/155)).
- No change for projects made from the template. `tests/e2e/Test-RunIssues.ps1` checks the merge recommendation: by default the `gh` stand-in gives NCode Review's review of the run's first push, a finding that only asks for another test, and `-Scenario max-rounds` sets `max-review-rounds: 1`; either way the run must recommend the merge once and put the open nits in the plan's `## Follow-ups`. `tests/e2e/Test-AddressFeedback.ps1` also runs `/address-feedback` on a pull request from `farewell;touch${IFS}pwned`, a branch name with shell characters, and checks that it stops before any worktree, push, comment or file ([#159](https://github.com/NCodeGroup/project-template/issues/159)).

### Fixed

- `USAGE.md` no longer says `/ship-plan` runs the prelude before every push: it runs only in the gate's command, so with `gate: none` nothing runs it ([#155](https://github.com/NCodeGroup/project-template/issues/155)).

## [0.43.0] - 2026-10-31

### Changed

- No change for projects made from the template. A test suite that stops with an error prints the work folder it keeps, as a failing one does: every `tests/Test-*.ps1` suite with `-Work` has a `trap` line, which `tests/Test-InvokeAllTests.ps1` checks. New checks cover the `.sample` filter that decides whether a clone has hooks of its own (`Test-GitHooks.ps1`), a curly apostrophe in the command `Set-RepositoryBaseline.ps1 -RequireChecks auto -WhatIf` prints (`Test-RepositoryBaseline.ps1`), and, for `Get-TemplateUpdate.ps1`, a `gh` call that fails, a project ahead of the newest tag and a section that brings an issue body to exactly its 60,000-character limit (`Test-TemplateUpdate.ps1`) ([#158](https://github.com/NCodeGroup/project-template/issues/158), [#160](https://github.com/NCodeGroup/project-template/issues/160)).

### Fixed

- `Update-Project.ps1`'s help says plainly when it says nothing about Git hooks: when `core.hooksPath` names a `.githooks` folder, or when `.pre-commit-config.yaml` runs `.githooks/commit-msg`. Its copy of `Get-GitHooksSetup` notes that it changes together with the one `Adopt-Project.ps1` uses ([#158](https://github.com/NCodeGroup/project-template/issues/158)).

## [0.42.1] - 2026-10-31

### Changed

- The `code-review.yml` a project gets pins `NCodeGroup/code-review` to the full commit SHA of v0.4.0, with the tag in a comment (it pinned v0.3.1), and adds `closed` to its `pull_request_target` types, as v0.4.0 asks of its callers: when a pull request closes, merged or not, the run records each posted finding's outcome (fixed, dismissed, acknowledged or ignored) with no model call, whoever closed it, and waits for a review in progress instead of cancelling it. `/review explain` and `/review teach` comments, new in v0.4.0, run in a concurrency group of their own, so they never cancel a review. The job keeps `issues: read`, which v0.4.0 also uses to mark a finding an open issue already tracks. This repository's own `code-review.yml` gets the same change. A project that already has the file keeps its own; update it the same way, adding `closed` only together with the v0.4.0 pin, since earlier releases would review a closed pull request ([#161](https://github.com/NCodeGroup/project-template/issues/161)).

### Fixed

- `tools/Set-RepositoryBaseline.ps1 -RequireChecks auto` finds the latest merged pull request among all of a repository's closed pull requests. It read only the 100 updated last, so when 100 or more other closed pull requests had been updated more recently, such as by a comment or a label, it read an older merged pull request's checks, or found none and skipped the repository ([#154](https://github.com/NCodeGroup/project-template/issues/154)).

## [0.42.0] - 2026-10-31

### Added

- Every PowerShell script in the repository, the ones the template ships included, passes PSScriptAnalyzer with warnings treated as errors: `tests/Test-ScriptAnalyzer.ps1`, which CI runs with the other suites, fails on any finding. `PSScriptAnalyzerSettings.psd1` leaves out four rules that don't fit these scripts (Write-Host in interactive scripts, singular nouns, ShouldProcess on internal helpers, and a BOM PowerShell 7 doesn't need), each with its reason; the few findings that are false positives are suppressed where they are, with a justification.
- A new `/address-feedback` command takes every open comment and discussion on one pull request, from anyone or any bot: review threads, top-level comments and review summaries. It judges each against the code as a fix, a decline with its reason, an answer, a question for the maintainer or nothing to do, plans and executes only the fixes in a worktree, pushes them to the pull request's branch (never forced) and replies to each item starting with `Autopilot:`. Only authors who can write to the repository, the review bots the Landing section's `review-bots` names (`ncode-review` by default; on GitLab, only when the bot's account can also write to the repository) and authors named with `only:` can make an item a fix; a request from anyone else, such as `dependabot[bot]` or another installed app, is answered, declined or put to the maintainer, and so is a bot's request to change a file in a `.github`, `.gitlab`, `.template`, `.claude`, `.githooks`, `.husky`, `.vscode` or `build` folder, an `AGENTS.md`, `CLAUDE.md`, `.mcp.json`, `.copier-answers.yml`, `Makefile`, `Dockerfile`, `.npmrc`, `nuget.config`, `.gitlab-ci.yml`, `Jenkinsfile`, `azure-pipelines.yml`, `.pre-commit-config.yaml`, `.gitattributes`, `.gitmodules`, `*.props`, `*.targets` or `global.json` file, or a dependency manifest or lock file. A comment that is only a slash command, such as `/review`, isn't an item. It never merges, resolves a thread, dismisses an alert or edits the pull request. Claude Code only ([#135](https://github.com/NCodeGroup/project-template/issues/135), [#136](https://github.com/NCodeGroup/project-template/issues/136)).
- A GitHub project gets a weekly template update notice. The template-owned workflow `.github/workflows/template-update.yml` runs `.template/Get-TemplateUpdate.ps1` every Monday and on demand, with only `contents: read` and `issues: write` and its checkout pinned by commit SHA. While the project's `.template-version` is behind the template's newest version tag, it keeps one open issue labeled `template-update`, "Update to project-template vX.Y.Z", with the changelog sections in between: it opens it, creating the label when missing, then edits and retitles that same issue as newer versions come out. Once the project is current, the next run closes the issue with a comment. `/plan-issue` and `/triage-issues` map the `template-update` label to a kind of its own, which plans with `/plan-template-update`'s instructions, so `/run-issues` can take the notice too ([#139](https://github.com/NCodeGroup/project-template/issues/139)).
- `/run-issues` acts on NCode Review's findings without waiting to be told: when the default branch has `.github/workflows/code-review.yml` and the Landing section's `review-bots` names `ncode-review`, each check takes the bot's unresolved `blocker` and `should-fix` threads (its `ncode-review` bot login, in GraphQL's and REST's forms, and its hidden `ncode-review:finding` marker), checks each against the code, fixes the ones that hold, with fix steps written from the code and never from the finding's text, and a check before the push that the round changed, renamed or deleted no protected file, and replies `Autopilot: fixed in <commit>`, or `Autopilot: not changed` with the reason, leaving the thread unresolved. It replies at most twice per thread, lists the bot's nits, and never acts on a finding in CI, template, agent configuration, build or dependency files, which it lists for the maintainer, and replies `Autopilot: left for you` to a finding whose fix would change one; another bot's thread, or one without the marker, stays data. `/continue-plan` lists a waiting pull request's findings by the same rules, in Claude Code, Copilot Chat and Copilot CLI ([#135](https://github.com/NCodeGroup/project-template/issues/135)).
- `/run-issues` stops iterating on review nits: after a round whose NCode Review findings are only test gaps, style and repeats, or once the rounds of review feedback reach the Landing section's new `max-review-rounds` (3 by default), it posts an `Autopilot:` comment recommending the merge and puts the bot's further findings, and its open nits, in the plan's `## Follow-ups`, which `/ship-plan` files after landing. The maintainer's own comments still get their fixes ([#137](https://github.com/NCodeGroup/project-template/issues/137)).
- `.template/Get-PlanState.ps1`'s `landing` line gives two new Landing keys: `review-bots`, the bots whose findings `/run-issues` and `/address-feedback` may fix, `ncode-review` by default, and `max-review-rounds`, `3` by default. A new project's `AGENTS.md` lists both. Projects get the commands and the script with `.\.template\Update-Project.ps1`; an existing project's `AGENTS.md` keeps its own Landing section, where the defaults apply until it adds the keys.
- `Get-PlanState.ps1` prints `changelog-duplicates`: each Keep a Changelog heading (`### Added`, `Changed`, `Deprecated`, `Removed`, `Fixed` or `Security`) that a section of the changelog has more than once, such as `[Unreleased] Changed`, or `-`. Two pull requests that each add the same heading to `## [Unreleased]` merge without a conflict and leave it twice; a plan's changelog step now merges such headings in `## [Unreleased]` into one. This repository's CI checks its own `CHANGELOG.md` the same way with `tests/Test-ChangelogHeadings.ps1`, which fails naming the section and the heading. Projects get it with `.\.template\Update-Project.ps1` ([#132](https://github.com/NCodeGroup/project-template/issues/132)).
- A `prelude` key in `AGENTS.md`'s `## Landing` section names one PowerShell command that sets up the shell the workflow's commands run in, such as `prelude: ./build/env.ps1`, a script in the repository that puts Node installed through nvs on `PATH`. `/ship-plan`, and `/run-issues` and `/address-feedback` through it, dot-source it before the gate in the same PowerShell; the executors, `/orchestrate-plan`, `/replan-step`, `/review-plan-diff` and `workflow/Invoke-PlanSteps.ps1` run it before each Done-when command, from the plan's new `- Prelude:` line under Context for the executor, which the planners write instead of a `PATH` guard in every step. When it fails, they stop and show its error. `Get-PlanState.ps1` prints it on its `landing` line, as `prelude=invalid` when it isn't one command on one line without a `#` comment (a script in the repository, written as `./<path>.ps1`, that exists, or another command with its arguments), and `/ship-plan` stops on it; `workflow/Invoke-PlanSteps.ps1` checks the plan's `- Prelude:` line by the same rule. The default, `prelude: none`, runs nothing ([#138](https://github.com/NCodeGroup/project-template/issues/138)).
- `tools/Set-RepositoryBaseline.ps1 -RequireChecks auto` requires the checks that passed on the repository's latest merged pull request: the GitHub Actions jobs that ran there for the `pull_request` event and succeeded, `Commit attribution` among them wherever it passed. It leaves out, with the reason, the review bot's advisory `Code review` and its job, CodeQL (the code-scanning rule covers it) and its Analyze jobs, other apps' checks, and anything skipped, neutral, failed or unfinished. `-WhatIf` lists them and prints the command that names them, and every run warns that they come from one pull request, since a job whose workflow has `paths` or `branches` filters would block a pull request it skips; a repository with no merged pull request is skipped with a clear message. It works with `-All`, and `Adopt-Project.ps1` suggests it for a repository that keeps its own CI ([#134](https://github.com/NCodeGroup/project-template/issues/134)).

### Changed

- The changelog rules that the plans and `/ship-plan` follow say that a section has at most one of each heading: an entry goes under its group's heading when the section already has one, including when a merge combines two sides' changes to the changelog; it never goes under a second heading of the same name ([#132](https://github.com/NCodeGroup/project-template/issues/132)).
- This repository's CI (`test-template.yml`) also runs for merge queue entries, and its commit attribution check reads a merge queue entry's base and head, so its required checks report there too.
- `tools/Set-RepositoryBaseline.ps1` adds a code-scanning rule to the "Protect main" ruleset it creates when CodeQL's default setup is configured for the repository: a pull request whose CodeQL results add an alert at warning level or above, or a security alert of any severity, can't merge. Without CodeQL results every pull request would wait for them, so a repository without the default setup gets no rule, and the script says so. Before it writes the ruleset, it switches a configured default setup to CodeQL's extended query suite, also one that reports no suite; when GitHub refuses the switch, it reports the repository as failed and changes nothing else, so the next run retries it.
- The "Protect main" ruleset that `tools/Set-RepositoryBaseline.ps1` creates lets nothing merge past feedback or a stale check: every conversation on a pull request must be resolved, and the required checks must pass on a branch that is up to date with the default branch.
- The `code-review.yml` a project gets pins `NCodeGroup/code-review` to the full commit SHA of v0.3.1, with the tag in a comment (it pinned the tag v0.1.0), and no longer checks out the pull request's head: from v0.3.0 the engine fetches the exact commit itself, so CodeQL no longer reports the workflow (two alerts, "checkout of untrusted code in a privileged context" and its TOCTOU variant, on every repository that adopted the bot). Rule checks run on by default, and there is an infrastructure reviewer for OpenTofu and Terraform changes. A SHA is the one pin CodeQL's extended suite accepts, and Dependabot updates the SHA and the comment together. A project that already has the file keeps its own; update it the same way.
- `/run-issues` no longer answers a top-level comment that is only a slash command, such as `/review` asking a review bot for another review: one command line, with nothing but white space before or after it, that matches `^\s*/[\w-]+([ \t][^\r\n]*)?\s*\z` ([#136](https://github.com/NCodeGroup/project-template/issues/136)).
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

[unreleased]: https://github.com/NCodeGroup/project-template/compare/v0.84.1...HEAD
[0.84.1]: https://github.com/NCodeGroup/project-template/compare/v0.84.0...v0.84.1
[0.84.0]: https://github.com/NCodeGroup/project-template/compare/v0.83.1...v0.84.0
[0.83.1]: https://github.com/NCodeGroup/project-template/compare/v0.83.0...v0.83.1
[0.83.0]: https://github.com/NCodeGroup/project-template/compare/v0.82.0...v0.83.0
[0.82.0]: https://github.com/NCodeGroup/project-template/compare/v0.81.0...v0.82.0
[0.81.0]: https://github.com/NCodeGroup/project-template/compare/v0.80.1...v0.81.0
[0.80.1]: https://github.com/NCodeGroup/project-template/compare/v0.80.0...v0.80.1
[0.80.0]: https://github.com/NCodeGroup/project-template/compare/v0.79.1...v0.80.0
[0.79.1]: https://github.com/NCodeGroup/project-template/compare/v0.79.0...v0.79.1
[0.79.0]: https://github.com/NCodeGroup/project-template/compare/v0.78.0...v0.79.0
[0.78.0]: https://github.com/NCodeGroup/project-template/compare/v0.77.0...v0.78.0
[0.77.0]: https://github.com/NCodeGroup/project-template/compare/v0.76.1...v0.77.0
[0.76.1]: https://github.com/NCodeGroup/project-template/compare/v0.76.0...v0.76.1
[0.76.0]: https://github.com/NCodeGroup/project-template/compare/v0.75.6...v0.76.0
[0.75.6]: https://github.com/NCodeGroup/project-template/compare/v0.75.5...v0.75.6
[0.75.5]: https://github.com/NCodeGroup/project-template/compare/v0.75.4...v0.75.5
[0.75.4]: https://github.com/NCodeGroup/project-template/compare/v0.75.3...v0.75.4
[0.75.3]: https://github.com/NCodeGroup/project-template/compare/v0.75.2...v0.75.3
[0.75.2]: https://github.com/NCodeGroup/project-template/compare/v0.75.1...v0.75.2
[0.75.1]: https://github.com/NCodeGroup/project-template/compare/v0.75.0...v0.75.1
[0.75.0]: https://github.com/NCodeGroup/project-template/compare/v0.74.0...v0.75.0
[0.74.0]: https://github.com/NCodeGroup/project-template/compare/v0.73.0...v0.74.0
[0.73.0]: https://github.com/NCodeGroup/project-template/compare/v0.72.0...v0.73.0
[0.72.0]: https://github.com/NCodeGroup/project-template/compare/v0.71.0...v0.72.0
[0.71.0]: https://github.com/NCodeGroup/project-template/compare/v0.70.0...v0.71.0
[0.70.0]: https://github.com/NCodeGroup/project-template/compare/v0.69.0...v0.70.0
[0.69.0]: https://github.com/NCodeGroup/project-template/compare/v0.68.4...v0.69.0
[0.68.4]: https://github.com/NCodeGroup/project-template/compare/v0.68.3...v0.68.4
[0.68.3]: https://github.com/NCodeGroup/project-template/compare/v0.68.2...v0.68.3
[0.68.2]: https://github.com/NCodeGroup/project-template/compare/v0.68.1...v0.68.2
[0.68.1]: https://github.com/NCodeGroup/project-template/compare/v0.68.0...v0.68.1
[0.68.0]: https://github.com/NCodeGroup/project-template/compare/v0.67.0...v0.68.0
[0.67.0]: https://github.com/NCodeGroup/project-template/compare/v0.66.0...v0.67.0
[0.66.0]: https://github.com/NCodeGroup/project-template/compare/v0.65.0...v0.66.0
[0.65.0]: https://github.com/NCodeGroup/project-template/compare/v0.64.1...v0.65.0
[0.64.1]: https://github.com/NCodeGroup/project-template/compare/v0.64.0...v0.64.1
[0.64.0]: https://github.com/NCodeGroup/project-template/compare/v0.63.1...v0.64.0
[0.63.1]: https://github.com/NCodeGroup/project-template/compare/v0.63.0...v0.63.1
[0.63.0]: https://github.com/NCodeGroup/project-template/compare/v0.62.0...v0.63.0
[0.62.0]: https://github.com/NCodeGroup/project-template/compare/v0.61.2...v0.62.0
[0.61.2]: https://github.com/NCodeGroup/project-template/compare/v0.61.1...v0.61.2
[0.61.1]: https://github.com/NCodeGroup/project-template/compare/v0.61.0...v0.61.1
[0.61.0]: https://github.com/NCodeGroup/project-template/compare/v0.60.0...v0.61.0
[0.60.0]: https://github.com/NCodeGroup/project-template/compare/v0.59.2...v0.60.0
[0.59.2]: https://github.com/NCodeGroup/project-template/compare/v0.59.1...v0.59.2
[0.59.1]: https://github.com/NCodeGroup/project-template/compare/v0.59.0...v0.59.1
[0.59.0]: https://github.com/NCodeGroup/project-template/compare/v0.58.2...v0.59.0
[0.58.2]: https://github.com/NCodeGroup/project-template/compare/v0.58.1...v0.58.2
[0.58.1]: https://github.com/NCodeGroup/project-template/compare/v0.58.0...v0.58.1
[0.58.0]: https://github.com/NCodeGroup/project-template/compare/v0.57.1...v0.58.0
[0.57.1]: https://github.com/NCodeGroup/project-template/compare/v0.57.0...v0.57.1
[0.57.0]: https://github.com/NCodeGroup/project-template/compare/v0.56.0...v0.57.0
[0.56.0]: https://github.com/NCodeGroup/project-template/compare/v0.55.0...v0.56.0
[0.55.0]: https://github.com/NCodeGroup/project-template/compare/v0.54.1...v0.55.0
[0.54.1]: https://github.com/NCodeGroup/project-template/compare/v0.54.0...v0.54.1
[0.54.0]: https://github.com/NCodeGroup/project-template/compare/v0.53.0...v0.54.0
[0.53.0]: https://github.com/NCodeGroup/project-template/compare/v0.52.0...v0.53.0
[0.52.0]: https://github.com/NCodeGroup/project-template/compare/v0.51.1...v0.52.0
[0.51.1]: https://github.com/NCodeGroup/project-template/compare/v0.51.0...v0.51.1
[0.51.0]: https://github.com/NCodeGroup/project-template/compare/v0.50.2...v0.51.0
[0.50.2]: https://github.com/NCodeGroup/project-template/compare/v0.50.1...v0.50.2
[0.50.1]: https://github.com/NCodeGroup/project-template/compare/v0.50.0...v0.50.1
[0.50.0]: https://github.com/NCodeGroup/project-template/compare/v0.49.0...v0.50.0
[0.49.0]: https://github.com/NCodeGroup/project-template/compare/v0.48.4...v0.49.0
[0.48.4]: https://github.com/NCodeGroup/project-template/compare/v0.48.3...v0.48.4
[0.48.3]: https://github.com/NCodeGroup/project-template/compare/v0.48.2...v0.48.3
[0.48.2]: https://github.com/NCodeGroup/project-template/compare/v0.48.1...v0.48.2
[0.48.1]: https://github.com/NCodeGroup/project-template/compare/v0.48.0...v0.48.1
[0.48.0]: https://github.com/NCodeGroup/project-template/compare/v0.47.0...v0.48.0
[0.47.0]: https://github.com/NCodeGroup/project-template/compare/v0.46.2...v0.47.0
[0.46.2]: https://github.com/NCodeGroup/project-template/compare/v0.46.1...v0.46.2
[0.46.1]: https://github.com/NCodeGroup/project-template/compare/v0.46.0...v0.46.1
[0.46.0]: https://github.com/NCodeGroup/project-template/compare/v0.45.0...v0.46.0
[0.45.0]: https://github.com/NCodeGroup/project-template/compare/v0.44.0...v0.45.0
[0.44.0]: https://github.com/NCodeGroup/project-template/compare/v0.43.1...v0.44.0
[0.43.1]: https://github.com/NCodeGroup/project-template/compare/v0.43.0...v0.43.1
[0.43.0]: https://github.com/NCodeGroup/project-template/compare/v0.42.1...v0.43.0
[0.42.1]: https://github.com/NCodeGroup/project-template/compare/v0.42.0...v0.42.1
[0.42.0]: https://github.com/NCodeGroup/project-template/compare/v0.41.1...v0.42.0
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
