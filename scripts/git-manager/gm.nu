# gm.nu: A script to manage git repositories with (or without) submodules
#
# Author: Jimmy Forrester-Fellowes (2025)
#
# A powerful Nushell script for managing Git repositories with or without
# submodules. Provides an intuitive interface for checking status, updating
# repositories, and committing changes across your entire repository ecosystem.

# ============================================================================
# Configuration & Constants
# ============================================================================
const CONFIG = {
    default_branch: "main",
    colors: {
        primary: (ansi cyan),
        success: (ansi green),
        warning: (ansi yellow),
        error: (ansi red),
        info: (ansi blue),
        accent: (ansi magenta),
        reset: (ansi reset)
    },
    icons: {
        clean: "✅",
        dirty: "❌",
        updated: "🔄",
        warning: "⚠️",
        processing: "🔄",
        success: "✨"
    },
    separators: {
        main: "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
        sub: "────────────────────────────────────────",
        thin: "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
    }
}

# ============================================================================
# Utility Functions
# ============================================================================

# Print a formatted separator line
def print-separator [type: string = "sub"] {
    let sep = match $type {
        "main" => $CONFIG.separators.main,
        "sub" => $CONFIG.separators.sub,
        "thin" => $CONFIG.separators.thin,
        _ => $CONFIG.separators.sub
    }
    print ($CONFIG.colors.accent + $sep + $CONFIG.colors.reset)
}

# Print a section header with styling
def print-header [text: string, icon: string = ""] {
    let header = if ($icon | is-empty) {
        $text
    } else {
        $icon + " " + $text
    }
    print ""
    print ($CONFIG.colors.info + $header + $CONFIG.colors.reset)
    print-separator "thin"
}

# Check if git repository is clean
def is-git-clean [path: string = "."] {
    let status = if $path == "." {
        git status --porcelain
    } else {
        git -C $path status --porcelain
    }
    $status | is-empty
}

# Get filtered git status (excluding submodules with modified content)
def get-main-project-files [path: string = "."] {
    # Get git status and filter out submodule entries (they contain "(modified content)")
    let status = if $path == "." {
        git status --porcelain
    } else {
        git -C $path status --porcelain
    }
    $status | lines | where $it !~ "\\(modified content\\)" | each { |line|
        $line | str substring 3..
    } | where $it != ""
}

# Execute git command with comprehensive error handling
def git-safe [command: list, path: string = ".", description: string = "Git operation"] {
    try {
        let result = if $path == "." {
            ^git ...$command
        } else {
            ^git -C $path ...$command
        }
        return { success: true, output: $result }
    } catch { |err|
        print ($CONFIG.colors.error + $CONFIG.icons.warning + " Failed: " + $description + $CONFIG.colors.reset)
        let error_msg = if ("msg" in $err) { $err.msg } else { "Unknown error" }
        print ($CONFIG.colors.error + "Error: " + $error_msg + $CONFIG.colors.reset)
        return { success: false, error: $error_msg }
    }
}

# Get a list of all submodule paths
def get-submodules [path: string = "."] {
    try {
        let submodule_output = if $path == "." {
            git submodule
        } else {
            git -C $path submodule
        }
        $submodule_output | lines | each { |line|
            let parts = ($line | str trim | split row ' ')
            if ($parts | length) >= 2 {
                $parts | get 1
            } else {
                null
            }
        } | compact
    } catch {
        print ($CONFIG.colors.error + $CONFIG.icons.warning + " Failed to get submodules list" + $CONFIG.colors.reset)
        []
    }
}

# ============================================================================
# Core Operations
# ============================================================================

# Update main repository and all submodules with progress indication
def submodule-update [submodules: list, path: string = ".", --dry-run] {
    if $dry_run {
        print-header "Would update:" $CONFIG.icons.processing
        print ($CONFIG.colors.accent + "  → 📁 Main Repository" + $CONFIG.colors.reset)
        $submodules | each { |submodule_path|
            print ($CONFIG.colors.primary + "  → 📦 " + $submodule_path + $CONFIG.colors.reset)
        }
        return
    }

    print-header "Updating repository and submodules" $CONFIG.icons.processing
    let total = ($submodules | length) + 1

    # Update main repository first
    print ($CONFIG.colors.accent + $"  [1/($total)] Updating main repository..." + $CONFIG.colors.reset)
    let main_result = git-safe ["pull" "origin" $CONFIG.default_branch] $path "Update main repository"
    if $main_result.success {
        print ($CONFIG.colors.success + "    ✓ Main repository updated" + $CONFIG.colors.reset)
    }

    # Update submodules
    $submodules | enumerate | each { |item|
        let submodule_path = $item.item
        let index = $item.index + 2  # +2 because main repo is index 1

        print ($CONFIG.colors.primary + $"  [($index)/($total)] Updating " + $submodule_path + "..." + $CONFIG.colors.reset)

        # Construct full path for submodule
        let full_submodule_path = if $path == "." {
            $submodule_path
        } else {
            $path + "/" + $submodule_path
        }
        let result = git-safe ["pull" "origin" $CONFIG.default_branch] $full_submodule_path $"Update $submodule_path"
        if $result.success {
            print ($CONFIG.colors.success + "    ✓ Successfully updated" + $CONFIG.colors.reset)
        }
    }
}

