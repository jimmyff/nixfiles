{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    zellij_module.enable = lib.mkEnableOption "enables zellij_module";
  };

  config = lib.mkIf config.zellij_module.enable {
    programs.zellij = {
      enable = true;
      
      settings = {
        default_shell = "${pkgs.nushell}/bin/nu";
        copy_on_select = true;
        scrollback_editor = "${pkgs.helix}/bin/hx";
      };
    };
  };
}