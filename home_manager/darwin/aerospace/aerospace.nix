# AeroSpace module for Darwin
{ pkgs, lib, config, ... }: {

    options = {

        aerospace_module.enable = lib.mkEnableOption "enables aerospace_module";

    };

    config = lib.mkIf config.aerospace_module.enable {

        home.packages = [ pkgs.aerospace ];

    };
}