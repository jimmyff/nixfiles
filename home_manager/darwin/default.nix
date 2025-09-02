{ pkgs, lib, username, ... }:
{
  # import sub modules
  imports = [
    ../shared/apps
    ../shared/dotfiles.nix
  ];

  # Not supported on darwin as of 2025-07-14
  chromium_module.enable =  false;



  # xdg.enable = true;
  # xdg.configHome = "/Users/${username}/.config";

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home = {
    username = username;
    homeDirectory = "/Users/${username}";
 
    stateVersion = "25.05";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # XDG Directories
  xdg = {
    enable = true;
    configHome = "/Users/${username}/.config";
    dataHome   = "/Users/${username}/.local/share";
    stateHome  = "/Users/${username}/.local/state";
    cacheHome  = "/Users/${username}/.cache";
  };

  # (Optional) ensure these session variables are exported too
  home.sessionVariables = {
    XDG_CONFIG_HOME = "/Users/${username}/.config";
    XDG_DATA_HOME   = "/Users/${username}/.local/share";
    XDG_STATE_HOME  = "/Users/${username}/.local/state";
    XDG_CACHE_HOME  = "/Users/${username}/.cache";
  };
}