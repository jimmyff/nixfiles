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
    projects = [ "jimmyff-website" "rocket-kit" "osdn" ];
  };

  # Platform-specific development tools
  android.enable = true;
  xcode.enable = true;

  # Applications
  signal.enable = true;
  raycast.enable = true;
  google-chrome.enable = true;
}