A story is ready to plan when it meets the Definition of Ready, as ADR-0042 in `docs/decisions/project-template/` records:

1. Its outcome is stated: what changes for its users or the system.
2. What is not in it is stated.
3. Its acceptance can be checked: a test, a command or a result anyone can see says when it is done.
4. Every issue it is blocked by is closed, or will be by the time it is planned, because a story ahead of it in the same run lands it first.
5. Every decision it needs is recorded in `docs/decisions/`, or is a story of its own that blocks it.
6. It fits one plan: one worktree, one pull request and at most one release.

A bug's outcome is the behavior it should have, and its acceptance the reproduction that then passes. A fact is missing only when the issue's text leaves it unclear: a small, plain issue needs no section for each.
