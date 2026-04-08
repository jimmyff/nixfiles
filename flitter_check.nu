# flitter.nu: Flutter Hot Reloader
#
# Author: Jimmy Forrester-Fellowes (2025)
#
# A Nushell script for Flutter development with hot reloading.
# Watches .dart files and sends hot reload signals.

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
    print $