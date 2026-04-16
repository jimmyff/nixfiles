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

  # Data disk mount (second virtual disk from Proxmox)
  # TODO: Update device path after VM creation
  fileSystems."/data" = {
    device = "/dev/disk/by-label/data";
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
      shared = {
        path = "/data/shared";
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
    exports = ''
      /data/media  192.168.0.0/24(rw,sync,no_subtree_check,no_root_squash)
      /data/shared 192.168.0.0/24(rw,sync,no_subtree_check,no_root_squash)
    '';
  };
  networking.firewall.allowedTCPPorts = [2049];

  # Create data directories
  systemd.tmpfiles.rules = [
    "d /data/media 0755 ${username} users -"
    "d /data/shared 0755 ${username} users -"
  ];
}
