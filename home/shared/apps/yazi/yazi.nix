{
  pkgs-apps,
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
      flavors = {
        flexoki-dark = pkgs-apps.fetchFromGitHub {
          owner = "gosxrgxx";
          repo = "flexoki-dark.yazi";
          rev = "main";
          sha256 = "0rjr1qrs85877ywv1n5sva8y6s6iy9qz7376ydz3ka0na1s15ifg";
        };
        catppuccin-frappe = pkgs-apps.fetchFromGitHub {
          owner = "yazi-rs";
          repo = "flavors";
          rev = "3e6da982edcb113d584b020d7ed08ef809c29a39";
          sha256 = "sha256-b9QtmZN1sxYJr93OPUCckWPBXiOe3Qb+6xclBHafLrU=";
          sparseCheckout = [ "catppuccin-frappe.yazi" ];
        } + "/catppuccin-frappe.yazi";
        dracula = pkgs-apps.fetchFromGitHub {
          owner = "dracula";
          repo = "yazi";
          rev = "main";
          sha256 = "059i9jssq8sknvv0caaax61navs87hx4z3zv7a373vj2nyvbf9y2";
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
