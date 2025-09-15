{ pkgs, lib, ... }:
{
  imports = [
    ../shared/core.nix
    ../shared/apps.nix
    ../users.nix
    ../shared/ssh.nix
    ../shared/fonts.nix
    ../shared/stow.nix
    ../../apps/signal.nix
    ../../apps/google-chrome.nix
  ];

 
  # Optimise store
  nix.optimise.automatic = true;
  
  # Garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  system = {
    stateVersion = "25.05";
  };


}