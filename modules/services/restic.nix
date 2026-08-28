{ lib, config, pkgs-stable, username, nixfiles-vault, ... }:
let
  cfg = config.restic;
  isDarwin = pkgs-stable.stdenv.isDarwin;
  homeDir =
    if isDarwin
    then "/Users/${username}"
    else "/home/${username}";
  userGroup =
    if isDarwin
    then "staff"
    else "users";

  vaultDir = "${homeDir}/data/vault";

  passwordFile = "/run/agenix/restic-password";
  healthcheckFile = "/run/agenix/restic-healthcheck-url";

  cacheDir =
    if isDarwin
    then "${homeDir}/Library/Caches/restic"
    else "${homeDir}/.cache/restic";

  # Hourly encrypted snapshots of the vault tier. restic encrypts data, metadata
  # and filenames itself, so this targets koofr-raw: directly rather than the
  # koofr: crypt remote — layering crypt underneath would add a second password
  # to the restore path for no added confidentiality.
  resticBackup = pkgs-stable.writeShellScriptBin "restic-backup" ''
    set -euo pipefail

    export HOME="${homeDir}"
    export RCLONE_CONFIG="${homeDir}/.config/rclone/rclone.conf"
    export RESTIC_REPOSITORY="${cfg.repository}"
    export RESTIC_PASSWORD_FILE="${passwordFile}"
    export RESTIC_CACHE_DIR="${cacheDir}"

    # restic shells out to `rclone` for the rclone: backend, and launchd agents
    # get a near-empty PATH — coreutils covers date/cat, which the timestamps and
    # the healthcheck read rely on.
    export PATH="${pkgs-stable.rclone}/bin:${pkgs-stable.coreutils}/bin:$PATH"

    RESTIC="${pkgs-stable.restic}/bin/restic"
    CURL="${pkgs-stable.curl}/bin/curl"

    HEALTH_URL=""
    if [ -f "${healthcheckFile}" ]; then
      HEALTH_URL=$(cat "${healthcheckFile}")
    fi

    ping_health() {
      if [ -n "$HEALTH_URL" ]; then
        "$CURL" -fsS -m 10 --retry 3 "$HEALTH_URL$1" >/dev/null || true
      fi
    }

    on_error() {
      echo "restic-backup: FAILED at $(date -u +%Y-%m-%dT%H:%M:%SZ)" >&2
      ping_health "/fail"
    }
    trap on_error ERR

    echo "restic-backup: starting $(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Preflight. These must fail loudly rather than silently back up nothing.
    if [ ! -f "$RCLONE_CONFIG" ]; then
      echo "restic-backup: missing $RCLONE_CONFIG — is rclone.enable set on this host?" >&2
      exit 1
    fi
    if [ ! -f "$RESTIC_PASSWORD_FILE" ]; then
      echo "restic-backup: missing $RESTIC_PASSWORD_FILE — agenix secret not decrypted?" >&2
      exit 1
    fi

    MISSING=0
    for p in ${lib.escapeShellArgs cfg.paths}; do
      if [ ! -e "$p" ]; then
        echo "restic-backup: backup path does not exist: $p" >&2
        MISSING=1
      fi
    done
    if [ "$MISSING" -ne 0 ]; then
      exit 1
    fi

    # First run initialises the repository.
    if ! "$RESTIC" cat config >/dev/null 2>&1; then
      echo "restic-backup: initialising repository $RESTIC_REPOSITORY"
      "$RESTIC" init
    fi

    # .stfolder/.stversions are excluded ahead of Syncthing landing on this tier.
    # --retry-lock: wait rather than fail if another host holds the repo lock.
    "$RESTIC" backup ${lib.escapeShellArgs cfg.paths} \
      --tag automated \
      --retry-lock 5m \
      --exclude '.DS_Store' \
      --exclude '._*' \
      --exclude '.stfolder' \
      --exclude '.stversions' \
      --exclude '.syncthing.*.tmp'
    ${lib.optionalString cfg.prune ''
      "$RESTIC" forget \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 12 \
        --retry-lock 5m \
        --prune
    ''}
    echo "restic-backup: completed $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    ping_health ""
  '';
