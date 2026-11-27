# 0042. A fork's pull request merges without a bypass

- **Status:** Accepted
- **Date:** 2026-11-27
- **Amends:** 0005, 0020, 0022 and 0030

## Context

NCodeGroup/NCode.Disposables#95, a pull request from a fork, sat `BLOCKED` with passing CI, a maintainer's approval and
every thread resolved. It merged once through a temporary `pull_request`-mode bypass for repository admins, removed right
after. Two causes kept it from merging under the baseline ruleset.

1. The code-scanning rule waits for CodeQL, and CodeQL never analyzes a fork's pull request.
   - CodeQL's default setup runs on pull requests "excluding pull requests from forks" (GitHub Docs, "Code scanning
     setup types", read 2026-11-27).
   - The rule blocks a pull request while "a required tool's analysis is still in progress" or "is not configured",
     whatever the thresholds ("Available rules for rulesets", read 2026-11-27), so the rule waits forever.
   - Code scanning "always allows the uploading of results when the pull_request event triggers the action run"
     ("Resource not accessible", read 2026-11-27), so a workflow's results meet the rule for a fork's pull request.
   - GitHub refuses a CodeQL workflow's results while default setup is on, so the two can't run side by side.
2. `strict_required_status_checks_policy` makes a pull request behind `main` update its branch before it merges.
   GitHub counts the merge that "Update branch" makes as the maintainer's push. `require_last_push_approval` then needs
   another writer's approval, which a repository with one writer doesn't have, and NCode Review's approver skips forks
   ([ADR-0022](0022-ncode-reviews-approval-gates-the-merge.md) decision 4).

## Decision

1. Every GitHub project gets a project-owned `.github/workflows/codeql.yml`.
   - It runs on every pull request, on a push to `main`, in a merge queue, weekly and on request, with a read-only token
     except `security-events: write` in the job that uploads the results.
   - A `CodeQL languages` job picks the languages at run time: `actions` always, and `csharp`,
     `javascript-typescript` and `python` where `git ls-files` lists a file in that language. A new project has no
     source file yet, and CodeQL fails a language with no code; the four are the languages of the template's stacks that
     support `build-mode: none`.
   - It runs the `security-extended` suite, the one the baseline gave default setup
     ([ADR-0030](0030-the-code-scanning-rule-is-added-only-where-codeql-analyzes-a-language.md)).
2. `tools/Set-RepositoryBaseline.ps1` counts a workflow as CodeQL's setup when its top-level `on:` names `pull_request`
   and a line that isn't a comment uses `github/codeql-action/analyze@`. A CodeQL workflow that runs only on push
   doesn't count, so default setup keeps deciding there. Where a workflow counts, which amends ADR-0030 decision 1 for
   such repositories:
   - a ruleset the baseline creates or rewrites gets the code-scanning rule whatever the default setup says, with no
     suite switch, and the baseline prints neither the suite notice nor ADR-0030's no-language warning;
   - the baseline turns the default setup off before it writes the ruleset, so GitHub accepts the workflow's results; a
     refusal fails the repository with nothing changed, as a refused suite switch does;
   - on a run that leaves the ruleset alone, the turn-off is reported as set, already set, would set or not available,
     and never fails the run;
   - the line names the languages default setup analyzed, so the owner can add one the workflow lacks;
   - `-RequireChecks auto` leaves out `CodeQL languages`, as it leaves out `Analyze (*)`: the code-scanning rule covers
     it.
3. A fork's author brings its branch up to date, and the maintainer approves it, as ADR-0022 decision 4 says, and never
   updates it. The contributor's update is their push, so the maintainer's approval, which counts because the
   maintainer isn't the author and can write, meets approval of the last push. `/address-feedback` stops on a fork's
   branch that is behind and says so.
4. `strict_required_status_checks_policy` and `require_last_push_approval` stay as they are.

## Options considered

- Drop the code-scanning rule, or set its thresholds to `none`. Rejected: the rule also blocks while a required tool's
  analysis is in progress or not configured, whatever the thresholds, and dropping it loses the SAST gate on every pull
  request; ADR-0030 never removes a kept rule.
- Turn strict checks off in a repository with one writer. Rejected: `/run-issues` lands plans side by side, and two pull
  requests that each pass could break `main` together.
- Turn approval of the last push off. Rejected: a maintainer could push to a bot's or a fork's pull request and approve
  it themselves, past NCode Review's gate.
- A `pull_request`-mode bypass for repository admins. Rejected: the issue rules it out; a bypass is the workaround this
  decision replaces.
- Have the approver app approve a fork's pull request after `/review`. Rejected here: NCodeGroup/code-review#251
  decides the approver's handling of forks, not this repository.
- A project-owned CodeQL workflow, and a fork's author who updates its own branch (chosen).

## Consequences

- Each pull request costs Actions minutes for CodeQL.
- A new project's baseline run turns default setup off and adds the rule right after the first push, so ADR-0030's
  no-language case doesn't arise with the workflow.
- An existing project's Analyze jobs fail between its template update and the baseline run, because GitHub refuses the
  workflow's results while default setup is on. The update's note says to run the baseline once the update merges.
- A language default setup analyzed beyond the four goes unanalyzed until the project adds it to the detect step, which
  the baseline's line names.
- An organization security configuration that enforces default setup makes the baseline fail or report until an owner
  sets code scanning to "Enabled with advanced setup allowed" or leaves it out of the configuration.
- A contributor new to GitHub waits for a maintainer's approval before CodeQL runs too
  ([ADR-0039](0039-fork-pull-request-workflows-run-for-established-contributors.md)).
- A fork's pull request whose author doesn't update it can't merge while it is behind. The maintainer closes it or opens
  the change again from a branch of their own after reading every file.

## References

- `.github/workflows/codeql.yml`, `tools/Set-RepositoryBaseline.ps1` and `tests/Test-RepositoryBaseline.ps1`
- GitHub Docs, [Code scanning setup types](https://docs.github.com/en/code-security/concepts/code-scanning/setup-types),
  [Available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
  and
  [Resource not accessible](https://docs.github.com/en/code-security/reference/code-scanning/troubleshoot-analysis-errors/resource-not-accessible)
- [ADR-0022](0022-ncode-reviews-approval-gates-the-merge.md),
  [ADR-0030](0030-the-code-scanning-rule-is-added-only-where-codeql-analyzes-a-language.md),
  [ADR-0036](0036-a-required-approval-is-met-by-ncode-reviews-approver-app.md) and
  [ADR-0039](0039-fork-pull-request-workflows-run-for-established-contributors.md)
- NCodeGroup/project-template#537, NCodeGroup/NCode.Disposables#95
