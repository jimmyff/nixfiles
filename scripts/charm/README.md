# charm

Orchestrate Dart/Flutter super-projects — the repos with a flock of packages inside.

Named after a *charm* of hummingbirds (Dash, the Dart mascot).

## What it does

Discovers all packages in your workspace, then runs git, test, and analyze operations across the lot — in parallel, with caching, and pretty tables.

## Usage

```bash
# The full picture
charm.nu overview --path workspace          # Cached git/test/analyze + live status
charm.nu overview --path workspace --fetch  # Fetch remotes first
charm.nu recache --path workspace           # Refresh all caches
charm.nu recache --path workspace --force   # Force refresh even if recent

# Individual operations
charm.nu test --filter blink_highlight      # Run tests
charm.nu analyze                            # Run dart analyze
charm.nu git                                # Git status (fetches by default)
charm.nu git --cached                       # Git status from cache (instant)
charm.nu git diff                           # Diff summary for dirty repos
charm.nu git diff --staged                  # Staged changes only

# Raw JSON (the Go binary directly)
charm status --path workspace
charm test --path workspace --timeout 120
charm analyze --cached --path workspace
charm git --path workspace
charm get --path workspace                  # pub get all packages
charm upgrade --path workspace              # pub upgrade all packages
charm git commit-sub <path> -m "msg" --path workspace
charm git commit-parent -m "msg" --path workspace sub1 sub2
charm git pull --path workspace
charm clean                                 # Tidy old sessions
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

- **`charm`** (Go binary) — discovery, runners, git ops. JSON to stdout, logs to stderr.
- **`charm.nu`** (Nushell wrapper) — parses JSON, formats tables with styled indicators.
- **Cache** at `~/.cache/charm/cache/<workspace>/` — written on live runs, read instantly with `--cached`.

## Requirements

Go 1.21+ (build) · Nushell · Git · Dart/Flutter SDK
