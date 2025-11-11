# Platform-agnostic Dart/Flutter development environment
# Imports platform-specific configuration based on system type
#
# Architecture:
# - Darwin (macOS): Uses writable Flutter at ~/.local/share/flutter (iOS-compatible)
# - Linux: Uses read-only Flutter from Nix store (works fine for Android/Linux)
#
# Both platforms:
# - Use same Flutter version (pinned via pkgs-dev-flutter input)
# - Share PUB_CACHE and other cache directories
# - Expose identical environment variables to projects
#
# This allows project flakes to be platform-agnostic while the system
# handles all platform-specific complexity.
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
  # Pinned independently from main nixpkgs for stability
  # Historical context:
  # - Flutter 3.35.x had Android build failures in nixpkgs
  # - Issues: #443842, #436427, #260278 (Gradle plugin write attempts to read-only store)
  # - Now using pkgs-dev-flutter input to pin Flutter version

  # Import platform-specific configuration
  platformConfig =
    if pkgs-dev-flutter.stdenv.isDarwin
    then import ./dart-darwin.nix {inherit pkgs-dev-flutter lib username;}
    else import ./dart-linux.nix {inherit pkgs-dev-flutter lib username;};
in {
  options.dart = {
    enable = lib.mkEnableOption "Dart and Flutter development environment";
  };

  # Conditionally enable platform-specific configuration
  config = lib.mkIf cfg.enable platformConfig;
}
