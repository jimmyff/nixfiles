{ lib, username, ... }:

{
  # import sub modules
  imports = [
    ../shared/apps

    ./desktop/environment_cosmic

    ../shared/dotfiles.nix
  ];


  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home = {
    username = username;
    stateVersion = "25.05";
    homeDirectory = "/home/${username}"; 
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  
}
