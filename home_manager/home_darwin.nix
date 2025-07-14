{ pkgs, lib, username, ... }:
{
  # import sub modules
  imports = [
    ./apps/_bundle.nix
    ./dotfiles.nix
  ];

  # Not supported on darwin as of 2025-07-14
  chromium_module.enable =  false;

  # Not supported on darwin
  # catppuccin_module.enable = false;

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home = {
    username = username;
    homeDirectory = "/Users/${username}";
 
    stateVersion = "25.05";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}