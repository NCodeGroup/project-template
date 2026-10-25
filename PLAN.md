# Plan: Keep project ignore rules during copier update

## Goal
`.template\Update-Project.ps1` fails on Windows with `FileNotFoundError: [WinError 206] The filename or extension is too long` when a project's own `.gitignore` ignores a large folder that the template's `.gitignore` doesn't, such as `node_modules/` in a .NET project with a frontend. The update then resets the project, so it can never be updated. After this fix, the update keeps the project's ignore rules in force while Copier runs, through `.git/info/exclude`, and succeeds. A new focused test script proves it, and CI runs that script.

## Context for the executor
- Build: none (PowerShell scripts and Copier template files).
- Test (this fix): `.\Test-UpdateIgnoredFiles.ps1`, about 40 seconds; its last line is `Update ignored-files tests: PASSED` or `Update ignored-files tests: FAILED (<n>)`.
- Test (everything, for the reviewer only; about 4 minutes): `.\Test-Template.ps1 -SkipDotnetBuild`, `.\Test-Adoption.ps1 -SkipDotnetBuild`, `.\Test-CommitAttribution.ps1`.
- Needs on PATH: `git` (2.31 or later), `copier` (or `uvx`), PowerShell 7.
- Conventions: imitate the root test scripts. `Check`, `Invoke-Git` and `Invoke-Copier` are copied verbatim from `Test-Template.ps1` (lines 28-46). Each check prints `PASS  <name>` or `FAIL  <name>  <detail>`, and the script ends like `Test-Adoption.ps1` (lines 308-311): an empty line, then the FAILED line with `exit 1`, or the PASSED line with `exit 0`. Read and write files with `[IO.File]` and absolute paths. Files are UTF-8 without BOM, with LF line endings.
- Gotchas:
  - `git rev-parse --git-path info/exclude` prints a *relative* path (`.git/info/exclude`), and `[IO.File]` resolves relative paths against the process directory, not PowerShell's location. Always use `git rev-parse --path-format=absolute --git-path info/exclude`. The `info` folder may not exist yet: create it with `New-Item -ItemType Directory -Force`.
  - The test only reproduces when each fake package also holds a file that no ignore rule matches (`package.json`). If every file in `node_modules` is ignored, Git reports the whole folder as one ignored entry and nothing overflows.
  - `Update-Project.ps1` throws on failure (`$ErrorActionPreference = 'Stop'`), so a caller must wrap the call in `try`/`catch`. Copier's traceback reaches the caller's `2>&1`, but only output already handed on survives the throw: `$x = try { ... | Out-String } catch { }` loses all of it, because `Out-String` never finishes. Collect lines as they stream with `ForEach-Object` into a list instead.
  - The test snapshots the working tree into `%TEMP%` and tags it `v0.1.0`, so it tests uncommitted edits to `template\.template\Update-Project.ps1` directly. The project updates from v0.1.0 to v0.1.0, and that still runs `copier update`, the failing path.

