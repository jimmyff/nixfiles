{
  description = "Development environment for rocket-kit";
  # Flutter and Android SDK are provided by Android Studio instead of Nix
  # This avoids iOS build issues where Xcode cannot write to read-only Flutter root
  # See: https://github.com/flutter/flutter/pull/155139

  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.05";
  };

  outputs = {
    self,
    nixpkgs-unstable,
    nixpkgs-stable,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];

    makeDevShell = system: let
      pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
      pkgs-stable = nixpkgs-stable.legacyPackages.${system};

      # Custom base64 wrapper for Darwin to fix CocoaPods compatibility
      # This forces the use of system base64 rather than coreutils
      darwinBase64 = pkgs-stable.writeShellScriptBin "base64" ''
        exec /usr/bin/base64 "$@"
      '';
    in
      pkgs-stable.mkShellNoCC {
        buildInputs =
          [
            pkgs-stable.jdk
          ]
          ++ pkgs-stable.lib.optionals pkgs-stable.stdenv.isDarwin [
            darwinBase64 # Fix CocoaPods compatibility on macOS
          ];

        shellHook = ''
          echo "🚀 Entering rocket-kit development environment"
          echo "Flutter: $(flutter --version 2>/dev/null | head -1 || echo 'Not found - install via Android Studio')"
          echo "Dart: $(dart --version 2>/dev/null || echo 'Not found - install via Android Studio')"
          echo "☕ JDK: ${pkgs-stable.jdk}"
          echo ""

          # Show README if it exists in workspace
          if [ -f workspace/README.md ]; then
            echo "📖 Project README:"
            echo "=================="
            if command -v bat >/dev/null 2>&1; then
              bat --style=plain workspace/README.md
            else
              cat workspace/README.md
            fi
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