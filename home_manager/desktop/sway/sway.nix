# Sway module
{ pkgs, lib, config, ... }: {

    options = {

        sway_module.enable = lib.mkEnableOption "enables sway_module";

    };

    config = lib.mkIf config.sway_module.enable {

      # Enable pointer
      home.pointerCursor.sway.enable = true;
      xdg.configFile."sway/config".source = ./config;

      catppuccin.sway.enable = true;
      #catppuccin.sway.flavor = "macchiato";

      catppuccin.swaylock.enable = true;
      #catppuccin.swaylock.flavor = "macchiato";

    };


}