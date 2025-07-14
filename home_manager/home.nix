{ lib, username, ... }:

{
  # import sub modules
  imports = [
    ./apps/catppuccin.nix
    ./apps/_bundle.nix

    ./desktop/environment_cosmic/_bundle.nix

    ./dotfiles.nix
  ];

  # Core
  catppuccin_module.enable = lib.mkDefault true;

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
