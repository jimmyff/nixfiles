# ✨glitter

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
glittering git commit-sub --message "msg" --path workspace [--all|--staged|--files f1 --files f2] <sub>
glittering git commit-parent --message "msg" --path workspace [--all] sub1 sub2
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

## Architecture

- **`glittering`** (Go binary) — discovery, runners, git ops. JSON to stdout, logs to stderr.
- **`glitter`** (Nushell wrapper) — parses JSON, formats tables with styled indicators.
- **Cache** at `~/.cache/glitter/cache/<workspace>/` — written on live runs, read instantly with `--cached`.

## Requirements

Go 1.21+ (build) · Nushell · Git · Dart/Flutter SDK
