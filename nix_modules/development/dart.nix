{
  inputs,
  pkgs,
  lib,
  config,
  username,
  ...
}: let
  cfg = config.dart;

  # Use nixpkgs Flutter for latest version (Linux only)
  # Note: nixpkgs input is already set to nixos-unstable in flake.nix
  nixpkgs = import inputs.nixpkgs {
    system = pkgs.system;
    config.allowUnfree = true;
  };

  # Cross-platform home directory
  homeDir =
    if pkgs.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  # XDG paths
  xdgCacheHome =
    if pkgs.stdenv.isDarwin
    then "${homeDir}/.cache"
    else "${homeDir}/.cache";

  xdgDataHome =
    if pkgs.stdenv.isDarwin
    then "${homeDir}/.local/share"
    else "${homeDir}/.local/share";

  # Cross-platform user group
  userGroup =
    if pkgs.stdenv.isDarwin
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
    environment.systemPackages = with nixpkgs; [
      flutter
      dart
      zulu17  # JDK 17 for Android development (compatible with Flutter/Gradle)
    ];

    # Platform-specific environment variables
    environment.variables = {
      # Common variables
      PUB_CACHE = "${xdgCacheHome}/dart-pub";
      
      # Use Nix-provided Flutter root
      # Note: This may cause iOS build issues on Darwin where Xcode cannot write to Flutter root
      # See: https://github.com/flutter/flutter/pull/155139
      FLUTTER_ROOT = "${nixpkgs.flutter}";
      
      # Set JAVA_HOME to JDK 17 for Flutter compatibility
      JAVA_HOME = "${nixpkgs.zulu17}";
    };

    # Setup Flutter cache directory and JDK configuration
    system.activationScripts.dartSetup = {
      text = ''
        echo "Setting up Dart/Flutter development environment..."

        # Create Dart pub cache directory (XDG compliant)
        mkdir -p ${xdgCacheHome}/dart-pub

        # Set ownership (don't fail if chown doesn't work)
        chown -R ${username}:${userGroup} ${xdgCacheHome}/dart-pub 2>/dev/null || echo "⚠️  Warning: Could not set ownership of Dart pub cache"

        # Configure Flutter to use Nix JDK 17 (run as user, not root)
        sudo -u ${username} ${nixpkgs.flutter}/bin/flutter config --jdk-dir="${nixpkgs.zulu17}" 2>/dev/null || echo "⚠️  Warning: Could not configure Flutter JDK"

        echo "Dart/Flutter development environment setup complete!"
        ${lib.optionalString pkgs.stdenv.isDarwin ''
        echo "📱 Note: iOS builds may have issues due to read-only Nix store. See: https://github.com/flutter/flutter/pull/155139"
        ''}
      '';
      deps = ["users" "groups"];
    };
  };
}