{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.xcode;
in {
  options.xcode = {
    enable = lib.mkEnableOption "Xcode/iOS development environment";
  };

  config = lib.mkIf cfg.enable {
    # Xcode/iOS development packages (only available on Darwin)
    environment.systemPackages = lib.optionals pkgs.stdenv.isDarwin (with pkgs; [
      ruby
      cocoapods
    ]);
  };
}