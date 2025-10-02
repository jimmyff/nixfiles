{
  pkgs-apps,
  lib,
  config,
  ...
}: let
  cfg = config.signal;
in {
  options.signal = {
    enable = lib.mkEnableOption "Signal Desktop messaging application";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs-apps.signal-desktop-bin
    ];
  };
}