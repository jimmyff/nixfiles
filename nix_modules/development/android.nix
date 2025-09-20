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

  # Cross-platform user group
  userGroup =
    if pkgs.stdenv.isDarwin
    then "staff"
    else "users";
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

    # Android Studio package (platform-specific)
    environment.systemPackages = with pkgs;
      lib.optionals pkgs.stdenv.isDarwin [
        (lib.mkIf (pkgs.stdenv.system == "x86_64-darwin") android-studio)
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [
        android-studio
      ];

    # Android environment variables
    environment.variables = {
      ANDROID_HOME = "${homeDir}/.local/share/android/sdk";
      # FLUTTER_ROOT and PUB_CACHE now handled by dart.nix module
    };

    # Deploy encrypted keystore using agenix
    age.secrets.android-keystore = {
      file = nixfiles-vault + "/android-release-key.jks.age";
      path = "${homeDir}/.local/share/android/key.jks";
      mode = "600";
      owner = username;
      group = userGroup;
    };

    # Setup Android directories and keystore deployment
    system.activationScripts.androidSetup = {
      text = ''
        echo "Setting up Android development environment..."

        # Create Android SDK directory structure
        mkdir -p ${homeDir}/.local/share/android/sdk
        mkdir -p ${homeDir}/.local/share/android
        # Flutter cache directory now handled by dart.nix module

        # Set ownership
        chown -R ${username}:${userGroup} ${homeDir}/.local/share/android 2>/dev/null || echo "Warning: Could not set ownership of Android directories"

        echo "Android development environment setup complete!"
      '';
      deps = ["users" "groups"];
    };
  };
}