{
  pkgs-apps,
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
    };
  };
}