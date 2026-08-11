---
name: glittering
description: Dart/Flutter workspace orchestrator (multi-package, git submodules). Use proactively when working in any multi-package workspace — run tests/analysis across packages (parallel, cached), commit submodule work (auto-push + parent ref sync), check workspace-wide git state (status/diff/push/pull/check). Not for single-file tests, git branch surgery, or single-package repos.
---

# glittering Command Reference

Workspace-level orchestrator for Dart/Flutter monorepos — a parent repo containing git submodules and/or multiple packages. Go binary: JSON to stdout, logs to stderr; parallel across packages, with caching. Treat the output as a contract — parse it and branch on its fields rather than skimming the prose.

Exit codes: `0` ok · `1` failure · `2` usage error · `3` partial (commit succeeded but parent files were left behind — see `parent.left_uncommitted`). A live `test` run also exits `1` when any package is `fail`/`error`/`timeout` (JSON still on stdout — parse it); `test --cached` always exits `0`.

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
| submodule stale after a parent merge/pull (`behind_parent`, phantom analyzer errors) | `glittering git sync` |
| review changes / file-level detail | `glittering git diff` — per-file staged/unstaged/untracked + patch `details_file` |
| understand package layout / size | `glittering status`, `glittering stats` |
| assess / create / clean up worktrees | `glittering worktree list / add / remove / prune` |
| bring the base branch into a worktree | `glittering worktree update` |
| finished work in a worktree → into main | `glittering worktree land` |

`glittering git` reports at repo level (dirty, ahead/behind); for which *files* changed, use `glittering git diff` — not raw `git status`.

## When NOT to use it — and why

- **Raw `git commit`/`git push` in a submodule workspace** leaves parent refs stale and work stranded unpushed on one machine — exactly the failure glittering exists to prevent. Always prefer `glittering git commit` (auto-pushes, verifies, syncs parent refs).
- **Per-package `dart test`/`dart analyze` for workspace checks** is serial, uncached, and misses cross-package breakage. Go raw only for a single targeted file: `dart test path/to/test.dart`.
- **Out of scope** — use raw tools for: git branch/checkout/merge/rebase/stash/log · `dart fix/format/run` · `flutter build/create/run` · repos that aren't multi-package workspaces.
- **After any raw `git merge`/`git pull` in the parent repo**, run `glittering git check`: a merge that moves a gitlink leaves the submodule worktree on the old commit (`behind_parent` — stale builds, phantom analyzer errors). Fix with `glittering git sync`, not `git submodule update` (which detaches HEAD).

## Commands

```
glittering status --path <root> [--filter <names>]              # package list (type, tests, deps)
glittering test --path <root> [--filter <names>] [--timeout 120] # run tests (parallel, cached)
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
glittering git pull --path <root> [--filter <names>]              # pull parent + subs (to branch TIPS)
glittering git sync --path <root> [--filter <names>] [--skip-fetch] # fast-forward subs to the parent's
  # PINNED refs, staying on-branch. The fix for behind_parent: a parent merge/pull moves a gitlink but
  # the submodule worktree stays on the old commit — builds/analysis silently run stale code. Forward-only
  # (never rewinds an ahead sub; that's `commit --parent-only`), reattaches detached subs at the pin,
  # skips dirty subs (warning), exits 1 on genuine divergence without touching the worktree.
```

### Worktree subcommands

For the bare-repo + worktree layout (`<proj>/.bare` + `<proj>/main`, `<proj>/<feature>`…). `--path` may be any worktree, the project root, or the bare dir — except for `update`/`land`, which act on the worktree `--path` is *inside*.

```
glittering worktree list --path <proj> [--cached] [--fetch] [--filter <n>]  # per-worktree status (JSON)
glittering worktree add <name> --path <proj> [--from <ref>] [--no-get] [--no-share-objects] [--no-hook]
glittering worktree update --path <worktree> [--skip-fetch]  # base ff, then merge the base branch in
glittering worktree land --path <worktree> [--allow-pin-rewind]  # push, then ff the base branch onto it
glittering worktree remove <name> --path <proj> [--force] [--delete-branch]
glittering worktree prune --path <proj> [--dry-run] [--force]
glittering worktree path <name> --path <proj>     # prints absolute path as PLAIN TEXT (not JSON), for cd
```

