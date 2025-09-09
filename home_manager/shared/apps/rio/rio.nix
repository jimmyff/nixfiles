{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    rio_module.enable = lib.mkEnableOption "enables rio_module";
  };

  config = lib.mkIf config.rio_module.enable {
    programs.rio = {
      enable = true;
      settings = {
        fonts = {
          family = "JetBrainsMono Nerd Font";
          size = 13;
        };

        shell = {
          program = "${pkgs.nushell}/bin/nu";
          args = ["--config" "${config.xdg.configHome}/nushell/config.nu"];
        };

        colors = {
          background = "#0d0e1c";
          foreground = "#ffffff";
          cursor = "#ff66ff";
          selection-background = "#555a66";
          selection-foreground = "#ffffff";

          # Modus Vivendi Tinted colors
          black = "#0d0e1c";
          red = "#ff5f59";
          green = "#44bc44";
          yellow = "#d0bc00";
          blue = "#2fafff";
          magenta = "#feacd0";
          cyan = "#00d3d0";
          white = "#a6a6a6";

          bright-black = "#595959";
          bright-red = "#ff6b55";
          bright-green = "#00c06f";
          bright-yellow = "#fec43f";
          bright-blue = "#79a8ff";
          bright-magenta = "#b6a0ff";
          bright-cyan = "#6ae4b9";
          bright-white = "#ffffff";
        };
      };
    };
  };
}
