#!/usr/bin/env nu
print "🚀 Rocketware Workspace"
if ("workspace" | path exists) {
    print $"Workspace: (ls workspace | length) items"
}
