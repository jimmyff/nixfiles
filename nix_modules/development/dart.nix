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
    environment.systemPackages = with nixpkgs; lib.optionals pkgs.stdenv.isLinux [
      flutter
      dart
    ];

    # Platform-specific environment variables
    environment.variables = lib.mkMerge [
      # Common variables
      {
        PUB_CACHE = "${xdgCacheHome}/dart-pub";
      }
      
      # Linux: Use Nix-provided Flutter root
      (lib.mkIf pkgs.stdenv.isLinux {
        FLUTTER_ROOT = "${nixpkgs.flutter}";
      })
      
      # Darwin: Use manual Flutter installation to avoid iOS build issues
      # This avoids the read-only Nix store issue where Xcode cannot write to Flutter root
      # See: https://github.com/flutter/flutter/pull/155139
      (lib.mkIf pkgs.stdenv.isDarwin {
        FLUTTER_ROOT = "${xdgDataHome}/flutter";
      })
    ];

    # Setup Flutter cache directory and platform-specific requirements
    system.activationScripts.dartSetup = {
      text = ''
        echo "Setting up Dart/Flutter development environment..."

        # Create Dart pub cache directory (XDG compliant)
        mkdir -p ${xdgCacheHome}/dart-pub

        ${lib.optionalString pkgs.stdenv.isDarwin ''
        # Darwin: Create Flutter installation directory for manual installation
        # Flutter and Android SDK are provided by Android Studio instead of Nix on Darwin
        # This avoids iOS build issues where Xcode cannot write to read-only Flutter root
        mkdir -p ${xdgDataHome}/flutter
        ''}

        # Set ownership (don't fail if chown doesn't work)
        chown -R ${username}:${userGroup} ${xdgCacheHome}/dart-pub 2>/dev/null || echo "Warning: Could not set ownership of Dart pub cache"
        ${lib.optionalString pkgs.stdenv.isDarwin ''
        chown -R ${username}:${userGroup} ${xdgDataHome}/flutter 2>/dev/null || echo "Warning: Could not set ownership of Flutter directory"
        ''}

        echo "Dart/Flutter development environment setup complete!"
        ${lib.optionalString pkgs.stdenv.isDarwin ''
        echo "Note: On macOS, Flutter should be installed via Android Studio to avoid iOS build issues."
        ''}
      '';
      deps = ["users" "groups"];
    };
  };
}