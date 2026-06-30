# Darwin: kanata home-row mods on the internal keyboard only.
# kanata must run as root (Karabiner IPC socket is root-only) and from a stable
# binary path (macOS TCC binds Input Monitoring to the binary's cdhash, so a
# /nix/store path bump would silently revoke the grant). See docs/darwin-install.md
# for the one-time manual driver install + permission ritual.
{ lib, config, pkgs, pkgs-kanata, ... }:
let
  cfg = config.kanata;
  kanata = pkgs-kanata.kanata; # pinned nixpkgs input (frozen cdhash keeps the TCC grant); 1.11.x → Karabiner v6 driver
  installedDriverVersion = "6.2.0"; # the manually-installed .pkg (manual setup step 1)
  kanataBin = "/usr/local/bin/kanata";
  cfgFile = import ../../../dotfiles/kanata/mkConfig.nix {
    inherit pkgs kanata;
    extraDefcfg = [
      "macos-dev-names-include (${lib.concatMapStringsSep " " (n: ''"${n}"'') cfg.includeDevices})"
    ];
    platformKeys = cfg.platformKeys;
  };
  vhidDaemon = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon";
in {
  options.kanata = {
    enable = lib.mkEnableOption "kanata home-row mods (internal keyboard)";
    includeDevices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "Apple Internal Keyboard / Trackpad" ];
      description = ''
        macOS product names kanata grabs (list with: sudo kanata -l); others
        (e.g. Moonlander w/ firmware HRM) are ignored. Caution: if NO name
        matches, kanata falls back to grabbing ALL keyboards.
      '';
    };
    platformKeys = import ../../../dotfiles/kanata/platformKeysOption.nix { inherit lib; };
  };

  config = lib.mkIf cfg.enable {
    # Fail eval when a flake update bumps kanata past the manually-installed driver.
    assertions = [{
      assertion = kanata.passthru.darwinDriverVersion == installedDriverVersion;
      message = "kanata ${kanata.version} expects Karabiner driver ${kanata.passthru.darwinDriverVersion}; installed pkg is ${installedDriverVersion} — install the matching pkg, re-activate the extension, bump installedDriverVersion.";
    }];

    environment.systemPackages = [ kanata ];

    # Stable path so the TCC Input-Monitoring grant survives rebuilds. Must be
    # extraActivation: nix-darwin never runs custom-named activation scripts,
    # and this slot runs before launchd loads the daemon on first switch.
    system.activationScripts.extraActivation.text = lib.mkAfter ''
      /bin/mkdir -p /usr/local/bin
      if ! /usr/bin/cmp -s ${kanata}/bin/kanata ${kanataBin}; then
        /usr/bin/install -m755 ${kanata}/bin/kanata ${kanataBin}
        echo "kanata binary changed — re-grant Input Monitoring + Accessibility for ${kanataBin}, then:" >&2
        echo "  sudo launchctl kickstart -k system/org.nixos.kanata" >&2
      fi
      # The DriverKit driver can't be installed by Nix (manual .pkg + extension
      # approval). Warn loudly at switch time if it's absent — without it kanata
      # runs but captures nothing. Non-fatal: the manual flow installs it first.
      if [ ! -e "${vhidDaemon}" ]; then
        echo "⚠ kanata: Karabiner DriverKit driver not installed — home-row mods will not work." >&2
        echo "  Install v${installedDriverVersion}: https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/tag/v${installedDriverVersion}" >&2
        echo "  Then follow docs/darwin-install.md → kanata setup." >&2
      fi
    '';

    # kanata: root daemon, stable binary, --nodelay fixes the Tahoe startup race; no --port.
    launchd.daemons.kanata.serviceConfig = {
      ProgramArguments = [ kanataBin "--cfg" "${cfgFile}" "--nodelay" "--no-wait" ];
      # Salt: nix-darwin restarts daemons only on plist diff; without this a
      # kanata bump leaves the old binary running until reboot.
      EnvironmentVariables.KANATA_PKG = "${kanata}";
      RunAtLoad = true;
      KeepAlive = { SuccessfulExit = false; };
      ProcessType = "Interactive";
      StandardOutPath = "/var/log/kanata.log";
      StandardErrorPath = "/var/log/kanata.log";
    };

    # Karabiner virtual-HID daemon (kanata's output path); installed by the standalone .pkg.
    launchd.daemons.karabiner-vhid-daemon.serviceConfig = {
      ProgramArguments = [ vhidDaemon ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/var/log/karabiner-vhid-daemon.log";
      StandardErrorPath = "/var/log/karabiner-vhid-daemon.log";
    };

    # Rotate both daemon logs (macOS only rotates what newsyslog knows about).
    environment.etc."newsyslog.d/kanata.conf".text = ''
      /var/log/kanata.log                root:wheel 644 5 1024 * J
      /var/log/karabiner-vhid-daemon.log root:wheel 644 5 1024 * J
    '';
  };
}
