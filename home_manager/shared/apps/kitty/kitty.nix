{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    kitty_module.enable = lib.mkEnableOption "enables kitty_module";
  };

  config = lib.mkIf config.kitty_module.enable {
    programs.kitty = {
      enable = true;
      enableGitIntegration = true;
      font.name = "JetBrainsMono Nerd Font";
      font.size = 13;

      darwinLaunchOptions = [
      ];
      settings = {
        copy_on_select = true;
        cursor_trail = 3;
        cursor_trail_decay = "0.1 0.4";
        adjust_line_height = "125%";
        # Explicitly specify nushell with config path for reliable startup
        shell = "${pkgs.nushell}/bin/nu --config ${config.xdg.configHome}/nushell/config.nu";

        # Modus Vivendi Tinted theme by Protesilaos Stavrou
        foreground = "#ffffff";
        background = "#0d0e1c";
        selection_foreground = "#ffffff";
        selection_background = "#555a66";
        color0 = "#0d0e1c";
        color1 = "#ff5f59";
        color2 = "#44bc44";
        color3 = "#d0bc00";
        color4 = "#2fafff";
        color5 = "#feacd0";
        color6 = "#00d3d0";
        color7 = "#a6a6a6";
        color8 = "#595959";
        color9 = "#ff6b55";
        color10 = "#00c06f";
        color11 = "#fec43f";
        color12 = "#79a8ff";
        color13 = "#b6a0ff";
        color14 = "#6ae4b9";
        color15 = "#ffffff";

        # Cursor styles
        cursor = "#ff66ff";

        # Tab styles
        active_tab_foreground = "#ffffff";
        active_tab_background = "#4a4f6a";
        inactive_tab_foreground = "#969696";
        inactive_tab_background = "#2b3046";

        # Border colors
        active_border_color = "#c6daff";
        inactive_border_color = "#595959";
      };
    };

    home.sessionVariables.TERMINAL = "kitty";
  };
}
