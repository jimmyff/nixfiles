# On-demand sops wrappers for development secrets.
#
# Pattern: each wrapper is a writeShellScriptBin that templates the vault's
# nix store path into its body at build time, uses `sops -d --output` to
# materialise any required binary files into a `mktemp -d` tempdir, exports
# env vars (via `sops exec-env` for yaml password files), runs the user
# command as a child, and an EXIT trap wipes the tempdir afterwards.
#
# Also bootstraps ~/.config/sops/age/keys.txt from the user's SSH key on
# first rebuild so sops has an identity to decrypt with.
#
# The wrappers defined below (`rocketware-android-sign`, `rocketware-minisign`)
# are specific to this repo's rocketware projects and serve as a working
# example of the pattern. Add your own wrappers alongside them as needed.
# See docs/secrets.md for the generic workflow.
{
  pkgs-stable,
  lib,
  config,
  username,
  nixfiles-vault,
  ...
}: let
  homeDir =
    if pkgs-stable.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  userGroup =
    if pkgs-stable.stdenv.isDarwin
    then "staff"
    else "users";

  sopsBin = "${pkgs-stable.sops}/bin/sops";

  # Wraps a build command with on-demand decryption of Android signing
  # keystores and their associated password env vars.
  #
  # Modes:
  #   standard    — standard flavor (release key, alias 'key')
  #   googleplay  — googleplay flavor (upload key, alias 'upload')
  #   all         — both keystores simultaneously for full-release builds
  #
  # Implementation: creates a secure tempdir, calls `sops -d --output` once
  # per keystore, exports path env vars, chains `sops exec-env` for the yaml
  # password files, then runs the user command as a child so the EXIT trap
  # can wipe the tempdir afterwards. The trap fires on any exit path
  # (normal, error, SIGINT, SIGTERM) thanks to bash's EXIT trap semantics.
  rocketware-android-sign = pkgs-stable.writeShellScriptBin "rocketware-android-sign" ''
    set -euo pipefail

    SOPS=${sopsBin}
    VAULT=${nixfiles-vault}

    STANDARD_KEYSTORE_SOPS="$VAULT/sops/rocketware-android-release-key.jks.sops"
    GOOGLEPLAY_KEYSTORE_SOPS="$VAULT/sops/rocketware-android-googleplay-upload-key.jks.sops"
    STANDARD_ENV_SOPS="$VAULT/sops/rocketware-android-signing.yaml"
    GOOGLEPLAY_ENV_SOPS="$VAULT/sops/rocketware-android-googleplay.yaml"

    usage() {
      cat >&2 <<'USAGE'
    Usage: rocketware-android-sign <standard|googleplay|all> -- <command> [args...]

    Modes:
      standard    Materialise the release-signing keystore (alias 'key').
                  Sets ANDROID_KEYSTORE_PATH, ANDROID_STANDARD_KEYSTORE_PATH,
                  ANDROID_KEY_ALIAS=key, and the standard password env vars.
                  Use for direct `flutter run --flavor standard` or single-
                  flavor script invocations.

      googleplay  Materialise the Play Store upload keystore (alias 'upload').
                  Sets ANDROID_KEYSTORE_PATH, ANDROID_GOOGLEPLAY_UPLOAD_KEYSTORE_PATH,
                  ANDROID_KEY_ALIAS=upload, and the googleplay password env vars.
                  Use for direct `flutter run --flavor googleplay` or single-
                  flavor script invocations.

      all         Materialise BOTH keystores. Sets the prefixed path env vars
                  (ANDROID_STANDARD_KEYSTORE_PATH + ANDROID_GOOGLEPLAY_UPLOAD_KEYSTORE_PATH)
                  and both password sets, but NOT the unprefixed gradle names
                  — consumers must select per flavor from the prefixed names.
                  Use for full-release builds via `nu package_android.nu`.

    Examples:
      # Dev run on device (one flavor):
      rocketware-android-sign googleplay -- flutter run --flavor googleplay \
        -t lib/main_android_googleplay.dart --release --device-id <id>

      # Single-flavor packaging:
      rocketware-android-sign googleplay -- nu package_android.nu --flavor googleplay

      # Full release (both flavors):
      rocketware-android-sign all -- nu package_android.nu
    USAGE
      exit 64
    }

    # Parse arguments
    mode="''${1:-}"
    case "$mode" in
      standard|googleplay|all) shift ;;
      *) usage ;;
    esac
    [ "''${1:-}" = "--" ] || usage
    shift
    [ $# -ge 1 ] || usage

    # Pre-flight: sops identity
    if [ ! -r "$HOME/.config/sops/age/keys.txt" ]; then
      echo "ERROR: sops identity not found at ~/.config/sops/age/keys.txt" >&2
      echo "       Run a system rebuild to bootstrap it from your SSH key." >&2
      exit 1
    fi

    # Pre-flight: encrypted files for the selected mode
    require_file() {
      if [ ! -f "$1" ]; then
        echo "ERROR: required sops file missing: $1" >&2
        echo "       The nixfiles-vault flake input may be stale." >&2
        echo "       Run: nix flake update nixfiles-vault && rebuild your system" >&2
        exit 1
      fi
    }
    case "$mode" in
      standard)
        require_file "$STANDARD_KEYSTORE_SOPS"
        require_file "$STANDARD_ENV_SOPS"
        ;;
      googleplay)
        require_file "$GOOGLEPLAY_KEYSTORE_SOPS"
        require_file "$GOOGLEPLAY_ENV_SOPS"
        ;;
      all)
        require_file "$STANDARD_KEYSTORE_SOPS"
        require_file "$STANDARD_ENV_SOPS"
        require_file "$GOOGLEPLAY_KEYSTORE_SOPS"
        require_file "$GOOGLEPLAY_ENV_SOPS"
        ;;
    esac

    # Create a secure tempdir for materialised keystores. Trap ensures
    # cleanup on ANY exit path (success, error, SIGINT, SIGTERM).
    TMPDIR_KS=$(mktemp -d -t rocketware-sign-XXXXXXXX)
    trap 'rm -rf -- "$TMPDIR_KS"' EXIT

    # Materialise the keystores the selected mode needs.
    if [ "$mode" = "standard" ] || [ "$mode" = "all" ]; then
      "$SOPS" --decrypt --input-type binary --output-type binary \
        --output "$TMPDIR_KS/standard.jks" "$STANDARD_KEYSTORE_SOPS"
      chmod 600 "$TMPDIR_KS/standard.jks"
      export ANDROID_STANDARD_KEYSTORE_PATH="$TMPDIR_KS/standard.jks"
    fi
    if [ "$mode" = "googleplay" ] || [ "$mode" = "all" ]; then
      "$SOPS" --decrypt --input-type binary --output-type binary \
        --output "$TMPDIR_KS/googleplay.jks" "$GOOGLEPLAY_KEYSTORE_SOPS"
      chmod 600 "$TMPDIR_KS/googleplay.jks"
      export ANDROID_GOOGLEPLAY_UPLOAD_KEYSTORE_PATH="$TMPDIR_KS/googleplay.jks"
    fi

    # `sops exec-env` takes the command as a SINGLE shell-command string
    # (which it runs via sh -c), not as separate argv elements. Build a
    # properly-quoted command string from "$@" via printf %q. Run as a
    # child (not exec) so the EXIT trap fires afterwards.
    quoted_cmd=$(printf '%q ' "$@")
    case "$mode" in
      standard)
        # The standard yaml file's keys are already named ANDROID_KEYSTORE_PASSWORD
        # and ANDROID_KEY_PASSWORD — the names gradle reads — so no aliasing
        # is needed. sops exec-env loads them directly.
        export ANDROID_KEYSTORE_PATH="$TMPDIR_KS/standard.jks"
        export ANDROID_KEY_ALIAS=key
        "$SOPS" exec-env "$STANDARD_ENV_SOPS" "$quoted_cmd"
        ;;
      googleplay)
        # The googleplay yaml uses prefixed key names
        # (ANDROID_GOOGLEPLAY_UPLOAD_KEYSTORE_PASSWORD,
        #  ANDROID_GOOGLEPLAY_UPLOAD_KEY_PASSWORD) so two sets of consumers
        # can coexist in `all` mode without colliding. For single-flavor
        # googleplay invocations gradle still reads ANDROID_KEYSTORE_PASSWORD
        # and ANDROID_KEY_PASSWORD though, so we alias the prefixed names
        # to the unprefixed gradle names inside sops's sh -c command before
        # exec'ing the user command.
        export ANDROID_KEYSTORE_PATH="$TMPDIR_KS/googleplay.jks"
        export ANDROID_KEY_ALIAS=upload
        aliased_cmd='export ANDROID_KEYSTORE_PASSWORD="$ANDROID_GOOGLEPLAY_UPLOAD_KEYSTORE_PASSWORD"; export ANDROID_KEY_PASSWORD="$ANDROID_GOOGLEPLAY_UPLOAD_KEY_PASSWORD"; exec '"$quoted_cmd"
        "$SOPS" exec-env "$GOOGLEPLAY_ENV_SOPS" "$aliased_cmd"
        ;;
      all)
        # Nest two sops exec-env calls: outer loads STANDARD vars and runs
        # an inner sops exec-env that loads GOOGLEPLAY vars and runs the cmd.
        # The inner invocation must itself be a single-string command for
        # the outer's sh -c to parse correctly. No aliasing here — `all`
        # mode is for orchestration scripts that pick the right per-flavor
        # env var name themselves.
        inner_cmd=$(printf '%q exec-env %q %q' "$SOPS" "$GOOGLEPLAY_ENV_SOPS" "$quoted_cmd")
        "$SOPS" exec-env "$STANDARD_ENV_SOPS" "$inner_cmd"
        ;;
    esac
  '';

  # Same tempdir+trap pattern as rocketware-android-sign, one keystore only.
  rocketware-minisign = pkgs-stable.writeShellScriptBin "rocketware-minisign" ''
    set -euo pipefail

    SOPS=${sopsBin}
    VAULT=${nixfiles-vault}

    KEYSTORE_SOPS="$VAULT/sops/rocketware-minisign.key.sops"
    ENV_SOPS="$VAULT/sops/rocketware-minisign.yaml"

    usage() {
      cat >&2 <<'USAGE'
    Usage: rocketware-minisign -- <command> [args...]

    Decrypts the rocketware minisign signing key (ephemeral tempfile) and
    its password from sops, then runs the given command with:
      MINISIGN_KEY_PATH               path to ephemeral decrypted key
      ROCKETWARE_MINISIGN_PASSWORD    signing key password

    Example:
      rocketware-minisign -- nu workspace/release-cache.nu
    USAGE
      exit 64
    }

    [ "''${1:-}" = "--" ] || usage
    shift
    [ $# -ge 1 ] || usage

    if [ ! -r "$HOME/.config/sops/age/keys.txt" ]; then
      echo "ERROR: sops identity not found at ~/.config/sops/age/keys.txt" >&2
      echo "       Run a system rebuild to bootstrap it from your SSH key." >&2
      exit 1
    fi
    if [ ! -f "$KEYSTORE_SOPS" ]; then
      echo "ERROR: sops minisign key missing: $KEYSTORE_SOPS" >&2
      echo "       Run: nix flake update nixfiles-vault && rebuild your system" >&2
      exit 1
    fi
    if [ ! -f "$ENV_SOPS" ]; then
      echo "ERROR: sops minisign env file missing: $ENV_SOPS" >&2
      echo "       Run: nix flake update nixfiles-vault && rebuild your system" >&2
      exit 1
    fi

    TMPDIR_KS=$(mktemp -d -t rocketware-minisign-XXXXXXXX)
    trap 'rm -rf -- "$TMPDIR_KS"' EXIT

    "$SOPS" --decrypt --input-type binary --output-type binary \
      --output "$TMPDIR_KS/minisign.key" "$KEYSTORE_SOPS"
    chmod 600 "$TMPDIR_KS/minisign.key"
    export MINISIGN_KEY_PATH="$TMPDIR_KS/minisign.key"

    # sops exec-env takes the command as a single shell string (run via sh -c)
    quoted_cmd=$(printf '%q ' "$@")
    "$SOPS" exec-env "$ENV_SOPS" "$quoted_cmd"
  '';

  # Env-var-only wrapper for Apple notarization credentials. No binary
  # keystore — notarytool talks to Apple's API with Apple ID + app-specific
  # password + team ID. Exports:
  #   APPLE_NOTARIZE_USERNAME    Apple ID email
  #   APPLE_NOTARIZE_PASSWORD    app-specific password (xxxx-xxxx-xxxx-xxxx)
  #   APPLE_NOTARIZE_TEAM_ID     Apple Developer Team ID
  rocketware-apple-notarize = pkgs-stable.writeShellScriptBin "rocketware-apple-notarize" ''
    set -euo pipefail

    SOPS=${sopsBin}
    VAULT=${nixfiles-vault}

    ENV_SOPS="$VAULT/sops/rocketware-apple-notarize.yaml"

    usage() {
      cat >&2 <<'USAGE'
    Usage: rocketware-apple-notarize -- <command> [args...]

    Decrypts Apple notarization credentials (ephemeral env vars) from sops,
    then runs the given command with:
      APPLE_NOTARIZE_USERNAME    Apple ID email
      APPLE_NOTARIZE_PASSWORD    app-specific password (xxxx-xxxx-xxxx-xxxx)
      APPLE_NOTARIZE_TEAM_ID     Apple Developer Team ID

    Example:
      rocketware-apple-notarize -- nu package_macos.nu --flavor macos
    USAGE
      exit 64
    }

    [ "''${1:-}" = "--" ] || usage
    shift
    [ $# -ge 1 ] || usage

    if [ ! -r "$HOME/.config/sops/age/keys.txt" ]; then
      echo "ERROR: sops identity not found at ~/.config/sops/age/keys.txt" >&2
      echo "       Run a system rebuild to bootstrap it from your SSH key." >&2
      exit 1
    fi
    if [ ! -f "$ENV_SOPS" ]; then
      echo "ERROR: sops apple-notarize env file missing: $ENV_SOPS" >&2
      echo "       Run: nix flake update nixfiles-vault && rebuild your system" >&2
      exit 1
    fi

    # sops exec-env takes the command as a single shell string (run via sh -c)
    quoted_cmd=$(printf '%q ' "$@")
    "$SOPS" exec-env "$ENV_SOPS" "$quoted_cmd"
  '';

  # Unified Apple signing wrapper. Materialises signing certificates
  # (.p12 files) and the App Store Connect API key (.p8 file) into an
  # ephemeral tempdir, then exports env vars pointing at those files plus
  # the passwords + identity names loaded from a single shared yaml.
  #
  # Modes:
  #   direct    — Developer ID Application cert only (direct macOS
  #               distribution: DMG + notarize via chained
  #               rocketware-apple-notarize)
  #   appstore  — Apple Distribution (sign .app) + Mac Installer
  #               Distribution (sign .pkg) + App Store Connect API key
  #               (Transporter upload)
  #   all       — Materialise everything from both modes above for
  #               full-release builds via `nu package_macos.nu`
  #
  # Single shared yaml `rocketware-apple-sign.yaml` holds all passwords,
  # identity names (e.g. "Apple Distribution: Rocketware Ltd (TEAMID)"),
  # team ID, and App Store Connect key ID/issuer ID. This keeps sops file
  # count down and avoids duplicating team ID across three yamls.
  #
  # Deviation from other wrappers — age identity resolution:
  # Accepts SOPS_AGE_KEY (raw key) or SOPS_AGE_KEY_FILE (path) env vars
  # in addition to the usual ~/.config/sops/age/keys.txt fallback. This
  # enables CI contexts where the age key arrives as an injected secret
  # rather than as a file. sops itself honours both env vars natively —
  # we just need to avoid erroring out when the file fallback is absent.
  rocketware-apple-sign = pkgs-stable.writeShellScriptBin "rocketware-apple-sign" ''
    set -euo pipefail

    SOPS=${sopsBin}
    VAULT=${nixfiles-vault}

    APP_DIST_P12_SOPS="$VAULT/sops/rocketware-apple-sign-app-distribution.p12.sops"
    INSTALLER_P12_SOPS="$VAULT/sops/rocketware-apple-sign-mac-installer.p12.sops"
    DEV_ID_APP_P12_SOPS="$VAULT/sops/rocketware-apple-sign-developer-id-app.p12.sops"
    API_KEY_P8_SOPS="$VAULT/sops/rocketware-apple-sign-api-key.p8.sops"
    ENV_SOPS="$VAULT/sops/rocketware-apple-sign.yaml"

    usage() {
      cat >&2 <<'USAGE'
    Usage: rocketware-apple-sign <direct|appstore|all> -- <command> [args...]

    Modes:
      direct    Materialise the Developer ID Application .p12 into an
                ephemeral tempfile. Exports:
                  APPLE_DEVELOPER_ID_APP_CERT_P12_PATH
                  APPLE_DEVELOPER_ID_APP_CERT_PASSWORD
                  APPLE_DEVELOPER_ID_CERT_NAME
                  APPLE_TEAM_ID
                Use for direct macOS distribution (DMG + notarize).
                Typically chained: `rocketware-apple-sign direct --
                rocketware-apple-notarize -- nu package_macos.nu --flavor macos`

      appstore  Materialise Apple Distribution + Mac Installer
                Distribution .p12s and the App Store Connect API key .p8.
                Exports:
                  APPLE_DISTRIBUTION_CERT_P12_PATH
                  APPLE_DISTRIBUTION_CERT_PASSWORD
                  APPLE_DISTRIBUTION_CERT_NAME
                  APPLE_INSTALLER_CERT_P12_PATH
                  APPLE_INSTALLER_CERT_PASSWORD
                  APPLE_INSTALLER_CERT_NAME
                  APPLE_APPSTORE_API_KEY_PATH
                  APPLE_APPSTORE_API_KEY_ID
                  APPLE_APPSTORE_API_ISSUER_ID
                  APPLE_TEAM_ID
                Use for Mac App Store distribution (.pkg + Transporter).

      all       Materialise everything from both modes simultaneously.
                Use for full-release builds that touch both flavors:
                  rocketware-apple-sign all -- rocketware-apple-notarize \
                    -- nu package_macos.nu

    All modes load passwords + identity names from the shared sops yaml
    rocketware-apple-sign.yaml.
    USAGE
      exit 64
    }

    # Parse arguments
    mode="''${1:-}"
    case "$mode" in
      direct|appstore|all) shift ;;
      *) usage ;;
    esac
    [ "''${1:-}" = "--" ] || usage
    shift
    [ $# -ge 1 ] || usage

    # Pre-flight: age identity must be reachable via env var OR file.
    # sops itself honours SOPS_AGE_KEY / SOPS_AGE_KEY_FILE natively — we
    # just need to avoid erroring out when the file fallback is absent
    # (e.g. on a CI runner with the key injected via env).
    if [ -n "''${SOPS_AGE_KEY:-}" ]; then
      : # sops honours SOPS_AGE_KEY directly
    elif [ -n "''${SOPS_AGE_KEY_FILE:-}" ]; then
      : # sops honours SOPS_AGE_KEY_FILE directly
    elif [ -r "$HOME/.config/sops/age/keys.txt" ]; then
      : # sops will find this on its own
    else
      echo "ERROR: no sops identity found." >&2
      echo "       Set SOPS_AGE_KEY (raw key), SOPS_AGE_KEY_FILE (path)," >&2
      echo "       or run a system rebuild to bootstrap ~/.config/sops/age/keys.txt." >&2
      exit 1
    fi

    # Pre-flight: encrypted files for the selected mode
    require_file() {
      if [ ! -f "$1" ]; then
        echo "ERROR: required sops file missing: $1" >&2
        echo "       The nixfiles-vault flake input may be stale." >&2
        echo "       Run: nix flake update nixfiles-vault && rebuild your system" >&2
        exit 1
      fi
    }
    require_file "$ENV_SOPS"  # yaml is always needed
    case "$mode" in
      direct)
        require_file "$DEV_ID_APP_P12_SOPS"
        ;;
      appstore)
        require_file "$APP_DIST_P12_SOPS"
        require_file "$INSTALLER_P12_SOPS"
        require_file "$API_KEY_P8_SOPS"
        ;;
      all)
        require_file "$DEV_ID_APP_P12_SOPS"
        require_file "$APP_DIST_P12_SOPS"
        require_file "$INSTALLER_P12_SOPS"
        require_file "$API_KEY_P8_SOPS"
        ;;
    esac

    # Create a secure tempdir for materialised certs + API key. Trap
    # ensures cleanup on ANY exit path (success, error, SIGINT, SIGTERM).
    TMPDIR_KS=$(mktemp -d -t rocketware-apple-sign-XXXXXXXX)
    trap 'rm -rf -- "$TMPDIR_KS"' EXIT

    # Materialise cert .p12s for the selected mode. Each file is chmod
    # 600 immediately after decryption so concurrent processes on the
    # machine can't read it.
    if [ "$mode" = "direct" ] || [ "$mode" = "all" ]; then
      "$SOPS" --decrypt --input-type binary --output-type binary \
        --output "$TMPDIR_KS/developer_id_application.p12" "$DEV_ID_APP_P12_SOPS"
      chmod 600 "$TMPDIR_KS/developer_id_application.p12"
      export APPLE_DEVELOPER_ID_APP_CERT_P12_PATH="$TMPDIR_KS/developer_id_application.p12"
    fi
    if [ "$mode" = "appstore" ] || [ "$mode" = "all" ]; then
      "$SOPS" --decrypt --input-type binary --output-type binary \
        --output "$TMPDIR_KS/app_distribution.p12" "$APP_DIST_P12_SOPS"
      chmod 600 "$TMPDIR_KS/app_distribution.p12"
      export APPLE_DISTRIBUTION_CERT_P12_PATH="$TMPDIR_KS/app_distribution.p12"

      "$SOPS" --decrypt --input-type binary --output-type binary \
        --output "$TMPDIR_KS/mac_installer_distribution.p12" "$INSTALLER_P12_SOPS"
      chmod 600 "$TMPDIR_KS/mac_installer_distribution.p12"
      export APPLE_INSTALLER_CERT_P12_PATH="$TMPDIR_KS/mac_installer_distribution.p12"

      "$SOPS" --decrypt --input-type binary --output-type binary \
        --output "$TMPDIR_KS/AuthKey.p8" "$API_KEY_P8_SOPS"
      chmod 600 "$TMPDIR_KS/AuthKey.p8"
      export APPLE_APPSTORE_API_KEY_PATH="$TMPDIR_KS/AuthKey.p8"
    fi

    # `sops exec-env` takes the command as a SINGLE shell-command string
    # (which it runs via sh -c), not as separate argv elements. Build a
    # properly-quoted command string from "$@" via printf %q. Run as a
    # child (not exec) so the EXIT trap fires afterwards.
    #
    # No mode branching here — all modes load the same shared yaml, which
    # defines every env var that any mode could need. Unused vars for the
    # current mode are simply present but ignored by downstream consumers.
    quoted_cmd=$(printf '%q ' "$@")
    "$SOPS" exec-env "$ENV_SOPS" "$quoted_cmd"
  '';

