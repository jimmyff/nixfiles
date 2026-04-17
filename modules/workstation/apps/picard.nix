{
  pkgs-apps,
  lib,
  config,
  ...
}: let
  cfg = config.picard;
in {
  options.picard = {
    enable = lib.mkEnableOption "MusicBrainz Picard audio tagger";
  };

  config = lib.mkIf cfg.enable (
    if pkgs-apps.stdenv.isDarwin
    then {
      homebrew.casks = ["musicbrainz-picard"];
    }
    else {
      environment.systemPackages = [pkgs-apps.picard];
    }
  );
}
