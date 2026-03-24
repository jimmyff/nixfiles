---
name: charm
description: Multi-package project orchestrator — git (status, diff, commit, push, pull, check), Dart/Flutter test, analyze, pub get/upgrade
---

# charm Command Reference

Orchestrate multi-package projects: git operations across parent + submodules, Dart/Flutter test/analyze, and dependency management — in parallel, with caching.

Source: `~/nixfiles/scripts/charm/`

## Architecture

- **`charm`** (Go binary) — JSON to stdout, logs to stderr
- **`charm.nu`** (Nushell wrapper) — formatted tables with styled indicators
- **Cache** at `~/.cache/charm/cache/<workspace>/` — use `--cached` for instant reads

## Tips

- Pass `--path <workspace_root>` to set the working directory
- Prefer `commit-sub` / `commit-parent` over raw `git commit` / `git push` — they auto-push and keep parent refs in sync
- JSON goes to stdout; logs go to stderr
- Run `charm <command> -help` for flag details
- Fall back to raw git when charm doesn't cover the operation

## Commands (Go binary — JSON output)

```
charm status --path <root> [--filter <names>]              # package list (type, tests, deps)
charm test --path <root> [--filter <names>] [--timeout 60] # run tests (parallel, cached)
charm analyze --path <root> [--filter <names>]             # dart analyze (parallel, cached)
charm get --path <root> [--filter <names>]                 # pub get all packages
charm upgrade --path <root> [--filter <names>]             # pub upgrade all packages
charm clean                                                # remove old session dirs
```

### Git subcommands

```
charm git --path <root>                             # fetch + status (branch, dirty, ahead/behind)
charm git --path <root> --skip-fetch                # status without fetching
charm git --path <root> --cached                    # read cached status (instant)
charm git check --path <root> [--cached]            # verify committed, pushed, refs in sync (exit 0 = clean)
charm git push --path <root>                        # push all repos with unpushed commits (subs first)
charm git diff --path <root> [--staged]             # diff summary + .patch detail files
charm git commit-sub <sub> -m "msg" --path <root> [--all]   # commit + push submodule
charm git commit-parent -m "msg" --path <root> <sub> [...]  # verify refs, stage, commit + push parent
charm git pull --path <root>                        # pull parent, checkout branches, pull all subs
```

## Nushell Wrapper (`charm.nu`)

Same commands with formatted table output. Additional commands:

```
charm.nu overview --path <root> [--fetch]   # combined dashboard: git + cached test/analyze
charm.nu recache --path <root> [--force]    # refresh all caches
```

## JSON Output Shapes

- **test/analyze**: `{ packages: [{ path, status, details_file, ... }], summary }` — read `details_file` for issue/failure details
- **git**: `{ repo: { branch, dirty, ahead_remote, ... }, submodules: [{ ..., ahead_parent, behind_parent }] }`
- **git check**: `{ clean: bool, issues: [{ repo, severity, type, message, fix }], summary }`
- **git diff**: `{ repos: [{ path, staged, unstaged, untracked_files, details_file }], summary }`
- **commit-sub / commit-parent**: `{ success, ref, pushed, error }`
- **git pull**: `{ branch, submodules: [{ path, new_commits, was_dirty }], warnings }`

## Related Skills

- `/charmfix` — automated test/analysis fixing workflow
- `/submodules` — git submodule commit/sync/verify workflows
