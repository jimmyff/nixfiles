{ pkgs, lib, ... }:
{
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    settings = {
      default-cache-ttl = 28800; # 8 hours
      max-cache-ttl = 86400;     # 24 hours
    };
  };

  # SSH agent is handled by GPG agent (enableSSHSupport = true above)

  # OpenSSH service for NixOS (needed for agenix system host keys)
  services.openssh = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Configure sudo to preserve SSH_AUTH_SOCK for agenix flake inputs
  security.sudo = lib.mkIf pkgs.stdenv.isLinux {
    extraConfig = ''
      Defaults env_keep+=SSH_AUTH_SOCK
    '';
  };
}