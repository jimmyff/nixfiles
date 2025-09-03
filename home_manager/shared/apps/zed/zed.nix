{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    zed_module.enable = lib.mkEnableOption "enables zed_module";
  };

  config = lib.mkIf config.zed_module.enable {
    programs.zed-editor = {
      enable = true;

      extensions = [
        "dart"
        "nix"
        "modus-themes"
      ];

      userSettings = {
        buffer_font_family = "JetBrainsMono Nerd Font";
        ui_font_family = "JetBrainsMono Nerd Font";
        buffer_font_size = 13;
        ui_font_size = 13;
        theme = "Modus Vivendi Tinted";
        vim_mode = true;
        
        telemetry = {
          diagnostics = false;
          metrics = false;
        };
      };
    };
  };
}