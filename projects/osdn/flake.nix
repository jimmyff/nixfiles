{
  description = "Development environment for OSDN Platform";

  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.05";
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = {
    self,
    nixpkgs-unstable,
    nixpkgs-stable,
    android-nixpkgs,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];

    makeDevShell = system: let
      pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
      pkgs-stable = nixpkgs-stable.legacyPackages.${system};
      android-sdk = android-nixpkgs.sdk.${system} (sdkPkgs:
        with sdkPkgs; [
          cmdline-tools-latest
          build-tools-34-0-0
          platform-tools
          platforms-android-34
          emulator
        ]);

      # Custom base64 wrapper for Darwin to fix CocoaPods compatibility
      # This forces the use of system base64 rather than coreutils
      darwinBase64 = pkgs-stable.writeShellScriptBin "base64" ''
        exec /usr/bin/base64 "$@"
      '';
    in
      pkgs-stable.mkShellNoCC {
        buildInputs =
          [
            pkgs-unstable.flutter # Includes Dart SDK 3.9+
            android-sdk
            pkgs-stable.jdk
          ]
          ++ pkgs-stable.lib.optionals pkgs-stable.stdenv.isDarwin [
            darwinBase64 # Fix CocoaPods compatibility on macOS
          ];

        shellHook = ''
          echo "🚀 Entering OSDN development environment"
          echo "Flutter: $(flutter --version | head -1)"
          echo "Dart: $(dart --version)"
          echo ""

          # Configure Flutter to use Nix JDK
          flutter config --jdk-dir "${pkgs-stable.jdk}"
          echo "🔧 Flutter configured to use JDK: ${pkgs-stable.jdk}"
          echo ""

          # Show README if it exists in workspace
          if [ -f workspace/README.md ]; then
            echo "📖 Project README:"
            echo "=================="
            cat workspace/README.md
            echo ""
          fi

          # Run startup script if it exists and nushell is available
          if [ -f startup.nu ] && command -v nu >/dev/null 2>&1 && nu -c "version" >/dev/null 2>&1; then
            nu startup.nu
          elif [ -f startup.nu ]; then
            echo ""
            echo "🔧 To start the development environment, run: ./startup.nu"
          fi
        '';
      };
  in {
    devShells = builtins.listToAttrs (map (system: {
        name = system;
        value = {default = makeDevShell system;};
      })
      supportedSystems);
  };
}
