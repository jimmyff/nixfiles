# Darwin-specific Flutter/Dart configuration
# Uses writable Flutter SDK at ~/.local/share/flutter to support iOS builds
{
  pkgs-dev-flutter,
  lib,
  username,
  ...
}: let
  homeDir = "/Users/${username}";
  xdgCacheHome = "${homeDir}/.cache";
  xdgDataHome = "${homeDir}/.local/share";
  flutterRoot = "${xdgDataHome}/flutter";

  # Create wrapper scripts that point to the writable Flutter installation
  # This ensures they're in PATH and found before any Nix store versions
  flutterWrapper = pkgs-dev-flutter.writeShellScriptBin "flutter" ''
    if [ -x "${flutterRoot}/bin/flutter" ]; then
      exec "${flutterRoot}/bin/flutter" "$@"
    else
      echo "⚠️  Flutter not found at ${flutterRoot}"
      echo "Run 'sudo darwin-rebuild switch' to set up writable Flutter SDK"
      exit 1
    fi
  '';

  dartWrapper = pkgs-dev-flutter.writeShellScriptBin "dart" ''
    if [ -x "${flutterRoot}/bin/dart" ]; then
      exec "${flutterRoot}/bin/dart" "$@"
    elif [ -x "${flutterRoot}/bin/cache/dart-sdk/bin/dart" ]; then
      exec "${flutterRoot}/bin/cache/dart-sdk/bin/dart" "$@"
    else
      echo "⚠️  Dart not found at ${flutterRoot}"
      echo "Run 'sudo darwin-rebuild switch' to set up writable Flutter SDK"
      exit 1
    fi
  '';
in {
  # Platform-specific Flutter and Dart installation
  # Use wrapper scripts that point to the writable Flutter SDK
  environment.systemPackages = [
    flutterWrapper
    dartWrapper
    pkgs-dev-flutter.zulu17 # JDK 17 for Android development
  ];

  # Darwin-specific environment variables
  environment.variables = {
    # Use writable Flutter installation for iOS compatibility
    # This allows Xcode to write to the Flutter SDK directory
    FLUTTER_ROOT = flutterRoot;

    # Set JAVA_HOME to JDK 17 for Flutter compatibility
    JAVA_HOME = "${pkgs-dev-flutter.zulu17}";

    # Common cache directories (XDG compliant)
    PUB_CACHE = "${xdgCacheHome}/dart-pub";
    FLUTTER_GRADLE_PLUGIN_BUILDDIR = "${xdgCacheHome}/flutter-gradle-plugin";
  };

  # Setup writable Flutter SDK and cache directories
  system.activationScripts.dartSetupDarwin = {
    text = ''
      # Get the Flutter version from Nix package
      NIX_FLUTTER="${pkgs-dev-flutter.flutter}"
      FLUTTER_VERSION=$($NIX_FLUTTER/bin/flutter --version --machine 2>/dev/null | grep -o '"frameworkVersion":"[^"]*"' | cut -d'"' -f4 || echo "unknown")

      # Create writable Flutter SDK directory if it doesn't exist
      if [ ! -d "${flutterRoot}" ]; then
        echo "🔧 Setting up writable Flutter SDK at ${flutterRoot}..."
        sudo -u ${username} mkdir -p ${xdgDataHome}

        # Clone Flutter at the same version as Nix provides
        sudo -u ${username} git clone https://github.com/flutter/flutter.git ${flutterRoot} 2>/dev/null || echo "⚠️  Warning: Could not clone Flutter repository"

        # Checkout the same version as Nix
        if [ "$FLUTTER_VERSION" != "unknown" ]; then
          cd ${flutterRoot} && sudo -u ${username} git checkout "$FLUTTER_VERSION" 2>/dev/null || echo "⚠️  Warning: Could not checkout Flutter version $FLUTTER_VERSION"
        fi
      fi

      # Ensure Flutter SDK is up to date with Nix version
      if [ -d "${flutterRoot}" ]; then
        CURRENT_VERSION=$(cd ${flutterRoot} && git describe --tags 2>/dev/null || echo "unknown")
        if [ "$CURRENT_VERSION" != "$FLUTTER_VERSION" ] && [ "$FLUTTER_VERSION" != "unknown" ]; then
          echo "🔄 Updating Flutter SDK to match Nix version: $FLUTTER_VERSION"
          cd ${flutterRoot} && sudo -u ${username} git fetch --all 2>/dev/null
          cd ${flutterRoot} && sudo -u ${username} git checkout "$FLUTTER_VERSION" 2>/dev/null || echo "⚠️  Warning: Could not update Flutter version"
        fi
      fi

      # Create cache directories (XDG compliant)
      mkdir -p ${xdgCacheHome}/dart-pub
      mkdir -p ${xdgCacheHome}/flutter-gradle-plugin

      # Set ownership
      chown -R ${username}:staff ${xdgCacheHome}/dart-pub 2>/dev/null || echo "⚠️  Warning: Could not set ownership of Dart pub cache"
      chown -R ${username}:staff ${xdgCacheHome}/flutter-gradle-plugin 2>/dev/null || echo "⚠️  Warning: Could not set ownership of Flutter Gradle plugin cache"
      chown -R ${username}:staff ${flutterRoot} 2>/dev/null || echo "⚠️  Warning: Could not set ownership of Flutter SDK"

      # Configure Flutter to use Nix JDK 17
      if [ -d "${flutterRoot}" ]; then
        sudo -u ${username} ${flutterRoot}/bin/flutter config --jdk-dir="${pkgs-dev-flutter.zulu17}" 2>/dev/null || echo "⚠️  Warning: Could not configure Flutter JDK"
      fi

      echo "🎯 Activated Dart/Flutter development environment (macOS)"
      echo "📱 Flutter SDK: ${flutterRoot} (writable, iOS-compatible)"
    '';
    deps = ["users" "groups"];
  };
}
