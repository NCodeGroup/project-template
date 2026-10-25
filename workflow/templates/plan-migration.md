---
description: Plan a dependency, framework or API upgrade
argument-hint: What to upgrade, from which version to which
role: planner
append-format: true
worktree: create
---
Plan this migration:

{{INPUT}}

1. Read the official upgrade guide and changelog between the two versions (fetch them if you can). List every breaking change.
2. Search the codebase for each breaking change and record where it applies, with file paths.
3. Order the work: tooling and configuration first, then mechanical API renames, then behavior changes, then removal of compatibility shims.
4. Keep the project building after every step. Where one step can't, say so and make that step as small as possible.
5. Each step names the exact old and new API forms, so the executor can apply them mechanically.
6. Done-when commands build and test what each step touched; the final step runs the full suite.
