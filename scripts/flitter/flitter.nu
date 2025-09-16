# flitter.nu: Flutter Hot Reloader with Optional Doppler Integration
#
# Author: Jimmy Forrester-Fellowes (2025)
#
# A Nushell script for Flutter development with hot reloading and optional
# Doppler secrets management. Watches .dart files and sends hot reload signals.

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
        flutter: "📱",
        hot_reload: "🔥",
        watching: "👀",
        doppler: "🔐",
        success: "✨",
        error: "❌",
        warning: "⚠️"
    },
    separators: {
        main: "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
        sub: "────────────────────────────────────────"
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
        _ => $CONFIG.separators.sub
    }
    print ($CONFIG.colors.accent + $sep + $CONFIG.colors.reset)
}

# Print a formatted header
def print-header [title: string, icon: string] {
    print-separator "main"
    print ($CONFIG.colors.primary + $icon + " " + $title + $CONFIG.colors.reset)
    print-separator "main"
}

# Print an error message and exit
def error-exit [message: string] {
    print ($CONFIG.colors.error + $CONFIG.icons.error + " Error: " + $message + $CONFIG.colors.reset)
    exit 1
}

# Print a warning message
def print-warning [message: string] {
    print ($CONFIG.colors.warning + $CONFIG.icons.warning + " Warning: " + $message + $CONFIG.colors.reset)
}

# Print a success message
def print-success [message: string] {
    print ($CONFIG.colors.success + $CONFIG.icons.success + " " + $message + $CONFIG.colors.reset)
}

# Print an info message
def print-info [message: string] {
    print ($CONFIG.colors.info + $CONFIG.icons.watching + " " + $message + $CONFIG.colors.reset)
}

# Generate a unique session ID
def generate-session-id [] {
    date now | format date "%Y%m%d_%H%M%S"
}

# Check if required tools are available
def check-prerequisites [] {
    # Check Flutter
    if (which flutter | is-empty) {
        error-exit "Flutter CLI not found. Please install Flutter SDK."
    }
    
    # Check entr
    if (which entr | is-empty) {
        error-exit "entr command not found. Please install entr for file watching."
    }
}

# Check if Doppler is available when needed
def check-doppler [] {
    if (which doppler | is-empty) {
        error-exit "Doppler CLI not found. Please install Doppler CLI when using --doppler-project."
    }
}


# Start Flutter with hot reload watching
def start-flutter-with-hot-reload [path: string, session_id: string, command: string, doppler_project: string, flutter_args: list<string>] {
    let pid_file = $"/tmp/flutter-($session_id).pid"
    
    # Check if lib directory exists
    let lib_path = ($path | path join "lib")
    if not ($lib_path | path exists) {
        error-exit $"No lib/ directory found in ($path). Are you in a Flutter project?"
    }
    
    print-info $"Starting Flutter in ($path)"
    print-info $"Session ID: ($session_id)"
    print-info $"PID file: ($pid_file)"
    
    # Show what command will be executed
    if ($doppler_project | is-not-empty) {
        print-info $"Will run: doppler run --project ($doppler_project) -- flutter ($command) (($flutter_args | str join ' ')) --pid-file ($pid_file)"
    } else {
        print-info $"Will run: flutter ($command) (($flutter_args | str join ' ')) --pid-file ($pid_file)"
    }
    
    # Setup cleanup on exit
    $env.FLITTER_PID_FILE = $pid_file
    
    # Change to project directory
    cd $path
    
    print-info "Starting Flutter process..."
    print-separator "sub"
    
    # Start Flutter in background using nushell job control
    if ($doppler_project | is-not-empty) {
        print-info "Starting Flutter with Doppler environment in background..."
        # Use bash to properly background the process
        ^bash -c $"doppler run --project ($doppler_project) -- flutter ($command) (($flutter_args | str join ' ')) --pid-file ($pid_file) &"
    } else {
        print-info "Starting Flutter in background..."
        # Use bash to properly background the process
        ^bash -c $"flutter ($command) (($flutter_args | str join ' ')) --pid-file ($pid_file) &"
    }
    
    print-info "Flutter process started in background, continuing to watcher setup..."
    
    # Wait for Flutter to start and create PID file
    print-info "Waiting for Flutter to create PID file..."
    mut wait_count = 0
    while not ($pid_file | path exists) and $wait_count < 120 {
        if ($wait_count mod 10) == 0 {  # Only show every 10 seconds to reduce spam
            print-info $"Waiting for PID file... (($wait_count + 1)/120)"
        }
        sleep 1sec
        $wait_count = $wait_count + 1
    }
    
    if not ($pid_file | path exists) {
        print-warning $"PID file not found at: ($pid_file)"
        print-info "Checking for any Flutter PID files in /tmp..."
        try {
            ^ls -la /tmp/flutter-*.pid
        } catch {
            print-info "No Flutter PID files found"
        }
        print-info "Checking if Flutter process is running..."
        try {
            ^ps aux | ^grep flutter | ^grep -v grep
        } catch {
            print-info "No Flutter processes found"
        }
        error-exit "Flutter failed to start - PID file not created"
    } else {
        print-success $"PID file found: ($pid_file)"
        let pid_content = (open $pid_file | str trim)
        print-info $"PID file contains: ($pid_content)"
    }
    
    print-success "Flutter started! Setting up hot reload watcher..."
    print-info "Watching for changes in lib/*.dart"
    print-info "Press Ctrl+C to stop"
    print-separator "sub"
    
    # Verify we can find dart files before starting the watcher
    let dart_files = try {
        ^find lib -name "*.dart" | lines
    } catch {
        []
    }
    if ($dart_files | length) == 0 {
        print-warning "No .dart files found in lib/ directory"
    } else {
        print-info $"Found ($dart_files | length) .dart files to monitor"
    }
    
    # Hot reload loop using the proven pattern from flutter_hotreloader
    # Build shell command with comprehensive debugging
    # Build shell script avoiding nushell parsing issues
    # Create a working hot reload command using single line with proper escaping
    # CRITICAL: Use $"..." (double quotes) NOT $'...' (single quotes) for variable expansion!
    # - $'...' = raw string literal - nushell does NOT expand ($variable) inside
    # - $"..." = interpolated string - nushell DOES expand ($variable) inside
    # This is why we were getting 'cat: ($pid_file): No such file or directory' errors
    # Read PID in nushell first to avoid shell parsing issues
    let flutter_pid = if ($pid_file | path exists) { 
        open $pid_file | str trim 
    } else { 
        "" 
    }
    
    let simple_reload_cmd = $"echo '🔥 File change detected'; if [ -f ($pid_file) ]; then PID=($flutter_pid); echo '📋 Hot reload signal sent to:' \$PID; if kill -0 \$PID 2>/dev/null; then kill -USR1 \$PID && echo \"($CONFIG.colors.success)($CONFIG.icons.hot_reload) Hot reload triggered($CONFIG.colors.reset)\" || echo \"($CONFIG.colors.error)❌ Signal failed($CONFIG.colors.reset)\"; else echo \"($CONFIG.colors.error)❌ Flutter process \$PID is no longer running($CONFIG.colors.reset)\"; rm ($pid_file); fi; else echo \"($CONFIG.colors.error)❌ PID file not found($CONFIG.colors.reset)\"; fi"
    
    print-info "Hot reload ready - save any .dart file to trigger reload"
    
    print-info "Starting file watcher loop (Ctrl+C to stop)..."
    
    # Simple approach: run entr directly and let it handle restarts
    try {
        ^find lib -name "*.dart" | ^entr -r sh -c $simple_reload_cmd
    } catch {
        print-info "Hot reload watcher stopped"
    }
}

