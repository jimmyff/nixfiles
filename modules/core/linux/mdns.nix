{
  lib,
  config,
  ...
}: let
  cfg = config.mdns;
in {
  # mDNS / Bonjour: advertise and/or resolve <hostname>.local on the LAN so
  # devices stay reachable by name regardless of DHCP-assigned IP changes.
  options.mdns = {
    publish = lib.mkEnableOption "advertising this host's <hostname>.local on the LAN";
    resolve = lib.mkEnableOption "resolving other hosts' .local names (nss-mdns)";
  };

  config = lib.mkIf (cfg.publish || cfg.resolve) {
    services.avahi = {
      enable = true;
      nssmdns4 = cfg.resolve; # insert mdns_minimal into nsswitch (resolution)
      publish = {
        enable = cfg.publish;
        addresses = cfg.publish; # advertise this host's A/AAAA record
      };
      openFirewall = true; # UDP 5353 in+out; only on opted-in hosts
    };
  };
}