- **`list`** is the fast orientation primitive. Each row carries `removable` (safe to delete) plus the components (`dirty`, `ahead_remote`, `head_on_remote`, `ahead_base`/`behind_base`, `uninit_submodules`, `last_commit_age_secs`). `--cached` reads each worktree's `git.json` (rows with none get `stale:true`).
- **`add`** checks out an existing branch (local, then `origin/<name>`) or creates one off the base; inits submodules (object-shared from the base worktree, parallel), seeds test/analyze/stats cache, runs `pub get`. `success:false` + exit `3` means usable-but-degraded — read `warnings` (e.g. uninitialised submodules, pub-get failures). Finally it runs optional on-add hooks (cwd = new worktree; env `GLITTER_WORKTREE_PATH`/`GLITTER_BASE_WORKTREE`/`GLITTER_PROJECT_DIR`; 60s timeout each; **after** `pub get`, so a hook that changes deps must re-run it): a user-level `${XDG_CONFIG_HOME:-~/.config}/glittering/hooks/worktree/on-add` for every project (e.g. seed a shared `.mcp.json`), then the project's `.glittering/hooks/worktree/on-add` from the **base worktree** (base-sourced so a branch can't inject one). `on_add_hook` is the aggregate of both (worst wins): `ok`/`failed`/`skipped`/`not_executable`/`""`; `--no-hook` skips both. Non-fatal — read `warnings` (scope-labelled `global`/`project`). To write a hook, see "Writing a worktree hook" in the package README.
- **`update`** brings the base branch in: fetch, fast-forward the base worktree to origin, `git merge <base>` into this worktree, then converge submodule pins on **both** worktrees (a fast-forward that moves a gitlink leaves the superproject dirty until its submodule follows). A merge, never a rebase — an already-pushed feature branch is not rewritten. Refuses (exit `1`, nothing touched) when this worktree is dirty or a merge is already in progress. A **conflict is left in progress on purpose**: `merge.status: "conflicts"` with `merge.conflicts` naming the paths (a submodule path there = two worktrees moved the same pin) — resolve, **stage only the conflicted paths**, commit, re-run. Never `git add -A` mid-merge: it re-stages every gitlink at its submodule worktree's HEAD, silently discarding the pins the merge just brought in (update warns if it finds a pin behind the base branch's). A dirty base worktree is a warning, not a failure: its fast-forward is skipped and its current tip is merged instead. Run on the base worktree itself, it degrades to just the fast-forward.
- **`land`** publishes the worktree and integrates it: pre-flight (every blocker at once), push submodules **then** the feature branch, `merge --ff-only` the base worktree onto it, converge its pins, push the base branch. **Fast-forward only** — the base branch only ever moves to a commit that already contains it, so landing cannot conflict; not fast-forwardable means one remedy: run `worktree update` first (the `hint` says so). Containment covers history, not gitlinks: land also refuses when a submodule pin is **behind or diverged from** the base branch's, which would fast-forward cleanly while reverting published submodule work — `--allow-pin-rewind` overrides it for a deliberate revert (still reported as a warning). Refusals exit `1` with `landed:false` + `reasons` and publish nothing. Never removes the worktree — the success `hint` names `worktree prune` for that.
- **`remove`** refuses base/current and (without `--force`) any worktree with uncommitted/unpushed work in the superproject or a submodule. Policy refusals exit `0` with `removed:false` + `reasons`; only git/IO failure exits `1`. Never deletes the branch unless `--delete-branch` (safe `-d` only). Also handles **orphans** — directories git no longer lists, left by a failed removal (surfaced by `list` under `orphans`): without `--force` it refuses with an explanatory reason (exit `0`); with `--force` it deletes the directory and its cache. If git's own removal fails mid-delete (e.g. an IDE recreated a file), the directory is removed directly with retries.
- **`prune`** reaps only merged-and-pushed clean worktrees (worktree dirs only — branches survive); `--force` also reaps clean+pushed-but-unmerged. Also sweeps cache subtrees whose disk path no longer exists, reporting them in `cache_removed` (listed but kept under `--dry-run`).

The three gates differ by design: `removable` (list) keys on **pushed**, `prune` on **merged**, `remove` does the **authoritative deep + submodule** check. So a `removable:true` row may still be skipped by `prune` ("not merged") or refused by `remove` (dirty submodule).

