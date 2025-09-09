{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    alacritty_module.enable = lib.mkEnableOption "enables alacritty_module";
  };

  config = lib.mkIf config.alacritty_module.enable {
    programs.alacritty = {
      enable = true;

      settings = {
        font = {
          normal = {
            family = "JetBrainsMono Nerd Font";
            style = "Regular";
          };
          bold = {
            family = "JetBrainsMono Nerd Font";
            style = "Bold";
          };
          italic = {
            family = "JetBrainsMono Nerd Font";
            style = "Italic";
          };
          size = 13;
        };

        selection = {
          save_to_clipboard = true;
        };

        # Modus Vivendi Tinted theme
        colors = {
          primary = {
            background = "#0d0e1c";
            foreground = "#ffffff";
          };

          cursor = {
            text = "#0d0e1c";
            cursor = "#ff66ff";
          };

          selection = {
            text = "#ffffff";
            background = "#555a66";
          };

          normal = {
            black = "#0d0e1c";
            red = "#ff5f59";
            green = "#44bc44";
            yellow = "#d0bc00";
            blue = "#2fafff";
            magenta = "#feacd0";
            cyan = "#00d3d0";
            white = "#a6a6a6";
          };

          bright = {
            black = "#595959";
            red = "#ff6b55";
            green = "#00c06f";
            yellow = "#fec43f";
            blue = "#79a8ff";
            magenta = "#b6a0ff";
            cyan = "#6ae4b9";
            white = "#ffffff";
          };
        };
      };
    };
  };
}
