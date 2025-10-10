{
  description = "Development environment for Jotter - Note-taking and journaling application";
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
      pkgs-stable.mkShell {
        buildInputs =
          [
            pkgs-stable.jdk
            pkgs-stable.cmake
            pkgs-stable.libgit2
            pkgs-stable.pkg-config
            pkgs-stable.gcc
            pkgs-unstable.uv
            pkgs-stable.python313
          ]
          ++ pkgs-stable.lib.optionals pkgs-stable.stdenv.isDarwin [
            darwinBase64 # Fix CocoaPods compatibility on macOS
          ]
          ++ pkgs-stable.lib.optionals pkgs-stable.stdenv.isLinux [
            # Linux Flutter dependencies - complete GTK stack
            pkgs-stable.gtk3
            pkgs-stable.gtk3.dev
            pkgs-stable.glib
            pkgs-stable.glib.dev
            pkgs-stable.pango
            pkgs-stable.pango.dev
            pkgs-stable.cairo
            pkgs-stable.cairo.dev
            pkgs-stable.gdk-pixbuf
            pkgs-stable.gdk-pixbuf.dev
            pkgs-stable.atk
            pkgs-stable.atk.dev
            pkgs-stable.harfbuzz
            pkgs-stable.harfbuzz.dev
            # Additional system dependencies
            pkgs-stable.util-linux
            pkgs-stable.pcre2
            pkgs-stable.libepoxy
            pkgs-stable.clang
          ];

        shellHook = ''
          echo "📝 Entering Jotter development environment"
          echo "Flutter: $(flutter --version 2>/dev/null | head -1 || echo 'Not found - install via Android Studio')"
          echo "Dart: $(dart --version 2>/dev/null || echo 'Not found - install via Android Studio')"
          echo "☕ JDK: ${pkgs-stable.jdk}"
          echo ""


          # Show README if it exists in workspace
          if [ -f workspace/README.md ]; then
            echo "📖 Project README:"
            echo "=================="
            if command -v bat >/dev/null 2>&1; then
              bat -pp workspace/README.md
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

          # Install speckit
          uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
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
