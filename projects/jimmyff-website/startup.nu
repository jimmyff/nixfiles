#!/usr/bin/env nu
print "🌐 jimmyff-website Development Environment"
if ("workspace" | path exists) {
    glitter overview --path workspace
}

if ("workspace/config.toml" | path exists) {
    print "📡 To start the development server, run:"
    print "   cd workspace && zola serve"
    print "   Your site will be available at http://127.0.0.1:1111"
} else {
    print "❌ No config.toml found in workspace/. Make sure the repository is cloned."
    print "💡 Try running 'dev-setup' to clone the repository."
}
