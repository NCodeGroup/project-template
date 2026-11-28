# 0047. codeql.yml runs like ci.yml and steps aside for a repository's own CodeQL workflow

- **Status:** Accepted
- **Date:** 2026-11-28
- **Amends:** 0044

## Context

[ADR-0044](0044-a-fork-pull-request-merges-without-a-bypass.md) gives every GitHub project
`.github/workflows/codeql.yml`, which runs CodeQL on every pull request, a fork's too, and has the baseline turn
CodeQL's default setup off where a workflow runs CodeQL on `pull_request`. It left three gaps
([NCodeGroup/project-template#541](https://github.com/NCodeGroup/project-template/issues/541)):

- the workflow had no concurrency groups, so each push to a pull request ran a full analysis beside the one it
  superseded;
- on C#, `build-mode: none` restored the projects' packages with the runner's .NET SDK, not the one `global.json`
  selects;
- an adoption or an update added it beside a repository's own CodeQL workflow, so each commit would be analyzed
  twice under the same categories, and the later upload of a category replaces the earlier one.

## Decision

1. `codeql.yml` shares `ci.yml`'s concurrency groups, named `codeql-` in place of `ci-`: a newer push to a pull
   request or a topic branch cancels the run it supersedes, and a run for a default-branch commit or a merge queue
   entry is never cancelled.
2. Before CodeQL starts on C#, it installs the .NET SDK `global.json` selects with `./.github/actions/install-dotnet`
   where the project has that action, as a .NET project does, so `build-mode: none` restores the projects' packages
   with that SDK.
3. A repository whose own workflow, other than `codeql.yml`, runs CodeQL on `pull_request` by the rules ADR-0044's
   decision 2 gives the baseline, where its `on:` names `pull_request` and a line that isn't a comment uses
   `github/codeql-action/analyze@`, keeps that workflow and gets no `codeql.yml`. The template's `Adopt-Project.ps1`
   and `.template/Update-Project.ps1` leave the file out and say so, and the adoption asks to reconcile no such
   workflow with `ci.yml`. The baseline counts that workflow as CodeQL's setup, and
   `tools/Get-AdoptionChecklist.ps1`'s row 2.3 counts it the same way.
4. A CodeQL workflow of the repository's own that doesn't run on `pull_request` doesn't count: the repository gets
   `codeql.yml` beside it, which analyzes every pull request, a fork's too.

## Options considered

- Add `codeql.yml` beside a repository's own CodeQL workflow. Rejected: each commit is analyzed twice, and the later
  upload of a category replaces the earlier one.
- Leave `codeql.yml` out beside any workflow that runs CodeQL, whatever its triggers. Rejected: a workflow that runs
  only on push or a schedule leaves a fork's pull request unanalyzed, the gap ADR-0044 closes, and the baseline
  doesn't count it, so default setup stays on.
- Pick the languages from the template's answers rather than the tracked files. Rejected: ADR-0044's languages job
  already covers a site's TypeScript and a Node.js tool, and analyzes no language without code.
- Share `ci.yml`'s concurrency groups, install the SDK for C#, and step aside for a workflow that runs CodeQL on
  `pull_request` (chosen).

## Consequences

- A push to a pull request cancels the CodeQL run it supersedes, as it cancels the CI run.
- A C# project's analysis restores its packages with the SDK its build uses.
- A repository whose own workflow runs CodeQL on pull requests analyzes what that workflow analyzes. To take the
  template's `codeql.yml`, its owner deletes that workflow and runs the update again.
- A project that has `codeql.yml` keeps it when it adds a workflow of its own for a language that needs a build, as
  ADR-0044 allows: the file is left out only where it is missing.

## References

- [ADR-0044](0044-a-fork-pull-request-merges-without-a-bypass.md)
- NCodeGroup/NCode.Disposables's `.github/workflows/codeql.yml` and its ADR-1014, which share `ci.yml`'s concurrency
  groups
- [NCodeGroup/project-template#541](https://github.com/NCodeGroup/project-template/issues/541)