## Decisions
- Root cause: `copier update` renders the new template straight into the project, which overwrites the merged file `.gitignore` with the template's version. Then, in `_apply_update` (copier 9.19.1, `copier/_main.py`), it runs `git status --ignored --porcelain` and adds one `--exclude=<path>` per ignored path to a single `git apply` command. With the project's own rules gone, a folder only the project ignored becomes untracked, and the template's rules (`bin/`, `obj/`, `*.user`, …) match paths inside it one by one. The resulting command line passes Windows' 32,767-character limit, and `CreateProcess` fails with WinError 206.
- Evidence: in `C:\GitHub\NCode\Identity` (stack `dotnet`, pnpm frontend), the template's rules alone produce 1,089 ignored entries (about 141,000 characters of excludes), versus 276 entries (about 17,000 characters) under the project's rules, and about 1.5 million files under `src/frontend/node_modules` stop being ignored. That accounted for the "10k+ changes" VS Code showed mid-update. A minimal repro reproduced the exact error: a dotnet project plus `node_modules/` in its `.gitignore`, and 700 packages, each with `package.json` and `bin/cli.js` (about 46,000 characters of excludes). Appending the project's `.gitignore` to `.git/info/exclude` before the update made the same run succeed.
- Fix: around the `copier update` call only, append the project's root `.gitignore` to `info/exclude`, and restore `info/exclude` byte for byte in a `finally`. Git always reads `info/exclude`, so Copier's render can't remove those rules, and nothing in the working tree changes. `copier recopy` needs no fix: the script passes it `--exclude` for every merged file, so it never overwrites `.gitignore`, and recopy runs no `git apply`.
- Only the root `.gitignore` is copied: the template renders no nested `.gitignore`, so nested ones are never overwritten. The script already assumes the project is the repository root (`Get-Change` compares paths with `.copier-answers.yml`), so root-relative patterns stay correct in `info/exclude`.
- The new rules come after the existing `info/exclude` content, separated by a newline, so a file without a trailing newline doesn't merge two patterns.
- The regression test is a separate script, `Test-UpdateIgnoredFiles.ps1`, because a step's check must finish in under two minutes and `Test-Template.ps1 -SkipDotnetBuild` takes about 200 seconds. `Test-Adoption.ps1` and `Test-CommitAttribution.ps1` set the precedent for focused root test scripts, and CI runs all of them.
- The test checks its own premise: under the template's `.gitignore` alone, the ignored paths must add up to more than 32,767 characters of `--exclude=` arguments. Without this check, a future template that ignores `node_modules/` for .NET would make the test pass without testing anything.
- The fix reaches a project once a template version that contains it is tagged: the project's old script hands the update over to the target version's script before Copier runs, so `NCode.Identity` (v0.3.0) is fixed by updating to the next tag. Tagging is the maintainer's job after review, not a plan step.
- Re-plan step 1: the test collects the update's output line by line, because `try { ... | Out-String } catch` discarded Copier's `WinError 206` traceback when the script threw, and the first run could not see the root cause in its output.
- `--path-format=absolute` needs Git 2.31 (March 2021); accepted, because Copier itself already warns below Git 2.24 and current Git for Windows is 2.56.

## Out of scope
- Copier's "Make sure Git >= 2.24 is installed to improve updates." warning: Git 2.56 rejects `--inter-hunk-context=-1`, Copier falls back to `0`, and that's harmless.
- Upstream Copier changes (for example, excluding only ignored paths that appear in the patch). A project with very many ignored folders under its *own* rules could still overflow (Identity sits at about 17,000 of 32,767 characters); that needs a Copier fix, not this plan.
- Adding `node_modules/` or other rules to `template/.gitignore.jinja`.
- `Adopt-Project.ps1`, `New-Project.ps1`, the root `Update-Project.ps1` wrapper, and `Test-Template.ps1`: none runs `copier update` themselves or needs a change.
- Tagging a release, pushing, or updating `NCode.Identity`.

## Steps