# Handle main project changes (excluding submodules)
def commit-main-project [path: string = "."] {
    let main_files = get-main-project-files $path

    if ($main_files | is-empty) {
        return
    }

    print-header "Main project changes" $CONFIG.icons.dirty

    # Show clean table of changed files
    let changed_files = $main_files | enumerate | each { |item|
        {
            "File": ($CONFIG.colors.primary + $item.item + $CONFIG.colors.reset)
        }
    }
    print ($changed_files | table --expand)
    print-separator

    let commit_message = input "Enter commit message for main project changes (leave empty to skip): "

    if not ($commit_message | is-empty) {
        mut all_added = true
        for file in $main_files {
            let result = git-safe ["add" $file] $path $"Add $file"
            if not $result.success {
                $all_added = false
            }
        }

        if $all_added {
            let commit_result = git-safe ["commit" "-m" $commit_message] $path "Commit main project changes"
            if $commit_result.success {
                let push_result = git-safe ["push"] $path "Push main project changes"
                if $push_result.success {
                    print ($CONFIG.colors.success + $CONFIG.icons.success + " Main project changes committed successfully" + $CONFIG.colors.reset)
                }
            }
        }
    } else {
        print ($CONFIG.colors.warning + "Skipping main project commit" + $CONFIG.colors.reset)
    }
}

# Handle dirty submodule commits (only processes submodules with uncommitted changes)
def commit-dirty-submodules [status: table, path: string = ".", --dry-run] {
    let dirty_submodules = $status | where status == "dirty" | get path

    if ($dirty_submodules | is-empty) {
        print ($CONFIG.colors.info + "No dirty submodules to commit" + $CONFIG.colors.reset)
        return []
    }

    if $dry_run {
        print-header "Would commit the following dirty submodules:" $CONFIG.icons.warning
        $dirty_submodules | each { |path|
            print ($CONFIG.colors.warning + "  → " + $path + $CONFIG.colors.reset)
        }
        return $dirty_submodules
    }

    # Process each submodule and collect successful commits
    let committed_results = $dirty_submodules | each { |submodule_path|
        print-header $"Processing ($submodule_path)" $CONFIG.icons.processing
        print-separator

        # Construct full path for submodule
        let full_submodule_path = if $path == "." {
            $submodule_path
        } else {
            $path + "/" + $submodule_path
        }
        git -C $full_submodule_path status
        print-separator

        let commit_message = input "Enter commit message for the changes (leave empty to skip): "

        if not ($commit_message | is-empty) {
            let commit_result = git-safe ["commit" "-a" "-m" $commit_message] $full_submodule_path $"Commit changes in $submodule_path"
            if $commit_result.success {
                let push_result = git-safe ["push" "--set-upstream" "origin" "HEAD"] $full_submodule_path $"Push changes in $submodule_path"
                if $push_result.success {
                    print ($CONFIG.colors.success + $CONFIG.icons.success + $" Successfully committed and pushed $submodule_path" + $CONFIG.colors.reset)
                    { path: $submodule_path, committed: true }
                } else {
                    { path: $submodule_path, committed: false }
                }
            } else {
                { path: $submodule_path, committed: false }
            }
        } else {
            print ($CONFIG.colors.warning + $"Skipping " + $CONFIG.colors.primary + $submodule_path + $CONFIG.colors.reset)
            { path: $submodule_path, committed: false }
        }
    }

    # Return only successfully committed paths
    $committed_results | where committed == true | get path
}

