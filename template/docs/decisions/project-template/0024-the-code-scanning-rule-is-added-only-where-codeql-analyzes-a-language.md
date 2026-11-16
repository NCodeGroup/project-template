# 0024. The code-scanning rule is added only where CodeQL analyzes a language

- **Status:** Accepted
- **Date:** 2026-11-16
- **Amends:** 0005

## Context

`tools/Set-RepositoryBaseline.ps1` in the project template gives the "Protect main" ruleset a code-scanning rule that
requires CodeQL's results ([ADR-0005](0005-the-default-branch-accepts-changes-only-through-pull-requests.md)). Such a
rule blocks a pull request while a required tool's analysis is still in progress, or while the tool is not configured
for the repository (GitHub Docs, "Available rules for rulesets", read 2026-11-16).

GitHub's REST API reports CodeQL's default setup as a `state` and the `languages` it analyzes ("Get a code scanning
default setup configuration", read 2026-11-16), and the two can disagree. On 2026-11-16 NCodeGroup/docs and
NCodeGroup/brand answered `"state": "configured"` with `"languages": []`, no `schedule` and no `updated_at`: their
organization's enforced security configuration had turned default setup on, and no CodeQL setup had run on either
since its creation. CodeQL analyzed no pull request, so every pull request stayed blocked with every check green.
GitHub's documentation describes an enabled setup that runs nothing too: when its analyses fail for every language,
default setup "will still be enabled, but it will not run any scans" until a language is added or the setup is
reconfigured ("Configuring default setup for code scanning", read 2026-11-16).

The baseline also switches a configured setup to the extended query suite, with an update that sends `query_suite`
alone. The REST reference makes every field of that update optional and describes `languages` only as "CodeQL
languages to be analyzed" ("Update a code scanning default setup configuration", read 2026-11-16). An update that names
no language sets none up: the two repositories kept `"languages": []` after the baseline switched them.

## Decision

CodeQL's default setup counts as configured for the code-scanning rule only when it is configured and its answer lists
at least one language.

1. Where the setup is configured with no language, or its answer lists none, the baseline gives "Protect main" no
   code-scanning rule, leaves the query suite as it is, and says why. A later run with `-RequireChecks` adds the rule
   once the repository's settings give CodeQL a language.
2. A "Protect main" ruleset that already has a code-scanning rule keeps it: an update never removes it. Where the setup
   analyzes no language, the baseline warns that every pull request stays blocked and names the fix: set up CodeQL's
   languages in the repository's settings, or remove the rule.
3. The switch to the extended suite runs only for a setup that analyzes a language, and names no language itself.

## Options considered

- Read `state` alone. Rejected: a configured setup that analyzes nothing blocks every merge for good.
- Name the languages in the baseline's update. Rejected: the script would guess which of the repository's languages
  CodeQL supports, and the REST reference does not say whether naming them stops GitHub from adding one later.
- Read the setup back after the switch. Rejected: an update can start a CodeQL setup run, which it answers with HTTP 202
  and the run's id, and the stored setup follows the run's end (on 2026-11-16 NCodeGroup/docs's `updated_at` came 2
  seconds after its 45-second setup run finished), so a read right after the switch can show the setup as it was.
- Remove a kept rule where the setup analyzes no language. Rejected: the baseline never loosens a ruleset, and the
  branch would have no code scanning once the languages are set up.
- Leave the rule out, and warn where one is kept (chosen).

## Consequences

- A repository whose setup analyzes no language gets no code-scanning rule until its owner sets up the languages and
  reruns the baseline with `-RequireChecks`.
- A repository that already has the rule stays blocked until its owner acts on the warning; `-All -WhatIf` prints the
  warning for each such repository.
- A setup that loses its languages after the rule is added blocks merges too; the next run of the baseline warns about
  it.
- The baseline checks only its own "Protect main" ruleset: a ruleset of the owner's that requires CodeQL's results gets
  no warning.

## References

- `tools/Set-RepositoryBaseline.ps1` and `tests/Test-RepositoryBaseline.ps1` in the project template's repository
- [Get and update a code scanning default setup configuration](https://docs.github.com/en/rest/code-scanning/code-scanning#update-a-code-scanning-default-setup-configuration),
  GitHub's REST API, read 2026-11-16
- [Require code scanning results](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets#require-code-scanning-results),
  GitHub Docs, read 2026-11-16
- [Configuring default setup for code scanning](https://docs.github.com/en/code-security/code-scanning/enabling-code-scanning/configuring-default-setup-for-code-scanning),
  GitHub Docs, read 2026-11-16
- [ADR-0005](0005-the-default-branch-accepts-changes-only-through-pull-requests.md): the default branch accepts changes
  only through pull requests.
