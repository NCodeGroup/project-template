---
description: Plan a new feature for the executor model to build
argument-hint: Feature to build and how it should behave
role: planner
append-format: true
worktree: create
---
Plan this feature for a smaller model to implement:

{{INPUT}}

Research first, then design:

1. Read the code paths the feature touches, end to end. Find the closest existing feature and use it as the template.
2. List the inputs, outputs, error cases and edge cases. Check how similar code handles validation, errors, logging and configuration.
3. Choose the design. Where real alternatives exist, pick one and record why under Decisions.
4. Identify what could break: callers of changed functions, stored or serialized formats, public APIs, migrations, performance.
5. Decide how each part is verified — unit tests first, then an integration or end-to-end check if the project has them.
6. If a requirement is ambiguous in a way that changes the design, ask me before writing the plan.
