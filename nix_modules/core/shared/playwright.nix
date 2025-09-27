{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.playwright;
in {
  options.playwright = {
    enable = lib.mkEnableOption "Playwright testing framework";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.playwright-driver
    ];
  };
}