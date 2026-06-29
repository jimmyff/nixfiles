---
name: glittering
description: Dart/Flutter workspace orchestrator (multi-package, git submodules). Use proactively when working in any multi-package workspace — run tests/analysis across packages (parallel, cached), commit submodule work (auto-push + parent ref sync), check workspace-wide git state (status/diff/push/pull/check). Not for single-file tests, git branch surgery, or single-package repos.
---

# glittering Command Reference

Workspace-level orchestrator for Dart/Flutter monorepos — a parent repo containing git submodules and/or multiple packages. Go binary: JSON to stdout, logs to stderr; parallel across packages, with caching. Treat the output as a contract — parse it and branch on its fields rather than skimming the prose.

Exit codes: `0` ok · `1` failure · `2` usage error · `3` partial (commit succeeded but parent files were left behind — see `parent.left_uncommitted`).

Source: `~/nixfiles/scripts/glittering/` (this skill lives at the package root).

## When to use it

In a multi-package workspace (cue: `.gitmodules` and/or multiple `pubspec.yaml` packages under one root), glittering is the default for anything workspace-wide. Orient first — `glittering git --cached --path <root>` (instant) or `glittering status --path <root>` — before reaching for raw git/dart.

| Asked to… | Run |
|---|---|
| run tests / verify they pass | `glittering test` |
| check code quality / analyzer issues | `glittering analyze` |
| commit and/or push work | `glittering git commit` |
| commit parent-repo-only files (docs/plans) | `glittering git commit --parent-only -f <file> -m "msg"` |
| "is everything committed/pushed?" (end of session) | `glittering git check` |
| pull latest / sync repos | `glittering git pull` |
| review changes / file-level detail | `glittering git diff` — per-file staged/unstaged/untracked + patch `details_file` |
| understand package layout / size | `glittering status`, `glittering stats` |

`glittering git` reports at repo level (dirty, ahead/behind); for which *files* changed, use `glittering git diff` — not raw `git status`.

## When NOT to use it — and why

- **Raw `git commit`/`git push` in a submodule workspace** leaves parent refs stale and work stranded unpushed on one machine — exactly the failure glittering exists to prevent. Always prefer `glittering git commit` (auto-pushes, verifies, syncs parent refs).
- **Per-package `dart test`/`dart analyze` for workspace checks** is serial, uncached, and misses cross-package breakage. Go raw only for a single targeted file: `dart test path/to/test.dart`.
- **Out of scope** — use raw tools for: git branch/checkout/merge/rebase/stash/log · `dart fix/format/run` · `flutter build/create/run` · repos that aren't multi-package workspaces.

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
glittering git commit --parent-only -f <file>... -m "msg" --path <root>  # commit parent-repo-only files (docs, plans); -F also accepted
glittering git pull --path <root> [--filter <names>]              # pull parent + subs
```

## Rules

- **Always use an absolute path** for `--path` (e.g. `--path /Users/jimmyff/projects/foo/workspace`). Relative paths can resolve incorrectly across repeated tool invocations due to CWD shifts
- **Never pipe through `head`/`tail`/truncate** glittering output — it's already summarised JSON; truncating breaks parsing
- **After a commit**: exit `3`/`partial: true` means parent files in `parent.left_uncommitted` were NOT committed — resolve before reporting done. On failure, the `hint` field gives the exact recovery command — follow it rather than re-running the whole commit
- Commit messages: no attribution lines, keep succinct

## Tips

- `--filter` uses substring matching: `--filter blog` matches `packages/blog`
- `git commit` auto-resolves short names: `git_dart` → `packages/git_dart`
- Surgical commit (sub also contains unrelated WIP): `glittering git commit <sub> -m "msg" -f a.dart -f b.dart` stages only those files (relative to sub root) and leaves the rest dirty — prefer this over hand-staging with raw `git add` + `--staged`
- `--no-parent` skips the parent update; `--parent-only` has two uses — bare: bump out-of-sync refs; with `-f`/`-F` + `-m`: commit parent-repo files alone. Add `-F <file>` to a sub commit to land parent files alongside the ref bumps (related files only, not unrelated WIP)
- `--filter .` targets the parent repo in `git`/`git diff`/`git check` (push/pull reject it); unmatched filter tokens warn on stderr
- `git diff` JSON stdout already IS the compact per-file summary (a `--stat` equivalent); the full patch is in `details_file`
- After a manual commit inside a submodule, push it with `git push --filter <sub>` and bump the parent ref with `git commit --parent-only`. `--filter` skips the parent-dirty pre-flight, so a pending parent ref bump won't block the submodule push
- Use `--cached` for instant reads from last live run
- Run `glittering <command> --help` for flag details

## JSON Output Shapes

- **test/analyze**: `{ packages: [{ path, status, details_file, ... }], summary }` — read `details_file` for details
- **stats**: `{ threshold, packages: [{ path, source_files, source_lines, test_files, test_lines, oversized_count, details_file }], summary }`
- **git**: `{ repo: { branch, dirty, ahead_remote, ... }, submodules: [{ ..., ahead_parent, behind_parent }] }`
- **git check**: `{ clean: bool, issues: [{ repo, severity, type, message, fix }], summary }`
- **git diff**: `{ repos: [{ path, staged, unstaged, untracked_files, details_file }], summary }`
- **commit**: `{ success, partial, hint, submodules: [{ path, ref, pushed }], parent: { ref, staged, left_uncommitted, pushed, warnings } }` — `partial: true` means the commit succeeded but parent files listed in `parent.left_uncommitted` were NOT committed
- **git pull**: `{ branch, submodules: [{ path, new_commits, was_dirty }], warnings }`

## Wrapper

- `glitter` (nushell wrapper, convenience alias) — same commands with human-friendly tables, plus `glitter overview` and `glitter recache`
