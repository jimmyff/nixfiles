{ lib, config, pkgs-stable, username, nixfiles-vault, ... }:
let
  cfg = config.tailscale;
  isDarwin = pkgs-stable.stdenv.hostPlatform.isDarwin;
in {
  # Tailscale mesh VPN: hosts reach each other by MagicDNS name from any network.
  # Enrol once with `sudo tailscale up`, or supply a pre-auth key from the vault.
  options.tailscale = {
    enable = lib.mkEnableOption "Tailscale tailnet membership";

    vaultFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "tailscale-authkey.age";
      description = "Vault file holding a pre-auth key for unattended enrolment (Linux only).";
    };

    acceptDns = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Register MagicDNS with systemd-resolved (Linux only). Split DNS, so it coexists with NextDNS.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = isDarwin -> cfg.vaultFile == null;
          message = "tailscale.vaultFile is Linux-only; enrol macOS by hand.";
        }
      ];
    }

    (lib.optionalAttrs (!isDarwin) {
      services.tailscale = {
        enable = true;
        package = pkgs-stable.tailscale;
        openFirewall = true; # direct peer connections instead of relays
        useRoutingFeatures = "client";
        authKeyFile = lib.mkIf (cfg.vaultFile != null) config.age.secrets.tailscale-authkey.path;
        # Applied on every boot; the operator grant lets the user drive the CLI without sudo.
        extraSetFlags = [ "--operator=${username}" ]
          ++ lib.optional (!cfg.acceptDns) "--accept-dns=false";
      };

      networking.firewall.trustedInterfaces = [ "tailscale0" ];

      age.secrets.tailscale-authkey = lib.mkIf (cfg.vaultFile != null) {
        file = nixfiles-vault + "/${cfg.vaultFile}";
        mode = "600";
      };
    })

    (lib.optionalAttrs isDarwin {
      # launchd daemon + CLI; nix-darwin also installs the ts.net resolver stub.
      services.tailscale = {
        enable = true;
        package = pkgs-stable.tailscale;
      };
    })
  ]);
}
