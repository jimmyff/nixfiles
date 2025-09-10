{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.raycast;
in {
  options.raycast = {
    enable = lib.mkEnableOption "Raycast productivity application";
  };

  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isDarwin) {
    environment.systemPackages = [
      pkgs.raycast
    ];
  };
}