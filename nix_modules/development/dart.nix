{
  inputs,
  pkgs-dev-flutter,
  lib,
  config,
  username,
  ...
}: let
  cfg = config.dart;

  # Use nixpkgs-dev-flutter for Flutter/Dart packages
  # Note: Previously used Flutter 3.32.8 instead of latest (3.35.x) due to Android build issues
  # Flutter 3.35.x had unresolved Android build failures in nixpkgs:
  # - nixpkgs#443842: "Could not create service of type OutputFilesRepository"
  # - nixpkgs#436427: Unable to build apk
  # - nixpkgs#260278: Flutter gradle plugin attempts to write to read-only nix store
  # Now using pkgs-dev-flutter input which can be pinned independently for stability

  # Cross-platform home directory
  homeDir =
    if pkgs-dev-flutter.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  # XDG paths
  xdgCacheHome =
    if pkgs-dev-flutter.stdenv.isDarwin
    then "${homeDir}/.cache"
    else "${homeDir}/.cache";

  xdgDataHome =
    if pkgs-dev-flutter.stdenv.isDarwin
    then "${homeDir}/.local/share"
    else "${homeDir}/.local/share";

  # Cross-platform user group
  userGroup =
    if pkgs-dev-flutter.stdenv.isDarwin
    then "staff"
    else "users";
in {
  options.dart = {
    enable = lib.mkEnableOption "Dart and Flutter development environment";
  };

  config = lib.mkIf cfg.enable {
    # Platform-specific Flutter and Dart installation
    # On Linux: Use Nix packages for reproducible builds
    # On Darwin: Use manual installation to avoid iOS build issues
    environment.systemPackages = with pkgs-dev-flutter; [
      flutter
      dart
      zulu17 # JDK 17 for Android development (compatible with Flutter/Gradle)
    ];

    # Platform-specific environment variables
    environment.variables = {
      # Common variables
      PUB_CACHE = "${xdgCacheHome}/dart-pub";

      # Use Nix-provided Flutter root
      # Note: This may cause iOS build issues on Darwin where Xcode cannot write to Flutter root
      # See: https://github.com/flutter/flutter/pull/155139
      FLUTTER_ROOT = "${pkgs-dev-flutter.flutter}";

      # Set JAVA_HOME to JDK 17 for Flutter compatibility
      JAVA_HOME = "${pkgs-dev-flutter.zulu17}";

      # Fix for Flutter Gradle plugin read-only store issue
      # See: https://github.com/NixOS/nixpkgs/issues/260278
      FLUTTER_GRADLE_PLUGIN_BUILDDIR = "${xdgCacheHome}/flutter-gradle-plugin";
    };

    # Setup Flutter cache directory and JDK configuration
    system.activationScripts.dartSetup = {
      text = ''

        # Create Dart pub cache directory (XDG compliant)
        mkdir -p ${xdgCacheHome}/dart-pub

        # Create Flutter Gradle plugin build directory (XDG compliant)
        mkdir -p ${xdgCacheHome}/flutter-gradle-plugin

        # Set ownership (don't fail if chown doesn't work)
        chown -R ${username}:${userGroup} ${xdgCacheHome}/dart-pub 2>/dev/null || echo "⚠️  Warning: Could not set ownership of Dart pub cache"
        chown -R ${username}:${userGroup} ${xdgCacheHome}/flutter-gradle-plugin 2>/dev/null || echo "⚠️  Warning: Could not set ownership of Flutter Gradle plugin cache"

        # Configure Flutter to use Nix JDK 17 (run as user, not root)
        sudo -u ${username} ${pkgs-dev-flutter.flutter}/bin/flutter config --jdk-dir="${pkgs-dev-flutter.zulu17}" 2>/dev/null || echo "⚠️  Warning: Could not configure Flutter JDK"

        echo "🎯 Activated Dart/Flutter development environment"
        ${lib.optionalString pkgs-dev-flutter.stdenv.isDarwin ''
          echo "📱 Note: iOS builds may have issues due to read-only Nix store. See: https://github.com/flutter/flutter/pull/155139"
        ''}
      '';
      deps = ["users" "groups"];
    };
  };
}
