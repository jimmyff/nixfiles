{ pkgs, lib, ... }:
{
  imports = [
    ../shared/core.nix
    ../shared/apps.nix
    ../users.nix
    ../shared/ssh.nix
    ./ssh.nix
    ../shared/fonts.nix
    ../shared/stow.nix
    ./qemu-guest.nix
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