# Handle parent repository submodule updates
def commit-parent-updates [committed_submodules: list, path: string = ".", --dry-run] {
    if ($committed_submodules | is-empty) {
        return
    }

    if $dry_run {
        print-header "Would commit parent repository with updated submodules:" $CONFIG.icons.processing
        $committed_submodules | each { |submodule_path|
            print ($CONFIG.colors.primary + "  → " + $submodule_path + $CONFIG.colors.reset)
        }
        return
    }

    print-header "Parent repository status after submodule commits" $CONFIG.icons.processing
    print-separator
    if $path == "." {
        git status
    } else {
        git -C $path status
    }
    print-separator

    let parent_commit_message = input "Enter commit message for the parent repository: "
    if not ($parent_commit_message | is-empty) {
        mut all_staged = true
        for submodule_path in $committed_submodules {
            let result = git-safe ["add" $submodule_path] $path $"Stage $submodule_path updates"
            if not $result.success {
                $all_staged = false
            }
        }

        if $all_staged {
            let commit_result = git-safe ["commit" "-m" $parent_commit_message] $path "Commit parent repository updates"
            if $commit_result.success {
                let push_result = git-safe ["push"] $path "Push parent repository updates"
                if $push_result.success {
                    print ($CONFIG.colors.success + $CONFIG.icons.success + " Parent repository updated successfully" + $CONFIG.colors.reset)
                }
            }
        }
    } else {
        print ($CONFIG.colors.warning + "Skipping parent repository commit" + $CONFIG.colors.reset)
    }
}

# Main commit workflow combining all commit operations
def submodule-commit [status: table, path: string = ".", --dry-run] {
    # Always handle main project changes first (even if no dirty submodules)
    commit-main-project $path

    # Handle dirty submodules
    let committed_submodules = commit-dirty-submodules $status $path --dry-run=$dry_run

    # Handle parent repository updates (only if submodules were committed)
    if not ($committed_submodules | is-empty) {
        commit-parent-updates $committed_submodules $path --dry-run=$dry_run
    }
}

# Get status of all submodules with error handling (three-state: clean/dirty/updated)
def get-status [submodules: list, path: string = "."] {
    # Get parent repository status to detect submodules with new commits
    let parent_status = try {
        if $path == "." {
            git status --porcelain | lines
        } else {
            git -C $path status --porcelain | lines
        }
    } catch {
        []
    }

    $submodules | each { |submodule_path|
        try {
            # Check internal submodule status - need to construct full path
            let full_submodule_path = if $path == "." {
                $submodule_path
            } else {
                $path + "/" + $submodule_path
            }
            let internal_status = (git -C $full_submodule_path status --porcelain)
            let has_internal_changes = (not ($internal_status | is-empty))

            # Check if parent sees this submodule as modified
            let parent_sees_modified = ($parent_status | any { |line|
                ($line | str contains $submodule_path) and (($line | str contains "(new commits)") or ($line | str starts-with " M "))
            })

            # Determine status based on both checks
            let status = if $has_internal_changes {
                "dirty"
            } else if $parent_sees_modified {
                "updated"
            } else {
                "clean"
            }

            {
                path: $submodule_path,
                status: $status,
                error: false
            }
        } catch {
            print ($CONFIG.colors.error + $CONFIG.icons.warning + $" Failed to get status for $submodule_path" + $CONFIG.colors.reset)
            {
                path: $submodule_path,
                status: "clean",
                error: true
            }
        }
    }
}

# Display status in a formatted table with enhanced styling
def display-status [status: table, title: string = "Repository Status", path: string = "."] {
    print-header $title $CONFIG.icons.processing

    # Get main project status
    let main_clean = is-git-clean $path
    let main_status_info = if $main_clean {
        $CONFIG.colors.success + $CONFIG.icons.clean + " CLEAN" + $CONFIG.colors.reset
    } else {
        $CONFIG.colors.error + $CONFIG.icons.dirty + " DIRTY" + $CONFIG.colors.reset
    }

    # Create main project row
    let main_row = {
        "Repository": ($CONFIG.colors.accent + "📁 Main Project" + $CONFIG.colors.reset),
        "Status": $main_status_info
    }

    # Calculate summary stats for three-state system
    let submodule_clean_count = ($status | where status == "clean" and error == false | length)
    let submodule_dirty_count = ($status | where status == "dirty" | length)
    let submodule_updated_count = ($status | where status == "updated" | length)
    let submodule_error_count = ($status | where error == true | length)
    let submodule_total = ($status | length)
    let main_clean_count = if $main_clean { 1 } else { 0 }
    let main_dirty_count = if $main_clean { 0 } else { 1 }

    let total_clean = $main_clean_count + $submodule_clean_count
    let total_dirty = $main_dirty_count + $submodule_dirty_count
    let total_updated = $submodule_updated_count
    let total_items = 1 + $submodule_total

    # Build summary with three states
    let summary = $"Total: ($total_items) | Clean: ($total_clean) | Dirty: ($total_dirty) | Updated: ($total_updated)"
    let summary_with_errors = if $submodule_error_count > 0 {
        $summary + $" | Errors: ($submodule_error_count)"
    } else {
        $summary
    }
    print ($CONFIG.colors.info + $summary_with_errors + $CONFIG.colors.reset)
    print ""

    # Create submodule rows with three-state display
    let submodule_rows = $status | each { |row|
        let status_info = if $row.error {
            $CONFIG.colors.error + $CONFIG.icons.warning + " ERROR" + $CONFIG.colors.reset
        } else if $row.status == "dirty" {
            $CONFIG.colors.error + $CONFIG.icons.dirty + " DIRTY" + $CONFIG.colors.reset
        } else if $row.status == "updated" {
            $CONFIG.colors.warning + $CONFIG.icons.updated + " UPDATED" + $CONFIG.colors.reset
        } else {
            $CONFIG.colors.success + $CONFIG.icons.clean + " CLEAN" + $CONFIG.colors.reset
        }

        {
            "Repository": ($CONFIG.colors.primary + "📦 " + $row.path + $CONFIG.colors.reset),
            "Status": $status_info
        }
    }

    # Combine main project and submodules in one table
    let all_rows = [$main_row] | append $submodule_rows
    print ($all_rows | table --expand)
}

