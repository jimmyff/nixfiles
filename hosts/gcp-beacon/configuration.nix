{ ... }:
{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "gcp-beacon";

  # Baked image locks jimmyff's password; wheel needs passwordless sudo to stay administratable.
  # Key-only SSH (core/linux) is the gate.
  security.sudo.wheelNeedsPassword = false;

  zramSwap.enable = true; # 1 GB RAM, no GCE swap — absorbs deploy-time memory spikes

  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://beacon.rocketware.io";
      listen-http = "127.0.0.1:2586";
      behind-proxy = true;
      auth-file = "/var/lib/ntfy-sh/user.db";
      auth-default-access = "deny-all";
      cache-file = "/var/lib/ntfy-sh/cache-file.db";
      cache-duration = "72h"; # 12h default would drop pings while the phone is offline
      attachment-cache-dir = "";
      web-root = "disable";
    };
  };

  services.caddy = {
    enable = true;
    email = "code@rocketware.co.uk";
    # Caddy self-manages the cert via built-in ACME — do NOT add useACMEHost.
    virtualHosts."beacon.rocketware.io".extraConfig = "reverse_proxy 127.0.0.1:2586";
  };

  networking.firewall.enable = true; # GCE profile defaults this off
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
