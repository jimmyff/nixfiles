{ pkgs-desktop, ... }:
{

  # Thunar (XFCE file manager)
  programs.thunar.enable = true;
  programs.thunar.plugins = with pkgs-desktop.xfce; [
    thunar-archive-plugin thunar-volman
  ];

}