# ============================================================================
# Main Function
# ============================================================================

# Confirm destructive operations
def confirm-operation [message: string] {
    let response = input ($CONFIG.colors.warning + $message + " (y/N): " + $CONFIG.colors.reset)
    ($response | str downcase) == "y"
}

# The main function with enhanced features
def main [
    path: string = "."  # Path to the repository (defaults to current directory)
    --status-only(-s)  # Just show the status and exit
    --update(-u)       # Automatically update all submodules
    --dry-run(-d)      # Show what would be done without executing
    --force(-f)        # Skip confirmation prompts
] {
    print-header "Git Submodule Manager" $CONFIG.icons.processing

    let submodules = get-submodules $path

    if ($submodules | is-empty) {
        print ($CONFIG.colors.info + "Repository has no submodules - operating on main repository only" + $CONFIG.colors.reset)
    }

    # Handle auto-update mode
    if $update {
        let status = get-status $submodules $path
        display-status $status "Current Status" $path

        # Check if main project is dirty
        let main_clean = is-git-clean $path

        # Check if any submodules have uncommitted changes
        let dirty_submodules = $status | where status == "dirty"

        if (not $main_clean) or (not ($dirty_submodules | is-empty)) {
            if not $main_clean {
                print ($CONFIG.colors.error + $CONFIG.icons.warning + " Main project has untracked changes. Please commit or stash them before updating." + $CONFIG.colors.reset)
            }
            if (not ($dirty_submodules | is-empty)) {
                print ($CONFIG.colors.error + $CONFIG.icons.warning + " Some submodules have untracked changes. Please commit or stash them before updating." + $CONFIG.colors.reset)
            }
            return
        }

        if $dry_run {
            submodule-update $submodules $path --dry-run
            print ($CONFIG.colors.info + "Dry run completed. Use --update without --dry-run to execute." + $CONFIG.colors.reset)
            return
        }


        submodule-update $submodules $path

        # Check if there are any changes to commit after updating
        let post_update_status = is-git-clean $path
        if not $post_update_status {
            # Commit submodule updates to parent repo
            print-header "Committing submodule updates" $CONFIG.icons.success
            let add_command = ["add"] | append $submodules
            let stage_result = git-safe $add_command $path "Stage submodule updates"
            if $stage_result.success {
                let commit_result = git-safe ["commit" "-m" "Update submodules"] $path "Commit submodule updates"
                if $commit_result.success {
                    let push_result = git-safe ["push"] $path "Push submodule updates"
                    if $push_result.success {
                        print ($CONFIG.colors.success + $CONFIG.icons.success + " All submodules updated and committed successfully!" + $CONFIG.colors.reset)
                    }
                }
            }
        } else {
            print ($CONFIG.colors.success + $CONFIG.icons.success + " All submodules updated successfully - no changes to commit!" + $CONFIG.colors.reset)
        }
        return
    }

    # Show status
    let status = get-status $submodules $path
    display-status $status "Repository Status" $path

    if $status_only {
        return
    }

    # Interactive mode
    print ""
    print ($CONFIG.colors.info + "What do you want to do? " + $CONFIG.colors.primary + "(u)" + $CONFIG.colors.reset + "pdate, " + $CONFIG.colors.primary + "(c)" + $CONFIG.colors.reset + "ommit dirty")
    let choice = input ": "

    match $choice {
        "u" => {
            if $dry_run {
                submodule-update $submodules $path --dry-run
            } else {
                submodule-update $submodules $path
                display-status (get-status $submodules $path) "Final Submodule Status" $path
            }
        },
        "c" => {
            submodule-commit $status $path --dry-run=$dry_run
        },
        _ => {
            print ($CONFIG.colors.info + "No action taken" + $CONFIG.colors.reset)
        }
    }
}