**Concurrency policy** — give concurrent worktrees *disjoint* submodules where you can: two worktrees editing one submodule collide at pin level, not file level. `worktree list` reports `overlaps` (submodules carrying local commits in ≥2 worktrees); check it before spawning a second agent. When it does happen, nothing is lost: `update` surfaces it as a submodule conflict, and `land` refuses in pre-flight with the integrate-then-bump-the-pin remedy.

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

- **test/analyze**: `{ packages: [{ path, status, details_file, ... }], summary }` — read `details_file` for details. Test statuses: `pass`/`fail`/`error`/`timeout` (analyze has no `timeout`). `timeout` = the package hit the per-package cap and was killed: counts are partial, and its `details_file` carries `failures` plus `incomplete` — tests that started but never finished, i.e. the hang suspects. Summary includes `timeout_packages`.
- **stats**: `{ threshold, packages: [{ path, source_files, source_lines, test_files, test_lines, oversized_count, details_file }], summary }`
- **git**: `{ repo: { branch, dirty, ahead_remote, ... }, submodules: [{ ..., ahead_parent, behind_parent }] }`
- **git check**: `{ clean: bool, issues: [{ repo, severity, type, message, fix }], summary }`
- **git diff**: `{ repos: [{ path, staged, unstaged, untracked_files, details_file }], summary }`
- **commit**: `{ success, partial, hint, submodules: [{ path, ref, pushed }], parent: { ref, staged, left_uncommitted, pushed, warnings } }` — `partial: true` means the commit succeeded but parent files listed in `parent.left_uncommitted` were NOT committed
- **git pull**: `{ branch, submodules: [{ path, new_commits, was_dirty }], warnings }`
- **git sync**: `{ success, submodules: [{ path, branch, action, from_ref, to_ref, new_commits, hint, error }], warnings }` — `action`: `in_sync`/`synced`/`reattached` (good) · `skipped_dirty` (warning) · `ahead` (bump the pin — follow `hint`) · `diverged`/`error` (exit 1, worktree untouched)
- **worktree list**: `{ project, project_dir, base_branch, current, stash_count, worktrees: [{ name, path, branch, current, dirty, removable, head_on_remote, ahead_remote, behind_remote, ahead_base, behind_base, uninit_submodules, submodules_ahead, last_commit_age_secs, stale }], orphans: [{ name, path, hint }], overlaps: [{ submodule, worktrees: [names] }] }` — `orphans` are directories from failed removals (`hint` is the exact reap command); `submodules_ahead`/`overlaps` are unlanded submodule work, per worktree and where it collides
- **worktree add**: `{ name, path, branch, base, success, created_branch, cache_seeded, submodules_expected, submodules_initialised, pub_get: [...], warnings, on_add_hook }` — `success:false`/exit 3 = degraded; `on_add_hook` (aggregate of the global + project hooks): `""`/`ok`/`failed`/`skipped`/`not_executable`
- **worktree update**: `{ worktree, path, branch, base_branch, success, base: { action, from_ref, to_ref, new_commits, submodules }, merge: { status, ref, commits_integrated, conflicts }, submodules: [git sync results for this worktree], reasons, warnings, hint }` — `base.action`: `up_to_date`/`fast_forwarded`/`skipped_dirty`/`missing`/`failed` · `merge.status`: `merged`/`up_to_date`/`conflicts`/`skipped`/`failed`. `reasons` non-empty = refused, nothing touched
- **worktree land**: `{ worktree, branch, base_branch, landed, success, reasons, pushed/skipped/failed: [{ path, status, ref, error }], base: { action, from_ref, to_ref, new_commits, pushed, submodules }, warnings, hint }` — `pushed` is in publish order (submodules first, then `.` = the feature branch); `landed` = the base branch moved, `success` = that plus everything pushed
- **worktree remove**: `{ removed, branch_deleted, name, path, reasons }` — `removed:false` = refused (see reasons)
- **worktree prune**: `{ dry_run, pruned: [{ name, path, branch }], skipped: [{ ..., reason }], cache_removed: [paths] }` — `cache_removed` = orphaned cache subtrees swept (would-be, when `dry_run`)

## Wrapper

- `glitter` (nushell wrapper, convenience alias) — same commands with human-friendly tables, plus `glitter overview` and `glitter recache`
