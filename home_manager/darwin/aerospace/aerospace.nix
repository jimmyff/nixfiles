# AeroSpace module for Darwin
{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    aerospace_module.enable = lib.mkEnableOption "enables aerospace_module";
  };

  config = lib.mkIf config.aerospace_module.enable {
    home.packages = [pkgs.aerospace];

    services.jankyborders = {
      enable = true;
      settings = {
        active_color = "0xfffff98c";
        inactive_color = "0xff494d64";
        width = 8;
      };
    };
  };
}
