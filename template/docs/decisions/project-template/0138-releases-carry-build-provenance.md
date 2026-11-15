# 0138. Releases carry build provenance

- **Status:** Accepted
- **Date:** 2026-11-14
- **Amends:** 0135

## Context

ADR-0135 publishes packages to nuget.org from a GitHub release. A consumer has no way to check that a package came from
the project's workflow and commit, and the release carries no packages or provenance to compare against.

## Decision

`release-provenance.yml` runs after a successful `Publish packages` run, attests the packages with
`actions/attest-build-provenance`, and attaches the packages and `<tag>.intoto.jsonl` to the GitHub release.

- Consumers verify a package with `gh attestation verify <package>.nupkg --repo <owner>/<repo>`.

## Options considered

- cosign keyless signing. Rejected: a second tool for the same Sigstore trust.
- The SLSA generic generator. Rejected: it is a reusable workflow referenced by tag, not by SHA, against ADR-0008.
- Adding the steps to `publish.yml`. Rejected: it is project-owned, so updates would never reach projects, and its
  publish job must hold only `id-token: write`.
- A template-owned workflow that runs after `Publish packages` (chosen).

## Consequences

- The assets stay on the release.
- A rerun of Publish packages re-attests and replaces the assets (`--clobber`).
- A project with its own publish workflow gets a workflow that never triggers.
- `workflow_run` runs the default branch's copy of the file, so the first release after the workflow lands on the
  default branch is the first one it covers.

## References

- [ADR-0135](0135-packages-are-published-from-a-github-release-through-trusted-publishing.md): packages are published
  from a GitHub release through trusted publishing.
- [ADR-0137](0137-the-release-workflow-starts-package-publishing.md): the Tag and publish release workflow starts
  package publishing.
- [ADR-0020](0020-github-projects-are-scored-by-openssf-scorecard.md): GitHub projects are scored by OpenSSF Scorecard.
- `.github/workflows/release-provenance.yml`
