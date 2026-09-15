{ pkgs, lib, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    
    # Both hosts set mdns.publish, so use .local rather than pinning a DHCP
    # lease — the hardcoded IPs had already drifted (nasbox moved to .250).
    # Keys are OpenSSH directive names (see ssh_config(5)).
    settings.nixbox = {
      HostName = "nixbox.local";
      User = "jimmyff";
    };

    settings.nasbox = {
      HostName = "nasbox.local";
      User = "jimmyff";
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