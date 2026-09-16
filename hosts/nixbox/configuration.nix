{
  config,
  pkgs-stable,
  lib,
  inputs,
  username,
  ...
}: {
  imports = [
    ./hardware-configuration.nix

    # Development environment
    ../../modules/development
  ];

  networking.hostName = "nixbox";
  qemu-guest.enable = true;
  mdns.publish = true; # reachable as nixbox.local regardless of DHCP IP
  tailscale.enable = true; # docs/remote-dev.md
  syncthing.enable = true; # docs/sync.md

  # Local DNS cache: parallel Nix builds burst thousands of lookups, which the
  # router's forwarder drops under load. Upstream stays DHCP-provided.
  services.resolved.enable = true;

  # Development environment configuration
  development = {
    enable = true;
    projects = ["cache" "jimmyff-website" "kosmos"];
  };

  # Platform-specific development tools
  android.enable = true;
  android.studio = false; # headless: SDK + adb only
  dart.enable = true;
  rust.enable = false;
  mitmproxy.enable = false;
  wireshark.enable = false;
  docker.enable = true;
}
