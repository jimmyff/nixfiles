{ lib, config, pkgs-stable, username, nixfiles-vault, ... }:
let
  cfg = config.syncthing;
  isDarwin = pkgs-stable.stdenv.hostPlatform.isDarwin;
  homeDir = if isDarwin then "/Users/${username}" else "/home/${username}";
  host = config.networking.hostName;

  # Device IDs identify machines, so they live in the private vault rather than here.
  devicesFile = nixfiles-vault + "/syncthing-devices.nix";
  haveDevices = builtins.pathExists devicesFile;
  deviceIds = if haveDevices then import devicesFile else { };
  registry = import ./folders.nix;

  enrolled = lib.filterAttrs (_: id: id != null) deviceIds;

  # Folders this host carries, per the registry. Hosts opt in there, not here.
  mine = lib.filterAttrs (_: f: builtins.elem host f.hosts) registry;

  peersOf = f: lib.filter (h: h != host && enrolled ? ${h}) f.hosts;
  unenrolledOf = f: lib.filter (h: h != host && !(enrolled ? ${h})) f.hosts;
  peerNames = lib.unique (lib.concatMap peersOf (lib.attrValues mine));
  missing = lib.unique (lib.concatMap unenrolledOf (lib.attrValues mine));

  mkFolder = id: f:
    {
      inherit id;
      label = f.label;
      path = f.paths.${host} or "${cfg.syncRoot}/${id}";
      devices = peersOf f;
      type = f.types.${host} or "sendreceive";
    }
    // lib.optionalAttrs ((f.versioning or null) != null) { versioning = f.versioning; }
    # ignorePatterns is a NixOS-module feature; macOS keeps .stignore by hand.
    // lib.optionalAttrs (!isDarwin && (f.ignorePatterns or [ ]) != [ ]) {
      ignorePatterns = f.ignorePatterns;
    };

  settings = {
    options = {
      globalAnnounceEnabled = false; # peers are LAN or tailnet; nothing public
      relaysEnabled = false;
      natEnabled = false;
      localAnnounceEnabled = true;
      urAccepted = -1;
      crashReportingEnabled = false;
    };
    devices = lib.genAttrs peerNames (name: {
      id = enrolled.${name};
      addresses = [ "dynamic" ];
    });
    folders = lib.mapAttrs mkFolder mine;
  };
in {
  # Syncthing peer. Folders come from the registry beside this file and device IDs from the
  # vault, so a host only says `syncthing.enable = true` and gets every folder that names it.
  # Folders live at $SYNC_ROOT/<folder-id> unless the registry overrides the path. See docs/sync.md.
  options.syncthing = {
    enable = lib.mkEnableOption "Syncthing peer";

    syncRoot = lib.mkOption {
      type = lib.types.str;
      default = "${homeDir}/sync";
      description = "Parent directory for synced folders; exported as SYNC_ROOT.";
    };

    guiAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8384";
      description = "Web UI bind address. Reach headless hosts over an ssh tunnel.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      warnings =
        lib.optional (!haveDevices)
          "syncthing: the vault has no syncthing-devices.nix; no peers will be configured (docs/sync.md)"
        ++ lib.optional (haveDevices && (deviceIds.${host} or null) == null)
          "syncthing: ${host} has no device ID yet — add it to the vault after the first start (docs/sync.md)"
        ++ map (h: "syncthing: peer ${h} has no device ID and is skipped") missing;

    }

    (lib.optionalAttrs (!isDarwin) {
      # PAM-set so nushell logins see it too (same pattern as modules/development).
      environment.sessionVariables.SYNC_ROOT = cfg.syncRoot;

      services.syncthing = {
        enable = true;
        package = pkgs-stable.syncthing;
        user = username;
        group = "users";
        dataDir = "${homeDir}/.local/share/syncthing";
        configDir = "${homeDir}/.config/syncthing";
        guiAddress = cfg.guiAddress;
        openDefaultPorts = true; # 22000 sync + 21027 LAN discovery
        overrideDevices = true; # the registry is authoritative; also drops the stock default folder
        overrideFolders = true;
        inherit settings;
      };
      systemd.tmpfiles.rules = [ "d ${cfg.syncRoot} 0755 ${username} users -" ];
    })

    (lib.optionalAttrs isDarwin {
      environment.variables.SYNC_ROOT = cfg.syncRoot;

      home-manager.users.${username}.services.syncthing = {
        enable = true;
        package = pkgs-stable.syncthing;
        guiAddress = cfg.guiAddress;
        overrideDevices = true;
        overrideFolders = true;
        inherit settings;
      };
    })
  ]);
}
