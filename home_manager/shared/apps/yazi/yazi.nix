{
  pkgs,
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
      flavors = {
        flexoki-dark = pkgs.fetchFromGitHub {
          owner = "gosxrgxx";
          repo = "flexoki-dark.yazi";
          rev = "main";
          sha256 = "1lxzd6kya0cfv0c1sg8qpgj9pl8q98489rm40j3kwn4yxk2q0hbw";
        };
      };
      settings = {
        mgr = {
          show_hidden = true;
          sort_by = "mtime";
          sort_dir_first = true;
          sort_reverse = true;
        };
      };
      theme = {
        flavor = {
          dark = "flexoki-dark";
        };
      };
    };
  };
}
