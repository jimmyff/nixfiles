{ username, ... }:

{
  # import sub modules
  imports = [
    ./apps/catppuccin.nix
    ./apps/default.nix
  ];

  # Core
  catppuccin_module.enable = lib.mkDefault true;

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home = {
    username = username;
    homeDirectory = "/home/${username}";

    stateVersion = "25.05";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}