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
      homebrew.casks = ["docker-desktop"]; # renamed upstream from "docker"
    }
    else {
      virtualisation.docker.enable = true;
      # nixos-25.11's default docker (28.5.2) is marked insecure — upstream stopped
      # maintaining the 28 series in Nov 2025. docker_29 ships in the same nixpkgs,
      # so this stays on stable rather than mixing channels.
      virtualisation.docker.package = pkgs-stable.docker_29;
      users.users.${username}.extraGroups = ["docker"];
    }
  );
}
