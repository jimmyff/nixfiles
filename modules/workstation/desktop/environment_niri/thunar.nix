{ pkgs-desktop, lib, config, ... }:
{
  options.thunar_module.enable = lib.mkEnableOption "Thunar file manager";

  config = lib.mkIf config.thunar_module.enable {
    # Thunar (XFCE file manager)
    programs.thunar.enable = true;
    programs.thunar.plugins = with pkgs-desktop.xfce; [
      thunar-archive-plugin thunar-volman
    ];
  };
}
