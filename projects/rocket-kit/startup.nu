#!/usr/bin/env nu
print "🚀 Rocket Kit Development Environment"
if ("workspace" | path exists) {
    glitter overview --path workspace
}
