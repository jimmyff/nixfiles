{ lib, config, pkgs-stable, username, nixfiles-vault, ... }:
let
  cfg = config.minisign;
  homeDir =
    if pkgs-stable.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";
  userGroup =
    if pkgs-stable.stdenv.isDarwin
    then "staff"
    else "users";
in {
  options.minisign = {
    enable = lib.mkEnableOption "Minisign release signing";
  };

  config = lib.mkIf cfg.enable {
    age.secrets.minisign-rocketware-signing-key = {
      file = nixfiles-vault + "/minisign-rocketware-signing-key.age";
      path = "${homeDir}/.minisign/minisign-rocketware.key";
      mode = "600";
      owner = username;
      group = userGroup;
    };
  };
}
