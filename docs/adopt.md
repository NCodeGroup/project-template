# Adopt a Project, End to End

This runbook takes a maintainer from nothing to a fully adopted repository, new or existing, top to bottom, without reading code. [README.md](../README.md) is the reference for each script, and this page is the order to run them in. Section 8 is a checklist to audit an adopted repository.

## How to Read It

Each step lists Applies to, Who, Where, Do, Check and Goes wrong.

The `Applies to` values are:

- `every project`
- `GitHub`
- `GitLab`
- `.NET library`
- `Node.js`
- `public repository`
- `with NCode Review`
- `where the project has one`

On GitLab, follow [2.5](#25-on-gitlab) for which steps apply.

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
- **Do:** Turn on two-factor authentication on every owner's account. Install PowerShell 7 (7.4 or later), Git with `user.name` and `user.email`, the GitHub CLI, uv and Copier, nvs for Node.js projects and glab for GitLab, as [USAGE.md](../USAGE.md#install-the-tools) and [Set Up Git and GitHub](../USAGE.md#set-up-git-and-github) say. `gh auth login` gives the token `repo`, `read:org` and `gist`, plus `workflow` with HTTPS Git, which lets Git push workflow files. `repo` covers the baseline (with the admin role on the repository) and `Dismiss-ScorecardAlerts.ps1` (its `security_events` scope is part of `repo`). `admin:org`, added with `gh auth refresh -h github.com -s admin:org`, is needed only for 0.2's `-OrganizationPolicy` and NCode Review's organization secrets (0.3, 5.1). Clone NCodeGroup/project-template and run `git pull` in it before each use.
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
- **Where:** NCodeGroup/code-review's README.
- **Do:** Create and install the two apps, NCode Review and NCode Review Approver, set up Anthropic, and store the organization secrets `NCODE_REVIEW_APP_PRIVATE_KEY` and `AWS_BEARER_TOKEN_BEDROCK` with its `tools/Enable-CodeReview.ps1`, as `https://github.com/NCodeGroup/code-review#using-it` says. Its end-to-end runbook is NCodeGroup/code-review#237. This page doesn't repeat it.
- **Check:** `gh secret list --org <org>` lists both secrets.
- **Goes wrong:** see code-review's runbook (NCodeGroup/code-review#237) for its own troubleshooting.

## 1. Create or Adopt

Do 1.1 or 1.2, then 1.3 for Node.js and 1.4.

### 1.1 A New Project

- **Applies to:** every project
- **Who:** a maintainer who may create repositories in the owner.
- **Where:** a clone of NCodeGroup/project-template.
- **Do:** Run `.\New-Project.ps1 -Path C:\src\<name> -CreateRemote`. Add `-Owner <org>`, `-Visibility private` and `-Data @{ ... }` as needed. Copier asks the questions [Questions](../README.md#questions) lists and records the answers in `.copier-answers.yml`. Answer `code_review` yes for NCode Review (GitHub only) and `nuget_package` yes for a .NET library. The script runs `git init -b main`, makes the first commit `Create project from project-template <version>`, creates the repository (public by default) and pushes `main`. On GitHub it then runs `tools/Set-RepositoryBaseline.ps1 -RequireChecks 'build-and-test'`, and on GitLab `tools/Set-GitLabBaseline.ps1`, unless you pass `-NoBaseline`. See [Create a Project](../README.md#create-a-project).
- **Check:** `Get-Content .template-version` in the project prints the version; `git log -1 --format=%s` shows the first commit; the repository exists on the host.
- **Goes wrong:** a missing Git `user.name` or `user.email`, or a signed-out `gh` or `glab`; a failed baseline leaves the repository created and prints the command to run again (see [2.1](#21-run-the-baseline)).

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

GitHub runs 2.1 to 2.4; GitLab runs only 2.5.

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
- **Do:** `scorecard.yml` runs on each push to the default branch and every Tuesday. With one writer, the baseline ends with a notice naming `tools/Dismiss-ScorecardAlerts.ps1`. Run `.\tools\Dismiss-ScorecardAlerts.ps1 -Repo <owner>/<name> -WhatIf`, then run it without `-WhatIf`. It dismisses only the Branch-Protection, CII-Best-Practices and Contributors alerts as won't fix, with the comment [ADR-0035](../template/docs/decisions/project-template/0035-a-sole-maintainer-dismisses-the-scorecard-alerts-one-person-cannot-clear.md) gives, and it dismisses nothing with two or more writers. Re-run Scorecard once the approver is set up and approver-approved pull requests fill the last 30 commits (#437): open the latest Scorecard run and choose Re-run all jobs, then compare each check with the table in [ADR-0020](../template/docs/decisions/project-template/0020-github-projects-are-scored-by-openssf-scorecard.md.jinja).
- **Check:** the `-WhatIf` run lists nothing to dismiss; `https://scorecard.dev/viewer/?uri=github.com/<owner>/<name>` shows the score.
- **Goes wrong:** an alert of any other check is the project's to fix, and stays open.

### 2.5 On GitLab

- **Applies to:** GitLab
- **Who:** a Maintainer of the project, signed in with `glab`.
- **Where:** a clone of NCodeGroup/project-template.
- **Do:** Run `.\tools\Set-GitLabBaseline.ps1 -Project <group/name> -WhatIf`, then run it without `-WhatIf`. Add `-Hostname` for a GitLab other than gitlab.com, or `-Path` to point at a clone. It turns on "All threads must be resolved" and "Pipelines must succeed", sets "Squash commits when merging" to "Do not allow", lets no one push to the default branch, and schedules the "Weekly dependency audit" pipeline. A .NET library adds `-BaselineToken`, which protects `v*` tags and creates the `raise-baseline` project access token (valid for a year) in the masked, protected `BASELINE_TOKEN` variable. On GitLab the other steps that apply are 0.1 (with `glab`), [section 1](#1-create-or-adopt), [4.3](#43-the-first-package-validation-baseline) and [7.1](#71-template-updates); the rest are GitHub only. See [Protect the Default Branch](../README.md#protect-the-default-branch).
- **Check:** the `-WhatIf` run prints `already set` for every setting.
- **Goes wrong:** a project whose CI runs no pipeline on a merge request can't merge; a protection that names users or groups (GitLab Premium) is left for Settings > Repository > Protected branches; after a year the token expires, so delete `BASELINE_TOKEN` and run the script with `-BaselineToken` again.

## 3. Releases

This section applies to a project whose `AGENTS.md` Landing section says `release: tag+release`, the default for a .NET library on GitHub, and not to one that says `none`.

### 3.1 How a Release Happens

- **Applies to:** GitHub
- **Who:** the maintainer who merges.
- **Where:** the plan, the pull request, the Actions tab.
- **Do:** A plan that changes what a release ships has a `Release:` line, and its last step writes that version's `CHANGELOG.md` section (and `version.json` in a library). A plan that ships nothing has none and tags nothing ([ADR-0032](../template/docs/decisions/project-template/0032-a-plan-is-released-only-when-it-changes-what-a-release-ships.md)). On merge, `tag-release.yml` reads `release`, runs `ci.yml` on the merged commit, then tags it with the newest changelog section's version, publishes the GitHub release from that section and, for a .NET library, starts `publish.yml` ([ADR-0016](../template/docs/decisions/project-template/0016-releases-are-tagged-and-published-when-their-pull-request-merges.md.jinja)).
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
- **Do:** The baseline turns immutable releases on, except where a default-branch workflow runs on a `release` event or uploads release assets, and with `-SkipImmutableReleases`. A .NET library's `publish.yml` and `release-provenance.yml` do, so its releases stay mutable. The baseline never turns them off, and prints the `gh api -X DELETE repos/<owner>/<name>/immutable-releases` command where they are on beside such a workflow.
- **Check:** `gh api repos/<owner>/<name>/immutable-releases` shows `"enabled":true` where they apply; `gh release verify <tag> --repo <owner>/<name>`.
- **Goes wrong:** an immutable release refuses a file attached after it is published; `.template/Update-Project.ps1` says to delete `SECURITY.md`'s "Releases are immutable" paragraph where they stay off.
