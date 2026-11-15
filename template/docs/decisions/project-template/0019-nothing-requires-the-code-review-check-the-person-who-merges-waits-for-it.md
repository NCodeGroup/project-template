# 0019. Nothing requires the Code review check; the person who merges waits for it

- **Status:** Accepted
- **Date:** 2026-11-14

## Context

In a project that runs NCode Review, `.github/workflows/code-review.yml` reviews a pull request when it opens, is
reopened or is marked ready for review, and when someone with write access comments `/review`; a push in between starts
no review. The review posts a "Code review" check run on the commit it reviewed, a summary comment and its findings as
review threads. The default branch's ruleset requires the CI jobs and every conversation resolved
([ADR-0005](0005-the-default-branch-accepts-changes-only-through-pull-requests.md),
[ADR-0014](0014-every-pull-request-discussion-is-remediated-and-replied-to-before-it-merges.md)), but not the review:
`tools/Set-RepositoryBaseline.ps1 -RequireChecks auto` leaves out "Code review" and the `review` job, which runs on
`pull_request_target`. While the review runs, GitHub shows "Able to merge, some non-required checks are still in
progress", and conversation resolution covers only the threads that exist, so a merge before the review posts its
findings skips them.

## Decision

The review is advice: no ruleset requires the "Code review" check or the `review` job, and the person who merges waits
for the review.

1. `-RequireChecks auto` leaves out "Code review" and the `review` job, and a person who names the required checks
   leaves them out too.
2. When the review runs on a pull request, the person who merges waits for its "Code review" check to complete and for
   its threads to be remediated and replied to, as
   [ADR-0014](0014-every-pull-request-discussion-is-remediated-and-replied-to-before-it-merges.md) says, before merging
   or turning on auto-merge.
3. When no review comes, because the workflow skips the pull request (a `skip-review` label, a fork, a pull request a
   bot opened) or the run fails, the person decides: re-run the job, comment `/review`, or merge without it.
4. `/run-issues` and `/run-feedback` wait for NCode Review's review of the commit they pushed before they recommend the
   merge.
