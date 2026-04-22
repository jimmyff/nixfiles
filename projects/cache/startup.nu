#!/usr/bin/env nu
print "📝 Cache Development Environment"
if ("workspace" | path exists) {
    glitter overview --path workspace
}
