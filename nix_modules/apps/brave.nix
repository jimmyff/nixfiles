{
  pkgs-apps,
  lib,
  config,
  ...
}: let
  cfg = config.brave;
in {
  # TODO: Switch to Helium browser when available in nixpkgs
  # https://github.com/nickcao/nixpkgs/pkgs/by-name/he/helium-browser
  # Brave is a temporary solution due to google-chrome updater being broken

  options.brave = {
    enable = lib.mkEnableOption "Brave web browser";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs-apps.brave
    ];
  };
}
