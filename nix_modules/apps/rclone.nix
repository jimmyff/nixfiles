{
  pkgs-apps,
  lib,
  config,
  username,
  nixfiles-vault,
  self,
  ...
}: let
  cfg = config.rclone;

  homeDir =
    if pkgs-apps.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  userGroup =
    if pkgs-apps.stdenv.isDarwin
    then "staff"
    else "users";

  # Wrapper script to run rclone-sync.nu
  rclone-sync = pkgs-apps.writeShellScriptBin "rclone-sync" ''
    exec ${pkgs-apps.nushell}/bin/nu ${self}/scripts/rclone-sync/rclone-sync.nu "$@"
  '';
in {
  options.rclone = {
    enable = lib.mkEnableOption "rclone cloud sync tool";
  };

  config = lib.mkIf cfg.enable {
    # Configure agenix identity paths for Darwin
    age.identityPaths = lib.mkIf pkgs-apps.stdenv.isDarwin [
      "${homeDir}/.ssh/id_ed25519"
      "${homeDir}/.ssh/id_rsa"
    ];

    environment.systemPackages = [
      pkgs-apps.rclone
      rclone-sync
    ];

    # Decrypt config password
    age.secrets.rclone-config-pass = {
      file = nixfiles-vault + "/rclone-config-pass.age";
      mode = "600";
      owner = username;
      group = userGroup;
    };

    # Create ~/Cloud directory
    system.activationScripts.rcloneSetup = {
      text = ''
        mkdir -p "${homeDir}/Cloud"
        chown ${username}:${userGroup} "${homeDir}/Cloud"
        echo "Activated rclone"
      '';
      deps = ["users" "groups"];
    };
  };
}
