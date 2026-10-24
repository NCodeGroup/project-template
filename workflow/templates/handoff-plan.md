---
description: Turn the plan from this conversation into PLAN.md for the executor model
argument-hint: Optional extra constraints or notes
role: planner
append-format: true
---
Convert the plan we agreed on in this conversation into an executable handoff for a smaller, cheaper executor model.

Extra notes from me (may be empty): {{INPUT}}

Before writing:

1. Re-read every file the plan touches, so paths, symbols and signatures in `PLAN.md` are exact rather than remembered.
2. Find the build and test commands this repository really uses (package scripts, Makefile, CI workflow, README) and run them once to confirm they work.
3. Turn every open question or "either way" choice from our conversation into an entry under Decisions. If a choice needs my input, ask me before writing `PLAN.md`.
4. Split the work so no step needs judgment and each step has a check that proves it.
