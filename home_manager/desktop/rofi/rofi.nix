# Sway module
{ pkgs, lib, config, ... }: {

    options = {
        rofi_module.enable = lib.mkEnableOption "enables rofi_module";
    };

    config = lib.mkIf config.rofi_module.enable {

        programs.rofi = {
            enable = true;
            package = pkgs.rofi-wayland;
            terminal = "${pkgs.ghostty}/bin/";
            modes = [
                "drun"
                "combi"
            ];

            extraConfig = {
                modi = "drun";
                show-icons = true;
                drun-display-format = "{icon} {name}";
                disable-history = false;
                hide-scrollbar = true;
                display-drun = "   Apps ";
                sidebar-mode = true;
            };
        };
    };
}

