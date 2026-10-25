---
description: "Find the root cause of a bug and plan a test-first fix"
argument-hint: "Symptom, error message and how to reproduce it"
agent: agent
model: "Claude Opus 5.5 (copilot)"
---
Investigate this bug and plan the fix:

${input:details:Symptom, error message and how to reproduce it}

Investigate before planning:

1. Reproduce it. Run the failing command or test and capture the exact error. If you can't reproduce it, report what you tried and stop.
2. Trace from the symptom to the cause. Read the code path, form hypotheses, and confirm or reject each one with evidence — a log line, a failing assertion, a small script — not intuition.
3. State the root cause in one or two sentences and explain why it produces the symptom. Keep it separate from the trigger.
4. Search the codebase for the same mistake elsewhere.
5. Plan the fix test-first. Step 1 adds a regression test that fails because of the root cause; its Done-when command succeeds while that test fails, for example `python -m pytest tests/test_x.py -k regression; if ($LASTEXITCODE) { exit 0 } else { exit 1 }`. The next step fixes the cause and its Done-when runs the same test normally. Further steps fix other occurrences.
6. Under Decisions, record the root cause and the evidence for it.

## Output: PLAN.md for the executor model

Write the result to `PLAN.md` in the repository root. Change no other file.

A smaller, cheaper model — a local model or a lower-cost Copilot model — will execute this plan one step at a time. It sees only `PLAN.md` and the files it opens — not this conversation, not your research. It follows instructions literally, loses track in long or vague steps, and cannot make design decisions. Write for that reader:

- Resolve every design decision here, in the plan. A step must never say "decide", "choose", "consider" or "as appropriate".
- Give each step 1–3 files. Name exact paths, functions, classes, signatures and data shapes.
- Point at existing code to imitate ("follow the pattern of `parseLog()` in `src/log.ts`") instead of describing a style.
- Show a short code sketch only where the shape is not obvious (a signature, a type, a tricky expression), never a full implementation.
- Order steps so each one builds and passes its check on its own. Put tests before or with the code they cover.
- Every step ends with one PowerShell command, run from the repository root, that exits 0 only when the step is done and finishes in under two minutes. Prefer a check that fails until the step is done — run the step's new test by name, or assert the new output — over a suite that already passes.
- Keep each step under about 25 lines. Split anything bigger.
- Expect escalations: when a step needs a decision the plan didn't make, the executor stops, marks it `[?]` with an `- Escalation:` note, and the step comes back to you for re-planning. Every escalation costs a round trip, so settle decisions now.

Use exactly this structure; the step runner parses the `### [ ] N.` headings and the `- Done when:` lines:

```markdown
# Plan: <title, 2-10 words>

## Goal
<What changes for the user or system, and why. 2-4 sentences.>

## Context for the executor
- Build: `<command>`
- Test: `<command>`
- Conventions: <naming, error handling, logging, formatting rules the code must follow>
- Gotchas: <anything surprising about this codebase that a newcomer would get wrong>

## Decisions
- <Each design decision made, with a one-line reason.>

## Out of scope
- <Changes the executor must not make, even if they look helpful.>

## Steps

### [ ] 1. <imperative title>
- Files: `<path>` (edit), `<path>` (new)
- Change: <exactly what to add, change or remove; reference symbols by name>
- Pattern: <existing code to imitate, if any>
- Done when: `<single PowerShell command that exits 0 on success>`

### [ ] 2. <imperative title>
...

## Review checklist
- <What the reviewer must confirm beyond the Done-when checks: behavior, edge cases, compatibility, performance.>
```

After writing `PLAN.md`, reply with the step list (one line per step) and any open risks. Do not start implementing.
