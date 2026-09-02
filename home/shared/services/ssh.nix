{ pkgs, lib, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    
    # Both hosts set mdns.publish, so use .local rather than pinning a DHCP
    # lease — the hardcoded IPs had already drifted (nasbox moved to .250).
    matchBlocks.nixbox = {
      hostname = "nixbox.local";
      user = "jimmyff";
    };

    matchBlocks.nasbox = {
      hostname = "nasbox.local";
      user = "jimmyff";
    };

    matchBlocks."*" = {
      addKeysToAgent = "yes";
      # Only restrict to named keys on systems that have local keys.
      # Servers use agent forwarding, so identitiesOnly would block that.
      identitiesOnly = pkgs.stdenv.hostPlatform.isDarwin;
      identityFile = [
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