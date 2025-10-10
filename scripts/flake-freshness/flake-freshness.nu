#!/usr/bin/env nu
# flake-freshness.nu: Monitor package versions across nixpkgs inputs
#
# Author: Jimmy Forrester-Fellowes (2025)
#
# A Nushell script for tracking package versions across your flake's specialized
# nixpkgs inputs. Compares installed versions against latest available versions
# and highlights which inputs need updating.

# ============================================================================
# Configuration & Constants
# ============================================================================
const CONFIG = {
    colors: {
        outdated_bg: (ansi red_bold),
        latest_bg: (ansi green_bold),
        equal: (ansi green),
        warning: (ansi yellow),
        error: (ansi red),
        info: (ansi blue),
        accent: (ansi cyan),
        reset: (ansi reset)
    },
    cache: {
        ttl: 3600  # 1 hour in seconds
    },
    defaults: {
        flake: "flake.nix"
    }
}

# Runtime paths that depend on environment
def get_cache_dir [] {
    $env.HOME | path join ".cache" "flake-freshness"
}

def get_default_package_paths [] {
    [
        "freshness.toml",
        ($env.HOME | path join ".config" "flake-freshness" "freshness.toml"),
        "scripts/flake-freshness/freshness.toml"
    ]
}

# Detect current system architecture
def get_current_system [] {
    nix eval --impure --expr 'builtins.currentSystem' --raw
    | complete
    | get stdout
    | str trim
}

# ============================================================================
# Helper Functions
# ============================================================================



# Find packages config file
def find_packages_config [override?: string] {
    if $override != null and $override != "" {
        if ($override | path exists) {
            return $override
        } else {
            error make {msg: $"Packages config not found: ($override)"}
        }
    }

    for path in (get_default_package_paths) {
        if ($path | path exists) {
            return $path
        }
    }

    error make {msg: "No config found. Create freshness.toml in your project root or ~/.config/flake-freshness/freshness.toml"}
}

# Extract nixpkgs input info from flake
def extract_input_info [flake_path: string] {
    let content = (open $flake_path | str trim)
    let flake_dir = ($flake_path | path dirname)

    # Extract branches from flake.nix
    let branches = ($content
        | lines
        | where {|line| $line =~ 'pkgs-.*\.url\s*=\s*"github:nixos/nixpkgs/'}
        | each {|line|
            let parts = ($line | parse -r 'pkgs-(?<input>[^.]+)\.url\s*=\s*"github:nixos/nixpkgs/(?<branch>[^"]+)"')
            if ($parts | is-empty) { null } else {
                {
                    input: $"pkgs-($parts.0.input)",
                    branch: $parts.0.branch
                }
            }
        }
        | where $it != null
    )

    # Get locked revisions from flake metadata
    let result = (nix flake metadata --json $flake_dir | complete)

    if $result.exit_code != 0 {
        print $"($CONFIG.colors.error)Error getting flake metadata: ($result.stderr)($CONFIG.colors.reset)"
        return {}
    }

    let metadata = ($result.stdout | from json)

    # Combine branch and locked info
    $branches | each {|b|
        let locked = ($metadata | get -o locks.nodes | get -o $b.input | get -o locked)
        let locked_rev = if $locked != null {
            $locked | get -o rev
        } else {
            null
        }

        {
            input: $b.input,
            branch: $b.branch,
            locked_rev: $locked_rev
        }
    } | reduce -f {} {|it, acc|
        $acc | insert $it.input {branch: $it.branch, locked_rev: $it.locked_rev}
    }
}

# Load packages from TOML config
def load_packages [config_path: string] {
    let config = (open $config_path)

    if "packages" not-in $config {
        error make {msg: "freshness.toml must contain a [packages] section"}
    }

    # New format: pkgs-ai = ["claude-code", "gemini-cli"]
    # Transform to list of {package, input} records
    $config.packages
    | transpose input packages
    | each {|row|
        $row.packages | each {|pkg|
            {package: $pkg, input: $row.input}
        }
    }
    | flatten
}

# Get cache file path for a specific key
def get_cache_path [key: string] {
    # Replace problematic characters in key
    let safe_key = ($key | str replace -a '/' '_' | str replace -a ':' '_')
    (get_cache_dir) | path join $"($safe_key).json"
}

# Check if cache is valid
def is_cache_valid [cache_path: string] {
    if not ($cache_path | path exists) {
        return false
    }

    let cache_time = (ls $cache_path | get modified | first)
    let now = (date now)
    let age = ($now - $cache_time | into int) / 1_000_000_000  # Convert to seconds

    $age < $CONFIG.cache.ttl
}

# Read from cache
def read_cache [key: string] {
    let cache_path = (get_cache_path $key)

    if (is_cache_valid $cache_path) {
        open $cache_path
    } else {
        null
    }
}

# Write to cache
def write_cache [key: string, value: any] {
    mkdir (get_cache_dir)
    let cache_path = (get_cache_path $key)
    $value | save -f $cache_path
}

