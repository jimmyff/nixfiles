# Waybar (niri) — gated on the host's desktop state, no independent toggle.
{ lib, config, pkgs-desktop, ... }:
let
  nuScript = name: pkgs-desktop.writeScriptBin name
    ("#!${pkgs-desktop.nushell}/bin/nu\n" + builtins.readFile ./scripts/${name}.nu);
in
{
  config = lib.mkIf config.desktop.enable {
    programs.waybar.enable = true;
    home.packages = [
      (nuScript "waybar-tailscale") # bar module
      (nuScript "waybar-disk-io")   # bar module
      (nuScript "battery-monitor") # battery on-click
    ];
    xdg.configFile."waybar/config.jsonc".source = ./config.jsonc;
    xdg.configFile."waybar/style.css".source = ./style.css;
  };
}
