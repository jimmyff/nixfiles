{
  pkgs-apps,
  pkgs-stable,
  pkgs-dev-tools,
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

  rcloneConfigDir = "${homeDir}/.config/rclone";

  # Wrapper script to run rclone-sync.nu
  rclone-sync = pkgs-apps.writeShellScriptBin "rclone-sync" ''
    exec ${pkgs-dev-tools.nushell}/bin/nu ${self}/scripts/rclone-sync/rclone-sync.nu "$@"
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
      pkgs-stable.rclone
      rclone-sync
    ];

    # Koofr credentials
    age.secrets.rclone-koofr-user = {
      file = nixfiles-vault + "/rclone-koofr-user.age";
      mode = "600";
      owner = username;
      group = userGroup;
    };

    age.secrets.rclone-koofr-pass = {
      file = nixfiles-vault + "/rclone-koofr-pass.age";
      mode = "600";
      owner = username;
      group = userGroup;
    };

    # Crypt passwords
    age.secrets.rclone-crypt-pass = {
      file = nixfiles-vault + "/rclone-crypt-pass.age";
      mode = "600";
      owner = username;
      group = userGroup;
    };

    age.secrets.rclone-crypt-salt = {
      file = nixfiles-vault + "/rclone-crypt-salt.age";
      mode = "600";
      owner = username;
      group = userGroup;
    };

    # Create ~/Cloud directory (runs early)
    system.activationScripts.rcloneSetup = {
      text = ''
        mkdir -p "${homeDir}/Cloud"
        mkdir -p "${rcloneConfigDir}"
        chown ${username}:${userGroup} "${homeDir}/Cloud"
        chown ${username}:${userGroup} "${rcloneConfigDir}"
      '';
    } // lib.optionalAttrs (!pkgs-apps.stdenv.isDarwin) {
      deps = ["users" "groups"];
    };

    # Generate rclone.conf from secrets (runs after agenix)
    system.activationScripts.postActivation.text = lib.mkAfter ''
      # Generate rclone.conf from agenix secrets
      KOOFR_USER=$(cat /run/agenix/rclone-koofr-user 2>/dev/null || echo "")
      KOOFR_PASS=$(cat /run/agenix/rclone-koofr-pass 2>/dev/null || echo "")
      CRYPT_PASS=$(cat /run/agenix/rclone-crypt-pass 2>/dev/null || echo "")
      CRYPT_SALT=$(cat /run/agenix/rclone-crypt-salt 2>/dev/null || echo "")

      if [ -n "$KOOFR_USER" ] && [ -n "$KOOFR_PASS" ]; then
        cat > "${rcloneConfigDir}/rclone.conf" << EOF
[koofr-raw]
type = koofr
provider = koofr
user = $KOOFR_USER
password = $KOOFR_PASS

[koofr]
type = crypt
remote = koofr-raw:
password = $CRYPT_PASS
password2 = $CRYPT_SALT

[default]
type = alias
remote = koofr:
EOF
        chmod 600 "${rcloneConfigDir}/rclone.conf"
        chown ${username}:${userGroup} "${rcloneConfigDir}/rclone.conf"
        echo "Activated rclone with koofr remotes"
      else
        echo "Warning: rclone secrets not available, skipping config generation"
      fi
    '';
  };
}
