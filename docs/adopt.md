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
