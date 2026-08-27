---
name: worktree-land
description: Integrate and publish this worktree — runs `glittering worktree update`, clears lockfile-only churn, then `glittering worktree land` to push submodules, the feature branch, and the base branch.
disable-model-invocation: true
model: sonnet
effort: medium
allowed-tools: Bash(pwd), Bash(git status:*), Bash(git clean -f:*), Bash(glittering worktree update:*), Bash(glittering worktree land:*), Bash(glittering get:*), Bash(glittering git commit:*)
---

# worktree-land

Ship this worktree: bring the base branch in, clear generated lockfile churn, publish. Landing is fast-forward only, so it cannot conflict — anything not ready is a refusal with coded `blockers[]`. Branch on `blockers[].code`, never on the prose in `reasons`.

Worktree: !`pwd`

## Flow

1. **Integrate** — `glittering worktree update --path <the absolute path above>`
2. If the only blockers are `stale_lockfiles`, or update succeeded with a hint that dependency versions changed: run the lockfile routine, then re-run update.
3. **Land** — `glittering worktree land --path <path>`
4. If land's only blockers are `stale_lockfiles`: lockfile routine, then re-run land.

Each remedy runs at most once — if the same blocker returns, report and stop. Any blocker code not listed below: report its `message` and `hint`, stop.

## Update outcomes

| Result | Action |
|---|---|
| `merge.status: "merged"` / `"up_to_date"` | Continue to land |
| `merge.status: "conflicts"` | Stop — see On conflicts |
| Blockers: only `stale_lockfiles` | Lockfile routine, re-run update once |
| Blockers: `user_changes` | The user's uncommitted work — report the paths, stop |
| Blockers: `submodule_ahead` / `submodule_dirty` / `submodule_diverged` / `submodule_unsynced` / `merge_in_progress` / `status_unreadable` | Report `message` + `hint`, stop |
| `merge.status: "failed"` or `base.action: "failed"` | Report the error and `hint`, stop |

A refusal may still have converged submodule pins forward (the pre-flight heals before it judges) — that work is kept and reported in `submodules[]`, never undone.

## Land outcomes

**`landed: true, success: true`** — done. Report `base.from_ref → base.to_ref`, `base.new_commits`, `pushed[]` in publish order (`.` is the feature branch), any healed pins (`submodules[]` entries with `synced`/`reattached`), and pass on the `worktree prune` hint.

**`landed: false`** (exit 1) — refused, **nothing published**. `stale_lockfiles` alone → lockfile routine, re-run once. `pin_rewind` → landing would revert published submodule work: name the submodule, stop. Anything else → report `message` + `hint`, stop.

**`landed: true, success: false`** — the base branch moved but something failed to push. Report each `failed[]` entry with its `error` plus the `hint`; flag as needing attention — it leaves work unpublished.

## Lockfile routine

Scope: `pubspec.lock` files only, taken from the blocker's `paths` (or, after a `glittering get`, from `git status --porcelain` filtered to `pubspec.lock`). If anything else would be swept up, stop instead.

- **Untracked** (`??` in `git status --porcelain -- <path>`): `git clean -f -- <paths>` — local residue nobody resolves from; `git clean` cannot touch tracked files. Suggest gitignoring them once in the final report.
- **Tracked, modified**: regenerated churn from a dependency bump — the new content is correct and wants committing. `glittering get --path <worktree>` first (so lockfiles match the merged pubspec.yaml), then commit only the lockfiles:
  - parent-repo paths → `glittering git commit --path <worktree> --parent-only -f <path> [-f …] -m "regenerate lockfiles"`
  - paths inside submodule `<sub>` → `glittering git commit <sub> --path <worktree> -m "regenerate lockfiles" -f <path relative to sub> [-f …]`

## On conflicts

Do not resolve them. Report the conflicted paths from `merge.conflicts`, which of those are submodules (two worktrees moved the same pin), that the merge is left in progress on purpose, and the remedy: fix the paths, stage **only** those paths, commit, re-run `/worktree-land`. Then stop — resolution needs full session context, not this command.

## Never

- resolve merge conflicts, or touch any non-lockfile dirt
- pass `--allow-pin-rewind` — it deliberately reverts published submodule work; that's the user's call
- `git clean` anything beyond the named `pubspec.lock` paths
- push, merge, or move a branch with raw git to get around a refusal — the refusal is the safety, `hint` is the remedy
- `git reset --hard`, `git rebase`, `git push --force`
- remove the worktree — land never does, and neither should you
