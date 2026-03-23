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

## charm

Prefer charm commands over manual git. Fall back to manual git when charm doesn't cover the operation.

**Important:** charm's `--path` flag sets the working directory. Always pass the workspace root path.

Available commands:
- `charm git --path <workspace>` — JSON status of repo + all submodules
- `charm git diff --path <workspace>` — structured diff summary for parent + all submodules (JSON on stdout, `.patch` files for full diffs). Use `--staged` for staged changes only
- `charm git commit-sub <path> -m "message" --path <workspace>` — commit staged files and push a submodule (add `--all` to stage all tracked changes)
- `charm git commit-parent -m "message" --path <workspace> sub1 sub2...` — verify refs are pushed, stage refs, commit and push parent
- `charm git pull --path <workspace>` — pull parent + sync submodules
- `charm git update --path <workspace>` — pull latest in each submodule

## Commit Messages

- Imperative mood, single line, no period
- Submodule commits: describe the change (e.g. `add search endpoint`, `fix date parsing`)
- Parent repo updates: `update <name> submodule ref` or `update <name1>, <name2> submodule refs`
- Check `git log --oneline -5` in each repo to match existing style

## Commands

### `status` — Overview of all submodules

**charm**: `charm git --path <workspace>`

Parse the JSON output. For each submodule, check: uncommitted changes, current branch, latest commit, tracking info.

Present a summary table with columns: path, branch, dirty/clean, ahead/behind remote, ahead/behind parent ref, latest commit message.

- **Ahead/behind remote**: how far the local branch is ahead/behind its upstream (omit if no upstream)
- **Ahead/behind parent ref**: how the submodule HEAD compares to the ref recorded in the parent's index — report if the submodule has commits beyond what the parent expects

### `diff` — Show changes across all submodules

**charm**: `charm git diff --path <workspace>` (add `--staged` for staged only)

Returns JSON with per-repo entries containing: staged/unstaged changed files (path, status M/A/D/R, insertions, deletions), untracked files, aggregate stats, and a `details_file` path to a `.patch` file with the full unified diff. Clean repos are omitted.

Read `.patch` detail files selectively to inspect full diffs for specific repos. Useful for reviewing work-in-progress across the project without committing.

### `commit` — Commit and push dirty submodules, then update parent

**charm**: Use `git commit-sub` for each dirty submodule, then `git commit-parent` to update the parent refs.

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

**3. Quality check**

Run `charm analyze --path <workspace>` on the packages being committed. If there are errors, warn the user before proceeding.

**4. Commit dirty submodules**

1. Stage appropriate files in each dirty submodule (prefer specific files over `git add -A`). If a submodule has a mix of unrelated changes, group them into separate commits by staging selectively
2. Present all proposed commit messages together in a single summary for the user to review, confirm, or adjust (avoid per-submodule back-and-forth when multiple are dirty)
3. Commit and push each submodule to its remote tracking branch

**5. Update parent repository**

1. Stage **only** the submodule references that were committed and pushed in step 3
2. Check if any **other** submodules have HEADs ahead of the parent's recorded ref. For each:
   - Verify the commit exists on the remote (`git fetch` then check). If not pushed, warn the user and do NOT stage it
   - If pushed, ask the user whether to include it in the parent update
3. Propose a commit message, ask user to confirm
4. Commit and push

### `sync` — Pull and sync everything

**charm**: `charm git pull --path <workspace>` (handles steps 1-2)

1. Pull parent and sync submodules via charm
2. For each submodule, reattach to its tracking branch **only if safe**:
   - Determine the tracking branch from `.gitmodules` (the `branch` field) or ask the user
   - Compare the submodule's current detached HEAD against the tracking branch tip
   - If they point to the same commit: safe to reattach
   - If the tracking branch is ahead: the parent ref is behind — warn the user and ask whether to reattach (which advances past the parent's recorded ref) or stay detached
   - If the tracking branch is behind: the parent expects a commit not on the branch — warn and ask the user
3. Report submodule status after sync

If a submodule has merge conflicts, stop and ask the user how to proceed.

### `update` — Pull latest in each submodule from its remote

**charm**: `charm git update --path <workspace>`

1. Pull latest from each submodule's tracked remote branch
2. Show which submodules received new commits
3. Ask if user wants to commit updated references in the parent (same as step 4 of `commit`)

If a pull results in merge conflicts, stop and ask the user how to proceed.

## Rules

- **No attribution**: Do not add `Co-Authored-By` or any author metadata to commit messages
- Always confirm before committing or pushing
- If a push fails (e.g. diverged branch), stop and ask the user
- No repo (parent or submodule) should ever be left in detached HEAD state. After any operation that detaches HEAD (e.g. `submodule update`), reattach to the tracking branch. If the tracking branch can't be determined, ask the user
- Use `/charmfix` if tests or analysis need fixing before committing
