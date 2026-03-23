#!/usr/bin/env nu
print "🚀 ESCP Development Environment"
if ("workspace" | path exists) {
    charm.nu overview --path workspace
}
