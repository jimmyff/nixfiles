{
  pkgs-stable,
  lib,
  config,
  username,
  ...
}: let
  cfg = config.docker;
in {
  options.docker = {
    enable = lib.mkEnableOption "Docker container platform";
  };

  config = lib.mkIf cfg.enable (
    if pkgs-stable.stdenv.isDarwin
    then {
      homebrew.casks = ["docker"];
    }
    else {
      virtualisation.docker.enable = true;
      users.users.${username}.extraGroups = ["docker"];
    }
  );
}
