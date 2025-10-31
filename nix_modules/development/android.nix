{
  inputs,
  pkgs-dev-android,
  lib,
  config,
  username,
  nixfiles-vault,
  ...
}: let
  cfg = config.android;

  # Cross-platform home directory
  homeDir =
    if pkgs-dev-android.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  # XDG paths
  xdgDataHome =
    if pkgs-dev-android.stdenv.isDarwin
    then "${homeDir}/.local/share"
    else "${homeDir}/.local/share";

  # Cross-platform user group
  userGroup =
    if pkgs-dev-android.stdenv.isDarwin
    then "staff"
    else "users";

  # Android SDK from android-nixpkgs
  # https://github.com/tadfisher/android-nixpkgs/tree/main/channels/beta
  androidSdk = inputs.android-nixpkgs.sdk.${pkgs-dev-android.system} (sdkPkgs:
    with sdkPkgs; [
      cmdline-tools-latest
      # build-tools-34-0-0
      build-tools-35-0-0
      platform-tools
      platforms-android-34
      platforms-android-35
      platforms-android-36
      emulator
      ndk-bundle
      # ndk-26-1-10909125
      # ndk-26-3-11579264
      ndk-27-0-12077973
      cmake-3-22-1
    ]);

  # Android Studio launcher for Darwin (macOS)
  # Uses writable Flutter SDK to enable Gradle sync in Android Studio
  androidStudioLauncher = pkgs-dev-android.writeShellScriptBin "androidstudio" ''
    # Android Studio Launcher for Darwin with writable Flutter SDK
    #
    # ARCHITECTURE:
    # - Uses writable Flutter SDK at ~/.local/share/flutter (for Android Studio/Gradle)
    # - Terminal/CLI still uses Nix Flutter (via $ANDROID_HOME in shell)
    # - Android Studio uses its own Android SDK at ~/Library/Android/sdk
    #
    # This allows Android Studio to work while maintaining NixOS compatibility

    WRITABLE_FLUTTER="${homeDir}/.local/share/flutter"
    ANDROID_SDK_DIR="${homeDir}/Library/Android/sdk"

    # Check if writable Flutter exists
    if [ ! -d "$WRITABLE_FLUTTER" ]; then
      echo "❌ Error: Writable Flutter SDK not found at $WRITABLE_FLUTTER"
      echo "   Run 'dev-setup' to install it, or clone manually:"
      echo "   git clone https://github.com/flutter/flutter.git $WRITABLE_FLUTTER"
      exit 1
    fi

    # Function to update local.properties for a Flutter project
    update_local_properties() {
      local android_dir="$1"
      local local_props="$android_dir/local.properties"

      # Only update if android directory exists
      if [ -d "$android_dir" ]; then
        echo "   📝 Updating $local_props"
        cat > "$local_props" << EOF
## This file must *NOT* be checked into Version Control Systems,
# as it contains information specific to your local configuration.
#
# Location of the SDK. This is only used by Gradle.
flutter.sdk=$WRITABLE_FLUTTER
sdk.dir=$ANDROID_SDK_DIR
EOF
      fi
    }

    # HACKY FIX: Update local.properties for Flutter projects in ~/Projects
    # This is required because Android Studio's Gradle needs a writable Flutter SDK,
    # but our Nix Flutter SDK is read-only. We maintain two Flutter installations:
    # - Nix Flutter (read-only) for terminal/CLI builds
    # - Writable Flutter (~/.local/share/flutter) for Android Studio
    # This hack automatically updates local.properties to point to the writable Flutter
    # before launching Android Studio, then terminal builds regenerate it back to Nix.
    echo "🔧 Configuring Flutter projects for Android Studio..."
    if [ -d "${homeDir}/Projects" ]; then
      # Find all Flutter projects using ripgrep (much faster than find)
      # Look for pubspec.yaml files, then check if they have android/ directory
      rg --files-with-matches --type yaml "^name:" "${homeDir}/Projects" 2>/dev/null | \
        grep "pubspec.yaml$" | \
        while read -r pubspec; do
          project_dir=$(dirname "$pubspec")
          android_dir="$project_dir/android"
          if [ -d "$android_dir" ]; then
            update_local_properties "$android_dir"
          fi
        done
    fi

    # CRITICAL: Remove all Nix paths from PATH to prevent finding Nix Flutter
    # Keep only system paths and add writable Flutter first
    export PATH="$WRITABLE_FLUTTER/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    # Use writable Flutter SDK (not Nix)
    export FLUTTER_ROOT="$WRITABLE_FLUTTER"

    # Redirect Gradle cache to writable location
    export GRADLE_USER_HOME="${homeDir}/.gradle"

    # Unset ALL Nix-related environment variables
    unset ANDROID_HOME
    unset ANDROID_SDK_ROOT
    unset JAVA_HOME
    unset NIX_PATH
    unset NIX_PROFILES

    echo ""
    echo "🚀 Launching Android Studio..."
    echo "   Flutter SDK: $FLUTTER_ROOT (writable, for Android Studio)"
    echo "   Android SDK: $ANDROID_SDK_DIR (managed by Android Studio)"
    echo "   Java: Android Studio bundled JDK"
    echo ""
    echo "Note: All Nix paths removed from environment to ensure clean setup"
    echo "      Terminal builds will continue to use Nix-managed Flutter/Android SDK"
    echo ""

    # Launch Android Studio
    exec "/Applications/Android Studio.app/Contents/MacOS/studio" "$@"
  '';
in {
  options.android = {
    enable = lib.mkEnableOption "Android development environment";
  };

  config = lib.mkIf cfg.enable {
    # Configure agenix identity paths for Darwin only
    # NixOS will use default system host keys via OpenSSH service
    age.identityPaths = lib.mkIf pkgs-dev-android.stdenv.isDarwin [
      "${homeDir}/.ssh/id_ed25519"
      "${homeDir}/.ssh/id_rsa"
    ];

    # Android development packages
    environment.systemPackages = with pkgs-dev-android;
      [
        androidSdk
      ]
      ++ lib.optionals pkgs-dev-android.stdenv.isLinux [
        android-studio
      ]
      ++ lib.optionals pkgs-dev-android.stdenv.isDarwin [
        androidStudioLauncher
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
        # Create Android keystore directory (XDG compliant)
        mkdir -p ${xdgDataHome}/android
        # Flutter cache directory now handled by dart.nix module

        # Set ownership
        chown -R ${username}:${userGroup} ${xdgDataHome}/android 2>/dev/null || echo "Warning: Could not set ownership of Android directories"

        echo "🤖 Activated Android development environment"
      '';
      deps = ["users" "groups"];
    };
  };
}
