{
  pkgs-apps,
  lib,
  config,
  ...
}:
let
  sharedLib = import ../lib.nix { inherit lib config; pkgs = pkgs-apps; };
in {
  options = {
    iamb_module.enable = lib.mkEnableOption "enables iamb_module";
  };

  config = lib.mkIf config.iamb_module.enable {
    programs.iamb = {
      enable = true;

      settings = {
        default_profile = "matrix.org";

        profiles."matrix.org" = {
          user_id = "@jimmyff:matrix.org";
        };

        settings = {
          image_preview = {
            protocol = {
              type = "kitty";
            };
            size = {
              height = 10;
              width = 66;
            };
          };
        };
      };
    };

    # Darwin-specific: Create symlink from default iamb location to home-manager config
    home.activation = sharedLib.mkDarwinAppSupportSymlink { appName = "iamb"; };
  };
}