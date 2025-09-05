#!/usr/bin/env nu

# Startup script for rocket-kit
print "🚀 Rocket Kit Flutter/Dart Development Environment"

if ("workspace" | path exists) {
    nu dartboard.nu workspace/ -s
    nu gm.nu workspace/ -s
}
