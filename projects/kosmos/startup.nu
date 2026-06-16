#!/usr/bin/env nu
print "🚀 Kosmos Development Environment"
if ("workspace" | path exists) {
    glitter overview --path workspace
}
