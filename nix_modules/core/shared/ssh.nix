{ pkgs, lib, ... }:
{
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Enable SSH client system-wide
  programs.ssh.startAgent = lib.mkIf (!pkgs.stdenv.isDarwin) false; # Use GPG agent instead
}