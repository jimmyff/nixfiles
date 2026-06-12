---
name: glittering
description: Multi-package project orchestrator — git (status, diff, commit, push, pull, check), Dart/Flutter test, analyze, stats, pub get/upgrade
---

# glittering Command Reference

Go binary for multi-package Dart/Flutter workspaces — git operations across parent + submodules, test/analyze, dependency management. JSON to stdout, logs to stderr. Quiet by default; add `--verbose`/`-v` for progress output.

Exit codes: `0` ok · `1` failure · `2` usage error · `3` partial (commit succeeded but parent files were left behind — see `parent.left_uncommitted`).

Source: `~/nixfiles/scripts/glitter/`

## Commands

```
glittering status --path <root> [--filter <names>]              # package list (type, tests, deps)
glittering test --path <root> [--filter <names>] [--timeout 60] # run tests (parallel, cached)
glittering analyze --path <root> [--filter <names>]             # dart analyze (parallel, cached)
glittering stats --path <root> [--filter <names>] [--threshold 200] # file/line counts, oversized detection (cached)
glittering get --path <root> [--filter <names>]                 # pub get all packages
glittering upgrade --path <root> [--filter <names>]             # pub upgrade all packages
glittering clean                                                # remove old session dirs
```

### Git subcommands

```
glittering git --path <root> [--filter <names>]                   # fetch + status
glittering git --path <root> --skip-fetch [--filter <names>]      # status without fetching
glittering git --path <root> --cached [--filter <names>]          # read cached status (instant)
glittering git check --path <root> [--cached] [--filter <names>]  # verify committed/pushed
glittering git push --path <root> [--filter <names>]              # push repos with unpushed
glittering git diff --path <root> [--staged] [--filter <names>]   # diff summary
glittering git commit <sub>... -m "msg" --path <root> [--all | -f file | --staged] [-F parent-file] [--no-parent] [--parent-only] [--parent-message "msg"]
  # Stage with --all (all changes), -f <file> (specific files), or --staged (use the index as-is).
  # One of these is required unless something is already staged — a bare commit with no flag
  # and an empty index errors with "nothing staged in <sub>".
  # IMPORTANT: --all/-f/--staged scope to the named SUBMODULES only — parent repo files are
  # never swept. The parent commit contains the ref bumps, files named with --parent-files/-F,
  # and anything already staged in the parent. Other dirty parent files are left behind and
  # reported via partial: true + parent.left_uncommitted — check both before claiming done.
glittering git pull --path <root> [--filter <names>]              # pull parent + subs
```

## Tips

- **Always use an absolute path** for `--path` (e.g. `--path /Users/jimmyff/Projects/foo/workspace`). Relative paths like `--path .` can resolve incorrectly across repeated tool invocations due to CWD shifts
- `--filter` uses substring matching: `--filter blog` matches `packages/blog`
- `git commit` auto-resolves short names: `git_dart` → `packages/git_dart`
- Prefer `git commit` over raw `git commit` / `git push` — it auto-pushes and keeps parent refs in sync
- Use `--no-parent` to skip parent update, `--parent-only` for parent-only mode
- To land parent-repo files (docs, plans) in the same commit as the ref bumps, name them with `-F/--parent-files` — only include files related to your change, not unrelated WIP
- After a manual commit inside a submodule, push it with `git push --filter <sub>` and bump the parent ref with `git commit --parent-only`. `--filter` skips the parent-dirty pre-flight, so a pending parent ref bump won't block the submodule push
- If a multi-submodule commit fails partway, the result's `hint` field gives the exact recovery command (e.g. already-pushed subs needing a `--parent-only` ref bump) — follow it rather than re-running the whole commit
- Commit messages: no attribution lines, keep succinct
- Use `--cached` for instant reads from last live run
- Never pipe through `head`/`tail`/truncate glittering output — it's already summarised JSON; truncating breaks parsing
- Run `glittering <command> --help` for flag details

## JSON Output Shapes

- **test/analyze**: `{ packages: [{ path, status, details_file, ... }], summary }` — read `details_file` for details
- **stats**: `{ threshold, packages: [{ path, source_files, source_lines, test_files, test_lines, oversized_count, details_file }], summary }`
- **git**: `{ repo: { branch, dirty, ahead_remote, ... }, submodules: [{ ..., ahead_parent, behind_parent }] }`
- **git check**: `{ clean: bool, issues: [{ repo, severity, type, message, fix }], summary }`
- **git diff**: `{ repos: [{ path, staged, unstaged, untracked_files, details_file }], summary }`
- **commit**: `{ success, partial, hint, submodules: [{ path, ref, pushed }], parent: { ref, staged, left_uncommitted, pushed, warnings } }` — `partial: true` means the commit succeeded but parent files listed in `parent.left_uncommitted` were NOT committed
- **git pull**: `{ branch, submodules: [{ path, new_commits, was_dirty }], warnings }`

## When to use raw commands instead

- Targeted single-file tests: `dart test path/to/test.dart`
- Git branch/checkout/merge/rebase/stash/log
- `dart fix/format/run`, `flutter build/create/run`

## Nushell wrapper (`glitter`)

Human-friendly formatted tables. Same commands plus `glitter overview` and `glitter recache`.

## Related Skills

- `/glitterfix` — automated test/analysis fixing workflow
- `/submodules` — git submodule commit/sync/verify workflows
