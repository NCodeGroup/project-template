---
description: Find the root cause of a bug and plan a test-first fix
argument-hint: Symptom, error message and how to reproduce it
role: planner
append-format: true
worktree: create
---
Investigate this bug and plan the fix:

{{INPUT}}

Investigate before planning:

1. Reproduce it. Run the failing command or test and capture the exact error. If you can't reproduce it, report what you tried and stop.
2. Trace from the symptom to the cause. Read the code path, form hypotheses, and confirm or reject each one with evidence — a log line, a failing assertion, a small script — not intuition.
3. State the root cause in one or two sentences and explain why it produces the symptom. Keep it separate from the trigger.
4. Search the codebase for the same mistake elsewhere.
5. Plan the fix test-first. Step 1 adds a regression test that fails because of the root cause; its Done-when command succeeds while that test fails, for example `python -m pytest tests/test_x.py -k regression; if ($LASTEXITCODE) { exit 0 } else { exit 1 }`. The next step fixes the cause and its Done-when runs the same test normally. Further steps fix other occurrences.
6. Under Decisions, record the root cause and the evidence for it.
