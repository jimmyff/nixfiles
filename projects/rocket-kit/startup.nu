#!/usr/bin/env nu
print "🚀 Rocket Kit Development Environment"
if ("workspace" | path exists) {
    charm.nu overview --path workspace
}
