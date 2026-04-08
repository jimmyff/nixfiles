{
  pkgs-dev-tools,
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
      package = pkgs-dev-tools.zed-editor;
    };
  };
}
