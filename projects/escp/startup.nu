#!/usr/bin/env nu

# Startup script for ESCP
print "🚀 ESCP Development Environment"

if ("workspace" | path exists) {
    nu dartboard.nu workspace/ -s
    nu gm.nu workspace/ -s
}
