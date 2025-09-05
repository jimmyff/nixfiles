# dartboard.nu: A script to manage Flutter/Dart projects with pubspec.yaml files
#
# Author: Jimmy Forrester-Fellowes (2025)
#
# A powerful Nushell script for managing Flutter and Dart projects. Provides an 
# intuitive interface for running pub get, pub upgrade, and tests across multiple
# projects in a directory tree.

# ============================================================================
# Configuration & Constants
# ============================================================================
const CONFIG = {
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
        processing: "🎯",
        success: "✨",
        dart: "🎯",
        flutter: "📱"
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

# Execute command with comprehensive error handling
def run-safe [command: list, path: string = ".", description: string = "Operation"] {
    try {
        let result = do { cd $path; ^$command.0 ...($command | skip 1) }
        return { success: true, output: $result, path: $path }
    } catch { |err|
        let error_msg = if ("msg" in $err) { $err.msg } else { "Unknown error" }
        return { success: false, error: $error_msg, path: $path }
    }
}

# ============================================================================
# Core Functions
# ============================================================================

# Find all pubspec.yaml files using fd
def find-projects [path: string = "."] {
    try {
        let pubspec_files = fd "pubspec.yaml" $path --type f | lines
        $pubspec_files | each { |file|
            let project_dir = ($file | path dirname)
            $project_dir
        } | sort
    } catch {
        print ($CONFIG.colors.error + $CONFIG.icons.warning + " Failed to find projects using fd" + $CONFIG.colors.reset)
        []
    }
}

# Parse pubspec.yaml to extract project info
def parse-pubspec [project_path: string] {
    try {
        let pubspec_path = ($project_path | path join "pubspec.yaml")
        let pubspec_content = open $pubspec_path
        
        let name = if "name" in $pubspec_content { 
            $pubspec_content.name 
        } else { 
            ($project_path | path basename) 
        }
        
        let description = if "description" in $pubspec_content { 
            $pubspec_content.description | str substring 0..50
        } else { 
            "" 
        }
        
        # Count dependencies
        let dep_count = if "dependencies" in $pubspec_content {
            ($pubspec_content.dependencies | columns | length)
        } else {
            0
        }
        
        let dev_dep_count = if "dev_dependencies" in $pubspec_content {
            ($pubspec_content.dev_dependencies | columns | length)
        } else {
            0
        }
        
        # Determine project type
        let has_flutter = if "dependencies" in $pubspec_content {
            "flutter" in ($pubspec_content.dependencies | columns)
        } else {
            false
        }
        
        let project_type = if $has_flutter { "Flutter" } else { "Dart" }
        let icon = if $has_flutter { $CONFIG.icons.flutter } else { $CONFIG.icons.dart }
        
        {
            name: $name,
            path: $project_path,
            type: $project_type,
            icon: $icon,
            description: $description,
            dependencies: $dep_count,
            dev_dependencies: $dev_dep_count,
            total_dependencies: ($dep_count + $dev_dep_count)
        }
    } catch { |err|
        {
            name: ($project_path | path basename),
            path: $project_path,
            type: "Unknown",
            icon: "❓",
            description: "Failed to parse pubspec.yaml",
            dependencies: 0,
            dev_dependencies: 0,
            total_dependencies: 0,
            error: true
        }
    }
}

# Display projects in a formatted table
def display-projects [projects: list, title: string = "Dart/Flutter Projects"] {
    print-header $title $CONFIG.icons.processing
    
    if ($projects | is-empty) {
        print ($CONFIG.colors.warning + "No projects found with pubspec.yaml files" + $CONFIG.colors.reset)
        return
    }
    
    let total_count = ($projects | length)
    let flutter_count = ($projects | where type == "Flutter" | length)
    let dart_count = ($projects | where type == "Dart" | length)
    
    let summary = $"Found: ($total_count) projects | Flutter: ($flutter_count) | Dart: ($dart_count)"
    print ($CONFIG.colors.info + $summary + $CONFIG.colors.reset)
    print ""
    
    # Create display table
    let display_rows = $projects | enumerate | each { |item|
        let project = $item.item
        let index = $item.index
        
        let name_display = $CONFIG.colors.primary + $project.icon + " " + $project.name + $CONFIG.colors.reset
        let type_display = if $project.type == "Flutter" {
            $CONFIG.colors.accent + $project.type + $CONFIG.colors.reset
        } else {
            $CONFIG.colors.info + $project.type + $CONFIG.colors.reset
        }
        
        {
            "#": $index,
            "Project": $name_display,
            "Type": $type_display,
            "Deps": $project.total_dependencies,
            "Path": ($project.path | str replace $env.HOME "~")
        }
    }
    
    print ($display_rows | table --expand)
}

# Execute operation on all projects with progress tracking
def run-operation [projects: list, operation: string] {
    let total = ($projects | length)
    let operation_name = match $operation {
        "get" => "pub get",
        "upgrade" => "pub upgrade", 
        "test" => "test",
        _ => $operation
    }
    
    print-header $"Running flutter ($operation_name) on all projects" $CONFIG.icons.processing
    
    $projects | enumerate | each { |item|
        let project = $item.item
        let index = ($item.index + 1)
        
        print ($CONFIG.colors.primary + $"  [($index)/($total)] " + $project.icon + " " + $project.name + $CONFIG.colors.reset)
        
        let command = ["flutter" $"pub" $operation]
        let result = run-safe $command $project.path $"flutter pub ($operation)"
        
        if $result.success {
            print ($CONFIG.colors.success + "    ✓ Success" + $CONFIG.colors.reset)
            {
                project: $project.name,
                path: $project.path,
                status: "success",
                message: ""
            }
        } else {
            print ($CONFIG.colors.error + "    ✗ Failed: " + $result.error + $CONFIG.colors.reset)
            {
                project: $project.name,
                path: $project.path,
                status: "error",
                message: $result.error
            }
        }
    }
}

# Display operation results in a formatted table
def display-results [results: list, operation: string] {
    print-header $"Operation Results: flutter pub ($operation)" $CONFIG.icons.success
    
    let success_count = ($results | where status == "success" | length)
    let error_count = ($results | where status == "error" | length)
    let total_count = ($results | length)
    
    let summary = $"Total: ($total_count) | Success: ($success_count) | Errors: ($error_count)"
    print ($CONFIG.colors.info + $summary + $CONFIG.colors.reset)
    print ""
    
    # Create results table
    let display_rows = $results | each { |result|
        let status_display = if $result.status == "success" {
            $CONFIG.colors.success + $CONFIG.icons.clean + " SUCCESS" + $CONFIG.colors.reset
        } else {
            $CONFIG.colors.error + $CONFIG.icons.dirty + " FAILED" + $CONFIG.colors.reset
        }
        
        let message_display = if $result.status == "error" {
            ($result.message | str substring 0..60)
        } else {
            ""
        }
        
        {
            "Project": ($CONFIG.colors.primary + $result.project + $CONFIG.colors.reset),
            "Status": $status_display,
            "Message": $message_display
        }
    }
    
    print ($display_rows | table --expand)
    
    if $error_count > 0 {
        print ""
        print ($CONFIG.colors.warning + "Some operations failed. Check the messages above for details." + $CONFIG.colors.reset)
    }
}

# ============================================================================
# Main Function
# ============================================================================

# The main function with CLI argument support
def main [
    path: string = "."         # Path to search for projects (defaults to current directory)
    --update(-u)               # Run flutter pub get on all projects
    --upgrade(-U)              # Run flutter pub upgrade on all projects  
    --test(-t)                 # Run flutter test on all projects
    --status(-s)               # Just show the project table and exit
] {
    print-header "Dart/Flutter Project Manager" $CONFIG.icons.dart
    
    # Discover projects
    let project_paths = find-projects $path
    
    if ($project_paths | is-empty) {
        print ($CONFIG.colors.warning + "No projects found with pubspec.yaml files in " + $path + $CONFIG.colors.reset)
        return
    }
    
    # Parse project information
    let projects = $project_paths | each { |project_path|
        parse-pubspec $project_path
    }
    
    # Display projects
    display-projects $projects
    
    # Handle command line flags
    if $status {
        return
    }
    
    if $update {
        let results = run-operation $projects "get"
        display-results $results "get"
        return
    }
    
    if $upgrade {
        let results = run-operation $projects "upgrade"
        display-results $results "upgrade"
        return
    }
    
    if $test {
        let results = run-operation $projects "test"
        display-results $results "test"
        return
    }
    
    # Interactive mode
    print ""
    print ($CONFIG.colors.info + "What do you want to do? " + $CONFIG.colors.primary + "(u)" + $CONFIG.colors.reset + "pdate, " + $CONFIG.colors.primary + "(U)" + $CONFIG.colors.reset + "pgrade, " + $CONFIG.colors.primary + "(t)" + $CONFIG.colors.reset + "est")
    let choice = input ": "
    
    match $choice {
        "u" => {
            let results = run-operation $projects "get"
            display-results $results "get"
        },
        "U" => {
            let results = run-operation $projects "upgrade"
            display-results $results "upgrade"
        },
        "t" => {
            let results = run-operation $projects "test"
            display-results $results "test"
        },
        _ => {
            print ($CONFIG.colors.info + "No action taken" + $CONFIG.colors.reset)
        }
    }
}