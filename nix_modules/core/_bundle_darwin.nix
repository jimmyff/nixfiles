{ pkgs, username, ... }:
{
  imports = [
 
    ./host-users.nix
    ./ssh.nix
    ./fonts.nix
  ];


  system.primaryUser = username;

  # Optimise store
  nix.optimise.automatic = true;
  
  # Garbage collection
  nix.gc = {
    automatic = true;
    interval = { Weekday = 0; Hour = 0; Minute = 0; };
    options = "--delete-older-than 30d";
  };

  system = {
    stateVersion = 6;
  };

  # Add ability to used TouchID for sudo authentication
  security.pam.services.sudo_local.touchIdAuth = true;

  # Create /etc/zshrc that loads the nix-darwin environment.
  # this is required if you want to use darwin's default shell - zsh
  programs.zsh.enable = true;


}