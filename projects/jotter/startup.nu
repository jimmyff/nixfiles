#!/usr/bin/env nu
print "📝 Jotter Development Environment"
if ("workspace" | path exists) {
    glitter overview --path workspace
}
