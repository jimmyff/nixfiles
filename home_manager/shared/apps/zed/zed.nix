{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    zed_module.enable = lib.mkEnableOption "enables zed_module";
  };

  config = lib.mkIf config.zed_module.enable {
    programs.zed-editor = {
      enable = true;
    };
  };
}