in {
  config = lib.mkIf config.development.enable {
    environment.systemPackages = [
      rocketware-android-sign
      rocketware-minisign
      rocketware-apple-notarize
      rocketware-apple-sign
    ];

    # Bootstrap sops age identity from the user's SSH key on first rebuild.
    # Must extend the canonical `postActivation` script: nix-darwin silently
    # drops custom activationScripts names. Runs as root, so the file is
    # chowned to the user afterwards. Parent dirs are chowned too in case
    # .config didn't already exist.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      SSH_KEY="${homeDir}/.ssh/id_ed25519"
      SOPS_DIR="${homeDir}/.config/sops"
      SOPS_AGE_DIR="$SOPS_DIR/age"
      SOPS_KEY_FILE="$SOPS_AGE_DIR/keys.txt"

      if [ ! -f "$SOPS_KEY_FILE" ]; then
        if [ -f "$SSH_KEY" ]; then
          mkdir -p "$SOPS_AGE_DIR"
          if ${pkgs-stable.ssh-to-age}/bin/ssh-to-age -private-key -i "$SSH_KEY" > "$SOPS_KEY_FILE" 2>/dev/null; then
            chmod 600 "$SOPS_KEY_FILE"
            chown ${username}:${userGroup} "$SOPS_KEY_FILE"
            chown ${username}:${userGroup} "$SOPS_AGE_DIR" 2>/dev/null || true
            chown ${username}:${userGroup} "$SOPS_DIR" 2>/dev/null || true
            echo "🔐 Bootstrapped sops age identity at $SOPS_KEY_FILE"
          else
            rm -f "$SOPS_KEY_FILE"
            echo "⚠️  Failed to derive sops age identity from $SSH_KEY"
            echo "    The SSH key may be passphrase-protected; sops requires an unencrypted key."
            echo "    Run manually: ssh-to-age -private-key -i $SSH_KEY > $SOPS_KEY_FILE && chmod 600 $SOPS_KEY_FILE"
          fi
        else
          echo "⚠️  Skipping sops bootstrap: $SSH_KEY not found"
        fi
      fi
    '';
  };
}