# Get package version from nix eval
def get_package_version [flake_ref: string, input: string, package: string, use_cache: bool] {
    let cache_key = $"($flake_ref)-($input)-($package)"

    if $use_cache {
        let cached = (read_cache $cache_key)
        if $cached != null {
            return $cached
        }
    }

    # Try to get version
    let result = (
        do -i {
            nix eval $"($flake_ref)#($input).($package).version" --raw
            | complete
        }
    )

    let version = if $result.exit_code == 0 {
        $result.stdout | str trim
    } else {
        "not found"
    }

    if $use_cache and $version != "not found" {
        write_cache $cache_key $version
    }

    $version
}

# Compare two version strings
def compare_versions [current: string, latest: string] {
    if $current == "not found" or $latest == "not found" {
        return "unknown"
    }

    if $current == $latest {
        return "equal"
    } else {
        return "outdated"
    }
}

# Format version with color
def format_version [version: string, status: string] {
    match $status {
        "outdated" => { $"($CONFIG.colors.outdated_bg)($version)($CONFIG.colors.reset)" },
        "equal" => { $"($CONFIG.colors.equal)($version)($CONFIG.colors.reset)" },
        _ => { $version }
    }
}

# ============================================================================
# Main Logic
# ============================================================================

# Monitor package versions across nixpkgs inputs
def main [
    --flake: string = "flake.nix"  # Path to flake.nix
    --pkgs: string                  # Path to freshness.toml config
    --input: string                 # Filter by specific input (e.g., pkgs-ai)
    --updates-only                  # Only show packages with updates available
    --no-cache                      # Skip cache, force fresh lookups
    --json                          # Output as JSON
] {
    # Validate flake exists
    if not ($flake | path exists) {
        print $"($CONFIG.colors.error)Error: flake.nix not found at ($flake)($CONFIG.colors.reset)"
        return
    }

    # Find and load packages config
    let pkgs_config = (find_packages_config $pkgs)
    print $"($CONFIG.colors.info)Loading packages from: ($pkgs_config)($CONFIG.colors.reset)"

    let packages = (load_packages $pkgs_config)

    # Extract input info from flake
    print $"($CONFIG.colors.info)Extracting inputs from: ($flake)($CONFIG.colors.reset)"
    let input_info = (extract_input_info $flake)

    # Filter by input if specified
    let filtered_packages = if $input != null {
        $packages | where input == $input
    } else {
        $packages
    }

    if ($filtered_packages | is-empty) {
        print $"($CONFIG.colors.warning)No packages found to check($CONFIG.colors.reset)"
        return
    }

    print $"($CONFIG.colors.info)Checking ($filtered_packages | length) packages...($CONFIG.colors.reset)\n"

    # Get flake directory for current versions
    let flake_dir = ($flake | path dirname)

    # Detect current system architecture
    let system = (get_current_system)

    # Check each package
    let use_cache = (not $no_cache)
    let results = ($filtered_packages | each {|pkg|
        let info = ($input_info | get -o $pkg.input)

        if $info == null {
            print $"($CONFIG.colors.warning)Warning: No info found for input ($pkg.input)($CONFIG.colors.reset)"
            return null
        }

        print $"  Checking ($pkg.package) from ($pkg.input)..."

        # Get current version from locked revision
        let current = if $info.locked_rev != null {
            get_package_version $"github:nixos/nixpkgs/($info.locked_rev)" $"legacyPackages.($system)" $pkg.package $use_cache
        } else {
            "no lock"
        }

        # Get latest version from upstream branch
        let latest = (get_package_version $"github:nixos/nixpkgs/($info.branch)" $"legacyPackages.($system)" $pkg.package $use_cache)

        let status = (compare_versions $current $latest)

        {
            package: $pkg.package,
            input: $pkg.input,
            branch: $info.branch,
            current: $current,
            latest: $latest,
            status: $status
        }
    } | where $it != null)

    # Filter results if updates-only
    let display_results = if $updates_only {
        $results | where status == "outdated"
    } else {
        $results
    }

    # Output results
    if $json {
        $display_results | to json
        return
    }

    # Display table
    print "\n"
    let table_data = ($display_results | each {|row|
        {
            package: $row.package,
            input: $row.input,
            current: (format_version $row.current $row.status),
            latest: (if $row.status == "outdated" {
                $"($CONFIG.colors.latest_bg)($row.latest)($CONFIG.colors.reset)"
            } else {
                $row.latest
            }),
            status: (match $row.status {
                "equal" => { $"($CONFIG.colors.equal)✓ up to date($CONFIG.colors.reset)" },
                "outdated" => { $"($CONFIG.colors.warning)⚠ update available($CONFIG.colors.reset)" },
                _ => { "?" }
            })
        }
    })

    print ($table_data | table -e)

    # Summary
    let outdated = ($results | where status == "outdated")
    let outdated_count = ($outdated | length)

    if $outdated_count > 0 {
        print $"\n($CONFIG.colors.accent)Summary:($CONFIG.colors.reset)"
        print $"  • ($outdated_count) packages with updates available"

        let inputs_to_update = ($outdated | get input | uniq)
        print $"  • Inputs to update: ($inputs_to_update | str join ', ')"

        print $"\n($CONFIG.colors.info)Next steps:($CONFIG.colors.reset)"
        $inputs_to_update | each {|inp|
            print $"  nix flake lock --update-input ($inp)"
        } | ignore
    } else {
        print $"\n($CONFIG.colors.equal)✓ All packages are up to date!($CONFIG.colors.reset)"
    }
}
