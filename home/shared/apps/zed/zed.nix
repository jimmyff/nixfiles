{
  pkgs-dev-tools,
  lib,
  config,
  ...
}: let
  # Import shared utilities
  sharedLib = import ../../lib.nix { inherit lib config; pkgs = pkgs-dev-tools; };

  # Create Doppler-wrapped zed package
  wrappedZed = sharedLib.mkDopplerWrapper {
    package = pkgs-dev-tools.zed-editor;
    project = "ide";
    binaries = [ "zeditor" ];
  };
in {
  options = {
    zed_module.enable = lib.mkEnableOption "enables zed_module";
  };

  config = lib.mkIf config.zed_module.enable {
    programs.zed-editor = {
      enable = true;
      package = wrappedZed;
    };
  };
}
