---
description: Measure a performance problem and plan verified fixes
argument-hint: What is slow, how slow, and the target
role: planner
append-format: true
---
Investigate and plan performance work for:

{{INPUT}}

1. Measure before theorizing. Find or write a repeatable benchmark or timing command and record the baseline numbers.
2. Profile or instrument to find where the time or memory goes. Name the top costs with evidence.
3. For each candidate fix, estimate the gain and the risk. Choose fixes that address measured costs; skip micro-optimizations.
4. Step 1 adds the benchmark or timing script to the repository. Each optimization step's Done-when runs the tests and the benchmark, and fails if the result is worse than a threshold you set from the baseline.
5. Under Decisions, record the baseline, the target, and why each fix was chosen.
