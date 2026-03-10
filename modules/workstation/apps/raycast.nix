{
  pkgs-apps,
  lib,
  config,
  ...
}: let
  cfg = config.raycast;
in {
  options.raycast = {
    enable = lib.mkEnableOption "Raycast productivity application";
  };

  config = lib.mkIf (cfg.enable && pkgs-apps.stdenv.hostPlatform.isDarwin) {
    environment.systemPackages = [
      pkgs-apps.raycast
    ];
  };
}