# Sway module
{ pkgs, lib, config, ... }: {

    options = {

        ghostty_module.enable = lib.mkEnableOption "enables ghostty_module";

    };

    config = lib.mkIf config.ghostty_module.enable {

        programs.ghostty = {
            enable = true;
            settings = {
                theme = "catppuccin-mocha";
                font-size = 14;
                font-family = "JetBrainsMono Nerd Font";
            };
        };
    };
}