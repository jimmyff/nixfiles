# Sway module
{ inputs, pkgs, lib, config, ... }: {


  imports = [
    inputs.catppuccin.homeModules.catppuccin
  ];

  options = {
      catppuccin_module.enable = lib.mkEnableOption "enables catppuccin_module";
  };

  config = lib.mkIf config.catppuccin_module.enable {


    catppuccin.enable = true;
    catppuccin.flavor = "mocha"; 
    catppuccin.kitty.enable = true; 
    catppuccin.sway.enable = true;
    catppuccin.swaylock.enable = true;

    catppuccin.gtk.enable = true;
    

  };

}