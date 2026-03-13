{
  description = "Development environment for Blink - Note-taking and journaling application";
  # Flutter and Dart are provided by system-level Nix configuration (~/nixfiles)
  # The system config handles platform-specific setup automatically:
  # - macOS: Writable Flutter at ~/.local/share/flutter (iOS-compatible)
  # - Linux: Read-only Flutter from Nix store
  # This keeps the project flake platform-agnostic

  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = {
    self,
    nixpkgs-unstable,
    nixpkgs-stable,
  }: let
    utils = import ./devshell-utils.nix;
  in {
    devShells = utils.eachSystem (system: let
      pkgs-unstable = nixpkgs-unstable.legacyPackages.${system};
      pkgs-stable = nixpkgs-stable.legacyPackages.${system};

      # mkShellNoCC on Darwin avoids NIX compiler toolchain conflicts with Xcode
      # mkShell on Linux includes gcc/clang from NIX
      shellFunc =
        if pkgs-stable.stdenv.isDarwin
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
            pkgs-unstable.nodejs_22
            pkgs-unstable.uv
            pkgs-unstable.zola
            pkgs-stable.minisign
            # Python with packages required for git_dart native builds
            # (mbedtls code generation scripts need jsonschema and jinja2)
            # Using Python 3.12 for better compatibility with nixpkgs-stable packages
            (pkgs-stable.python312.withPackages (ps:
              with ps; [
                jsonschema
                jinja2
              ]))
          ]
          ++ pkgs-stable.lib.optionals pkgs-stable.stdenv.isDarwin [
            # Fix CocoaPods compatibility on macOS
            pkgs-stable.darwin.base64
            pkgs-stable.sqlite
          ]
          ++ pkgs-stable.lib.optionals pkgs-stable.stdenv.isLinux [
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
            pkgs-unstable.util-linux
            pkgs-unstable.pcre2
            pkgs-unstable.libepoxy
            pkgs-unstable.openssl
            pkgs-unstable.openssl.dev
            pkgs-stable.gcc
            pkgs-unstable.clang
            pkgs-unstable.sqlite
            pkgs-unstable.zenity
            # Webview support (desktop_webview_window plugin)
            pkgs-unstable.webkitgtk_4_1
            pkgs-unstable.libsoup_3
            # System profiling support (required by glib-2.0)
            pkgs-unstable.libsysprof-capture
            # SELinux support (required by gio-2.0)
            pkgs-unstable.libselinux
            pkgs-unstable.libsepol
            # Secure storage support (flutter_secure_storage_linux plugin)
            pkgs-unstable.libsecret
            pkgs-unstable.libgcrypt
            # Thai text support (required by pango)
            pkgs-unstable.libthai
            # PCRE support (required by libgit2)
            pkgs-unstable.pcre
            # Build system for native compilation
            pkgs-stable.ninja
            # Linux packaging tools (package_linux.nu)
            pkgs-stable.nfpm
          ];

        shellHook = ''
          ${utils.darwinPathHook pkgs-stable}
          echo "📝 Entering Blink development environment"
          echo "Flutter: $(flutter --version 2>/dev/null | head -1 || echo 'Not available')"
          echo "Dart: $(dart --version 2>/dev/null || echo 'Not available')"
          echo "Flutter root: ''${FLUTTER_ROOT:-Not set}"
          echo "☕ JDK: ${pkgs-stable.jdk}"
          echo "🟢 Node.js: $(node --version 2>/dev/null || echo 'Not available')"
          echo "📦 npm: $(npm --version 2>/dev/null || echo 'Not available')"
          ${pkgs-stable.lib.optionalString pkgs-stable.stdenv.isDarwin ''
            export DYLD_LIBRARY_PATH="${pkgs-stable.sqlite.out}/lib''${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
            echo "🔧 Toolchain: Xcode (mkShellNoCC - no NIX compiler)"
            echo "   CC: $(which clang 2>/dev/null || echo 'not in PATH')"
            echo "   LD: $(which ld 2>/dev/null || echo 'not in PATH')"
          ''}
          ${pkgs-stable.lib.optionalString pkgs-stable.stdenv.isLinux ''
            export LD_LIBRARY_PATH="${pkgs-unstable.sqlite.out}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            echo "🔧 Toolchain: NIX (mkShell)"
            echo "   CC: $(which gcc 2>/dev/null || echo 'not in PATH')"
          ''}
          echo ""
          ${utils.commonShellHook}
        '';
      }));
  };
}
