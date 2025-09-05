#!/usr/bin/env nu

# Startup script for jimmyff-website
print "🌐 jimmyff-website Development Environment"

# Show git repository and submodules status if workspace exists
if ("workspace" | path exists) {
    print "📊 Repository status:"
    nu gm.nu workspace/ -s
}

# Prompt user to run zola serve manually
if ("workspace/config.toml" | path exists) {
    print "📡 To start the development server, run:"
    print "   cd workspace && zola serve"
    print "   Your site will be available at http://127.0.0.1:1111"
} else {
    print "❌ No config.toml found in workspace/. Make sure the repository is cloned."
    print "💡 Try running 'dev-setup' to clone the repository."
}
