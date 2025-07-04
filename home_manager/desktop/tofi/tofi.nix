# Sway module
{ pkgs, lib, config, ... }: {

    options = {

        tofi_module.enable = lib.mkEnableOption "enables tofi_module";

    };

    config = lib.mkIf config.tofi_module.enable {

        programs.tofi = {
            enable = true;
            settings = {
                background-color = "#000000";
                border-width = 0;
                font = "monospace";
                height = "100%";
                num-results = 5;
                outline-width = 0;
                padding-left = "35%";
                padding-top = "35%";
                result-spacing = 25;
                width = "100%";
            };
        };
    };
}