### [ ] 1. Add the regression test Test-UpdateIgnoredFiles.ps1
- Files: `Test-UpdateIgnoredFiles.ps1` (new)
- Change: a self-contained test script, in this order:
  1. Comment-based help like `Test-Adoption.ps1` lines 1-23. SYNOPSIS: "Test that a project's update succeeds when the project's own .gitignore ignores a large folder that the template's doesn't." DESCRIPTION explains the WinError 206 overflow in two sentences. `.PARAMETER Work`: the scratch folder, default `%TEMP%\project-template-update-ignored-test`. `.PARAMETER Packages`: fake packages in `node_modules`, default 700.
  2. `[CmdletBinding()] param([string]$Work = (Join-Path $env:TEMP 'project-template-update-ignored-test'), [int]$Packages = 700)`, then `$ErrorActionPreference = 'Stop'`, `$failures`, and `Check`, `Invoke-Copier` and `Invoke-Git` copied verbatim from `Test-Template.ps1` lines 26-36 and 43-46.
  3. Snapshot: copy `Test-Template.ps1` lines 48-57 verbatim (`$tpl = Join-Path $Work 'template-repo'`, tagged `v0.1.0`).
  4. Render: `$project = Join-Path $Work 'project'`, then `Invoke-Copier copy --defaults --quiet --vcs-ref v0.1.0 --data 'project_name=Test Ignored' --data stack=dotnet --data git_host=github --data 'workflow_tools=[claude]' $tpl $project`.
  5. In `Push-Location $project` / `try` / `finally { Pop-Location }`: `$gitignore = Join-Path $project '.gitignore'`; `$templateRules = [IO.File]::ReadAllText($gitignore)`; `[IO.File]::AppendAllText($gitignore, "node_modules/`n")`; `Invoke-Git init -q -b main; Invoke-Git add -A; Invoke-Git commit -q -m 'Create project'`. For `$i` in `1..$Packages`: create `node_modules/some-fairly-long-package-name-{0:d4}` (format `$i`) holding `package.json` with the text `{}` and `bin/cli.js` with the text `x`.
  6. Premise check: save `$projectRules = [IO.File]::ReadAllText($gitignore)`, write `$templateRules` to `$gitignore`, compute `$length = (git status --ignored --porcelain | Where-Object { $_.StartsWith('!! ') } | ForEach-Object { $_.Length + 8 } | Measure-Object -Sum).Sum`, and write `$projectRules` back. `Check 'fixture: under the template''s .gitignore alone, the ignored paths overflow a Windows command line' ($length -gt 32767) "$length characters"`.
  7. `$infoExclude = git rev-parse --path-format=absolute --git-path info/exclude`; `$excludeBefore = if (Test-Path -LiteralPath $infoExclude) { [IO.File]::ReadAllText($infoExclude) }`.
  8. Run, collecting each output line as it streams so the lines printed before a throw are kept: `$lines = [Collections.Generic.List[string]]::new()`, then `try { & (Join-Path $project '.template\Update-Project.ps1') 2>&1 | ForEach-Object { $lines.Add("$_") } } catch { $lines.Add("THROWN: $_") }`, then `$output = $lines -join "`n"`.
  9. Checks: `'update: no WinError 206'` (`-not $output.Contains('WinError 206')`, detail `$output.Trim()`); `'update: succeeds with a folder only the project ignores'` (`$output -match 'Committed "Update from project-template v0\.1\.0"|Already up to date: template v0\.1\.0'`, detail `$output.Trim()`); `'update: nothing left over'` (`-not (git status --porcelain)`); `'update: info/exclude restored'` (`$excludeAfter = if (Test-Path -LiteralPath $infoExclude) { [IO.File]::ReadAllText($infoExclude) }`, then `$excludeAfter -eq $excludeBefore`); `'update: node_modules kept'` (`Test-Path -LiteralPath node_modules/some-fairly-long-package-name-0001/package.json`).
  10. Ending: copy `Test-Adoption.ps1` lines 308-311, with `Update ignored-files tests` in place of `Adoption tests`.
- Pattern: `Test-Template.ps1` (helpers, snapshot, render); `Test-Adoption.ps1` (help block, ending).
- Done when: `$o = .\Test-UpdateIgnoredFiles.ps1 | Out-String; if ($o.Contains('PASS  fixture: under the template') -and $o.Contains('FAIL  update: no WinError 206') -and $o.Contains('Update ignored-files tests: FAILED')) { exit 0 } else { $o; exit 1 }`

