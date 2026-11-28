# 0046. An adoption notes a repository name that doesn't fit NCodeGroup's rule

- **Status:** Accepted
- **Date:** 2026-11-28
- **Amends:** 0045

## Context

[ADR-0045](0045-new-project-names-a-repository-by-ncodegroups-rule-and-refuses-a-name-that-doesnt-fit.md) has
`New-Project.ps1 -CreateRemote` refuse a repository name that doesn't fit NCodeGroup/.github ADR-1001, and its
decision 5 says the template's `Adopt-Project.ps1`, which adopts a repository that already exists, checks nothing. An
adopted repository whose name doesn't follow ADR-1001 then keeps it until someone finds it by hand
([NCodeGroup/project-template#548](https://github.com/NCodeGroup/project-template/issues/548)).

## Decision

1. The template's `Adopt-Project.ps1` refuses nothing for a repository's name: the repository and its clone exist
   already, and a rename goes through an issue in that repository, as ADR-1001 says.
2. Where the repository's `origin` remote is on GitHub, the one place its name comes from, the adoption checks that
   name against the `stack` answer it works out, by ADR-0045's decision 1. For a name that doesn't fit, it prints a
   note with the name that fits, worked out as ADR-0045's decision 3 says, and what ADR-1001's Consequences say a
   rename touches, and goes on.
3. `New-Project.ps1`'s refusal and the adoption's note apply one rule, `Get-RepositoryNameMismatch` in the template's
   `tools/adopt/Adoption.psm1`, so the two never disagree on a name.

## Options considered

- Refuse the adoption, as `New-Project.ps1 -CreateRemote` refuses a new repository. Rejected: the repository already
  exists, so stopping the adoption fixes nothing.
- Rename the repository during the adoption. Rejected: a rename touches services outside the repository, which
  ADR-1001's checklist covers through an issue.
- Check nothing, as ADR-0045 decided. Rejected: a misnamed repository is found only by hand.
- Note the name that fits and what a rename touches, and go on (chosen).

## Consequences

- An adoption names a repository that doesn't follow ADR-1001, so its rename gets its issue instead of being found by
  hand; the adoption renames nothing.
- A repository without an `origin` remote gets no note.

## References

- [ADR-0045](0045-new-project-names-a-repository-by-ncodegroups-rule-and-refuses-a-name-that-doesnt-fit.md)
- [NCodeGroup/.github ADR-1001](https://github.com/NCodeGroup/.github/blob/main/docs/decisions/1001-a-dotnet-repository-is-named-for-its-root-namespace-and-every-other-repository-in-lowercase.md)
- The template's `Adopt-Project.ps1`, and `Get-RepositoryNameWarning` in its `tools/adopt/Adoption.psm1`
- [NCodeGroup/project-template#548](https://github.com/NCodeGroup/project-template/issues/548)
