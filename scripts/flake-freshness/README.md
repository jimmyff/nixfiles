# flake-freshness

![Callie & Marrie say Stay Fresh!](https://www.jimmyff.co.uk/processed_images/stay-fresh.453646a2f5f5794f.webp)

Monitor package versions across your flake's specialized nixpkgs inputs. Compare installed versions against latest available versions and identify which inputs need updating. For background information [read my blog post](https://www.jimmyff.co.uk/blog/keeping-my-nix-inputs-fresh/).

## Features

- **Multi-input tracking**: Monitor packages across different nixpkgs inputs (pkgs-ai, pkgs-dev-tools, etc.)
- **Smart caching**: 1-hour cache to avoid repeated nix eval calls
- **Flexible filtering**: Filter by input or show only packages with updates
- **Rich output**: Color-coded table showing current vs latest versions
- **Actionable summary**: Direct commands to update specific inputs

## Installation

1. Create a `freshness.toml` in your flake's root directory (or copy the example):
   ```bash
   cp freshness.example.toml freshness.toml
   ```

2. Edit `freshness.toml` to add packages you want to monitor

3. Make the script executable:
   ```bash
   chmod +x flake-freshness.nu
   ```

The script will auto-discover `freshness.toml` in your project root, or check other default locations:

- `freshness.toml` (project root - checked first)
- `~/.config/flake-freshness/freshness.toml` (user-specific)
- `scripts/flake-freshness/freshness.toml`

## Usage

```bash
# Check all packages with defaults
./flake-freshness.nu

# Specify custom flake and config
./flake-freshness.nu --flake ~/nixfiles/flake.nix --pkgs ./my-freshness.toml

# Show only packages with updates available
./flake-freshness.nu --updates-only

# Filter by specific input
./flake-freshness.nu --input pkgs-ai

# Skip cache and force fresh lookups
./flake-freshness.nu --no-cache

# Output as JSON for scripting
./flake-freshness.nu --json
```

## Configuration

The `freshness.toml` file groups packages by their nixpkgs input:

```toml
[packages]

pkgs-ai = [
    "claude-code",
    "gemini-cli"
]

pkgs-dev-tools = [
    "helix",
    "zed-editor",
    "vscode"
]
```

## Output

```
Package        Input            Current    Latest     Status
─────────────────────────────────────────────────────────────
claude-code    pkgs-ai          2.0.0      2.0.8      ⚠ update available
helix          pkgs-dev-tools   24.07      24.07      ✓ up to date
flutter        pkgs-dev-flutter 3.35.2     3.35.2     ✓ up to date

Summary:
  • 1 package(s) with updates available
  • Inputs to update: pkgs-ai

Next steps:
  nix flake lock --update-input pkgs-ai
```

## Options

| Flag             | Description                                            |
| ---------------- | ------------------------------------------------------ |
| `--flake <path>` | Path to flake.nix (default: ./flake.nix)               |
| `--pkgs <path>`  | Path to config (default: auto-discover freshness.toml) |
| `--input <name>` | Filter by specific input (e.g., pkgs-ai)               |
| `--updates-only` | Only show packages with updates available              |
| `--no-cache`     | Skip cache, force fresh lookups                        |
| `--json`         | Output as JSON                                         |
| `-h, --help`     | Show help message                                      |

## Cache

Cache files are stored in `~/.cache/flake-freshness/` with a 1-hour TTL. Use `--no-cache` to bypass.

## Author

Jimmy Forrester-Fellowes (2025)
