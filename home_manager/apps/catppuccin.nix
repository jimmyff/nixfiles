# Sway module
{ pkgs, lib, config, ... }: {

    options = {
        catppuccin_module.enable = lib.mkEnableOption "enables catppuccin_module";
    };

    config = lib.mkIf config.catppuccin_module.enable {

      catppuccin.enable = true;
      catppuccin.flavor = "mocha"; 
      catppuccin.kitty.enable = true; 
    };


}