{ pkgs, lib, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    
    matchBlocks."*" = {
      addKeysToAgent = "yes";
    };
    
    extraConfig = ''
      # SSH client defaults
      SendEnv LANG LC_*
      HashKnownHosts yes
      UserKnownHostsFile ~/.ssh/known_hosts
      GlobalKnownHostsFile /etc/ssh/ssh_known_hosts
      
      # macOS keychain support (ignored on Linux)
      ${lib.optionalString pkgs.stdenv.isDarwin "UseKeychain yes"}
      IgnoreUnknown UseKeychain
    '';
  };
}