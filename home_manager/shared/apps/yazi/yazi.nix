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
        catppuccin-frappe = pkgs.fetchFromGitHub {
          owner = "yazi-rs";
          repo = "flavors";
          rev = "3e6da982edcb113d584b020d7ed08ef809c29a39";
          sha256 = "sha256-b9QtmZN1sxYJr93OPUCckWPBXiOe3Qb+6xclBHafLrU=";
          sparseCheckout = [ "catppuccin-frappe.yazi" ];
        } + "/catppuccin-frappe.yazi";
        dracula = pkgs.fetchFromGitHub {
          owner = "dracula";
          repo = "yazi";
          rev = "main";
          sha256 = "sha256-dFhBT9s/54jDP6ZpRkakbS5khUesk0xEtv+xtPrqHVo=";
        };
      };
      settings = {
        mgr = {
          show_hidden = false;
          sort_by = "mtime";
          sort_dir_first = true;
          sort_reverse = true;
        };
      };
      theme = {
        flavor = {
          dark = "dracula";
        };
      };
    };
  };
}
