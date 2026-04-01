---
name: glittering
description: Multi-package project orchestrator — git (status, diff, commit, push, pull, check), Dart/Flutter test, analyze, pub get/upgrade
---

# glittering Command Reference

Go binary for multi-package Dart/Flutter workspaces — git operations across parent + submodules, test/analyze, dependency management. JSON to stdout, logs to stderr. Quiet by default; add `--verbose`/`-v` for progress output.

Source: `~/nixfiles/scripts/glitter/`

## Commands

```
glittering status --path <root> [--filter <names>]              # package list (type, tests, deps)
glittering test --path <root> [--filter <names>] [--timeout 60] # run tests (parallel, cached)
glittering analyze --path <root> [--filter <names>]             # dart analyze (parallel, cached)
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
glittering git commit <sub>... -m "msg" --path <root> [--all | -f file | --staged] [--no-parent] [--parent-only] [--parent-message "msg"]
glittering git pull --path <root> [--filter <names>]              # pull parent + subs
```

## Tips

- Pass `--path <workspace_root>` to every command
- `--filter` uses substring matching: `--filter blog` matches `packages/blog`
- `git commit` auto-resolves short names: `git_dart` → `packages/git_dart`
- Prefer `git commit` over raw `git commit` / `git push` — it auto-pushes and keeps parent refs in sync
- Use `--no-parent` to skip parent update, `--parent-only` for parent-only mode
- Use `--cached` for instant reads from last live run
- Never pipe through `head`/`tail`/truncate glittering output — it's already summarised JSON; truncating breaks parsing
- Run `glittering <command> --help` for flag details

## JSON Output Shapes

- **test/analyze**: `{ packages: [{ path, status, details_file, ... }], summary }` — read `details_file` for details
- **git**: `{ repo: { branch, dirty, ahead_remote, ... }, submodules: [{ ..., ahead_parent, behind_parent }] }`
- **git check**: `{ clean: bool, issues: [{ repo, severity, type, message, fix }], summary }`
- **git diff**: `{ repos: [{ path, staged, unstaged, untracked_files, details_file }], summary }`
- **commit**: `{ success, submodules: [{ path, ref, pushed }], parent: { ref, staged, pushed } }`
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
