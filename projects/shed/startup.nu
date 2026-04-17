#!/usr/bin/env nu
print "🏚️ Shed Tinkering Space"
if ("workspace" | path exists) {
    print $"Workspace: (ls workspace | length) items"
}
