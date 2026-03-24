#!/usr/bin/env nu
print "🚀 ESCP Development Environment"
if ("workspace" | path exists) {
    glitter overview --path workspace
}
