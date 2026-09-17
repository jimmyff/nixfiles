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
  ];

  networking.hostName = "nasbox";
  qemu-guest.enable = true;
  mdns.publish = true; # reachable as nasbox.local regardless of DHCP IP
  tailscale.enable = true; # docs/remote-dev.md
  zramSwap.enable = true; # no swap disk; headroom for memory spikes

  # Always-on sync peer; folders sit on the archive tier so the Drive push covers them.
  syncthing.enable = true;
  syncthing.syncRoot = "/data/important/sync";

  # Cloud sync. The archive tier will push to Drive from here; this host is
  # deliberately not granted the Koofr credentials, which are workstation-only.
  rclone.enable = true;
  rclone.koofr.enable = false;

  # Data disk mounts (Proxmox virtual disks)
  fileSystems."/data/media" = {
    device = "/dev/disk/by-label/data_media";
    fsType = "ext4";
    options = ["defaults" "nofail"];
  };

  fileSystems."/data/important" = {
    device = "/dev/disk/by-label/data_important";
    fsType = "ext4";
    options = ["defaults" "nofail"];
  };

  # Jellyfin media server
  services.jellyfin = {
    enable = true;
    openFirewall = true;
    # Web UI: http://nasbox:8096
  };

  # Samba file shares (macOS/Windows access)
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "nasbox";
        "security" = "user";
        "map to guest" = "Bad User";
      };
      media = {
        path = "/data/media";
        "read only" = "no";
        "browseable" = "yes";
        "valid users" = username;
        "create mask" = "0644";
        "directory mask" = "0755";
      };
      important = {
        path = "/data/important";
        "read only" = "no";
        "browseable" = "yes";
        "valid users" = username;
        "create mask" = "0644";
        "directory mask" = "0755";
      };
    };
  };

  # NFS file shares (Linux access)
  services.nfs.server = {
    enable = true;
    # LAN is 192.168.86.0/24 — the previous 192.168.0.0/24 matched no client,
    # so these exports were silently unreachable. root_squash (the default) is
    # deliberate: this holds the archive tier's primary copy, and anything that
    # corrupts it here propagates to Drive on the next push.
    exports = ''
      /data/media     192.168.86.0/24(rw,sync,no_subtree_check)
      /data/important 192.168.86.0/24(rw,sync,no_subtree_check)
    '';
  };
  networking.firewall.allowedTCPPorts = [2049];

  # Create data directories
  systemd.tmpfiles.rules = [
    "d /data/media 0755 ${username} users -"
    "d /data/important 0755 ${username} users -"
  ];
}
