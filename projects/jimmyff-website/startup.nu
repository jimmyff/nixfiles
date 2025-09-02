#!/usr/bin/env nu

# Startup script for jimmyff-website
echo "🌐 Starting Zola development server..."

# Check if we're in the workspace directory
if not ("workspace/config.toml" | path exists) {
    echo "❌ No config.toml found in workspace/. Make sure the repository is cloned."
    echo "💡 Try running 'dev-setup' to clone the repository."
    exit 1
}

# Change to workspace directory and start zola serve
echo "📡 Running 'zola serve' in workspace/ - your site will be available at http://127.0.0.1:1111"
echo "   Press Ctrl+C to stop the server"
echo ""

# Change to workspace directory and run zola serve
cd workspace
zola serve