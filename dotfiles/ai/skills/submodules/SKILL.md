---
name: submodules
description: Manage git submodule workflows — status, commit, sync, and update across repos with submodules
disable-model-invocation: true
---

# Git Submodules Management

Manage repositories containing git submodules.

## Usage

`/submodules $ARGUMENTS`

Arguments: `status`, `diff`, `commit`, `sync`, `update`, or omit to run `status` then ask the user what they'd like to do.

## Pre-flight

1. Confirm `.gitmodules` exists
2. Read `.gitmodules` to identify all submodule paths

## Commit Messages

- Imperative mood, single line, no period
- Submodule commits: describe the change (e.g. `add search endpoint`, `fix date parsing`)
- Parent repo updates: `update <name> submodule ref` or `update <name1>, <name2> submodule refs`
- Check `git log --oneline -5` in each repo to match existing style

## Commands

### `status` — Overview of all submodules

For each submodule, check: uncommitted changes, current branch, latest commit, tracking info.

Present a summary table with columns: path, branch, dirty/clean, ahead/behind remote, ahead/behind parent ref, latest commit message.

- **Ahead/behind remote**: how far the local branch is ahead/behind its upstream (omit if no upstream)
- **Ahead/behind parent ref**: how the submodule HEAD compares to the ref recorded in the parent's index — report if the submodule has commits beyond what the parent expects

### `diff` — Show changes across all submodules

For each submodule with uncommitted changes, show the diff summary and any untracked files. Useful for reviewing work-in-progress across the project without committing.

### `commit` — Commit and push dirty submodules, then update parent

**1. Audit**

- Identify submodules with uncommitted changes (if none, report and exit)
- For each, check branch state — warn and stop if detached HEAD
- Show status and diff summary for each dirty submodule

**2. Safety checks**

Before staging, flag and ask the user about:
- Secrets: `.env`, credentials, keys, tokens, `.pem`, `.p12`
- Large binaries or build artifacts
- OS/IDE junk: `.DS_Store`, `Thumbs.db`, `.idea/`, `.vscode/` (unless already tracked)
- Anything that looks out of place

Do NOT stage flagged files without explicit user approval.

**3. Commit dirty submodules**

1. Stage appropriate files in each dirty submodule (prefer specific files over `git add -A`)
2. Present all proposed commit messages together in a single summary for the user to review, confirm, or adjust (avoid per-submodule back-and-forth when multiple are dirty)
3. Commit and push each submodule to its remote tracking branch

**4. Update parent repository**

1. Stage the updated submodule references
2. Propose a commit message, ask user to confirm
3. Commit and push

### `sync` — Pull and sync everything

1. Pull parent repository
2. Init and update all submodules recursively
3. For each submodule, reattach to its tracking branch **only if safe**:
   - Determine the tracking branch from `.gitmodules` (the `branch` field) or ask the user
   - Compare the submodule's current detached HEAD against the tracking branch tip
   - If they point to the same commit: safe to reattach
   - If the tracking branch is ahead: the parent ref is behind — warn the user and ask whether to reattach (which advances past the parent's recorded ref) or stay detached
   - If the tracking branch is behind: the parent expects a commit not on the branch — warn and ask the user
4. Report submodule status after sync

If a submodule has merge conflicts, stop and ask the user how to proceed.

### `update` — Pull latest in each submodule from its remote

1. Pull latest from each submodule's tracked remote branch
2. Show which submodules received new commits
3. Ask if user wants to commit updated references in the parent (same as step 4 of `commit`)

If a pull results in merge conflicts, stop and ask the user how to proceed.

## Rules

- Always confirm before committing or pushing
- If a push fails (e.g. diverged branch), stop and ask the user
- No repo (parent or submodule) should ever be left in detached HEAD state. After any operation that detaches HEAD (e.g. `submodule update`), reattach to the tracking branch. If the tracking branch can't be determined, ask the user
