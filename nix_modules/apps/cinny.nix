{
  pkgs-apps,
  lib,
  config,
  ...
}: let
  cfg = config.cinny;
in {
  options.cinny = {
    enable = lib.mkEnableOption "Cinny Matrix client";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs-apps.cinny-desktop
    ];
  };
}
