#!/usr/bin/env nu
print "🚀 OSDN Development Environment"
if ("workspace" | path exists) {
    charm.nu overview --path workspace
}
