# Sops wrapper derivation registry.
#
# Pure function (no NixOS module context) that returns wrapper derivations
# keyed by name. Consumed by:
#   - sops-wrappers.nix (host-level systemPackages)
#   - kiln/lib.nix (container/devShell string→derivation resolution)
{ pkgs, nixfilesVault }:
let
  mkSopsWrapper = import ./sops-wrappers-lib.nix;
in {

  # Wraps a build command with on-demand decryption of Android signing
  # keystores and their associated password env vars.
  #
  # Modes:
  #   standard    — standard flavor (release key, alias 'key')
  #   googleplay  — googleplay flavor (upload key, alias 'upload')
  #   all         — both keystores simultaneously for full-release builds
  #
  # Uses body override: mode dispatch, env-var aliasing in googleplay mode,
  # and nested sops exec-env in `all` mode don't fit the standard template.
  rocketware-android-sign = mkSopsWrapper {
    name = "rocketware-android-sign";
    inherit pkgs nixfilesVault;
    body = ''

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

      # Pre-flight: encrypted files for the selected mode
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
  };

  # Simple wrapper: single binary keystore + single env yaml.
  rocketware-minisign = mkSopsWrapper {
    name = "rocketware-minisign";
    description = ''
      Decrypts the rocketware minisign signing key (ephemeral tempfile) and
      its password from sops, then runs the given command with:
        MINISIGN_KEY_PATH               path to ephemeral decrypted key
        ROCKETWARE_MINISIGN_PASSWORD    signing key password

      Example:
        rocketware-minisign -- nu workspace/release-cache.nu'';
    sopsFiles = {
      "minisign.key" = "sops/rocketware-minisign.key.sops";
    };
    envFiles = [ "sops/rocketware-minisign.yaml" ];
    envVarsAfterDecrypt = {
      MINISIGN_KEY_PATH = "minisign.key";
    };
    inherit pkgs nixfilesVault;
  };

  # Env-var-only wrapper for Apple notarization credentials. No binary
  # keystore — notarytool talks to Apple's API with Apple ID + app-specific
  # password + team ID.
  rocketware-apple-notarize = mkSopsWrapper {
    name = "rocketware-apple-notarize";
    description = ''
      Decrypts Apple notarization credentials (ephemeral env vars) from sops,
      then runs the given command with:
        APPLE_NOTARIZE_USERNAME    Apple ID email
        APPLE_NOTARIZE_PASSWORD    app-specific password (xxxx-xxxx-xxxx-xxxx)
        APPLE_NOTARIZE_TEAM_ID     Apple Developer Team ID

      Example:
        rocketware-apple-notarize -- nu package_macos.nu --flavor macos'';
    envFiles = [ "sops/rocketware-apple-notarize.yaml" ];
    inherit pkgs nixfilesVault;
  };

  # Unified Apple signing wrapper. Materialises signing certificates
  # (.p12 files) and the App Store Connect API key (.p8 file) into an
  # ephemeral tempdir, then exports env vars pointing at those files plus
  # the passwords + identity names loaded from a single shared yaml.
  #
  # Modes:
  #   direct    — Developer ID Application cert only
  #   appstore  — Apple Distribution + Mac Installer Distribution + API key
  #   all       — everything from both modes
  #
  # Uses body override: per-mode binary decryption doesn't fit the standard
  # template.
  rocketware-apple-sign = mkSopsWrapper {
    name = "rocketware-apple-sign";
    inherit pkgs nixfilesVault;
    body = ''

      APP_DIST_P12_SOPS="$VAULT/sops/rocketware-apple-sign-app-distribution.p12.sops"
      INSTALLER_P12_SOPS="$VAULT/sops/rocketware-apple-sign-mac-installer.p12.sops"
      DEV_ID_APP_P12_SOPS="$VAULT/sops/rocketware-apple-sign-developer-id-app.p12.sops"
      API_KEY_P8_SOPS="$VAULT/sops/rocketware-apple-sign-api-key.p8.sops"
      IOS_PROV_PROFILE_SOPS="$VAULT/sops/rocketware-apple-sign-ios-provisioning-profile.mobileprovision.sops"
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
                    APPLE_IOS_PROVISIONING_PROFILE_PATH
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

      # Pre-flight: encrypted files for the selected mode
      require_file "$ENV_SOPS"  # yaml is always needed
      case "$mode" in
        direct)
          require_file "$DEV_ID_APP_P12_SOPS"
          ;;
        appstore)
          require_file "$APP_DIST_P12_SOPS"
          require_file "$INSTALLER_P12_SOPS"
          require_file "$API_KEY_P8_SOPS"
          require_file "$IOS_PROV_PROFILE_SOPS"
          ;;
        all)
          require_file "$DEV_ID_APP_P12_SOPS"
          require_file "$APP_DIST_P12_SOPS"
          require_file "$INSTALLER_P12_SOPS"
          require_file "$API_KEY_P8_SOPS"
          require_file "$IOS_PROV_PROFILE_SOPS"
          ;;
      esac

      # Create a secure tempdir for materialised certs + API key. Trap
      # ensures cleanup on ANY exit path (success, error, SIGINT, SIGTERM).
      TMPDIR_KS=$(mktemp -d -t rocketware-apple-sign-XXXXXXXX)
      trap 'rm -rf -- "$TMPDIR_KS"' EXIT

      # Materialise cert .p12s for the selected mode.
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

        "$SOPS" --decrypt --input-type binary --output-type binary \
          --output "$TMPDIR_KS/provisioning_profile.mobileprovision" "$IOS_PROV_PROFILE_SOPS"
        chmod 600 "$TMPDIR_KS/provisioning_profile.mobileprovision"
        export APPLE_IOS_PROVISIONING_PROFILE_PATH="$TMPDIR_KS/provisioning_profile.mobileprovision"
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
  };
}
