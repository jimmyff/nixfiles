# ✨glittering

> *glittering* (n.) — a flock of hummingbirds. See also: [Dash](https://docs.flutter.dev/dash).

Multi-package orchestrator for Dart/Flutter workspaces — git, test, analyze, and stats across parent repos and submodules, in parallel, with caching.

## Usage

```bash
glitter overview --path workspace            # Combined dashboard (git + cached test/analyze/stats)
glitter overview --path workspace --refresh # Refresh all caches first

glitter test --filter blink_highlight       # Run tests
glitter analyze                             # Run dart analyze
glitter stats                               # File/line counts, oversized detection
glitter git                                # Git status (fetches by default)
glitter git --cached                       # Git status from cache (instant)
glitter git check                          # Verify committed, pushed, refs in sync
glitter git push                           # Push all repos with unpushed commits
glitter git diff                           # Diff summary for dirty repos

glitter worktree list                       # All worktrees + status (removable flag)
glitter worktree add <name>                 # Create worktree (submodules, cache seed, pub get)
glitter worktree remove <name>              # Remove a worktree (safety-gated)
glitter worktree prune                      # Reap merged-and-pushed worktrees
```

### JSON output (`glittering`)

```bash
glittering status --path workspace
glittering test --path workspace --timeout 120
glittering analyze --cached --path workspace
glittering stats --path workspace [--threshold 200]
glittering git --path workspace [--filter name]
glittering git check --path workspace [--filter name]
glittering git push --path workspace [--filter name]
glittering get --path workspace                  # pub get all packages
glittering upgrade --path workspace              # pub upgrade all packages
glittering git diff --path workspace [--filter name]
glittering git commit <sub>... --message "msg" --path workspace [--all|--staged|--files f] [--parent-files f]
glittering git commit --parent-only --path workspace             # bump out-of-sync submodule refs
glittering git commit --parent-only -f <file> -m "msg" --path workspace  # commit parent-repo files only
glittering git pull --path workspace [--filter name]
glittering clean                                 # Tidy old sessions
```

## Example output

```
Packages: 26 (17 flutter, 9 dart, 26 testable)

╭────┬─────────────────────┬────────────┬──────────┬─────────┬──────────────╮
│  # │       package       │    git     │  tests   │ analyze │    stats     │
├────┼─────────────────────┼────────────┼──────────┼─────────┼──────────────┤
│  0 │ workspace           │ main       │ ✓ 4      │ ✓       │ 1k · 12f     │
│  1 │ editor ●            │ main ↑· ↓· │ ✓ 42     │ ✓       │ 6k · 30f     │
│  2 │ blink_filesystem    │ main ↑1 ↓· │ ✗ 3      │ 2e 1w   │ 1k · 8f      │
│  3 │ notes               │ main ↑· ↓· │ ✓ 18     │ 3i      │ 18k · 85f 2XL│
╰────┴─────────────────────┴────────────┴──────────┴─────────┴──────────────╯
Git 7min ago · Tests 2hr ago · Analysis 2hr ago · Stats 2hr ago
```

**Indicators:** `●` dirty · `↑N` ahead · `↓N` behind · `·` zero · failures in red · `XL` oversized files

## Worktrees

For projects in a bare-repo + worktree layout (`<proj>/.bare` + `<proj>/main`, `<proj>/<feature>`…):

```bash
glittering worktree list --path <proj>             # JSON: per-worktree status + `removable`
glittering worktree add <name> --path <proj>       # existing branch else off base; inits submodules
                                                   #   (object-shared via --reference --dissociate,
                                                   #   parallel), seeds test/analyze/stats cache, pub get
glittering worktree remove <name> --path <proj>    # refuses base/current/dirty/unpushed; --force overrides
glittering worktree prune --path <proj>            # remove merged+pushed worktrees (--dry-run)
glittering worktree path <name> --path <proj>      # print absolute path (plain text, for cd)
```

`add` makes a fresh worktree usable fast: submodule objects copied from the base worktree (self-contained, no network re-download of objects), slow test/analyze/stats caches seeded, `pub get` run. `--no-get` / `--no-share-objects` opt out.

## Architecture

- **`glittering`** (Go binary) — discovery, runners, git ops. JSON to stdout, logs to stderr.
- **`glitter`** (Nushell wrapper, convenience alias) — parses JSON, formats tables with styled indicators.
- **Cache** at `~/.cache/glittering/cache/<workspace>/` — written on live runs, read instantly with `--cached`.

## Requirements

Go 1.21+ (build) · Nushell · Git · Dart/Flutter SDK
