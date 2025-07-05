# Sway module
{ pkgs, lib, config, ... }: {

    options = {
        rofi_module.enable = lib.mkEnableOption "enables rofi_module";
    };

    config = lib.mkIf config.rofi_module.enable {
        
        programs.rofi = {
            enable = true;
            package = pkgs.rofi-wayland;
            #theme = "purple";
            font = "JetBrainsPropo Nerd Font";
            terminal = "kitty";
            modes = [
                "drun"
                "combi"
            ];

        };
    };
}

