---
name: glitterfix
description: Run tests and/or analysis across Dart/Flutter workspace packages and fix failures
disable-model-invocation: true
---

# glitterfix

Run tests and/or analysis across all Dart/Flutter packages in the workspace and fix issues.

## Usage

`/glitterfix [$ARGUMENTS]`

Arguments:
- `tests` — run tests and fix failures
- `analyze` — run analysis and fix issues
- No subcommand — run both (analyze first, then tests)
- `fix` — auto-fix without prompting
- Comma-separated filter: `blink_highlight,blink_core` to target specific packages

Combine freely: `/glitterfix fix tests blink_highlight`, `/glitterfix analyze`, `/glitterfix fix`.

## Common Steps

1. Parse arguments: extract subcommand (`tests`, `analyze`, or both), `fix` flag, and package filter
2. Run: `glittering get --path <workspace_root> [--filter <filter>]` to ensure dependencies are resolved

## Analyze

### Phase 1 — Run Analysis

1. Run: `glittering analyze --path <workspace_root> [--filter <filter>]`
2. Parse the JSON output from stdout
3. Present a summary table with columns: package, status, errors, warnings, infos
4. For packages with issues, read the session detail file (from `details_file` in the JSON) and list: severity, file:line:col, message, code
5. If all pass: report success and stop
6. If issues exist and `fix` was NOT passed: ask the user whether to auto-fix
7. If issues exist and `fix` was passed: proceed to Phase 2

### Phase 2 — Fix Issues

For each package with errors or warnings, spawn a parallel Agent (one per package) with this prompt:

> Fix analysis issues in `<package_path>`.
>
> Workspace root: `<workspace_root>`
> This package is part of a multi-package workspace. Run `glittering status --path <workspace_root>` if you need to understand the package layout.
>
> **Issues:**
> - `<severity>` `<file>:<line>:<col>` — `<message>` (`<code>`)
> (list all issues for this package)
>
> **Steps:**
> 1. Read the files with issues and understand the context
> 2. Read README.md and CLAUDE.md in the package if they exist
> 3. Fix each issue. Prefer fixes that address root causes over suppressing warnings
> 4. If a fix requires cross-package changes: STOP and describe what you found
> 5. Verify: `cd <workspace_root>/<package_path> && dart analyze`
> 6. Report what you fixed and any remaining issues

### Post-fix (Analyze)

1. Re-run `glittering analyze --path <workspace_root> [--filter <filter>]` to verify
2. Present a final report: packages fixed, packages still with issues

## Tests

### Phase 1 — Run Tests

1. Run: `glittering test --path <workspace_root> [--filter <filter>]`
2. Parse the JSON output from stdout
3. Present a summary table with columns: package, status, passed, failed, skipped
4. For packages with `error` status: check the error message. If it's a compilation error, run `glittering analyze` on that package to get details. If it's a missing dependency, re-run `glittering get`. Resolve before proceeding
5. For packages with `fail` status, read the session detail file (from `details_file` in the JSON) and list: test name, file:line, truncated error (first 2 lines)
6. If all pass: report success and stop
7. Run `glittering analyze --path <workspace_root> [--filter <filter>]` on failing packages — analysis errors are often the root cause of test failures. If found, fix analysis errors first and re-run tests before proceeding to Phase 2
8. If failures remain and `fix` was NOT passed: ask the user whether to auto-fix
9. If failures remain and `fix` was passed: proceed to Phase 2

### Phase 2 — Fix Failures

For each package with failures, spawn a parallel Agent (one per package) with this prompt:

> Fix failing tests in `<package_path>`.
>
> Runner: `<dart|flutter> test`
> Workspace root: `<workspace_root>`
> This package is part of a multi-package workspace. Run `glittering status --path <workspace_root>` if you need to understand the package layout.
>
> **Failures:**
> - `<test_name>` in `<test_file>:<line>` — `<error_summary>`
> (list all failures for this package)
>
> **Steps:**
> 1. Read the failing test file(s) and the source code they test
> 2. Read README.md and CLAUDE.md in the package if they exist
> 3. Determine: is the test stale (source changed) or is the source buggy?
> 4. If the fix is clear and contained: make the fix
> 5. If ambiguous or requires cross-package changes: STOP and describe what you found
> 6. Verify: `cd <workspace_root>/<package_path> && timeout 90 <runner> test`
> 7. Verify: `cd <workspace_root>/<package_path> && dart analyze`
> 8. Report what you fixed and any remaining issues

### Post-fix (Tests)

1. Re-run `glittering test --path <workspace_root> [--filter <filter>]` to verify the full suite
2. Present a final report: packages fixed, packages still failing, packages needing manual attention

## Final

- Do NOT commit — inform the user they can review changes and use `/submodules commit`
