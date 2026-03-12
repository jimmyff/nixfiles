{ pkgs, lib, ... }:
{
  # OpenSSH service for NixOS (needed for agenix system host keys)
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Configure sudo to preserve SSH_AUTH_SOCK for agenix flake inputs
  security.sudo = {
    extraConfig = ''
      Defaults env_keep+=SSH_AUTH_SOCK
    '';
  };
}