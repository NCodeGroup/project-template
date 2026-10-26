---
name: plan-migration
description: "Plan a dependency, framework or API upgrade"
---
Plan this migration:

the request given after the command name

1. Read the official upgrade guide and changelog between the two versions (fetch them if you can). List every breaking change.
2. Search the codebase for each breaking change and record where it applies, with file paths.
3. Order the work: tooling and configuration first, then mechanical API renames, then behavior changes, then removal of compatibility shims.
4. Keep the project building after every step. Where one step can't, say so and make that step as small as possible.
5. Each step names the exact old and new API forms, so the executor can apply them mechanically.
6. Done-when commands build and test what each step touched; the final step runs the full suite.

## Output: PLAN.md for the executor model

Write the result to `PLAN.md` in the repository root. Change no other file.

`PLAN.md` is a local working file: never commit or push it, and never stage it. If `git check-ignore -q PLAN.md` exits non-zero, append the line `PLAN.md` to `info/exclude` in the folder that `git rev-parse --path-format=absolute --git-common-dir` prints, so no `git add -A` can pick it up.

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
