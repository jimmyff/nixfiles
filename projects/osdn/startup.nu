#!/usr/bin/env nu
print "🚀 OSDN Development Environment"
if ("workspace" | path exists) {
    glitter overview --path workspace
}
