# Waybar (niri) — gated on the host's desktop state, no independent toggle.
{ lib, config, ... }: {

  config = lib.mkIf config.desktop.enable {
    programs.waybar.enable = true;
    xdg.configFile."waybar/config.jsonc".source = ./config.jsonc;
    xdg.configFile."waybar/style.css".source = ./style.css;
  };
}
