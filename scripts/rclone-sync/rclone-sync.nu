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
    reset: (ansi reset)
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

    let exclude_flags = ["--exclude" ".DS_Store" "--exclude" "._*" "--exclude" ".Spotlight-V100" "--exclude" ".Trashes" "--exclude" "*~lock~*"]

    let local_path = $cwd
    let remote_path = $"($remote):($rel_path)"

    let direction = if $push { "→" } else { "←" }
    let src = if $push { $local_path } else { $remote_path }
    let dst = if $push { $remote_path } else { $local_path }

    print $"($COLORS.info)Syncing: ($local_path) ($direction) ($remote_path)($COLORS.reset)"

    # Handle --skip-dry-run flag
    if $skip_dry_run {
        print ""
        rclone sync $src $dst ...$exclude_flags --progress
        print ""
        print $"($COLORS.success)Sync complete($COLORS.reset)"
        return
    }

    print ""
    print $"($COLORS.info)=== Dry Run ===($COLORS.reset)"

    # Run dry-run
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
        print ""
        print $"($COLORS.success)No changes to sync($COLORS.reset)"
        return
    }

    print ""
    let response = (input $"($COLORS.info)Proceed with sync? [y/N] ($COLORS.reset)")
    if ($response | str downcase) == "y" {
        print ""
        rclone sync $src $dst ...$exclude_flags --progress
        print ""
        print $"($COLORS.success)Sync complete($COLORS.reset)"
    }
}
