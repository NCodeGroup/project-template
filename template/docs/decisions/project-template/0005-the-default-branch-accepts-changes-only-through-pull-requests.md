# 0005. The default branch accepts changes only through pull requests that pass CI

- **Status:** Accepted
- **Date:** 2026-10-31

## Context

CI runs the build, the tests and the commit attribution check on every pull request, but a direct push to the default
branch skips all of it. The push is the one path by which an unchecked commit reaches the trunk. Every other
contributor already works through branches: plans land through `/ship-plan`, `/run-issues` opens a pull request per
issue, and dependency bots and cloud agents open pull requests of their own.

A rule that requires an approving review cannot be met in a repository with one maintainer, because a host does not
let the author approve their own pull request. A pull request rule with zero required approvals, combined with
required status checks, can be met by one person and still enforces the gate.

## Decision

The default branch accepts changes only through a pull request whose required checks pass on a branch up to date with
it.

1. On GitHub, one repository ruleset protects the default branch, with no bypass actors, as the template's repository
   baseline writes it:
   - the branch cannot be deleted or force-pushed;
   - a pull request is required, with zero required approvals and every review conversation resolved before the merge;
   - merges are by merge commit or rebase, never squash, so a plan's step commits stay on the branch and a squash
     cannot copy agent co-author trailers into the default branch
     ([ADR-0002](0002-commits-are-attributed-to-people-not-agents.md));
   - the CI jobs, `build-and-test` and `Commit attribution` by default, are required status checks on a branch that is
     up to date with the default branch;
   - where CodeQL's default setup is configured, a code-scanning rule blocks a pull request that adds an alert at
     warning level or above, or a security alert of any severity.
   The repository also deletes a pull request's head branch when it merges.
2. `AGENTS.md`'s Landing section says `integrate: pull-request`, so `/ship-plan` pushes the plan's branch and opens a
   pull request; it never pushes the default branch.
3. A required check reports on every pull request. A job whose workflow has `paths` or `branches` filters reports
   nothing on a pull request the filters skip, which then waits forever, so a required job runs unconditionally and
   decides inside the job what work to skip.
4. On a host that cannot require pull requests, such as a private repository on GitHub Free, the Landing section sets
   `protect: hook`, and `.githooks/pre-push` refuses any push to the default branch from a clone that runs the
   template's hooks. On GitLab, a protected branch with "Pipelines must succeed" plays the ruleset's part.
5. An approval requirement is added when a second maintainer exists.

## Options considered

- No protection, relying on people and agents to run the checks before pushing. Rejected: a direct push skips the gate
  that CI already runs.
- Require one approving review. Rejected while there is one maintainer: it cannot be met.
- Allow squash merges. Rejected: they collapse a plan's verified step commits and copy every commit's co-author trailers
  into the commit that lands.
- `integrate: direct`, pushing reviewed plans straight to the default branch. A Landing option for a project that
  chooses it, but not the default: it forgoes the server-side gate, and a project that uses it records why.
- Pull requests with required checks and zero approvals (chosen).

## Consequences

- Every change, a person's, an agent's or a bot's, reaches the default branch only through a green, up-to-date pull
  request.
- A branch behind the default branch takes it in before it merges.
- A CI job added later that should gate merges is added to the ruleset's required checks, and must report on every pull
  request; a job that runs only on a release or a schedule is never required, since it would block every merge.
- Changing the ruleset is an administrator's action in the host's settings, and the host records it.

## References

- `AGENTS.md` Landing section, `.githooks/pre-push`, `.github/workflows/ci.yml` or `.gitlab-ci.yml`
- `tools/Set-RepositoryBaseline.ps1` in the project template's repository, which writes the ruleset
- [ADR-0002](0002-commits-are-attributed-to-people-not-agents.md): commits are attributed to people, not agents.
- [ADR-0004](0004-trunk-based-development-on-the-default-branch.md): trunk-based development on the default branch.
- [ADR-0006](0006-a-person-merges-every-pull-request.md): a person merges every pull request.
