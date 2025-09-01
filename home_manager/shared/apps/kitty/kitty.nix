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
      ];
      settings = {
        copy_on_select = true;
        cursor_trail = 3;
        cursor_trail_decay = "0.1 0.4";
      };
    };

    home.sessionVariables.TERMINAL = "kitty";

  };
}
