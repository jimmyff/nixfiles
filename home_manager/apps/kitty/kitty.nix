{ pkgs, lib, config, ... }: {

    options = {

        kitty_module.enable = lib.mkEnableOption "enables kitty_module";

    };

    config = lib.mkIf config.kitty_module.enable {

        programs.kitty = {
            enable = true;
            enableGitIntegration = true;
            font.name = "JetBrainsMono Nerd Font";
            font.size = 14;

            darwinLaunchOptions = [
                "nu"
            ];
        };

        home.sessionVariables.TERMINAL = "kitty";
      
    };
}