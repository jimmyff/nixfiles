# Sway module
{ inputs, pkgs, lib, config, ... }: {


  imports = [
    inputs.catppuccin.homeModules.catppuccin
  ];

  options = {
      catppuccin_module.enable = lib.mkEnableOption "enables catppuccin_module";
  };

  config = lib.mkIf config.catppuccin_module.enable {

    home.packages = [
        pkgs.catppuccin-gtk    # theme
    ];

    catppuccin.enable = true;
    catppuccin.flavor = "mocha"; 
    catppuccin.kitty.enable = true; 
  };

}