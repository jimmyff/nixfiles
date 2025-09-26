{ inputs, pkgs, lib, username, ... }:
{
  imports = [
    # development environment
    ../../nix_modules/development
  ];

  networking.hostName = "jimmyff-mpb14";

  # Development environment configuration
  development = {
    enable = true;
    projects = [ "jimmyff-website" "rocket-kit" "osdn" "jotter" ];
  };

  # Platform-specific development tools
  android.enable = true;
  dart.enable = true;
  xcode.enable = true;
  rust.enable = true;

  # Applications
  signal.enable = true;
  raycast.enable = true;
  google-chrome.enable = true;
  playwright.enable = true;
}