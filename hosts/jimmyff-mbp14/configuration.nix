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
    projects = [ "jimmyff-website" "osdn" "cache" "escp" "kosmos" "shed" "warcrest" ];
  };

  # Platform-specific development tools
  android.enable = true;
  dart.enable = true;
  xcode.enable = true;
  rust.enable = false;
  mitmproxy.enable = true;
  wireshark.enable = false;
  docker.enable = true;

  # Applications
  cinny.enable = false; # 2026-02-20: temporarily disabled, nixpkgs version mismatch (cinny 4.10.3 vs cinny-desktop 4.10.2)
  little-snitch.enable = false;
  workstation-security.enable = true;
  signal.enable = true;
  raycast.enable = true;
  kanata.enable = true; # home-row mods on the internal keyboard (see docs/darwin-install.md)
  kanata.platformKeys = import ./hardware/kanata-fn.nix; # MacBook function-row + caps layout
  playwright.enable = true;
  # NextDNS via the tailnet's nameserver; a local profile would hide MagicDNS.
  nextdns.enable = false;
  # nextdns.vaultFile = "nextdns_mbp14.age";
  tailscale.enable = true; # docs/remote-dev.md
  tailscale.overrideLocalDns = true;
  networking.knownNetworkServices = [ "Wi-Fi" "USB 10/100/1000 LAN" "Thunderbolt Bridge" ];
  syncthing.enable = true; # docs/sync.md
  rclone.enable = true;
  restic.enable = true; # hourly vault snapshots → Koofr (see docs/restore.md)
  minisign.enable = true;
  picard.enable = true;

  # AI tools (home-manager modules)
  home-manager.users.jimmyff.antigravity-cli_module.enable = true;
}