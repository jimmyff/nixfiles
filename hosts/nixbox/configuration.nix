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

  # Out-of-memory: kill a build rather than stall the VM.
  zramSwap.enable = true;
  services.earlyoom = {
    enable = true;
    extraArgs = [
      "--prefer" "^(java|dart|dartaotruntime|gen_snapshot)$"
      "--avoid" "^(sshd|sshd-session|tailscaled|systemd|systemd-journal|syncthing)$"
    ];
  };

  # Gradle memory caps; overrides each project's gradle.properties.
  home-manager.users.${username}.home.file.".gradle/gradle.properties".text = ''
    org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=2g -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError
    kotlin.daemon.jvmargs=-Xmx2g
    org.gradle.daemon.idletimeout=1800000
  '';

  # Software OpenGL for GUI apps shown via waypiper (no GPU).
  hardware.graphics.enable = true;

  # Grow root to fill the disk on boot (Proxmox resizes).
  boot.growPartition = true;
  fileSystems."/".autoResize = true;

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
