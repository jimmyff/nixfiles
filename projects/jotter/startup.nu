#!/usr/bin/env nu
print "📝 Jotter Development Environment"
if ("workspace" | path exists) {
    charm.nu overview --path workspace
}
