{ pkgs, lib, ... }:
{
  imports = [
    ../shared/core.nix
    ../shared/apps.nix
    ../users.nix
    ../shared/ssh.nix
    ./ssh.nix
    ../shared/fonts.nix
    ../shared/stow.nix
    ./qemu-guest.nix
  ];

 
  # Optimise store
  nix.optimise.automatic = true;

  # Garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # NTP via Cloudflare anycast IPs so time sync works even when DNS is broken.
  # Strict DoT (NextDNS) needs a valid clock for TLS, and timesyncd's default
  # pool.ntp.org servers need DNS — without IP-based fallback the system can
  # deadlock with a stale clock after a long power-off or RTC battery failure.
  services.timesyncd = {
    enable = true;
    servers = [
      "162.159.200.1"
      "162.159.200.123"
    ];
    fallbackServers = [
      "0.nixos.pool.ntp.org"
      "1.nixos.pool.ntp.org"
    ];
  };

  system = {
    stateVersion = "25.05";
  };


}