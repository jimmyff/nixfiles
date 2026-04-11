# mkKiln — build environment factory for Flutter CI.
#
# Produces Docker images (Linux/Android) and dev shells (macOS) with a
# shared entrypoint script guaranteeing identical invocation shape.
# See README.md in this directory for API reference.
{ inputs }:

{
  # Required
  project,
  system,
  pkgs,
  version,

  # Base selection
  base ? "linux-x86",
  targets ? [],

  # Toolchain
  flutterPackage ? pkgs.flutter,
  androidSdkPackages ? null,
  androidSdk ? null,

  # Extensibility
  extraPackages ? [],
  extraEnv ? {},
  extraShellHook ? "",

  # Sops wrapper integration
  sopsWrappers ? [],
  vaultInput ? inputs.nixfiles-vault or null,

  # Entry command
  defaultCommand ? [ "bash" ],

  # Image configuration (ignored for macos base)
  imageName ? "kiln-${project}-${base}",
  imageTag ? version,
  imageMaxLayers ? 100,

  # Convention
  workspaceDir ? "/workspace",
}:

let
  lib = pkgs.lib;
  isDarwin = base == "macos";

  # --- Input validation ---

  _ = [
    (assert lib.assertMsg (builtins.isString project && project != "")
      "mkKiln: 'project' must be a non-empty string"; null)
    (assert lib.assertMsg (builtins.isString system && system != "")
      "mkKiln: 'system' must be a non-empty string"; null)
    (assert lib.assertMsg (builtins.isString version && version != "")
      "mkKiln: 'version' must be a non-empty string"; null)
    (assert lib.assertMsg (builtins.isString base && base != "")
      "mkKiln: 'base' must be a non-empty string"; null)
    (assert lib.assertMsg (builtins.isList defaultCommand && defaultCommand != [])
      "mkKiln: 'defaultCommand' must be a non-empty list"; null)
  ];

  # --- Base module resolution ---

  basePath = ./base + "/${base}.nix";
  baseModule =
    if builtins.pathExists basePath
    then import basePath { inherit pkgs inputs; }
    else throw "mkKiln: base module '${base}' not found at modules/kiln/base/${base}.nix. Available bases are defined in modules/kiln/base/.";

  # --- Android SDK resolution ---

  resolvedAndroidSdk =
    if androidSdk != null then androidSdk
    else if androidSdkPackages != null then
      inputs.android-nixpkgs.sdk.${system} androidSdkPackages
    else null;

  # --- Sops wrapper resolution ---

  registry =
    if vaultInput != null
    then import ../development/sops-wrappers-registry.nix {
      inherit pkgs;
      nixfilesVault = vaultInput;
    }
    else {};

  resolveWrapper = w:
    if builtins.isString w then
      registry.${w} or (throw "mkKiln: unknown sops wrapper '${w}'. Known: ${builtins.concatStringsSep ", " (builtins.attrNames registry)}")
    else w;

  resolvedSopsWrappers = map resolveWrapper sopsWrappers;

  # --- Shared entrypoint script ---

  entrypoint = pkgs.writeShellScriptBin "kiln-entrypoint" ''
    set -euo pipefail

    # Workspace discovery
    if [ -d "${workspaceDir}" ] && [ "$(ls -A ${lib.escapeShellArg workspaceDir} 2>/dev/null)" ]; then
      cd ${lib.escapeShellArg workspaceDir}
    fi

    # Age key resolution (sops honours the env vars natively)
    if [ -n "''${SOPS_AGE_KEY:-}" ]; then
      : # SOPS_AGE_KEY set — sops will use it directly
    elif [ -n "''${SOPS_AGE_KEY_FILE:-}" ]; then
      : # SOPS_AGE_KEY_FILE set — sops will use it directly
    elif [ -r "$HOME/.config/sops/age/keys.txt" ]; then
      export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
    fi

    # Flutter writability shim: Nix store is read-only, some Flutter
    # commands need to write to bin/cache/. Copy on first use.
    # rsync --copy-unsafe-links dereferences symlinks that point OUTSIDE the
    # source tree (Nix store absolute symlinks, relative symlinks that escape)
    # while preserving internal symlinks (macOS framework bundle structure
    # that codesign requires: e.g. FlutterMacOS -> Versions/Current/FlutterMacOS).
    if [ -n "''${FLUTTER_ROOT:-}" ] && [[ "$FLUTTER_ROOT" == /nix/store/* ]]; then
      if [ ! -d /tmp/flutter-writable ]; then
        rsync -a --copy-unsafe-links "$FLUTTER_ROOT/" /tmp/flutter-writable/
        chmod -R u+w /tmp/flutter-writable
        # rsync dereferenced bin/dart (was a relative symlink escaping the tree)
        # into a standalone binary. The dart front-end locates dartvm relative
        # to its real path, so re-point to cache/dart-sdk/bin/ where dartvm lives.
        rm -f /tmp/flutter-writable/bin/dart
        ln -s cache/dart-sdk/bin/dart /tmp/flutter-writable/bin/dart
      fi
      export FLUTTER_ROOT=/tmp/flutter-writable
      export PATH="/tmp/flutter-writable/bin:$PATH"
      flutter --disable-analytics 2>/dev/null || true
    fi

    # Argument handling
    if [ "''${1:-}" = "--" ]; then
      shift
    fi

    if [ $# -eq 0 ]; then
      exec ${lib.escapeShellArgs defaultCommand}
    else
      exec "$@"
    fi
  '';

  # --- Merged environment variables ---
  # Precedence (low→high): base → flutter → ephemeral → android → kiln-meta → extra

  flutterEnv = lib.optionalAttrs (flutterPackage != null) {
    FLUTTER_ROOT = "${flutterPackage}";
  };

  ephemeralEnv = {
    PUB_CACHE = "/tmp/pub-cache";
    GRADLE_USER_HOME = "/tmp/gradle";
    FLUTTER_GRADLE_PLUGIN_BUILDDIR = "/tmp/flutter-gradle-plugin";
    TZ = "UTC";
  };

  androidEnv = lib.optionalAttrs (resolvedAndroidSdk != null) {
    ANDROID_HOME = "${resolvedAndroidSdk}/share/android-sdk";
    ANDROID_SDK_ROOT = "${resolvedAndroidSdk}/share/android-sdk";
  };

  kilnMetaEnv = {
    KILN_PROJECT = project;
    KILN_BASE = base;
    KILN_WORKSPACE = workspaceDir;
  };

  mergedEnv =
    baseModule.baseEnv
    // flutterEnv
    // ephemeralEnv
    // androidEnv
    // kilnMetaEnv
    // extraEnv;

  # --- Package list ---

  allPackages =
    baseModule.corePackages
    ++ lib.optional (flutterPackage != null) flutterPackage
    ++ lib.optional (resolvedAndroidSdk != null) resolvedAndroidSdk
    ++ resolvedSopsWrappers
    ++ extraPackages
    ++ [ entrypoint ];

  # --- Environment export helpers ---

  envExports = lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v:
    "export ${n}=${lib.escapeShellArg v}"
  ) mergedEnv);

  flutterShimShellHook = ''
    # Flutter copy-on-write shim (matches Docker entrypoint behavior)
    if [ -n "''${FLUTTER_ROOT:-}" ] && [[ "$FLUTTER_ROOT" == /nix/store/* ]]; then
      if [ ! -d /tmp/flutter-writable ]; then
        rsync -a --copy-unsafe-links "$FLUTTER_ROOT/" /tmp/flutter-writable/
        chmod -R u+w /tmp/flutter-writable
        rm -f /tmp/flutter-writable/bin/dart
        ln -s cache/dart-sdk/bin/dart /tmp/flutter-writable/bin/dart
      fi
      export FLUTTER_ROOT=/tmp/flutter-writable
      export PATH="/tmp/flutter-writable/bin:$PATH"
    fi
  '';

  # --- Docker image (linux only) ---

  dockerImage =
    if isDarwin then null
    else pkgs.dockerTools.streamLayeredImage {
      name = imageName;
      tag = imageTag;
      contents = allPackages ++ [ pkgs.cacert ];
      maxLayers = imageMaxLayers;

      config = {
        Cmd = [ "${entrypoint}/bin/kiln-entrypoint" ];
        WorkingDir = workspaceDir;
        Env = lib.mapAttrsToList (n: v: "${n}=${v}") (mergedEnv // {
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        });
        Labels = {
          "org.opencontainers.image.title" = imageName;
          "org.opencontainers.image.version" = imageTag;
          "org.opencontainers.image.description" = "Kiln build environment for ${project}";
          "dev.kiln.project" = project;
          "dev.kiln.base" = base;
          "dev.kiln.targets" = builtins.concatStringsSep "," targets;
        };
      };

      extraCommands = ''
        mkdir -p etc tmp workspace
        echo "root:x:0:0:root:/root:/bin/bash" > etc/passwd
        echo "root:x:0:" > etc/group
      '';
    };

  # --- Load/push scripts (linux only) ---

  loadScript =
    if isDarwin then null
    else pkgs.writeShellScriptBin "kiln-${project}-${base}-load" ''
      set -euo pipefail
      if ! command -v docker &>/dev/null; then
        echo "ERROR: docker not found." >&2
        exit 1
      fi
      echo "Loading ${imageName}:${imageTag} into Docker..."
      ${dockerImage} | docker load
      echo "Done. Image: ${imageName}:${imageTag}"
    '';

  pushScript =
    if isDarwin then null
    else pkgs.writeShellScriptBin "kiln-${project}-${base}-push" ''
      set -euo pipefail
      if [ -z "''${KILN_REGISTRY:-}" ]; then
        echo "ERROR: KILN_REGISTRY is not set." >&2
        echo "       Set it to the target registry (e.g. ghcr.io/jimmyff)." >&2
        exit 1
      fi
      echo "Pushing ${imageName}:${imageTag} to $KILN_REGISTRY..."
      ${dockerImage} | ${pkgs.skopeo}/bin/skopeo copy \
        docker-archive:/dev/stdin \
        "docker://$KILN_REGISTRY/${imageName}:${imageTag}"
      echo "Done. Pushed: $KILN_REGISTRY/${imageName}:${imageTag}"
    '';

  # --- Dev shell ---

  shellFunc = if isDarwin then pkgs.mkShellNoCC else pkgs.mkShell;

  devShell = shellFunc {
    name = "kiln-${project}-${base}";
    buildInputs = allPackages;
    shellHook = ''
      ${envExports}
      ${flutterShimShellHook}
      ${extraShellHook}
    '';
  };

  # --- Meta ---

  meta = {
    inherit project version base system targets imageName imageTag;
    description = "Kiln build environment for ${project} (${base})";
  };

in {
  inherit entrypoint dockerImage loadScript pushScript devShell meta;
  packages = allPackages;
  env = mergedEnv;
}