in {
  options.restic = {
    enable = lib.mkEnableOption "restic encrypted backups";

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ vaultDir ];
      description = "Absolute paths to back up. All must exist or the run fails.";
      example = [ "/Users/jimmyff/data/vault" ];
    };

    repository = lib.mkOption {
      type = lib.types.str;
      default = "rclone:koofr-raw:restic-vault";
      description = "restic repository URI. Targets the raw remote, not the crypt layer.";
    };

    prune = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Apply the retention policy after backup. Enable on exactly one host —
        prune takes an exclusive repository lock, so concurrent prunes contend.
        Retention groups by host and path, so one host pruning covers them all.
      '';
    };

    healthcheckUrlFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Vault filename containing a healthchecks.io ping URL. Null disables monitoring.";
      example = "restic-healthcheck-url.age";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Common: secret, packages, and the vault directory itself
    {
      age.secrets.restic-password = {
        file = nixfiles-vault + "/restic-password.age";
        mode = "600";
        owner = username;
        group = userGroup;
      };

      # restic on PATH for manual restores; see docs/restore.md
      environment.systemPackages = [ pkgs-stable.restic resticBackup ];
    }

    (lib.mkIf (cfg.healthcheckUrlFile != null) {
      age.secrets.restic-healthcheck-url = {
        file = nixfiles-vault + "/${cfg.healthcheckUrlFile}";
        mode = "600";
        owner = username;
        group = userGroup;
      };
    })

    # Linux: hourly timer. Persistent catches up after suspend/downtime;
    # RandomizedDelaySec staggers hosts so they rarely contend for the repo lock.
    (lib.optionalAttrs (!isDarwin) {
      # NixOS honours arbitrary activationScripts names.
      system.activationScripts.resticSetup = {
        text = ''
          mkdir -p "${vaultDir}"
          chown ${username}:${userGroup} "${homeDir}/data" "${vaultDir}"
        '';
        deps = ["users" "groups"];
      };

      systemd.services.restic-backup = {
        description = "restic snapshot of the vault tier";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = username;
          ExecStart = "${resticBackup}/bin/restic-backup";
        };
      };

      systemd.timers.restic-backup = {
        description = "Hourly restic snapshot of the vault tier";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "hourly";
          Persistent = true;
          RandomizedDelaySec = "5m";
        };
      };
    })

    # Darwin: hourly user agent. StartInterval rather than StartCalendarInterval
    # because launchd coalesces missed events and fires on wake — correct for a
    # laptop that is closed for much of the day.
    (lib.optionalAttrs isDarwin {
      age.identityPaths = [
        "${homeDir}/.ssh/id_ed25519"
        "${homeDir}/.ssh/id_rsa"
      ];

      # nix-darwin's activation script interpolates a fixed list of names, so a
      # custom `resticSetup` would be silently dropped. preActivation runs before
      # the launchd agents are loaded, so the directory exists before RunAtLoad
      # fires the first backup.
      system.activationScripts.preActivation.text = lib.mkAfter ''
        mkdir -p "${vaultDir}"
        chown ${username}:${userGroup} "${homeDir}/data" "${vaultDir}"
      '';

      launchd.user.agents.restic-backup = {
        serviceConfig = {
          ProgramArguments = [ "${resticBackup}/bin/restic-backup" ];
          StartInterval = 3600;
          RunAtLoad = true;
          ProcessType = "Background";
          StandardOutPath = "${homeDir}/Library/Logs/restic-backup.log";
          StandardErrorPath = "${homeDir}/Library/Logs/restic-backup.log";
        };
      };
    })
  ]);
}