# Cleanup function
def cleanup [] {
    print-info "Cleaning up processes and files..."
    
    # Kill Flutter process if PID file exists
    if ($env.FLITTER_PID_FILE? | is-not-empty) and ($env.FLITTER_PID_FILE | path exists) {
        let pid_content = try { open $env.FLITTER_PID_FILE | str trim } catch { "" }
        if ($pid_content | is-not-empty) {
            print-info $"Terminating Flutter process: ($pid_content)"
            try {
                ^kill $pid_content 2>/dev/null
                sleep 2sec
                # Force kill if still running
                ^kill -9 $pid_content 2>/dev/null
            } catch {
                # Process already dead
            }
        }
        print-info $"Cleaning up PID file: ($env.FLITTER_PID_FILE)"
        rm $env.FLITTER_PID_FILE
    }
    
    # Kill any background file watchers (entr processes)
    try {
        ^pkill -f "entr.*\\.dart" 2>/dev/null
    } catch {
        # Ignore errors if no processes found
    }
    
    # Kill any orphaned Flutter processes
    try {
        ^pkill -f "flutter.*run" 2>/dev/null
    } catch {
        # Ignore errors if no processes found
    }
    
    print-success "Cleanup completed"
}

# ============================================================================
# Main Function
# ============================================================================
def main [
    path: string = "."                    # Path to Flutter project (defaults to current directory)
    --doppler-project(-d): string         # Doppler project for environment variables
    --command(-c): string = "run"         # Flutter command (defaults to 'run')
    --flavor: string                      # Flutter build flavor
    --target(-t): string                  # Main entry point file
    --device-id: string                   # Target device ID
    --debug                               # Build in debug mode
    --profile                             # Build in profile mode
    --release                             # Build in release mode
    --verbose(-v)                         # Enable verbose logging
] {
    print-header "flitter.nu" $CONFIG.icons.flutter
    
    # Check prerequisites
    check-prerequisites
    
    # Resolve absolute path
    let project_path = ($path | path expand)
    
    if not ($project_path | path exists) {
        error-exit $"Path does not exist: ($project_path)"
    }
    
    # Check if Doppler integration is requested
    if ($doppler_project | is-not-empty) {
        check-doppler
    }
    
    # Build Flutter arguments array
    mut flutter_args = []
    
    if ($flavor | is-not-empty) {
        $flutter_args = ($flutter_args | append ["--flavor", $flavor])
    }
    
    if ($target | is-not-empty) {
        $flutter_args = ($flutter_args | append ["--target", $target])
    }
    
    if ($device_id | is-not-empty) {
        $flutter_args = ($flutter_args | append ["--device-id", $device_id])
    }
    
    if $debug {
        $flutter_args = ($flutter_args | append "--debug")
    }
    
    if $profile {
        $flutter_args = ($flutter_args | append "--profile")
    }
    
    if $release {
        $flutter_args = ($flutter_args | append "--release")
    }
    
    if $verbose {
        $flutter_args = ($flutter_args | append "--verbose")
    }
    
    # Generate unique session ID
    let session_id = (generate-session-id)
    
    # Store session info for cleanup
    let pid_file = $"/tmp/flutter-($session_id).pid"
    $env.FLITTER_PID_FILE = $pid_file
    
    print-info "Press Ctrl+C to stop and cleanup processes"
    
    try {
        # Start Flutter with hot reload
        start-flutter-with-hot-reload $project_path $session_id $command $doppler_project $flutter_args
    } catch {
        print-info "Script interrupted, cleaning up..."
        cleanup
        exit 0
    }
    
    # Cleanup on normal exit
    cleanup
}