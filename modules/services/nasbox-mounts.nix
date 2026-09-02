{ lib, config, pkgs-stable, username, nixfiles-vault, ... }:
let
  cfg = config.nasbox-mounts;
  isDarwin = pkgs-stable.stdenv.hostPlatform.isDarwin;

  mkShare = share: {
    name = "${cfg.mountPoint}/${share}";
    value = {
      device = "//${cfg.host}/${share}";
      fsType = "cifs";
      options = [
        "credentials=${config.age.secrets.smb-credentials.path}"
        "uid=${username}"
        "gid=users"
        "file_mode=0644"
        "dir_mode=0755"
        "iocharset=utf8"

        # nasbox is powered off most of the time. Mount lazily on first access,
        # never at boot, and fail fast rather than hanging a login or a unit
        # waiting for a host that isn't there.
        "noauto"
        "nofail"
        "_netdev"
        "x-systemd.automount"
        "x-systemd.mount-timeout=10s"
        "x-systemd.idle-timeout=60"
      ];
    };
  };
in {
  options.nasbox-mounts = {
    enable = lib.mkEnableOption "CIFS mounts for the nasbox shares";

    host = lib.mkOption {
      type = lib.types.str;
      default = "nasbox.local";
      description = "Host serving the shares. mDNS rather than an IP, which drifts with DHCP.";
    };

    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nasbox";
      description = "Parent directory the shares are mounted under.";
    };

    shares = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "media" "important" ];
      description = "Samba share names to mount, matching services.samba on nasbox.";
    };
  };

  # `fileSystems` has no nix-darwin equivalent, and undeclared options are caught
  # structurally — mkIf is pushed down into the attrset, so a disabled module
  # would still fail to evaluate on a Mac. optionalAttrs drops the definition
  # outright, leaving only the assertion to explain an accidental enable.
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = !isDarwin;
          message = "nasbox-mounts is Linux-only. macOS mounts SMB via Finder with the password in Keychain.";
        }
      ];
    })

    (lib.optionalAttrs (!isDarwin) (lib.mkIf cfg.enable {
      # Root-owned: mount.cifs reads this as root, so no owner/group here.
      age.secrets.smb-credentials = {
        file = nixfiles-vault + "/smb-credentials.age";
        mode = "600";
      };

      environment.systemPackages = [ pkgs-stable.cifs-utils ];

      fileSystems = lib.listToAttrs (map mkShare cfg.shares);
    }))
  ];
}
