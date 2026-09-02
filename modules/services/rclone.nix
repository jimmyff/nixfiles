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
    if pkgs-apps.stdenv.hostPlatform.isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  userGroup =
    if pkgs-apps.stdenv.hostPlatform.isDarwin
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

    koofr.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Configure the Koofr remote. Disable on hosts not granted the Koofr
        credentials in secrets.nix — declaring a secret a host cannot decrypt
        fails at activation.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Configure agenix identity paths for Darwin
    age.identityPaths = lib.mkIf pkgs-apps.stdenv.hostPlatform.isDarwin [
      "${homeDir}/.ssh/id_ed25519"
      "${homeDir}/.ssh/id_rsa"
    ];

    environment.systemPackages = [
      pkgs-stable.rclone
      rclone-sync
    ];

    age.secrets = lib.mkMerge [
      # Crypt passwords — shared by every remote that wraps one
      {
        rclone-crypt-pass = {
          file = nixfiles-vault + "/rclone-crypt-pass.age";
          mode = "600";
          owner = username;
          group = userGroup;
        };

        rclone-crypt-salt = {
          file = nixfiles-vault + "/rclone-crypt-salt.age";
          mode = "600";
          owner = username;
          group = userGroup;
        };
      }

      # Koofr credentials
      (lib.mkIf cfg.koofr.enable {
        rclone-koofr-user = {
          file = nixfiles-vault + "/rclone-koofr-user.age";
          mode = "600";
          owner = username;
          group = userGroup;
        };

        rclone-koofr-pass = {
          file = nixfiles-vault + "/rclone-koofr-pass.age";
          mode = "600";
          owner = username;
          group = userGroup;
        };
      })
    ];

    # Legacy ~/Cloud sync tree, paired with the Koofr remote. Being retired in
    # favour of ~/data; see plans/2026-08-18-cloud-backup.md.
    system.activationScripts.rcloneSetup = lib.mkIf cfg.koofr.enable ({
      text = ''
        mkdir -p "${homeDir}/Cloud"
        chown ${username}:${userGroup} "${homeDir}/Cloud"
      '';
    } // lib.optionalAttrs (!pkgs-apps.stdenv.hostPlatform.isDarwin) {
      deps = ["users" "groups"];
    });

    # Generate rclone.conf from secrets (runs after agenix). The config dir is
    # created here rather than in rcloneSetup above because nix-darwin only
    # interpolates a fixed list of activation script names and silently drops
    # custom ones — so on darwin rcloneSetup never runs at all.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      umask 077
      mkdir -p "${rcloneConfigDir}"

      CRYPT_PASS=$(cat /run/agenix/rclone-crypt-pass 2>/dev/null || echo "")
      CRYPT_SALT=$(cat /run/agenix/rclone-crypt-salt 2>/dev/null || echo "")

      ${
        if cfg.koofr.enable
        then ''
          KOOFR_USER=$(cat /run/agenix/rclone-koofr-user 2>/dev/null || echo "")
          KOOFR_PASS=$(cat /run/agenix/rclone-koofr-pass 2>/dev/null || echo "")

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
            chown ${username}:${userGroup} "${rcloneConfigDir}/rclone.conf"
            echo "Activated rclone with koofr remotes"
          else
            echo "Warning: rclone koofr secrets not available, skipping config generation"
          fi
        ''
        else ''
          echo "rclone: koofr disabled on this host; no remotes configured yet"
        ''
      }
    '';
  };
}
