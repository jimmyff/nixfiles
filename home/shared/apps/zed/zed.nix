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
      package =
        if pkgs-dev-tools.stdenv.isDarwin
        then pkgs-dev-tools.zed-editor
        else pkgs-dev-tools.zed-editor-fhs;
    };
    home.file.".config/zed".source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nixfiles/dotfiles/zed";
  };
}
