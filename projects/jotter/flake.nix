{
  description = "Development environment for Blink - Note-taking and journaling application";
  # Flutter and Dart are provided by system-level Nix configuration (~/nixfiles)
  # The system config handles platform-specific setup automatically:
  # - macOS: Writable Flutter at ~/.local/share/flutter (iOS-compatible)
  # - Linux: Read-only Flutter from Nix store
  # This keeps the project flake platform-agnostic

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

      # Use mkShellNoCC on Darwin to avoid NIX compiler toolchain
      # macOS relies on Xcode's native toolchain (clang, ld, etc.)
      # mkShellNoCC uses stdenvNoCC which excludes NIX's clang-wrapper and bintools,
      # allowing Xcode's native /usr/bin/clang and /usr/bin/ld to be used directly
      # without NIX wrapper interference. This is essential for Flutter/CocoaPods builds.
      # Use mkShell on Linux which includes gcc/clang from NIX
      shellFunc = if pkgs-stable.stdenv.isDarwin
                  then pkgs-stable.mkShellNoCC
                  else pkgs-stable.mkShell;
    in
      shellFunc ({
        buildInputs =
          [
            pkgs-stable.jdk
            pkgs-stable.cmake
            pkgs-stable.libgit2
            pkgs-stable.pkg-config
            # gcc moved to Linux-only section to avoid Xcode toolchain conflicts on macOS
            pkgs-unstable.uv
            # Python with packages required for git_dart native builds
            # (mbedtls code generation scripts need jsonschema and jinja2)
            # Using Python 3.12 for better compatibility with nixpkgs-stable packages
            (pkgs-stable.python312.withPackages (ps: with ps; [
              jsonschema
              jinja2
            ]))
          ]
          ++ pkgs-stable.lib.optionals pkgs-stable.stdenv.isDarwin [
            darwinBase64 # Fix CocoaPods compatibility on macOS
          ]
          ++ pkgs-stable.lib.optionals pkgs-stable.stdenv.isLinux [
            # Linux Flutter dependencies - complete GTK stack
            # Using pkgs-unstable to match system Flutter's GTK dependencies
            pkgs-unstable.gtk3
            pkgs-unstable.gtk3.dev
            pkgs-unstable.glib
            pkgs-unstable.glib.dev
            pkgs-unstable.pango
            pkgs-unstable.pango.dev
            pkgs-unstable.cairo
            pkgs-unstable.cairo.dev
            pkgs-unstable.gdk-pixbuf
            pkgs-unstable.gdk-pixbuf.dev
            pkgs-unstable.atk
            pkgs-unstable.atk.dev
            pkgs-unstable.harfbuzz
            pkgs-unstable.harfbuzz.dev
            # Additional system dependencies
            pkgs-unstable.util-linux
            pkgs-unstable.pcre2
            pkgs-unstable.libepoxy
            pkgs-unstable.openssl
            pkgs-unstable.openssl.dev
            # Build tools (Linux only - macOS uses Xcode's native toolchain)
            pkgs-stable.gcc
            pkgs-unstable.clang
            # SQLite database support
            pkgs-unstable.sqlite
            # File picker dialog support
            pkgs-unstable.zenity
          ];

        shellHook = ''
          echo "📝 Entering Blink development environment"
          echo "Flutter: $(flutter --version 2>/dev/null | head -1 || echo 'Not available')"
          echo "Dart: $(dart --version 2>/dev/null || echo 'Not available')"
          echo "Flutter root: ''${FLUTTER_ROOT:-Not set}"
          echo "☕ JDK: ${pkgs-stable.jdk}"
          ${pkgs-stable.lib.optionalString pkgs-stable.stdenv.isDarwin ''
            echo "🔧 Toolchain: Xcode (mkShellNoCC - no NIX compiler)"
            echo "   CC: $(which clang 2>/dev/null || echo 'not in PATH')"
            echo "   LD: $(which ld 2>/dev/null || echo 'not in PATH')"
          ''}
          ${pkgs-stable.lib.optionalString pkgs-stable.stdenv.isLinux ''
            echo "🔧 Toolchain: NIX (mkShell)"
            echo "   CC: $(which gcc 2>/dev/null || echo 'not in PATH')"
          ''}
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
      });
  in {
    devShells = builtins.listToAttrs (map (system: {
        name = system;
        value = {default = makeDevShell system;};
      })
      supportedSystems);
  };
}
