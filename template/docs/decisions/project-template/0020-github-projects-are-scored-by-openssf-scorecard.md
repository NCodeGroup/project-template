# 0020. A GitHub project is scored by OpenSSF Scorecard

- **Status:** Accepted
- **Date:** 2026-11-14

## Context

OpenSSF Scorecard grades a repository's supply-chain practice from outside, with a score from 0 to 10 over a fixed set
of checks. The Buffers library, built from this template, scored 7. Some checks the template controls; others need a
person, a second reviewer or a registration the template cannot make.

## Decision

Every GitHub project runs `.github/workflows/scorecard.yml`. The workflow publishes the score for the README badge and
uploads its findings to code scanning. A private repository deletes the workflow with the `project_owned_files`
answer, because publishing the score needs a public repository.

The table lists each check, what the template does for it and what needs a person.

| Check | The template | Needs a person |
| --- | --- | --- |
| Binary-Artifacts | Commits no binary files. | Nothing. |
| Dangerous-Workflow | No workflow runs untrusted pull request code with a privileged token. | Nothing. |
| Pinned-Dependencies | Workflow actions are pinned by commit SHA (ADR-0008). | Nothing. |
| Token-Permissions | Every workflow has a top-level read-only token; job-level write is only in `tag-release.yml`, `code-review-auto-merge.yml` and `release-provenance.yml`. | Nothing. |
| Dependency-Update-Tool | Dependabot is configured. | Nothing. |
| Security-Policy | `SECURITY.md` ships. | Nothing. |
| License | `LICENSE` ships. | Nothing. |
| SAST | CodeQL runs through the ruleset. | Nothing. |
| Vulnerabilities | Dependency and vulnerability scanning is configured. | Fix the findings it reports. |
| CI-Tests | Pull requests run the CI workflow. | Nothing. |
| Maintained | Scheduled automation keeps the repository active. | Keep committing and answering issues. |
| Signed-Releases | A GitHub .NET library attaches build provenance to its releases (ADR-0138). | Nothing. |
| Packaging | `publish.yml` publishes the packages. | The first successful `publish.yml` run. |
| Branch-Protection | The ruleset blocks deletion and force pushes, requires a pull request, an up-to-date branch and the status check, dismisses stale reviews and requires approval of the last push. | Approvals need a second reviewer. |
| Code-Review | Pull requests are reviewed. | A second human; bot reviews do not count. |
| Contributors | None. | Contributors from other organizations. |
| Fuzzing | A .NET project adds FsCheck property tests to its test project. | Write the property tests. |
| CII-Best-Practices | None. | The maintainer registers the repository at https://www.bestpractices.dev; passing scores 5, in progress scores 2. |

## Options considered

- Requiring one approving review in the ruleset. Rejected: a sole maintainer could not merge.
- Running Scorecard without publishing the score. Rejected: the badge and code scanning findings are the point.
- Running the Scorecard workflow in every GitHub project (chosen).

## Consequences

- A solo project's score tops out below 10, and the README says why.
- A private repository deletes the workflow, and its score is not published.

## References

- [ADR-0005](0005-the-default-branch-accepts-changes-only-through-pull-requests.md): the default branch accepts changes
  only through pull requests.
- [ADR-0008](0008-external-inputs-are-pinned-and-kept-current.md): external inputs are pinned and kept current.
- [ADR-0138](0138-releases-carry-build-provenance.md): releases carry build provenance.
- `.github/workflows/scorecard.yml`
