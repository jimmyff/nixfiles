#!/usr/bin/env nu

# Startup script for rocket-kit
echo "🚀 Rocket Kit Flutter/Dart Development Environment"

# Update git repository and submodules if workspace exists
if ("workspace" | path exists) {
    echo "🔄 Updating repository and submodules..."
    nu gm.nu workspace/ -u
    nu dartboard.nu workspace/ -u
    nu dartboard.nu workspace/ -t
}
