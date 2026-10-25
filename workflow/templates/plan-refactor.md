---
description: Plan a behavior-preserving refactor in small, always-green steps
argument-hint: What to restructure and the target shape
role: planner
append-format: true
worktree: create
---
Plan this refactor so that behavior does not change:

{{INPUT}}

1. Describe the current structure, the target structure, and the problem the refactor solves.
2. Find every caller and dependent of the code being moved or renamed — search the whole repository, including tests, scripts, configuration and reflection-style string references.
3. Check test coverage of the affected behavior. If it is thin, the first steps add characterization tests that pin the current behavior.
4. Sequence the change so the build and tests stay green after every step: add the new structure, move callers over in small groups, then delete the old structure.
5. Every step's Done-when runs the full relevant test suite, not only new tests.
6. Under Out of scope, forbid behavior changes, renames beyond the plan, and formatting-only churn.
