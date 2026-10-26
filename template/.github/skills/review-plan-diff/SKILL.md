---
name: review-plan-diff
description: "Review the executor's work against PLAN.md and queue fix steps"
---
Review the changes made while executing `PLAN.md`.

Compare against (may be empty): the request given after the command name
If empty, use the parent of the first commit whose message starts with "Plan step" or "Re-plan step", or `main`.

1. Read `PLAN.md`: Goal, Decisions, Out of scope, Steps and Review checklist.
2. Read the full diff (`git diff <base>` including uncommitted changes) and the changed files in full where context matters.
3. Check every step was done as written: the right files, the right behavior, and no shortcuts such as skipped or weakened tests, swallowed errors, hard-coded values or leftover TODOs. Flag every deviation from the step text as at least should-fix even when its checks pass — creating something the step said already exists, touching files the step doesn't list, or changing an interface — because a deviation means the executor improvised instead of escalating.
4. Check what the Done-when commands can't: edge cases, error handling, security, performance, API compatibility, and each Review checklist item.
5. Run the test suite and the checks listed under Context for the executor.
6. Report findings as a table: severity (blocker, should-fix, nit), file and line, problem, fix.
7. For every blocker and should-fix, append a new step to the end of the Steps section of `PLAN.md`, numbered in sequence and in the same format as the existing steps (`### [ ] N. …` with Files, Change and a Done-when command), so the executor model can fix it. Change nothing else in the repository.
8. When the review found no blocker or should-fix, end by saying the plan is done: once its commits are pushed or merged, finish-plan retires it and deletes its branch.
