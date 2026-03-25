{ inputs, lib, username, ... }:
{
  imports = [
    # development environment
    ../../modules/development
  ];

  networking.hostName = "jimmyff-mbp14";

  # Development environment configuration
  development = {
    enable = true;
    projects = [ "jimmyff-website" "rocket-kit" "osdn" "jotter" "escp" ];
  };

  # Platform-specific development tools
  android.enable = true;
  dart.enable = true;
  xcode.enable = true;
  rust.enable = true;
  mitmproxy.enable = true;
  wireshark.enable = false;

  # Applications
  cinny.enable = false; # 2026-02-20: temporarily disabled, nixpkgs version mismatch (cinny 4.10.3 vs cinny-desktop 4.10.2)
  signal.enable = true;
  raycast.enable = true;
  playwright.enable = true;
  nextdns.enable = true;
  nextdns.vaultFile = "nextdns_mbp14.age";
  rclone.enable = true;
  minisign.enable = true;

  # AI tools (home-manager modules)
  home-manager.users.jimmyff.gemini-cli_module.enable = true;
}