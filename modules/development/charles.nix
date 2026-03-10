{
  pkgs-stable,
  lib,
  config,
  ...
}: let
  cfg = config.charles;
in {
  options.charles = {
    enable = lib.mkEnableOption "Charles Proxy";
  };

  config = lib.mkIf cfg.enable (
    if pkgs-stable.stdenv.isDarwin
    then {
      homebrew.casks = ["charles"];
    }
    else {
      environment.systemPackages = [pkgs-stable.charles];
    }
  );
}
