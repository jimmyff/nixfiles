---
name: glitter
description: Multi-package project orchestrator — git (status, diff, commit, push, pull, check), Dart/Flutter test, analyze, pub get/upgrade
---

# ✨glitter Command Reference

Orchestrate multi-package projects: git operations across parent + submodules, Dart/Flutter test/analyze, and dependency management — in parallel, with caching.

Source: `~/nixfiles/scripts/glitter/`

## Architecture

- **`glittering`** (Go binary) — JSON to stdout, logs to stderr
- **`glitter`** (Nushell wrapper) — formatted tables with styled indicators
- **Cache** at `~/.cache/glitter/cache/<workspace>/` — use `--cached` for instant reads

## Tips

- Pass `--path <workspace_root>` to set the working directory
- Prefer `commit-sub` / `commit-parent` over raw `git commit` / `git push` — they auto-push and keep parent refs in sync
- JSON goes to stdout; logs go to stderr
- Run `glittering <command> -help` for flag details
- Fall back to raw git when glittering doesn't cover the operation

## Commands (Go binary — JSON output)

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
glittering git --path <root>                             # fetch + status (branch, dirty, ahead/behind)
glittering git --path <root> --skip-fetch                # status without fetching
glittering git --path <root> --cached                    # read cached status (instant)
glittering git check --path <root> [--cached]            # verify committed, pushed, refs in sync (exit 0 = clean)
glittering git push --path <root>                        # push all repos with unpushed commits (subs first)
glittering git diff --path <root> [--staged]             # diff summary + .patch detail files
glittering git commit-sub <sub> -m "msg" --path <root> [--all]   # commit + push submodule
glittering git commit-parent -m "msg" --path <root> <sub> [...]  # verify refs, stage, commit + push parent
glittering git pull --path <root>                        # pull parent, checkout branches, pull all subs
```

## Nushell Wrapper (`glitter`)

Same commands with formatted table output. Additional commands:

```
glitter overview --path <root> [--fetch]   # combined dashboard: git + cached test/analyze
glitter recache --path <root> [--force]    # refresh all caches
```

## JSON Output Shapes

- **test/analyze**: `{ packages: [{ path, status, details_file, ... }], summary }` — read `details_file` for issue/failure details
- **git**: `{ repo: { branch, dirty, ahead_remote, ... }, submodules: [{ ..., ahead_parent, behind_parent }] }`
- **git check**: `{ clean: bool, issues: [{ repo, severity, type, message, fix }], summary }`
- **git diff**: `{ repos: [{ path, staged, unstaged, untracked_files, details_file }], summary }`
- **commit-sub / commit-parent**: `{ success, ref, pushed, error }`
- **git pull**: `{ branch, submodules: [{ path, new_commits, was_dirty }], warnings }`

## Related Skills

- `/glitterfix` — automated test/analysis fixing workflow
- `/submodules` — git submodule commit/sync/verify workflows
