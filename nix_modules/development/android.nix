{
  inputs,
  pkgs,
  lib,
  config,
  username,
  nixfiles-vault,
  ...
}: let
  cfg = config.android;

  # Cross-platform home directory
  homeDir =
    if pkgs.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  # XDG paths
  xdgDataHome =
    if pkgs.stdenv.isDarwin
    then "${homeDir}/.local/share"
    else "${homeDir}/.local/share";

  # Cross-platform user group
  userGroup =
    if pkgs.stdenv.isDarwin
    then "staff"
    else "users";

  # Android SDK from android-nixpkgs
  # https://github.com/tadfisher/android-nixpkgs/tree/main/channels/beta
  androidSdk = inputs.android-nixpkgs.sdk.${pkgs.system} (sdkPkgs:
    with sdkPkgs; [
      cmdline-tools-latest
      # build-tools-34-0-0
      build-tools-35-0-0
      platform-tools
      # platforms-android-34
      # platforms-android-35
      platforms-android-36
      emulator
      ndk-bundle
      # ndk-26-1-10909125
      # ndk-26-3-11579264
      ndk-27-0-12077973
      cmake-3-22-1
    ]);
in {
  options.android = {
    enable = lib.mkEnableOption "Android development environment";
  };

  config = lib.mkIf cfg.enable {
    # Configure agenix identity paths for Darwin only
    # NixOS will use default system host keys via OpenSSH service
    age.identityPaths = lib.mkIf pkgs.stdenv.isDarwin [
      "${homeDir}/.ssh/id_ed25519"
      "${homeDir}/.ssh/id_rsa"
    ];

    # Android development packages
    environment.systemPackages = with pkgs;
      [
        androidSdk
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [
        android-studio
      ];

    # Android environment variables
    environment.variables = {
      ANDROID_HOME = "${androidSdk}/share/android-sdk";
      ANDROID_SDK_ROOT = "${androidSdk}/share/android-sdk";
      # FLUTTER_ROOT and PUB_CACHE now handled by dart.nix module
    };

    # Add Android SDK tools to system PATH
    environment.extraInit = ''
      export PATH="${androidSdk}/share/android-sdk/platform-tools:$PATH"
      export PATH="${androidSdk}/share/android-sdk/cmdline-tools/latest/bin:$PATH"
      export PATH="${androidSdk}/share/android-sdk/build-tools/34.0.0:$PATH"
      export PATH="${androidSdk}/share/android-sdk/build-tools/33.0.2:$PATH"
    '';

    # Deploy encrypted keystore using agenix
    age.secrets.android-keystore = {
      file = nixfiles-vault + "/android-release-key.jks.age";
      path = "${xdgDataHome}/android/key.jks";
      mode = "600";
      owner = username;
      group = userGroup;
    };

    # Setup Android keystore deployment directory
    system.activationScripts.androidSetup = {
      text = ''
        echo "Setting up Android development environment..."

        # Create Android keystore directory (XDG compliant)
        mkdir -p ${xdgDataHome}/android
        # Flutter cache directory now handled by dart.nix module

        # Set ownership
        chown -R ${username}:${userGroup} ${xdgDataHome}/android 2>/dev/null || echo "Warning: Could not set ownership of Android directories"

        echo "Android development environment setup complete!"
      '';
      deps = ["users" "groups"];
    };
  };
}
