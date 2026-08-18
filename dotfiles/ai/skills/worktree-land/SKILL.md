---
name: worktree-land
description: Publish this worktree and fast-forward the base branch onto it with `glittering worktree land` — pushes submodules, then the feature branch, then moves and pushes the base.
disable-model-invocation: true
model: sonnet
effort: medium
allowed-tools: Bash(glittering worktree:*), Bash(pwd)
---

# worktree-land

Publish this worktree's work and integrate it into the base branch. `glittering worktree land` runs a full pre-flight (every blocker reported at once), then pushes submodules → feature branch → fast-forwards and pushes the base branch. Fast-forward only, so landing cannot conflict.

Worktree: !`pwd`

## Run

`glittering worktree land --path <the absolute path above>`

Parse the JSON. `landed` = the base branch moved. `success` = that plus everything pushed.

## Outcomes

**`landed: true, success: true`** — done. Report `base.from_ref → base.to_ref`, `base.new_commits`, and `pushed[]` in publish order (`.` is the feature branch). Land never removes the worktree; pass on `glittering worktree prune` if the success `hint` names it.

**`landed: false`** (exit 1) — refused in pre-flight, **nothing was published**. Report every entry in `reasons`. The two common ones:

- not fast-forwardable → the remedy is `/worktree-update` first, then re-run. Say so; don't run it yourself.
- a submodule pin is behind or diverged from the base branch's → landing would fast-forward cleanly while reverting published submodule work. Name the submodule and stop.

**`landed: true, success: false`** — the base branch moved but something failed to push. Report each `failed[]` entry with its `error` plus the `hint`. Flag this as needing attention; it leaves work unpublished.

Always report `warnings` and any `skipped[]` entries.

## Never

- pass `--allow-pin-rewind`. It exists to deliberately revert published submodule work — that's the user's call, never yours. On a pin-rewind refusal, report it and stop.
- push, merge, or move a branch with raw git to get around a refusal. The refusal is the safety; `hint` is the remedy.
- `git reset --hard`, `git rebase`, `git push --force`
- remove the worktree — land never does, and neither should you
