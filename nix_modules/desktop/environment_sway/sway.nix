{ lib, config, inputs, ... }: {

    options = {
        sway_module.enable = lib.mkEnableOption "enables sway_module";
    };

    config = lib.mkIf config.sway_module.enable {

      security.polkit.enable = true;
      programs.sway = {
        enable = true;
        wrapperFeatures.gtk = true;
      };

    };
}