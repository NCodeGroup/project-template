---
description: Assess an area for security weaknesses and plan hardening
argument-hint: Component, endpoint or data flow to harden
role: planner
append-format: true
---
Assess and plan security hardening for:

{{INPUT}}

1. Map the trust boundaries: where untrusted input enters, where secrets live, and who can call what.
2. Check for the relevant weakness classes: injection, path traversal, authentication and authorization gaps, secrets in code or logs, unsafe deserialization, missing input validation, vulnerable dependencies.
3. Rate each finding by impact and likelihood, with file and line as evidence. Drop theoretical issues that have no realistic path.
4. Plan fixes for the findings worth fixing, highest risk first. Each fix includes a test that shows the weakness is closed.
5. Keep real secrets and tokens out of `PLAN.md`, and keep test payloads minimal.
