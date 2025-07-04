{ pkgs, ... }:
{
    imports = [
 
    ./host-users.nix
    ./system.nix
    ./ssh.nix
    ./fonts.nix
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

  # Add ability to used TouchID for sudo authentication
  security.pam.enableSudoTouchIdAuth = true;



}