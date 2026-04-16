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

  # Development environment configuration
  development = {
    enable = true;
    projects = ["jotter" "jimmyff-website"];
  };

  # Platform-specific development tools
  android.enable = false;
  dart.enable = true;
  rust.enable = false;
  mitmproxy.enable = false;
  wireshark.enable = false;
  docker.enable = true;
}
