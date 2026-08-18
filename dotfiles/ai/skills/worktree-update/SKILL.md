---
name: worktree-update
description: Bring the base branch into the current worktree with `glittering worktree update` — fast-forward the base, merge it in, converge submodule pins. Halts on conflict rather than resolving it.
disable-model-invocation: true
model: sonnet
effort: medium
allowed-tools: Bash(glittering worktree:*), Bash(pwd)
---

# worktree-update

Bring the base branch into this worktree. `glittering worktree update` does all the work: fetch, fast-forward the base worktree to origin, `git merge <base>` into this one, then converge submodule pins on both. A merge, never a rebase — an already-pushed branch is not rewritten.

Worktree: !`pwd`

## Run

`glittering worktree update --path <the absolute path above>`

Parse the JSON on stdout. Branch on `reasons` first, then `merge.status`.

## Outcomes

| Result | Meaning | Action |
|---|---|---|
| `reasons` non-empty (exit 1) | Refused, nothing touched — worktree is dirty, or a merge is already in progress | Report the reasons verbatim, stop. Don't tidy up on your own. |
| `merge.status: "up_to_date"` | Already current | Report, stop |
| `merge.status: "merged"` | Base integrated | Report `merge.commits_integrated`, then done |
| `merge.status: "conflicts"` | Merge left in progress **on purpose** | Stop — see below |
| `merge.status: "failed"` or `base.action: "failed"` | Git error | Report the error and `hint`, stop |

Surface these whatever the status:

- `base.action: "skipped_dirty"` — the base worktree is dirty, so its current tip was merged instead of origin's. A warning, not a failure; say so.
- Any `warnings`.
- Any `submodules[]` entry whose action is not `in_sync`/`synced`/`reattached` — i.e. `skipped_dirty`, `ahead`, `diverged`, `error`.

Run inside the base worktree itself, this degrades to just the fast-forward. That's expected.

## On conflicts

Do not resolve them. Report and hand back:

- the conflicted paths from `merge.conflicts`
- which of those are submodules — a submodule path here means two worktrees moved the same pin
- that the merge is still in progress, and the resolution is: fix the paths, stage **only** those paths, commit, re-run `/worktree-update`

Then stop. Conflict resolution needs full session context, not this command.

## Never

- `git add -A` or `git add .` with a merge in progress — it re-stages every gitlink at its submodule's HEAD and silently discards the pins the merge just brought in
- `git reset --hard`, `git rebase`, `git push --force`
- work around a refusal with raw git — the `hint` field is the remedy
