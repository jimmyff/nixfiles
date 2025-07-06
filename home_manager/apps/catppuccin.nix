# Sway module
{
  inputs,
  pkgs,
  lib,
  config,
  ...
}: {
  imports = [
    inputs.catppuccin.homeModules.catppuccin
  ];

  options = {
    catppuccin_module.enable = lib.mkEnableOption "enables catppuccin_module";
  };

  config = lib.mkIf config.catppuccin_module.enable {
    # for all options see: https://nix.catppuccin.com/search/v1.2/
    catppuccin.enable = true;
    catppuccin.flavor = "mocha";
    catppuccin.kitty.enable = true;
    catppuccin.sway.enable = true;
    catppuccin.swaylock.enable = true;
    catppuccin.btop.enable = true;

    catppuccin.gtk.enable = true;
  };
}

