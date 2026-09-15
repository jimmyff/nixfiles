{ pkgs, lib, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    
    # Hosts are reached over the tailnet: `tailscale nc` resolves the MagicDNS name
    # itself, so this works on any network regardless of the local resolver.
    # Keys are OpenSSH directive names (see ssh_config(5)).
    settings.nixbox = {
      HostName = "nixbox";
      User = "jimmyff";
      ProxyCommand = "tailscale nc %h %p";
    };

    settings.nasbox = {
      HostName = "nasbox";
      User = "jimmyff";
      ProxyCommand = "tailscale nc %h %p";
    };

    settings.gcp-beacon = {
      HostName = "gcp-beacon";
      User = "jimmyff";
      ProxyCommand = "tailscale nc %h %p";
    };

    settings."*" = {
      AddKeysToAgent = "yes";
      # Only restrict to named keys on systems that have local keys.
      # Servers use agent forwarding, so IdentitiesOnly would block that.
      IdentitiesOnly = pkgs.stdenv.hostPlatform.isDarwin;
      IdentityFile = [
        "~/.ssh/id_ed25519"
        "~/.ssh/id_rsa"
      ];
    };
    
    extraConfig = ''
      # SSH client defaults
      SendEnv LANG LC_*
      HashKnownHosts yes
      UserKnownHostsFile ~/.ssh/known_hosts
      GlobalKnownHostsFile /etc/ssh/ssh_known_hosts
      
      # macOS keychain support (ignored on Linux)
      ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "UseKeychain yes"}
      IgnoreUnknown UseKeychain
    '';
  };
}