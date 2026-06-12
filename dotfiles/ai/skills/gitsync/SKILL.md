---
name: gitsync
description: Bring a multi-package workspace fully in sync when moving between machines — commit (with approval), push, pull, verify clean. State-driven; dirty repos trigger the commit ritual first. Command syntax lives in the glittering skill.
disable-model-invocation: true
effort: medium
---

# gitsync — workspace machine sync

One ritual for switching machines: run it when leaving (commits + pushes + pulls) and when arriving (pulls). It is state-driven — the dirty check decides what's needed, not the direction of travel. Mechanics defer to the `/glittering` skill; commit policy (staging gates, confirmations) to the global guidelines.

## Usage

`/gitsync [status]` — no argument runs the full flow; `status` is orientation only, no changes.

## Flow

1. **Orient**: `glittering git --path <root>` (live fetch, so ahead/behind is accurate). Summarise dirty repos, ahead/behind remote, parent ref drift.
2. **Dirty? Run the commit ritual first** (commit before pull — `git pull` skips dirty submodules, so pulling first would skip exactly the repos that need syncing):
   - Review each dirty repo with `glittering git diff --filter <sub>`; group related changes into commits
   - Propose ALL commit messages together in one summary for approval — this is where leftover half-done WIP gets caught: anything declined stays uncommitted
   - Commit via `glittering git commit` (prefer `-f` selective staging over `--all`; `-F` for related parent files)
   - Resolve everything the results report: `partial`/`left_uncommitted` means parent files still uncommitted; on failure, follow the `hint` field
3. **Pull**: `glittering git pull --path <root>` — pulls parent, inits new submodules, checks out tracking branches, pulls each sub. Declined-WIP subs are skipped with warnings (expected — surface them). Merge conflicts: stop and ask.
4. **Verify**: `glittering git check --path <root>`. Submodules ahead of the parent ref mean the remote moved past what the parent recorded — bump with `glittering git commit --parent-only`. No repo left in detached HEAD.
5. **Done when `git check` reports clean** (apart from deliberately kept WIP) — safe to switch machines.

## `status`

`glittering git --path <root>` (add `--cached` for instant). Summarise per repo: branch, dirty/clean, ahead/behind remote, ahead/behind parent ref, latest commit.
