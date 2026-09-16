# Darwin-specific Flutter/Dart configuration
# Writable Flutter SDK at ~/.local/share/flutter (Xcode/CocoaPods write into it).
# dev-setup clones it and pins it to the nixpkgs release; the wrappers warn on drift.
{
  pkgs-dev-flutter,
  lib,
  username,
  ...
}: let
  homeDir = "/Users/${username}";
  xdgCacheHome = "${homeDir}/.cache";
  xdgDataHome = "${homeDir}/.local/share";
  flutterRoot = "${xdgDataHome}/flutter";
  flutterVersion = pkgs-dev-flutter.flutter.version;

  # Shared env vars for launchd.user.envVariables and login agent
  dartEnvVars = {
    FLUTTER_ROOT = flutterRoot;
    JAVA_HOME = "${pkgs-dev-flutter.zulu17}";
    PUB_CACHE = "${xdgCacheHome}/dart-pub";
    FLUTTER_GRADLE_PLUGIN_BUILDDIR = "${xdgCacheHome}/flutter-gradle-plugin";
  };

  # Warn on every call if the clone's version differs from nixpkgs.
  # Reads the version file Flutter writes when it builds its cache (cheap, no git).
  driftCheck = ''
    have=$(sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p' "${flutterRoot}/bin/cache/flutter.version.json" 2>/dev/null)
    if [ -n "$have" ] && [ "$have" != "${flutterVersion}" ]; then
      echo "⚠️  Flutter SDK drift: ${flutterRoot} is $have, nixpkgs pins ${flutterVersion} — run 'dev-setup'" >&2
    fi
  '';

  missing = tool: ''
    echo "⚠️  ${tool} not found at ${flutterRoot}" >&2
    echo "Run 'dev-setup' to clone the writable Flutter SDK" >&2
    exit 1
  '';

  # Wrappers that run the writable SDK; they sit in PATH ahead of Nix store versions.
  flutterWrapper = pkgs-dev-flutter.writeShellScriptBin "flutter" ''
    ${driftCheck}
    if [ -x "${flutterRoot}/bin/flutter" ]; then
      exec "${flutterRoot}/bin/flutter" "$@"
    fi
    ${missing "Flutter"}
  '';

  dartWrapper = pkgs-dev-flutter.writeShellScriptBin "dart" ''
    ${driftCheck}
    if [ -x "${flutterRoot}/bin/dart" ]; then
      exec "${flutterRoot}/bin/dart" "$@"
    elif [ -x "${flutterRoot}/bin/cache/dart-sdk/bin/dart" ]; then
      exec "${flutterRoot}/bin/cache/dart-sdk/bin/dart" "$@"
    fi
    ${missing "Dart"}
  '';
in {
  environment.systemPackages = [
    flutterWrapper
    dartWrapper
    pkgs-dev-flutter.zulu17 # JDK 17 for Android development
  ];

  environment.variables = dartEnvVars;

  # Propagate dart/flutter env vars to GUI apps (Xcode) via launchd
  launchd.user.envVariables = dartEnvVars;

  # Persist dart env vars across reboots via login agent
  launchd.user.agents.nix-env-dart = {
    serviceConfig = {
      RunAtLoad = true;
      ProgramArguments = [
        "/bin/sh"
        "-c"
        (builtins.concatStringsSep " && " (
          lib.mapAttrsToList
          (name: value: "/bin/launchctl setenv ${name} '${value}'")
          dartEnvVars
        ))
      ];
    };
  };

  # SDK setup lives in dev-setup: nix-darwin drops activation scripts with custom names.
}
