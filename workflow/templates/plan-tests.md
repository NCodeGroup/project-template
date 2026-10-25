---
description: Plan tests for risky or untested code
argument-hint: Module, feature or folder to cover
role: planner
append-format: true
worktree: create
---
Plan tests for:

{{INPUT}}

1. Map the public behavior of the area: entry points, inputs, outputs, side effects and error paths.
2. Find what existing tests cover and what they miss. Rank the gaps by risk: complex logic, past bugs (check `git log` for fixes in these files), data-loss or security paths, boundary values.
3. Choose the test level for each gap (unit or integration), using the project's existing framework, fixtures, helpers and naming.
4. For each test, state the scenario and the exact expected result, precisely enough to write without seeing this conversation.
5. Group the tests into steps of one test file each; each step's Done-when runs that file.
6. If a test would fail because the code is wrong, don't plan a fix — list it under Review checklist as a suspected bug.
