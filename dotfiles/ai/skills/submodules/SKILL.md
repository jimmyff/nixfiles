---
name: submodules
description: Manage git submodule workflows — status, commit, sync across repos with submodules
disable-model-invocation: true
---

# Git Submodules Management

Manage repositories containing git submodules.

## Usage

`/submodules $ARGUMENTS`

Arguments: `status`, `diff`, `commit`, `sync`, or omit to run `status` then ask the user what they'd like to do.

## glittering

Prefer glittering commands over manual git. Run `/glittering` for full command reference.

**Important:** Always use `commit-sub`/`commit-parent` (which push automatically) rather than raw `git commit`/`git push`. Raw git leaves work unpushed and parent refs out of sync.

## Commit Messages

- Imperative mood, single line, no period
- Submodule commits: describe the change (e.g. `add search endpoint`, `fix date parsing`)
- Parent repo updates: `update <name> submodule ref` or `update <name1>, <name2> submodule refs`
- Check `git log --oneline -5` in each repo to match existing style

## Commands

### `status` — Overview of all submodules

**glittering**: `glittering git --path <workspace>`

Parse the JSON output. For each submodule, check: uncommitted changes, current branch, latest commit, tracking info.

Present a summary table with columns: path, branch, dirty/clean, ahead/behind remote, ahead/behind parent ref, latest commit message.

- **Ahead/behind remote**: how far the local branch is ahead/behind its upstream (omit if no upstream)
- **Ahead/behind parent ref**: how the submodule HEAD compares to the ref recorded in the parent's index — report if the submodule has commits beyond what the parent expects

### `diff` — Show changes across all submodules

**glittering**: `glittering git diff --path <workspace>` (add `--staged` for staged only)

Returns JSON with per-repo entries containing: staged/unstaged changed files (path, status M/A/D/R, insertions, deletions), untracked files, aggregate stats, and a `details_file` path to a `.patch` file with the full unified diff. Clean repos are omitted.

Read `.patch` detail files selectively to inspect full diffs for specific repos. Useful for reviewing work-in-progress across the project without committing.

### `commit` — Commit and push dirty submodules, then update parent

**glittering**: Use `git commit-sub` for each dirty submodule, then `git commit-parent` to update the parent refs.

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

Run `glittering analyze --path <workspace>` on the packages being committed. If there are errors, warn the user before proceeding.

**4. Commit dirty submodules**

1. Stage appropriate files in each dirty submodule using `--files` for selective staging (prefer `--files` over `--all`). If a submodule has a mix of unrelated changes, group them into separate commits with different `--files` lists
2. Present all proposed commit messages together in a single summary for the user to review, confirm, or adjust (avoid per-submodule back-and-forth when multiple are dirty)
3. Commit and push each submodule to its remote tracking branch

**5. Update parent repository**

1. Stage **only** the submodule references that were committed and pushed in step 3 (use `--all` to include other tracked parent changes alongside submodule refs)
2. Check if any **other** submodules have HEADs ahead of the parent's recorded ref. For each:
   - Verify the commit exists on the remote (`git fetch` then check). If not pushed, warn the user and do NOT stage it
   - If pushed, ask the user whether to include it in the parent update
3. Propose a commit message, ask user to confirm
4. Commit and push

### `sync` — Pull and sync everything

**glittering**: `glittering git pull --path <workspace>`

`glittering git pull` handles the full sync workflow:
1. Pull parent repo
2. Init any new submodules (without resetting existing ones)
3. Checkout each submodule's tracking branch and pull latest

Submodules with uncommitted changes are skipped with a warning.

After sync, run `glittering git --path <workspace>` to verify state. If any submodules show ahead of parent ref, the remote had commits the parent hasn't recorded yet — use `commit` to update parent refs if needed.

If a pull results in merge conflicts, stop and ask the user how to proceed.

### `verify` — Check everything is committed and pushed

**glittering**: `glittering git check --path <workspace>`

Run after committing to verify the workspace is fully committed, pushed, and parent refs are up-to-date. Clean output means safe to switch machines. Use `--cached` for an instant check against the last fetched data.

## Rules

- **No attribution**: Do not add `Co-Authored-By` or any author metadata to commit messages
- Always confirm before committing or pushing
- If a push fails (e.g. diverged branch), stop and ask the user
- No repo (parent or submodule) should ever be left in detached HEAD state. After any operation that detaches HEAD (e.g. `submodule update`), reattach to the tracking branch. If the tracking branch can't be determined, ask the user
- Use `/glitterfix` if tests or analysis need fixing before committing
