# Linux-specific Flutter/Dart configuration
# Uses Flutter from Nix store (read-only) which works fine for Android/Linux builds
{
  pkgs-dev-flutter,
  lib,
  username,
  ...
}: let
  homeDir = "/home/${username}";
  xdgCacheHome = "${homeDir}/.cache";
in {
  # Platform-specific Flutter and Dart installation from Nix store
  environment.systemPackages = with pkgs-dev-flutter; [
    flutter
    dart
    zulu17 # JDK 17 for Android development
  ];

  # Linux-specific environment variables
  environment.variables = {
    # Use Nix-provided Flutter root (read-only, works fine on Linux)
    FLUTTER_ROOT = "${pkgs-dev-flutter.flutter}";

    # Set JAVA_HOME to JDK 17 for Flutter compatibility
    JAVA_HOME = "${pkgs-dev-flutter.zulu17}";

    # Common cache directories (XDG compliant)
    PUB_CACHE = "${xdgCacheHome}/dart-pub";
    FLUTTER_GRADLE_PLUGIN_BUILDDIR = "${xdgCacheHome}/flutter-gradle-plugin";
  };

  # Setup cache directories
  system.activationScripts.dartSetupLinux = {
    text = ''
      # Create cache directories (XDG compliant)
      mkdir -p ${xdgCacheHome}/dart-pub
      mkdir -p ${xdgCacheHome}/flutter-gradle-plugin

      # Set ownership
      chown -R ${username}:users ${xdgCacheHome}/dart-pub 2>/dev/null || echo "⚠️  Warning: Could not set ownership of Dart pub cache"
      chown -R ${username}:users ${xdgCacheHome}/flutter-gradle-plugin 2>/dev/null || echo "⚠️  Warning: Could not set ownership of Flutter Gradle plugin cache"

      # Configure Flutter to use Nix JDK 17
      sudo -u ${username} ${pkgs-dev-flutter.flutter}/bin/flutter config --jdk-dir="${pkgs-dev-flutter.zulu17}" 2>/dev/null || echo "⚠️  Warning: Could not configure Flutter JDK"

      echo "🎯 Activated Dart/Flutter development environment (Linux)"
      echo "📦 Flutter SDK: ${pkgs-dev-flutter.flutter} (Nix store)"
    '';
    deps = ["users" "groups"];
  };
}
