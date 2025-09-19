{ pkgs, lib, ... }:
{
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
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
}