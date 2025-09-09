{ pkgs, lib, ... }:
{
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # SSH agent is handled by GPG agent (enableSSHSupport = true above)
}