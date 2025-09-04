#!/usr/bin/env nu

# Startup script for rocket-kit
echo "🚀 Rocket Kit Flutter/Dart Development Environment"

# Update git repository and submodules if workspace exists
if ("workspace" | path exists) {
    echo "🔄 Updating repository and submodules..."
    nu gm.nu workspace/ -u
}

# Check if we're in a Flutter project workspace
if ("workspace/pubspec.yaml" | path exists) {
    echo "📦 Found pubspec.yaml in workspace/ - this looks like a Flutter/Dart project!"
    
    # Change to workspace directory for operations
    cd workspace
    
    # Check if dependencies are installed
    if not ("pubspec.lock" | path exists) {
        echo "📥 Installing dependencies..."
        flutter pub get
    } else {
        echo "✅ Dependencies already installed"
    }
    
    # Return to project root
    cd ..
    
    # Show available commands
    echo ""
    echo "🛠️  Common commands (run from workspace/ directory):"
    echo "   cd workspace && flutter run         - Run the app"
    echo "   cd workspace && flutter test        - Run tests"
    echo "   cd workspace && flutter build       - Build the app"
    echo "   cd workspace && dart analyze        - Analyze code"
    echo "   cd workspace && dart format .       - Format code"
    
} else {
    echo "ℹ️  No pubspec.yaml found in workspace/. Make sure the repository is cloned."
    echo "💡 Try running 'dev-setup' to clone the repository."
    echo "   Or create a new Flutter project: cd workspace && flutter create <project_name>"
}

echo ""