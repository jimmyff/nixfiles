{
  lib,
  config,
  ...
}: {
  options = {
    yazi_module.enable = lib.mkEnableOption "enables yazi_module";
  };

  config = lib.mkIf config.yazi_module.enable {
    # https://yazi-rs.github.io/docs/configuration/overview/
    programs.yazi = {
      enable = true;
      shellWrapperName = "yy"; # Keep legacy behavior (stateVersion < 26.05)
      settings = {
        mgr = {
          show_hidden = false;
          sort_by = "mtime";
          sort_dir_first = true;
          sort_reverse = true;
        };
      };
    };
  };
}
