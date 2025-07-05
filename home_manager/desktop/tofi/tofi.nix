{ pkgs, lib, config, ... }: {

    options = {

        tofi_module.enable = lib.mkEnableOption "enables tofi_module";

    };

    config = lib.mkIf config.tofi_module.enable {

        programs.tofi = {
            enable = true;
            settings = {
                                
                prompt-text = ">";
                prompt-padding = 4;
                font = "JetBrainsMono Nerd Font";
                font-size = 16;
                height = "100%";
                width = "100%";
                num-results = 8;
                outline-width = 0;
                border-width = 0;
                padding-left = "35%";
                padding-top = "30%";
                result-spacing = 8;

                # Catppuccin Mocha
                text-color          = "#cdd6f4";
                prompt-color        = "#f38ba8";
                selection-color     = "#f9e2af";
                background-color    = "#1e1e2e";
            };
        };
    };
}