### [ ] 2. Keep the project's ignore rules in force during copier update
- Files: `template/.template/Update-Project.ps1` (edit)
- Change: replace the single line `        Invoke-Copier @copierArgs` (inside the outer `try`, just after the `foreach ($file in $deleted)` line) with the block below. Keep the indentation (8 spaces) and leave every other line unchanged:
  ```powershell
          # Copier writes the template's .gitignore over the project's before merging the project's edits back, then passes
          # every path Git reports as ignored to one `git apply` command. Keep the project's rules in force meanwhile, or a
          # folder only they ignore, such as node_modules/, is listed file by file and overflows Windows' command line.
          $infoExclude = git rev-parse --path-format=absolute --git-path info/exclude
          $excludeBefore = if (Test-Path -LiteralPath $infoExclude) { [IO.File]::ReadAllText($infoExclude) }
          $projectIgnore = Join-Path $project '.gitignore'
          try {
              if (Test-Path -LiteralPath $projectIgnore) {
                  New-Item -ItemType Directory -Force (Split-Path $infoExclude) | Out-Null
                  [IO.File]::WriteAllText($infoExclude, "$excludeBefore`n$([IO.File]::ReadAllText($projectIgnore))")
              }
              Invoke-Copier @copierArgs
          }
          finally {
              if ($null -eq $excludeBefore) { Remove-Item -LiteralPath $infoExclude -Force -ErrorAction SilentlyContinue }
              else { [IO.File]::WriteAllText($infoExclude, $excludeBefore) }
          }
  ```
- Pattern: the script's existing `try`/`finally` around `Push-Location` (lines 104 and 213-217).
- Done when: `.\Test-UpdateIgnoredFiles.ps1; exit $LASTEXITCODE`

### [ ] 3. Run the new test in CI
- Files: `.github/workflows/test-template.yml` (edit)
- Change: after the step `- name: Test adopting existing repositories` / `run: ./Test-Adoption.ps1`, add a step with the same indentation: `- name: Test updating a project that ignores a large folder` with `run: ./Test-UpdateIgnoredFiles.ps1`.
- Pattern: the existing `Test adopting existing repositories` step.
- Done when: `$y = Get-Content .github/workflows/test-template.yml -Raw; if ($y -match '(?s)run: \./Test-Adoption\.ps1\s+- name: Test updating a project that ignores a large folder\s+run: \./Test-UpdateIgnoredFiles\.ps1') { exit 0 } else { exit 1 }`

### [ ] 4. Document the new test in README.md
- Files: `README.md` (edit)
- Change, five edits in "Change the Template" and "Repository Layout":
  1. Step 3 of the numbered list (starts "3. Run `.\Test-Template.ps1`"): list `.\Test-UpdateIgnoredFiles.ps1` after `.\Test-Adoption.ps1`, and `Update ignored-files tests: PASSED` after `Adoption tests: PASSED`, keeping the sentence's "X, Y and Z" form.
  2. The paragraph starting "`Test-Template.ps1` works on a tagged snapshot": change "It, `Test-Adoption.ps1` and `Test-CommitAttribution.ps1` run" to "It, `Test-Adoption.ps1`, `Test-UpdateIgnoredFiles.ps1` and `Test-CommitAttribution.ps1` run".
  3. In the check table, after the row starting "| `Test-Adoption.ps1`:", add: `| `Test-UpdateIgnoredFiles.ps1`: a .NET project whose own `.gitignore` ignores a `node_modules` folder that the template's `.gitignore` doesn't updates without overflowing Windows' command line (WinError 206), and `.git/info/exclude` is left as it was | Always |`
  4. In the Repository Layout table, after the `Test-Adoption.ps1` row, add: `| `Test-UpdateIgnoredFiles.ps1` | Update a project whose own `.gitignore` ignores a large folder |`
  5. In the `.github/workflows/test-template.yml` layout row, change "Runs `Test-Template.ps1`, `Test-Adoption.ps1` and `Test-CommitAttribution.ps1`" to "Runs `Test-Template.ps1`, `Test-Adoption.ps1`, `Test-UpdateIgnoredFiles.ps1` and `Test-CommitAttribution.ps1`".
- Pattern: the neighbouring `Test-Adoption.ps1` mentions in the same places.
- Done when: `$r = Get-Content README.md -Raw; if (([regex]::Matches($r, 'Test-UpdateIgnoredFiles\.ps1')).Count -ge 6 -and $r.Contains('Update ignored-files tests: PASSED') -and $r.Contains('Runs `Test-Template.ps1`, `Test-Adoption.ps1`, `Test-UpdateIgnoredFiles.ps1` and `Test-CommitAttribution.ps1`')) { exit 0 } else { exit 1 }`

## Review checklist
- Step 1's test failed for the root cause (its output held `WinError 206`) before step 2, and passes after it.
- `info/exclude` is restored on every path: success, a conflict (the script exits 1 after the `finally`), and a Copier failure (the outer `catch` resets the project after the `finally` has run). It is removed again when it didn't exist before.
- `.\Test-Template.ps1 -SkipDotnetBuild` still ends with `Template tests: PASSED`: the merge, conflict, handover and root-wrapper update checks are unaffected.
- `.\Test-Adoption.ps1 -SkipDotnetBuild` and `.\Test-CommitAttribution.ps1` still pass.
- The new script and edits are UTF-8 without BOM with LF line endings, and the comment in `Update-Project.ps1` explains *why* (Copier's overwrite plus the per-path `--exclude`), not just what.
- No file outside the four listed was changed, and `PLAN.md` is the only other change on the branch.
