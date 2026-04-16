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
    home.file.".config/zellij".source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nixfiles/dotfiles/zellij";
  };
}