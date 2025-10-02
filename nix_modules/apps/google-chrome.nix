{
  pkgs-apps,
  lib,
  config,
  ...
}: let
  cfg = config.google-chrome;
in {
  options.google-chrome = {
    enable = lib.mkEnableOption "Google Chrome web browser";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs-apps.google-chrome
    ];
  };
}