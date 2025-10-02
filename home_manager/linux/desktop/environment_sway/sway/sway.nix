{ pkgs-desktop, lib, config, inputs, ... }: {

    options = {
        sway_module.enable = lib.mkEnableOption "enables sway_module";
    };

    config = lib.mkIf config.sway_module.enable {

      xdg.configFile."sway/config".source = ./config;
      xdg.configFile."swaylock/config".source = ./config_swaylock;

      # swaylock
      programs.swaylock = {
        enable = true;
      };

      # Enable pointer
      home.pointerCursor.sway.enable = true;


    };
}