# Plan: Add multiply and divide to calc

## Goal
Extend the `calc` package with `multiply` and `divide`, and print their results from `main.py`. Division by zero must raise a clear `ValueError` instead of Python's `ZeroDivisionError`, so callers can handle bad input the same way as other validation errors.

## Context for the executor
- Build: none (pure Python, no dependencies)
- Test: `python -m unittest discover -s . -t .`
- Conventions: one function per operation in `calc/ops.py`, two positional parameters, no type hints; one `test_<name>` method per function in `tests/test_ops.py`, using `self.assertEqual` / `self.assertRaises`.
- Gotchas: run commands from the repository root so `calc` imports resolve.

## Decisions
- `divide(a, b)` returns `a / b` (true division, float result) — matches Python's default and needs no rounding rules.
- Zero divisor raises `ValueError("division by zero")` — one exception type for all input validation.

## Out of scope
- No changes to `add`.
- No command-line arguments or input parsing in `main.py`.
- No new files other than those listed in the steps.

## Steps

### [ ] 1. Add multiply with a test
- Files: `calc/ops.py` (edit), `tests/test_ops.py` (edit)
- Change: add `def multiply(a, b): return a * b` after `add` in `calc/ops.py`. In `tests/test_ops.py`, import `multiply` alongside `add` and add `test_multiply` asserting `multiply(4, 5) == 20` and `multiply(-2, 3) == -6`.
- Pattern: `add` and `test_add`.
- Done when: `python -m unittest tests.test_ops -v`

### [ ] 2. Add divide with zero-divisor validation
- Files: `calc/ops.py` (edit), `tests/test_ops.py` (edit)
- Change: add `divide(a, b)` after `multiply`. If `b == 0`, raise `ValueError("division by zero")`; otherwise return `a / b`. Add `test_divide` asserting `divide(10, 4) == 2.5`, and `test_divide_by_zero` asserting `divide(1, 0)` raises `ValueError`.
- Pattern: `multiply` and `test_multiply`.
- Done when: `python -m unittest tests.test_ops -v`

### [ ] 3. Print the new results from main.py
- Files: `main.py` (edit)
- Change: import `multiply` and `divide` alongside `add`; after the existing `print(add(2, 3))`, add `print(multiply(4, 5))` and `print(divide(10, 4))`.
- Done when: `$out = python main.py; if (($out -join ',') -eq '5,20,2.5') { exit 0 } else { exit 1 }`

## Review checklist
- `divide` raises `ValueError` (not `ZeroDivisionError`) for a zero divisor, including `0.0`.
- No other files changed; `add` is untouched.
