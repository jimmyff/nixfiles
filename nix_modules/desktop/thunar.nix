{ pkgs, ... }:
{

  # Thunar (XFCE file manager)
  programs.thunar.enable = true;
  programs.thunar.plugins = with pkgs.xfce; [
    thunar-archive-plugin thunar-volman
  ];
  
}