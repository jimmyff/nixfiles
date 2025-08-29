# Sway module
{ pkgs, lib, config, ... }: {

    options = {

        waybar_module.enable = lib.mkEnableOption "enables waybar_module";

    };

    config = lib.mkIf config.waybar_module.enable {

      programs.waybar.enable = true;
#      
      xdg.configFile."waybar/config.jsonc".source = ./config.jsonc;
      xdg.configFile."waybar/style.css".source = lib.mkForce ./style.css;
     

      

    };


}