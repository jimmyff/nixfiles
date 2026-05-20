#!/usr/bin/env nu
print "📚 Libram Development Environment"
if ("workspace" | path exists) {
    glitter overview --path workspace
}
