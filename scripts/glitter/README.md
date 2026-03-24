# ✨glitter

Orchestrate Dart/Flutter super-projects — the repos with a flock of packages inside.

Named after a *glittering* of hummingbirds (Dash, the Dart mascot).

## What it does

Discovers all packages in your workspace, then runs git, test, and analyze operations across the lot — in parallel, with caching, and pretty tables.

## Usage

```bash
# The full picture
glitter overview --path workspace          # Cached git/test/analyze + live status
glitter overview --path workspace --fetch  # Fetch remotes first
glitter recache --path workspace           # Refresh all caches
glitter recache --path workspace --force   # Force refresh even if recent

# Individual operations
glitter test --filter blink_highlight      # Run tests
glitter analyze                            # Run dart analyze
glitter git                                # Git status (fetches by default)
glitter git --cached                       # Git status from cache (instant)
glitter git check                          # Verify committed, pushed, refs in sync
glitter git check --cached                 # Check from cached data (instant)
glitter git push                           # Push all repos with unpushed commits
glitter git diff                           # Diff summary for dirty repos
glitter git diff --staged                  # Staged changes only

# Raw JSON (the Go binary directly)
glittering status --path workspace
glittering test --path workspace --timeout 120
glittering analyze --cached --path workspace
glittering git --path workspace
glittering git check --path workspace            # verify state (JSON)
glittering git push --path workspace             # push all unpushed repos (JSON)
glittering get --path workspace                  # pub get all packages
glittering upgrade --path workspace              # pub upgrade all packages
glittering git commit-sub <path> -m "msg" --path workspace
glittering git commit-parent -m "msg" --path workspace sub1 sub2
glittering git pull --path workspace
glittering clean                                 # Tidy old sessions
```

## Example output

```
Packages: 26 (17 flutter, 9 dart, 26 testable)

╭────┬─────────────────────┬────────────┬──────────┬─────────╮
│  # │       package       │    git     │  tests   │ analyze │
├────┼─────────────────────┼────────────┼──────────┼─────────┤
│  0 │ workspace           │ main       │ ✓ 4      │ ✓       │
│  1 │ editor ●            │ main ↑· ↓· │ ✓ 42     │ ✓       │
│  2 │ blink_filesystem    │ main ↑1 ↓· │ ✗ 3      │ 2e 1w   │
│  3 │ notes               │ main ↑· ↓· │ ✓ 18     │ 3i      │
╰────┴─────────────────────┴────────────┴──────────┴─────────╯
Git 7min ago · Tests 2hr ago · Analysis 2hr ago
```

**Indicators:** `●` dirty · `↑N` ahead · `↓N` behind · `·` zero · test/analyze failures in red

## Architecture

- **`glittering`** (Go binary) — discovery, runners, git ops. JSON to stdout, logs to stderr.
- **`glitter`** (Nushell wrapper) — parses JSON, formats tables with styled indicators.
- **Cache** at `~/.cache/glitter/cache/<workspace>/` — written on live runs, read instantly with `--cached`.

## Requirements

Go 1.21+ (build) · Nushell · Git · Dart/Flutter SDK
