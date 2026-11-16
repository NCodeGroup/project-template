# 0029. GitLab projects audit their dependencies in CI

- **Status:** Accepted
- **Date:** 2026-11-16

## Context

The OpenSSF Best Practices silver MUST `dependency_monitoring` asks that dependencies be monitored or checked
periodically for known vulnerabilities. On GitHub, Dependabot does it. A GitLab project had nothing, so it was a Gap in
`docs/best-practices-criteria.md`.

## Decision

`.gitlab-ci.yml` gives a Node.js or Python project a `dependency-audit` job that runs the package manager's audit on
every pipeline and fails on a vulnerability of moderate severity or above: `npm audit`, `pnpm audit`, `yarn npm audit`,
`bun audit` or `pip-audit`. A .NET project's build already fails in CI on a NuGet advisory.

The template's `tools/Set-GitLabBaseline.ps1` schedules a weekly pipeline on the default branch, "Weekly dependency
audit", Mondays at 06:00 UTC, so the checks run when nothing is pushed too. GitLab mails a failed scheduled pipeline to
its owner.

## Options considered

- GitLab's Dependency Scanning. Rejected: its results show only on GitLab Ultimate.
- Renovate. Rejected: it is a bot and a token to set up by hand per project.
- The package managers' own audits (chosen): they are free, need no setup, and are in the images CI already uses.

## Consequences

- A new advisory fails the next merge request's pipeline until the dependency is moved or the finding is judged
  unexploitable.
- A PowerShell or other project still has no dependency check.
- GitLab caps scheduled pipelines, and a weekly one stays well inside the cap.

## References

- `.gitlab-ci.yml`, `tools/Set-GitLabBaseline.ps1` in the template's repository,
  https://docs.gitlab.com/ci/pipelines/schedules/
