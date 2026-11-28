# 0045. New-Project.ps1 names a repository by NCodeGroup's rule and refuses a name that doesn't fit

- **Status:** Accepted
- **Date:** 2026-11-27
- **Refines:** [NCodeGroup/.github ADR-1001](https://github.com/NCodeGroup/.github/blob/main/docs/decisions/1001-a-dotnet-repository-is-named-for-its-root-namespace-and-every-other-repository-in-lowercase.md)

## Context

NCodeGroup/.github ADR-1001 names a repository whose main deliverable is .NET code for its root namespace, in the
namespace's casing and without the leading `NCode.`, so `NCode.Buffers` is `Buffers`, and every other repository in
lowercase kebab case, such as `project-template`. `.github` keeps the name GitHub requires, and the name decides the
clone's folder.

`New-Project.ps1 -CreateRemote`, in NCodeGroup/project-template, creates a project's GitHub repository with
`gh repo create`, named after the destination folder. The template serves only NCodeGroup's repositories
([ADR-0040](0040-the-template-serves-ncodegroups-repositories-on-github-only.md)), so the script that creates a
repository can apply the organization's rule. A repository's name is costly to change once it exists: a rename that
changes more than the case relies on GitHub's redirect and moves the clone folder, the nuget.org trusted publishing
policy and the links to a GitHub Pages site (ADR-1001).

## Decision

1. Before it runs `gh repo create`, `New-Project.ps1 -CreateRemote` checks the repository's name, the destination
   folder's name, against the project's `stack` answer:
   - `stack: dotnet`: PascalCase segments joined by `.`, each starting with a capital letter and holding only letters
     and digits, with no leading `NCode.`, such as `Buffers` or `Collections.Providers`;
   - every other stack: lowercase kebab case, words of lowercase letters and digits joined by single hyphens, such as
     `qso-viewer`;
   - `.github` fits any stack.
2. The `dotnet` answer stands for ADR-1001's .NET repository: the template gives that stack a solution at the root
   that CI builds, tests and ships. A repository that only describes, deploys or supports .NET code answers another
   stack.
3. It refuses a name that doesn't fit and creates nothing: no repository on GitHub, no first commit and no files in
   the folder. Its error states the rule and the name that fits, worked out from the folder's name: a leading `NCode.`
   dropped, then, for .NET, each word's first letter capitalized, so `buffers` is `Buffers`, and otherwise words split
   at capitals and punctuation, joined by hyphens and lowercased, so `QsoViewer` is `qso-viewer`.
4. When `-Data` answers `stack`, it checks before Copier runs, so nothing is asked. Otherwise it checks once Copier has
   recorded the answer, and deletes the files Copier wrote, so the folder can be named again, also where only its
   case changes on a file system that ignores case.
5. Without `-CreateRemote` the script creates no repository and checks nothing. `Adopt-Project.ps1` adopts a
   repository that already exists, and checks nothing either.

## Options considered

- Warn and create the repository anyway. Rejected: the repository exists by the time the warning shows, and fixing
  its name is a rename, with ADR-1001's checklist.
- Name the repository from the `project_name` answer. Rejected: `project_name` is a heading, such as
  `QSO Log Viewer`, not a namespace, and the folder would differ from the repository's name, which decides the folder.
- Create the repository under the name that fits, whatever the folder is called. Rejected: the clone's folder would
  keep the other name, and a script that finds a sibling clone looks for the repository's name exactly.
- Refuse, and name the name that fits (chosen).

## Consequences

- A repository `New-Project.ps1` creates follows ADR-1001 from its first push, and its clone's folder matches its
  name.
- A run that leaves `stack` to Copier's questions asks them before it refuses, and the next run asks them again;
  answering `stack` in `-Data` refuses before any question.
- A .NET repository whose name the pattern doesn't cover, such as one whose segment starts with a digit, isn't
  created by the script; `gh repo create` creates it by hand.
- Renaming an existing repository is outside the script: each one that doesn't follow the rule has its own issue.

## References

- [NCodeGroup/.github ADR-1001](https://github.com/NCodeGroup/.github/blob/main/docs/decisions/1001-a-dotnet-repository-is-named-for-its-root-namespace-and-every-other-repository-in-lowercase.md)
- [ADR-0040](0040-the-template-serves-ncodegroups-repositories-on-github-only.md)
- NCodeGroup/project-template's `New-Project.ps1`, and `Get-RepositoryNameRefusal` in its `tools/adopt/Adoption.psm1`
- [NCodeGroup/project-template#546](https://github.com/NCodeGroup/project-template/issues/546)
