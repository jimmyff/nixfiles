#!/usr/bin/env nu
# rclone-sync.nu: One-way sync for rclone remotes
#
# Author: Jimmy Forrester-Fellowes (2025)
#
# Syncs folders under ~/Cloud with a remote rclone destination.
# Run from within a subfolder of ~/Cloud to sync that folder.

const COLORS = {
    info: (ansi cyan),
    success: (ansi green),
    warning: (ansi yellow),
    error: (ansi red),
    cmd: (ansi yellow_dimmed),
    reset: (ansi reset)
}

# Build displayable rclone command string
def build-cmd [src: string, dst: string, exclude_flags: list<string>, extra_flags: list<string>] {
    let excludes = ($exclude_flags | chunks 2 | each {|pair| $"($pair.0) \"($pair.1)\""} | str join " ")
    let extras = ($extra_flags | str join " ")
    $"rclone sync ($src) ($dst) ($excludes) ($extras)"
}

def main [
    remote: string = "default"  # Remote name (default: "default")
    --push                      # Sync local → cloud
    --pull                      # Sync cloud → local
    --skip-dry-run              # Skip dry run, sync immediately
] {
    let cloud_dir = ($env.HOME | path join "Cloud")
    let cwd = ($env.PWD)

    # Check we're under ~/Cloud
    if not ($cwd | str starts-with $cloud_dir) {
        print $"($COLORS.error)Error: Must be in a folder under ($cloud_dir)($COLORS.reset)"
        exit 1
    }

    # Get relative path
    let rel_path = ($cwd | str replace $"($cloud_dir)/" "")
    if $rel_path == $cwd or $rel_path == "" {
        print $"($COLORS.error)Error: Must be in a subfolder of ($cloud_dir)($COLORS.reset)"
        exit 1
    }

    # Require --push or --pull
    if not $push and not $pull {
        print $"($COLORS.error)Error: Must specify --push (local → cloud) or --pull (cloud → local)($COLORS.reset)"
        print ""
        print "Usage:"
        print "  rclone-sync --push    # Upload local changes to cloud"
        print "  rclone-sync --pull    # Download cloud changes to local"
        exit 1
    }

    if $push and $pull {
        print $"($COLORS.error)Error: Cannot specify both --push and --pull($COLORS.reset)"
        exit 1
    }

    let exclude_flags = ["--exclude" ".DS_Store" "--exclude" "._*"]

    let local_path = $cwd
    let remote_path = $"($remote):($rel_path)"

    let direction = if $push { "→" } else { "←" }
    let src = if $push { $local_path } else { $remote_path }
    let dst = if $push { $remote_path } else { $local_path }

    print $"($COLORS.info)Syncing: ($local_path) ($direction) ($remote_path)($COLORS.reset)"

    # Handle --skip-dry-run flag
    if $skip_dry_run {
        let cmd = (build-cmd $src $dst $exclude_flags ["--progress"])
        print $"\n($COLORS.cmd)$ ($cmd)($COLORS.reset)\n"
        rclone sync $src $dst ...$exclude_flags --progress
        print $"\n($COLORS.success)Sync complete($COLORS.reset)"
        return
    }

    # Dry run first
    print $"\n($COLORS.info)=== Dry Run ===($COLORS.reset)"
    let dry_cmd = (build-cmd $src $dst $exclude_flags ["--dry-run"])
    print $"($COLORS.cmd)$ ($dry_cmd)($COLORS.reset)\n"

    let result = (do -i { rclone sync $src $dst ...$exclude_flags --dry-run } | complete)
    let output = $"($result.stdout)($result.stderr)"
    print $output

    if $result.exit_code != 0 {
        print $"($COLORS.error)Dry run failed($COLORS.reset)"
        exit 1
    }

    # Check if there are no changes
    let no_changes = ($output | lines | any {|line|
        ($line | str contains "Transferred:") and (($line | str contains "0 / 0") or ($line | str contains "0 B / 0 B"))
    })
    if $no_changes {
        print $"\n($COLORS.success)No changes to sync($COLORS.reset)"
        return
    }

    # Show actual command and confirm
    let sync_cmd = (build-cmd $src $dst $exclude_flags ["--progress"])
    print $"\n($COLORS.info)Command to execute:($COLORS.reset)"
    print $"($COLORS.cmd)$ ($sync_cmd)($COLORS.reset)\n"

    let response = (input $"($COLORS.info)Proceed? [y/N] ($COLORS.reset)")
    if ($response | str downcase) == "y" {
        print ""
        rclone sync $src $dst ...$exclude_flags --progress
        print $"\n($COLORS.success)Sync complete($COLORS.reset)"
    }
}
