# Adopt a Project, End to End

This runbook takes a maintainer from nothing to a fully adopted repository, new or existing, top to bottom, without reading code. [README.md](../README.md) is the reference for each script, and this page is the order to run them in. Section 8 is a checklist to audit an adopted repository, which `tools/Get-AdoptionChecklist.ps1` runs in one command.

## How to Read It

Each step lists Applies to, Who, Where, Do, Check and Goes wrong.

The `Applies to` values are:

- `every project`
- `GitHub`
- `.NET library`
- `Node.js`
- `public repository`
- `with NCode Review`
- `with Copilot`
- `where the project has one`

A step with several values applies where every one of them holds.

Commands run in PowerShell 7 from the folder the step's Where names.

## Contents

- [How to Read It](#how-to-read-it)
- [0. Before You Start](#0-before-you-start)
- [1. Create or Adopt](#1-create-or-adopt)
- [2. Protect the Default Branch and Tags](#2-protect-the-default-branch-and-tags)
- [3. Releases](#3-releases)
- [4. .NET Libraries on nuget.org](#4-net-libraries-on-nugetorg)
- [5. NCode Review](#5-ncode-review)
- [6. Other One-Time Settings](#6-other-one-time-settings)
- [7. Stay Current](#7-stay-current)
- [8. Checklist](#8-checklist)

## 0. Before You Start

Do these once per organization, and once per maintainer's PC for 0.1.

### 0.1 Accounts and Tools

- **Applies to:** every project
- **Who:** every maintainer; an organization owner checks 2FA.
- **Where:** each maintainer's PC; GitHub's Settings > Password and authentication.
- **Do:** Turn on two-factor authentication on every owner's account. Install PowerShell 7 (7.4 or later), Git with `user.name` and `user.email`, the GitHub CLI, uv and Copier, and nvs for Node.js projects, as [USAGE.md](../USAGE.md#install-the-tools) and [Set Up Git and GitHub](../USAGE.md#set-up-git-and-github) say. `gh auth login` gives the token `repo`, `read:org` and `gist`, plus `workflow` with HTTPS Git, which lets Git push workflow files. `repo` covers the baseline (with the admin role on the repository) and `Dismiss-ScorecardAlerts.ps1` (its `security_events` scope is part of `repo`). `admin:org`, added with `gh auth refresh -h github.com -s admin:org`, is needed only for 0.2's `-OrganizationPolicy` and NCode Review's organization secrets (0.3, 5.1). Clone NCodeGroup/project-template and run `git pull` in it before each use.
- **Check:** `gh auth status` shows the account and its token scopes; `copier --version`, `pwsh --version` (7.4 or later), `git config user.email`; USAGE.md's [Check the Setup](../USAGE.md#check-the-setup).
- **Goes wrong:** a stale project-template clone runs an older script, so run `git pull` first; a `GH_TOKEN` or `GITHUB_TOKEN` in the profile replaces the signed-in account's token and its scopes.

### 0.2 The Organization's Actions Policy

- **Applies to:** GitHub
- **Who:** an organization owner, with `admin:org`.
- **Where:** a clone of NCodeGroup/project-template; `https://github.com/organizations/<org>/settings/actions` and `https://github.com/organizations/<org>/settings/security`.
- **Do:** Run `.\tools\Set-RepositoryBaseline.ps1 -OrganizationPolicy -Owner <org> -WhatIf`, then without `-WhatIf`. It sets the organization's default workflow token (`GITHUB_TOKEN`) to read-only, so a workflow writes only where its job asks. It turns off "Allow GitHub Actions to create and approve pull requests", because with it on any writer's pull request can add a workflow that approves itself and meets a required approval (#460, [ADR-0036](../template/docs/decisions/project-template/0036-a-required-approval-is-met-by-ncode-reviews-approver-app.md)). It creates the event policy "Allow pull_request_target for code review" for `code-review.yml` and `code-review-auto-merge.yml` on every repository, because from December 2, 2026 GitHub blocks `pull_request_target` in a public repository without such a policy. Then turn on "Require two-factor authentication" on the security page; each repository's baseline run reports it as `organization two-factor requirement: required`.
- **Check:** the same command with `-WhatIf` prints `already set` on both lines; `gh api orgs/<org>/actions/permissions/workflow` shows `"default_workflow_permissions":"read"` and `"can_approve_pull_request_reviews":false`.
- **Goes wrong:** without `admin:org` the lines say `not available` and it exits 1; on GitHub Free the event policy answers "Upgrade to GitHub Team to enable this feature.", and then 2.1's run creates the same policy per repository. See [Protect the Default Branch](../README.md#protect-the-default-branch) for the details.

### 0.3 NCode Review's Organization Setup

- **Applies to:** GitHub, with NCode Review
- **Who:** an organization owner, with `admin:org`.
- **Where:** NCodeGroup/code-review's runbook, [Set Up NCode Review, End to End](https://github.com/NCodeGroup/code-review/blob/main/docs/setup.md).
- **Do:** Follow the runbook's [1. Once per Organization](https://github.com/NCodeGroup/code-review/blob/main/docs/setup.md#1-once-per-organization), 1.1 to 1.5: give `gh` the `admin:org` scope, create and install the two apps, NCode Review and NCode Review Approver, set up Anthropic, and store the organization secrets `NCODE_REVIEW_APP_PRIVATE_KEY` and `AWS_BEARER_TOKEN_BEDROCK` with NCodeGroup/code-review's `tools/Enable-CodeReview.ps1`. This page doesn't repeat them.
- **Check:** `gh secret list --org <org>` lists both secrets.
- **Goes wrong:** see the runbook's [5. Troubleshooting](https://github.com/NCodeGroup/code-review/blob/main/docs/setup.md#5-troubleshooting).

## 1. Create or Adopt

Do 1.1 or 1.2, then 1.3 for Node.js and 1.4.

### 1.1 A New Project

- **Applies to:** every project
- **Who:** a maintainer who may create repositories in the owner.
- **Where:** a clone of NCodeGroup/project-template.
- **Do:** Run `.\New-Project.ps1 -Path C:\src\<name> -CreateRemote`, where `<name>` is the repository's name by NCodeGroup's rule ([ADR-0045](../template/docs/decisions/project-template/0045-new-project-names-a-repository-by-ncodegroups-rule-and-refuses-a-name-that-doesnt-fit.md)): a .NET project's root namespace without `NCode.`, such as `Buffers` for `NCode.Buffers`, or lowercase kebab case for any other stack, such as `qso-viewer`. Answer `stack` in `-Data` to have the name checked before Copier asks anything. Add `-Owner <org>`, `-Visibility private` and `-Data @{ ... }` as needed. Copier asks the questions [Questions](../README.md#questions) lists and records the answers in `.copier-answers.yml`. Answer `code_review` yes for NCode Review and `nuget_package` yes for a .NET library. The script runs `git init -b main`, makes the first commit `Create project from project-template <version>`, creates the repository (public by default) and pushes `main`. It then runs `tools/Set-RepositoryBaseline.ps1 -RequireChecks 'build-and-test'`, unless you pass `-NoBaseline`. See [Create a Project](../README.md#create-a-project).
- **Check:** `Get-Content .template-version` in the project prints the version; `git log -1 --format=%s` shows the first commit; the repository exists on the host.
- **Goes wrong:** a missing Git `user.name` or `user.email`, or a signed-out `gh`; a failed baseline leaves the repository created and prints the command to run again (see [2.1](#21-run-the-baseline)); a folder name that doesn't fit the `stack` answer stops the script, which names the one that fits, deletes what Copier wrote and creates no repository.

### 1.2 An Existing Repository

- **Applies to:** every project
- **Who:** a maintainer with write access.
- **Where:** a clone of NCodeGroup/project-template, pointing at the repository's clean clone, on a branch of its own (run `git switch -c adopt-project-template` in the repository first).
- **Do:** Run `.\Adopt-Project.ps1 -Path C:\src\<name>`. It asks nothing and works out the answers. Pass `-Data @{ code_review = $true }` for NCode Review and `-Data @{ project_owned_files = '.github/workflows/ci.yml' }` to keep a CI workflow of its own. It leaves alone a `ci.yml` the repository has and every workflow beside it, a library's own workflow that runs `nuget push` (recorded as `nuget_publisher`, with no template `publish.yml`, `release-provenance.yml` or `raise-baseline.yml`), and the changelog's format. It runs the build and test commands and commits `Adopt project-template <version>`, then prints the baseline command and a `/plan-migration ...` request. Run that request in the repository with Claude Code or Copilot. It folds `.github/copilot-instructions.md` into `AGENTS.md`, reconciles workflows and, where tags lack changelog sections, backfills them. See [Adopt an Existing Repository](../README.md#adopt-an-existing-repository).
- **Check:** `.copier-answers.yml` exists; `git log -1 --format=%s` shows `Adopt project-template <version>`.
- **Goes wrong:** it refuses a dirty tree, a repository with no commits, or one that already has `.copier-answers.yml` (use `.template\Update-Project.ps1`); a failing build stages everything, commits nothing and exits 1; a kept `ci.yml` without a `workflow_call` trigger, or one that asks for more than `contents: read`, means no release is tagged until it is fixed (the script prints the note); a blank `license` answer warns.

### 1.3 Node.js: nvs and the Prelude

- **Applies to:** Node.js
- **Who:** every maintainer.
- **Where:** the project's folder.
- **Do:** Once per PC, run `./.template/Initialize-Nvs.ps1`, which installs and links the `.node-version` release. The project's `AGENTS.md` Landing names `prelude: ./.template/Use-Node.ps1`, which every plan step dot-sources.
- **Check:** `./.template/Use-Node.ps1; node --version` prints the `.node-version` major.
- **Goes wrong:** `Use-Node.ps1` fails naming `Initialize-Nvs.ps1` when nvs is missing, so run it.

### 1.4 First Push and First Pull Request

- **Applies to:** every project
- **Who:** the maintainer.
- **Where:** the project's folder.
- **Do:** A new project is already pushed (see [1.1](#11-a-new-project)), so open its first change as a pull request. For an adopted repository, run `git push -u origin adopt-project-template`, then `gh pr create --fill`. Wait for CI, then merge it with a merge commit or by rebasing. The checks that pass here are the ones [2.1](#21-run-the-baseline) requires: the template's CI job is `build-and-test`.
- **Check:** `gh pr checks <number>` shows every check passed.
- **Goes wrong:** a job that runs only on a schedule, a release or with `paths` filters never reports on every pull request, so requiring it blocks merges; `-RequireChecks auto` needs a merged pull request, so merge this one before 2.1.

## 2. Protect the Default Branch and Tags

### 2.1 Run the Baseline

- **Applies to:** GitHub
- **Who:** an admin of the repository (`repo` scope).
- **Where:** a clone of NCodeGroup/project-template.
- **Do:** Run `.\tools\Set-RepositoryBaseline.ps1 -Repo <name> -Owner <owner> -RequireChecks 'build-and-test' -WhatIf`, then run it without `-WhatIf`. `-Owner` defaults to NCodeGroup. A repository with its own CI uses `-RequireChecks auto -WhatIf`, which lists the checks that passed on its latest merged pull request and prints the command to trim and run. The script sets:
  - the "Protect main" ruleset: no deletion, no force push, a pull request with every conversation resolved, stale approvals dismissed on push, merge commit or rebase only, the required checks on an up-to-date branch, the code-scanning rule where CodeQL analyzes a language (see [2.3](#23-codeqls-languages)), and the approval that [2.2](#22-when-an-approval-is-required) describes
  - the "Protect release tags" ruleset on `v*`: no deletion, no update
  - delete branch on merge
  - a read-only workflow token, with Actions unable to approve pull requests
  - secret scanning and push protection (public repositories)
  - Dependabot alerts and security updates
  - private vulnerability reporting
  - immutable releases (see [3.3](#33-immutable-releases))
  - allow auto-merge
  - for a public repository with the code-review workflows, the `pull_request_target` event policy
  - a report of the organization's two-factor requirement

  Run it again after every change 2.2 lists. See [Protect the Default Branch](../README.md#protect-the-default-branch).
- **Check:** the same command with `-WhatIf` prints no `would set` line.
- **Goes wrong:** requiring a check that doesn't run on every pull request blocks every merge; a ruleset of the owner's is kept and only gets notices; a setting the organization decides prints `not available`.

### 2.2 When an Approval Is Required

- **Applies to:** GitHub
- **Who:** as in [2.1](#21-run-the-baseline)
- **Where:** as in [2.1](#21-run-the-baseline)
- **Do:** The baseline requires one approval, of the last push, only where NCode Review's approver is set up (see [section 5](#5-ncode-review)) or where `code-review.yml` passes `approve: true` and two or more people can write. Otherwise it requires none, since GitHub counts no approval from someone without write access ([ADR-0034](../template/docs/decisions/project-template/0034-with-one-writer-the-baseline-requires-no-approval.md), [ADR-0036](../template/docs/decisions/project-template/0036-a-required-approval-is-met-by-ncode-reviews-approver-app.md)). Run [2.1](#21-run-the-baseline) again after setting up the approver, and after adding or removing a writer.
- **Check:** `gh api repos/<owner>/<name>/rules/branches/main --jq '.[] | select(.type == "pull_request") | .parameters.required_approving_review_count'` prints `1` where the approval is required and `0` elsewhere.
- **Goes wrong:** requiring the approval before the approver is live blocks every merge, so the script checks the input and the secret first and requires nothing without both; a ruleset made before v0.96.0 can require last-push approval with no approval (#436), and the run prints the `gh api` command that turns it off.

### 2.3 CodeQL's Languages

- **Applies to:** GitHub
- **Who:** an admin of the repository.
- **Where:** the repository's Settings > Advanced Security > CodeQL analysis.
- **Do:** Set up default setup with the repository's languages. Then run [2.1](#21-run-the-baseline) again with the same `-RequireChecks`, which adds the code-scanning rule and switches the setup to the extended query suite.
- **Check:** `gh api repos/<owner>/<name>/code-scanning/default-setup --jq '.state + " " + (.languages | join(","))'` prints `configured` and at least one language.
- **Goes wrong:** an organization's security configuration can turn default setup on with no language, as on NCodeGroup/docs and NCodeGroup/brand; the baseline then leaves the rule out and says why, and a rule kept from an older run blocks every pull request until a language is set up ([ADR-0030](../template/docs/decisions/project-template/0030-the-code-scanning-rule-is-added-only-where-codeql-analyzes-a-language.md)).

### 2.4 Scorecard

- **Applies to:** GitHub, public repository
- **Who:** a maintainer with write access (`repo`, which includes `security_events`).
- **Where:** a clone of NCodeGroup/project-template; the repository's Security > Code scanning.
- **Do:** `scorecard.yml` runs on each push to the default branch and every Tuesday. With one writer, the baseline ends with a notice naming `tools/Dismiss-ScorecardAlerts.ps1`. Run `.\tools\Dismiss-ScorecardAlerts.ps1 -Repo <owner>/<name> -WhatIf`, then run it without `-WhatIf`. It dismisses only the Branch-Protection, CII-Best-Practices and Contributors alerts as won't fix, with a standard comment: the one [ADR-0035](../template/docs/decisions/project-template/0035-a-sole-maintainer-dismisses-the-scorecard-alerts-one-person-cannot-clear.md) gives for CII-Best-Practices and Contributors, and for Branch-Protection one that cites [ADR-0034](../template/docs/decisions/project-template/0034-with-one-writer-the-baseline-requires-no-approval.md) and [ADR-0036](../template/docs/decisions/project-template/0036-a-required-approval-is-met-by-ncode-reviews-approver-app.md), since the one ADR-0035 gives predates ADR-0036. It dismisses nothing with two or more writers. Re-run Scorecard once the approver is set up and approver-approved pull requests fill the last 30 commits: open the latest Scorecard run and choose Re-run all jobs, then compare each check with the table in [ADR-0020](../template/docs/decisions/project-template/0020-github-projects-are-scored-by-openssf-scorecard.md.jinja), where Branch-Protection scores 8 with the approver set up.
- **Check:** the `-WhatIf` run lists nothing to dismiss; `https://scorecard.dev/viewer/?uri=github.com/<owner>/<name>` shows the score.
- **Goes wrong:** an alert of any other check is the project's to fix, and stays open.

## 3. Releases

This section applies to a project whose `AGENTS.md` Landing section says `release: tag+release`, the default for a .NET library on GitHub, and not to one that says `none`. A .NET library on GitHub that says `none` or `tag` publishes nothing on merge: `Adopt-Project.ps1` and every `.\.template\Update-Project.ps1` run print the one-line change to `- release: tag+release` while it has `.github/workflows/tag-release.yml`.

### 3.1 How a Release Happens

- **Applies to:** GitHub
- **Who:** the maintainer who merges.
- **Where:** the plan, the pull request, the Actions tab.
- **Do:** A plan that changes what a release ships has a `Release:` line, and its last step writes that version's `CHANGELOG.md` section (and `version.json` in a library). A plan that ships nothing has none and tags nothing ([ADR-0032](../template/docs/decisions/project-template/0032-a-plan-is-released-only-when-it-changes-what-a-release-ships.md)). On merge, `tag-release.yml` reads `release`, runs `ci.yml` on the merged commit, then tags it with the newest changelog section's version, publishes the GitHub release from that section and, for a .NET library, starts `publish.yml`, or the workflows its `nuget_publisher` answer names ([ADR-0016](../template/docs/decisions/project-template/0016-releases-are-tagged-and-published-when-their-pull-request-merges.md.jinja)).
- **Check:** the Actions tab's "Tag and publish release" run passed; `gh release view <tag> --repo <owner>/<name>` shows the release.
- **Goes wrong:** a `ci.yml` without `workflow_call`, or one that asks for more than `contents: read`, stops the run; a `version.json` holding another version is refused; after a failed run, choose Re-run failed jobs on it, which tags the same commit.

### 3.2 Signed Tags

- **Applies to:** GitHub, public repository
- **Who:** nobody sets it up.
- **Where:** `tag-release.yml`.
- **Do:** Nothing. In a public repository the tag is signed with gitsign through the job's OIDC token, with no key to keep. A private repository's tags stay unsigned ([ADR-0028](../template/docs/decisions/project-template/0028-github-releases-are-immutable-and-their-tags-signed.md)).
- **Check:** with gitsign installed (`https://github.com/sigstore/gitsign`), run `gitsign verify-tag --certificate-identity https://github.com/<owner>/<name>/.github/workflows/tag-release.yml@refs/heads/main --certificate-oidc-issuer https://token.actions.githubusercontent.com <tag>`.
- **Goes wrong:** GitHub shows the signature as Unverified, since its certificate authority isn't GitHub's; `gitsign verify-tag` is the check that counts.

### 3.3 Immutable Releases

- **Applies to:** GitHub
- **Who:** the baseline (see [2.1](#21-run-the-baseline)).
- **Where:** [2.1](#21-run-the-baseline)'s run, and `https://github.com/<owner>/<name>/releases`.
- **Do:** The baseline turns immutable releases on, except where a default-branch workflow runs on a `release` event or uploads release assets, and with `-SkipImmutableReleases`. A .NET library's `publish.yml` and `release-provenance.yml` do, so its releases stay mutable: whether releases are immutable depends on what a project attaches after publishing, and the template doesn't draft a library's release to make it immutable ([ADR-0028](../template/docs/decisions/project-template/0028-github-releases-are-immutable-and-their-tags-signed.md)). A project whose own workflow runs on a `release` event only to publish elsewhere, attaching nothing, can turn them on with `gh api -X PUT repos/<owner>/<name>/immutable-releases`, which the baseline never undoes. The baseline never turns them off, and prints the `gh api -X DELETE repos/<owner>/<name>/immutable-releases` command where they are on beside such a workflow.
- **Check:** `gh api repos/<owner>/<name>/immutable-releases` shows `"enabled":true` where they apply; `gh release verify <tag> --repo <owner>/<name>`.
- **Goes wrong:** an immutable release refuses a file attached after it is published; `.template/Update-Project.ps1` says to delete `SECURITY.md`'s "Releases are immutable" paragraph where they stay off.

## 4. .NET Libraries on nuget.org

This section is for a .NET library on GitHub with the template's `publish.yml`, whose header ([publish.yml](../template/.github/workflows/publish.yml)) describes the setup. A library whose own workflow runs `nuget push` keeps its own setup.

### 4.1 Trusted Publishing on nuget.org

- **Applies to:** .NET library
- **Who:** the nuget.org account that owns the packages.
- **Where:** `https://www.nuget.org/account/trustedpublishing`.
- **Do:** Add a trusted publishing policy for GitHub Actions with the package owner, repository owner `<owner>`, repository `<name>`, workflow file `publish.yml` and environment `nuget`. No API key is stored anywhere: `publish.yml` exchanges the job's OIDC token for a short-lived key.
- **Check:** the page lists the policy.
- **Goes wrong:** `NUGET_USER` (see [4.2](#42-the-nuget-environment-and-nuget_user)) must name the account that owns the policy, or the login step fails; a renamed workflow file needs a new policy.

### 4.2 The nuget Environment and NUGET_USER

- **Applies to:** .NET library
- **Who:** an admin of the repository.
- **Where:** `https://github.com/<owner>/<name>/settings/environments` and `gh`.
- **Do:** Create the environment `nuget`. Add yourself, or the maintainers, as required reviewers, and leave "Prevent self-review" off with one maintainer. Set Deployment branches and tags to selected ones: the branch `main` (the default branch, for [4.5](#45-re-publish-a-release-that-failed)) and the tag pattern `v*` (for the run `tag-release.yml` starts on the tag). Then run `gh variable set NUGET_USER --body <nuget.org account> --repo <owner>/<name>`, using the account's profile name, not its email.
- **Check:** `gh api repos/<owner>/<name>/environments/nuget/deployment-branch-policies --jq '.branch_policies[] | .type + " " + .name'` prints `branch main` and `tag v*`; `gh variable list --repo <owner>/<name>` lists `NUGET_USER`.
- **Goes wrong:** a tags-only rule refuses 4.5's run from the default branch; without reviewers nothing waits for approval.

### 4.3 The First Package Validation Baseline

- **Applies to:** .NET library
- **Who:** the maintainer, in a plan or pull request.
- **Where:** the project's `Directory.Build.props`, after its import, or a packable project's `.csproj`.
- **Do:** Before the first release there is no baseline, so package validation still compares target frameworks. After the first stable release reaches nuget.org, set `<PackageValidationBaselineVersion>` once, by hand, to the last version on nuget.org. `.template\Update-Project.ps1` and `Adopt-Project.ps1` name the version to set ([ADR-0147](../template/docs/decisions/project-template/0147-packages-are-validated-against-the-last-published-package.md)). From then on [4.6](#46-raise-the-baseline-after-a-stable-release) raises it.
- **Check:** `git grep PackageValidationBaselineVersion` shows it; `./build/dod.ps1` passes (`-Fast` doesn't pack, so it doesn't validate).
- **Goes wrong:** a version not on nuget.org fails the pack; `CP0002` means a public member was removed or changed, and the template's [api-compatibility page](../template/docs/api-compatibility.md.jinja) says how to record an intended break.

### 4.4 Publish a Release

- **Applies to:** .NET library
- **Who:** a required reviewer of `nuget`.
- **Where:** the Publish packages run in the Actions tab.
- **Do:** [3.1](#31-how-a-release-happens)'s run starts Publish packages on the tag. Its pack job checks the tag is on the default branch, then tests and packs. The publish job waits for approval: open the run, choose Review deployments, tick `nuget`, and choose Approve and deploy.
- **Check:** the run's summary says `Published <n> of <n> packages at <version> to nuget.org`.
- **Goes wrong:** a run that ends in `startup_failure` at once, as NCodeGroup/Buffers' v5.5.0 did when a called workflow asked for more than `publish.yml` granted (#467, fixed in v0.111.1); update the template, then follow [4.5](#45-re-publish-a-release-that-failed). `Every package is already on nuget.org` means publish a new version.

### 4.5 Re-publish a Release That Failed

- **Applies to:** .NET library
- **Who:** a maintainer, then a `nuget` reviewer.
- **Where:** Actions > Publish packages > Run workflow, with "Use workflow from" set to the default branch, or `gh workflow run publish.yml --ref main -f tag=<tag> --repo <owner>/<name>`.
- **Do:** Start a **new** run from the default branch with the tag. It still checks out and packs the tag, and skips packages already pushed. Never choose Re-run on the failed run: a re-run replays the tag's own workflow files, so a fix on the default branch doesn't reach it.
- **Check:** as in [4.4](#44-publish-a-release).
- **Goes wrong:** the `nuget` environment refuses a run from `main` unless [4.2](#42-the-nuget-environment-and-nuget_user) allows the branch.

### 4.6 Raise the Baseline After a Stable Release

- **Applies to:** .NET library
- **Who:** a maintainer.
- **Where:** the issue the run opens.
- **Do:** After a stable release, the publish run's `baseline` job (`raise-baseline.yml`) waits for nuget.org to list the version, pushes `baseline-<version>` and opens an issue whose link opens the pull request with its title, description and `Closes #<issue>` filled in. Follow the link, create the pull request, let CI and NCode Review run, and merge it ([ADR-0150](../template/docs/decisions/project-template/0150-a-workflow-raises-the-package-validation-baseline-after-each-release.md.jinja), [ADR-0151](../template/docs/decisions/project-template/0151-release-follow-ups-are-jobs-publish-calls.md), [ADR-0036](../template/docs/decisions/project-template/0036-a-required-approval-is-met-by-ncode-reviews-approver-app.md)). It does nothing until [4.3](#43-the-first-package-validation-baseline)'s first baseline is set.
- **Check:** the pull request from `baseline-<version>` is merged and the issue is closed.
- **Goes wrong:** no workflow opens the pull request itself, since Actions may not create pull requests (see [0.2](#02-the-organizations-actions-policy)); after a run that failed after its push, `gh workflow run raise-baseline.yml -f tag=<tag> --repo <owner>/<name>` finds the branch and issue and writes the link again; pre-releases raise nothing.

### 4.7 Check the Package

- **Applies to:** .NET library
- **Who:** a maintainer.
- **Where:** `https://www.nuget.org/packages/<package id>` and the GitHub release.
- **Do:** On nuget.org, check the version is listed and its README tab shows the readme. On the release, `gh release view <tag> --repo <owner>/<name> --json assets --jq '.assets[].name'` lists each `.nupkg` and `.snupkg` (the symbol packages also went to nuget.org's symbol server), `<tag>.intoto.jsonl` (the provenance) and `<tag>.spdx.json` (the SBOM). `gh attestation verify <package>.nupkg --repo <owner>/<name>` passes.
- **Check:** those commands.
- **Goes wrong:** provenance still missing within 14 days of the run; `gh workflow run release-provenance.yml -f tag=<tag> -f run-id=<run id> --repo <owner>/<name>` backfills it.

## 5. NCode Review

This section is for a GitHub project with NCode Review, after [0.3](#03-ncode-reviews-organization-setup). NCode Review's runbook gives the per-repository steps in full, in [2. Once per Repository](https://github.com/NCodeGroup/code-review/blob/main/docs/setup.md#2-once-per-repository); 5.1 to 5.3 summarize them, in the same order.

### 5.1 Set Up the Repository

- **Applies to:** GitHub, with NCode Review
- **Who:** an organization owner (`admin:org`).
- **Where:** each app's installation settings (Organization settings > GitHub Apps > Configure > Repository access), and an up-to-date clone of NCodeGroup/code-review (run `git pull` first).
- **Do:** As the runbook's [2.1](https://github.com/NCodeGroup/code-review/blob/main/docs/setup.md#21-add-the-repository-to-both-apps-installations), [2.2](https://github.com/NCodeGroup/code-review/blob/main/docs/setup.md#22-store-the-approvers-key) and [2.3](https://github.com/NCodeGroup/code-review/blob/main/docs/setup.md#23-pass-the-approval-inputs-in-code-reviewyml) say, add the repository to both apps' installations, NCode Review and NCode Review Approver. Run `.\tools\Enable-CodeReview.ps1 -Repo <name> -ApproverPrivateKeyPath <path to the approver's .pem>`. It creates the `code-review` environment (default branch only), gives the repository the organization secrets, and stores `NCODE_REVIEW_APPROVER_PRIVATE_KEY` in that environment. Then delete the `.pem` (see [7.3](#73-rotate-a-key)). Make sure the default branch has `.github/workflows/code-review.yml`, from the `code_review` answer (see [1.1](#11-a-new-project) and [1.2](#12-an-existing-repository)) or from `.\.template\Update-Project.ps1 -Data @{ code_review = $true }` in the project. It pins NCodeGroup/code-review v1.5.0 or later by full commit SHA, and its review job passes `approve: true` and `approver-private-key: ${{ secrets.NCODE_REVIEW_APPROVER_PRIVATE_KEY }}`. `.template\Update-Project.ps1` says what an older file lacks.
- **Check:** `gh secret list --env code-review --repo <owner>/<name>` lists `NCODE_REVIEW_APPROVER_PRIVATE_KEY`.
- **Goes wrong:** a stale clone's script doesn't know `-ApproverPrivateKeyPath`; `gh`'s token can't list an installation's repositories, so the script warns and goes on, and you add the repository on the app's page; a public repository needs the event policy (see [0.2](#02-the-organizations-actions-policy) or [2.1](#21-run-the-baseline)) or GitHub blocks the review; the runbook's [5. Troubleshooting](https://github.com/NCodeGroup/code-review/blob/main/docs/setup.md#5-troubleshooting) has the rest.

### 5.2 Require the Approval

- **Applies to:** GitHub, with NCode Review
- **Who:** as in [2.1](#21-run-the-baseline)
- **Where:** as in [2.1](#21-run-the-baseline)
- **Do:** Only once [5.1](#51-set-up-the-repository) is on the default branch, run [2.1](#21-run-the-baseline)'s command again. It checks the input and the secret, then requires one approval, of the last push ([ADR-0036](../template/docs/decisions/project-template/0036-a-required-approval-is-met-by-ncode-reviews-approver-app.md)).
- **Check:** [2.2](#22-when-an-approval-is-required)'s check prints `1`.
- **Goes wrong:** run before 5.1, it requires nothing and names the missing piece.

### 5.3 Check the Approval

- **Applies to:** GitHub, with NCode Review
- **Who:** a maintainer.
- **Where:** the next pull request.
- **Do:** Mark it ready and let the review finish.
- **Check:** after a clean review, `gh api repos/<owner>/<name>/pulls/<number>/reviews --jq '.[] | .user.login + " " + .state'` shows `ncode-review-approver[bot] APPROVED`, and `gh pr view <number> --json reviewDecision` shows `APPROVED`.
- **Goes wrong:** an approval from `ncode-review[bot]` instead means no approver key reached the review, so recheck [5.1](#51-set-up-the-repository); a later review that doesn't approve dismissed it.

### 5.4 Day to Day

- **Applies to:** GitHub, with NCode Review
- **Who:** the maintainers.
- **Where:** each pull request.
- **Do:**
  - A draft pull request is reviewed when it is marked ready.
  - A push to a ready pull request is reviewed after a comment with `/review` on its first line.
  - A review that doesn't approve dismisses the earlier approval.
  - NCode Review reviews a pull request Dependabot opens, and again after each push Dependabot makes, and approves a clean one; a maintainer approves another bot's pull request ([ADR-0041](../template/docs/decisions/project-template/0041-ncode-review-reviews-and-approves-dependabots-pull-requests.md)).
  - The `AGENTS.md` Landing line `draft: yes` has `/ship-plan` open drafts, because marking a pull request ready is the person's review ([ADR-0022](../template/docs/decisions/project-template/0022-ncode-reviews-approval-gates-the-merge.md.jinja)).
  - Nothing requires the "Code review" check, so the person who merges waits for it ([ADR-0019](../template/docs/decisions/project-template/0019-nothing-requires-the-code-review-check-the-person-who-merges-waits-for-it.md.jinja)).
- **Check:** the pull request shows the review and the approval.
- **Goes wrong:** an NCode Review outage blocks merges where the approval is required, until it is fixed or the ruleset changes.

## 6. Other One-Time Settings

### 6.1 The OpenSSF Best Practices Badge

- **Applies to:** every project
- **Who:** a maintainer.
- **Where:** `https://www.bestpractices.dev` and the project.
- **Do:** The project's `docs/best-practices-criteria.md` maps every criterion to its evidence. On GitHub, `/best-practices` in the project writes the prompt that registers the project or updates its answers. Once the project is registered, run `.\.template\Update-Project.ps1 -Data @{ best_practices_project = '<number>' }` and add the badge line the update prints near the top of `README.md`.
- **Check:** the update prints no badge reminder.
- **Goes wrong:** `require_2FA` and `secure_2FA` stay Unmet until an owner confirms the organization's two-factor requirement (see [0.2](#02-the-organizations-actions-policy)).

### 6.2 Codecov

- **Applies to:** where the project has one
- **Who:** an organization owner installs the app; a maintainer adds the workflow.
- **Where:** `https://github.com/apps/codecov`.
- **Do:** The template publishes no coverage: CI's coverage gate is the verdict ([ADR-0026](../template/docs/decisions/project-template/0026-tests-gate-coverage-at-the-gold-thresholds-and-a-release-waits-for-them.md)). A project that shows a Codecov badge adds a workflow of its own, as NCodeGroup/Buffers' `.github/workflows/coverage.yml` does on each push to the default branch. It uploads with the job's OIDC token instead of a stored `CODECOV_TOKEN`, so its one setup is the Codecov GitHub App installed for the organization. Keep it out of `ci.yml`, which `tag-release.yml` calls with only `contents: read`.
- **Check:** the project's page on codecov.io shows the default branch's latest commit.
- **Goes wrong:** a job asking for `id-token: write` inside `ci.yml` stops every release run.

### 6.3 The Documentation Site and GitHub Pages

- **Applies to:** where the project has one
- **Who:** an admin of the repository.
- **Where:** `https://github.com/<owner>/<name>/settings/pages`.
- **Do:** Do as NCodeGroup/Buffers' `docs.yml` does, which builds `docs/site/` with the NCodeGroup/docs toolchain. Set Pages' source to GitHub Actions. The `github-pages` environment deploys from the default branch only. Set the custom domain, such as `buffers.ncode.io`, with its DNS record, and Enforce HTTPS. Set the repository's website with `gh repo edit <owner>/<name> --homepage https://<domain>/`. `docs/site/site.config.json`'s `site.url` also becomes a library package's project page.
- **Check:** `gh api repos/<owner>/<name>/pages --jq '.build_type + " " + .cname + " " + (.https_enforced | tostring)'` prints `workflow <domain> true`.
- **Goes wrong:** HTTPS can't be enforced until the DNS record resolves.

### 6.4 The Copilot Cloud Agent's Environment

- **Applies to:** GitHub, with Copilot
- **Who:** a maintainer.
- **Where:** the Actions tab; `https://github.com/<owner>/<name>/settings/environments`.
- **Do:** `.github/workflows/copilot-setup-steps.yml` prepares the agent's runner, and GitHub runs it only from the default branch. Run it once with `gh workflow run copilot-setup-steps.yml --repo <owner>/<name>`. A secret or variable the agent's session needs goes in the repository's `copilot` environment, never in the workflow.
- **Check:** `gh run list --workflow copilot-setup-steps.yml --limit 1 --repo <owner>/<name>` shows it passed.
- **Goes wrong:** a failing step is skipped past and the session starts without that tool.

### 6.5 Labels

- **Applies to:** GitHub
- **Who:** nobody, usually.
- **Where:** `https://github.com/<owner>/<name>/labels`.
- **Do:** `/ship-plan` makes `follow-up` the first time it files a follow-up. The template-update workflow makes `template-update` with its first notice. `documentation` is one of GitHub's default labels, which `/plan-issue` reads as a docs plan. A repository whose default labels were deleted makes it with `gh label create documentation --repo <owner>/<name>`.
- **Check:** `gh label list --repo <owner>/<name>`.
- **Goes wrong:** nothing beyond the deleted label.

## 7. Stay Current

See [Update a Project](../README.md#update-a-project) and [Stay Current](../README.md#stay-current) in the README for the reference.

### 7.1 Template Updates

- **Applies to:** every project
- **Who:** a maintainer.
- **Where:** the project.
- **Do:** `template-update.yml` keeps one open issue labeled `template-update`, "Update to project-template <version>", every Monday at 07:00 UTC. Run `/plan-issue <number>` on it, or `/plan-template-update`, or `.\.template\Update-Project.ps1` on a branch of its own. The update also says what a `code-review.yml` lacks (a pin before v1.5.0, `approve: true`, `approver-private-key`) and a missing `draft: yes`.
- **Check:** `gh issue list --label template-update --state open --repo <owner>/<name>` lists nothing once the project is current.
- **Goes wrong:** an update that conflicts stops with the files to fix (see [Resolve a Conflict](../README.md#resolve-a-conflict)).

### 7.2 Dependabot

- **Applies to:** GitHub
- **Who:** a maintainer merges.
- **Where:** the repository's pull requests; `.github/dependabot.yml`.
- **Do:**
  - `.github/dependabot.yml` opens a weekly grouped pull request per ecosystem for versions at least three days old, its cooldown, and security updates in their own.
  - A minor or patch bump of the NCode Review pin comes alone and merges itself through `code-review-auto-merge.yml` once the required checks pass, which needs "Allow auto-merge" (see [2.1](#21-run-the-baseline)).
  - Where an approval is required, the NCode Review Approver approves it after a clean review, where it is set up, so the bump merges with no person's action; elsewhere a person with write access approves it.
  - A major release and every other update wait for a person.
  - No new .NET SDK major is offered.
- **Check:** the repository's Insights > Dependency graph > Dependabot shows recent checks.
- **Goes wrong:** a CI pin moved in both the template and the project conflicts on update, so keep the newer version.

### 7.3 Rotate a Key

- **Applies to:** GitHub, with NCode Review
- **Who:** an organization owner.
- **Where:** the app's settings page, `https://github.com/organizations/<org>/settings/apps/<app>`, and NCodeGroup/code-review's clone.
- **Do:**
  - Generate a new private key.
  - Store it: the NCode Review app's with `.\tools\Enable-CodeReview.ps1 -AppPrivateKeyPath <pem>`, the approver's with `-Repo <every repository that uses it> -ApproverPrivateKeyPath <pem>`.
  - Delete the `.pem` from disk.
  - Only after every repository has the new key, delete the old key on the app's page.
  - Never keep a `.pem` on disk: GitHub keeps the secret, a new key can be generated at any time, and a leaked approver key can mint a Contents: write token for every repository the approver is installed on ([ADR-0036](../template/docs/decisions/project-template/0036-a-required-approval-is-met-by-ncode-reviews-approver-app.md)).
- **Check:** the app's page lists only the new key; the check in [5.3](#53-check-the-approval) passes on the next review.
- **Goes wrong:** deleting the old key before every repository has the new one stops their reviews from approving.

## 8. Checklist

Audit an adopted repository with `.\tools\Get-AdoptionChecklist.ps1 -Path C:\src\<name>`, from a clone of NCodeGroup/project-template, on an up-to-date clone of the repository on its default branch. It changes nothing: it runs each row's check through the clone, `gh`, and the `-WhatIf` runs the last column names, prints each row as `done`, `not done`, `unreadable` or `does not apply`, with the reason, then a count of each, and exits 1 when a row is not done. A row that only a web page shows, such as 4.1, is `unreadable` and names the page. The last column names the script whose `-WhatIf` run checks a row on its own.

| Step | Applies to | Shows it is done | Checked by a script |
| --- | --- | --- | --- |
| [0.1](#01-accounts-and-tools) | every project | `gh auth status` shows the account and its scopes; `copier --version`, `pwsh --version`, `git config user.email` print values | No |
| [0.2](#02-the-organizations-actions-policy) | GitHub | `-WhatIf` prints `already set` on both lines; `gh api orgs/<org>/actions/permissions/workflow` shows read-only and `can_approve_pull_request_reviews` false | `Set-RepositoryBaseline.ps1 -OrganizationPolicy -WhatIf`; the repository run's `organization two-factor requirement` line for two-factor authentication |
| [0.3](#03-ncode-reviews-organization-setup) | GitHub, with NCode Review | `gh secret list --org <org>` lists both secrets | No |
| [1.1](#11-a-new-project) | every project | `Get-Content .template-version` prints the version; the repository exists on the host | No |
| [1.2](#12-an-existing-repository) | every project | `.copier-answers.yml` exists; the last commit is `Adopt project-template <version>` | No |
| [1.3](#13-nodejs-nvs-and-the-prelude) | Node.js | `./.template/Use-Node.ps1; node --version` prints the `.node-version` major | No |
| [1.4](#14-first-push-and-first-pull-request) | every project | `gh pr checks <number>` shows every check passed | No |
| [2.1](#21-run-the-baseline) | GitHub | `-WhatIf` prints no `would set` line | `Set-RepositoryBaseline.ps1 -WhatIf` |
| [2.2](#22-when-an-approval-is-required) | GitHub | the branch rule's `required_approving_review_count` is `1` where an approval is required and `0` elsewhere | `Set-RepositoryBaseline.ps1 -WhatIf` |
| [2.3](#23-codeqls-languages) | GitHub | `gh api repos/<owner>/<name>/code-scanning/default-setup` shows `configured` and a language | `Set-RepositoryBaseline.ps1 -WhatIf` |
| [2.4](#24-scorecard) | GitHub, public repository | the `-WhatIf` run lists nothing to dismiss; the Scorecard viewer shows the score | `Dismiss-ScorecardAlerts.ps1 -WhatIf` |
| [3.1](#31-how-a-release-happens) | GitHub | the "Tag and publish release" run passed; `gh release view <tag>` shows the release | No |
| [3.2](#32-signed-tags) | GitHub, public repository | `gitsign verify-tag` accepts the tag | No |
| [3.3](#33-immutable-releases) | GitHub | `gh api repos/<owner>/<name>/immutable-releases` shows `"enabled":true` where they apply; `gh release verify <tag>` | `Set-RepositoryBaseline.ps1 -WhatIf` |
| [4.1](#41-trusted-publishing-on-nugetorg) | .NET library | nuget.org's Trusted Publishing page lists the policy | No |
| [4.2](#42-the-nuget-environment-and-nuget_user) | .NET library | the `nuget` environment allows `branch main` and `tag v*`; `gh variable list` lists `NUGET_USER` | No |
| [4.3](#43-the-first-package-validation-baseline) | .NET library | `git grep PackageValidationBaselineVersion` shows it; `./build/dod.ps1` passes | `.template/Update-Project.ps1`'s notes |
| [4.4](#44-publish-a-release) | .NET library | the run's summary says `Published <n> of <n> packages at <version> to nuget.org` | No |
| [4.5](#45-re-publish-a-release-that-failed) | .NET library | as 4.4 | No |
| [4.6](#46-raise-the-baseline-after-a-stable-release) | .NET library | the `baseline-<version>` pull request is merged and the issue is closed | No |
| [4.7](#47-check-the-package) | .NET library | the commands in 4.7 succeed | No |
| [5.1](#51-set-up-the-repository) | GitHub, with NCode Review | `gh secret list --env code-review --repo <owner>/<name>` lists `NCODE_REVIEW_APPROVER_PRIVATE_KEY` | `Set-RepositoryBaseline.ps1 -WhatIf` for the secret; `.template/Update-Project.ps1`'s notes for `code-review.yml` |
| [5.2](#52-require-the-approval) | GitHub, with NCode Review | 2.2's check prints `1` | No |
| [5.3](#53-check-the-approval) | GitHub, with NCode Review | after a clean review the reviews list shows `ncode-review-approver[bot] APPROVED` and `reviewDecision` is `APPROVED` | No |
| [5.4](#54-day-to-day) | GitHub, with NCode Review | the pull request shows the review and the approval | No |
| [6.1](#61-the-openssf-best-practices-badge) | every project | the update prints no badge reminder | `.template/Update-Project.ps1`'s notes |
| [6.2](#62-codecov) | where the project has one | codecov.io shows the default branch's latest commit | No |
| [6.3](#63-the-documentation-site-and-github-pages) | where the project has one | `gh api repos/<owner>/<name>/pages` prints `workflow <domain> true` | No |
| [6.4](#64-the-copilot-cloud-agents-environment) | GitHub, with Copilot | `gh run list --workflow copilot-setup-steps.yml --limit 1` shows it passed | No |
| [6.5](#65-labels) | GitHub | `gh label list --repo <owner>/<name>` lists the labels | No |
| [7.1](#71-template-updates) | every project | `gh issue list --label template-update --state open` lists nothing once current | `template-update.yml` |
| [7.2](#72-dependabot) | GitHub | Insights > Dependency graph > Dependabot shows recent checks | No |
| [7.3](#73-rotate-a-key) | GitHub, with NCode Review | the app's page lists only the new key; 5.3's check passes | No |

For a row marked No, the checker reads what the Shows it is done column names where a command can: 1.4 and 5.3 from the latest merged pull request, 3.1, 4.4 and 6.4 from their workflow's latest run, 1.3 from the node on PATH or the releases nvs has installed, without running `Use-Node.ps1`, which installs a missing release, and 4.3 without running `./build/dod.ps1`.
