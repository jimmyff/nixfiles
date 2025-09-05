{
  description = "Development environment for jimmyff-website";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: {
    devShells = {
      x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShellNoCC {
        buildInputs = with nixpkgs.legacyPackages.x86_64-linux; [
          zola
        ];

        shellHook = ''
          echo "🚀 Entering jimmyff-website development environment"

          # Show README if it exists in workspace
          if [ -f workspace/README.md ]; then
            echo ""
            echo "📖 Project README:"
            echo "==================="
            cat workspace/README.md
            echo ""
          fi

          # Run startup script if it exists and nushell is available
          if [ -f startup.nu ] && command -v nu >/dev/null 2>&1 && nu -c "version" >/dev/null 2>&1; then
            nu startup.nu
          elif [ -f startup.nu ]; then
            echo ""
            echo "🔧 To start the development server, run: ./startup.nu"
          fi
        '';
      };

      aarch64-linux.default = nixpkgs.legacyPackages.aarch64-linux.mkShellNoCC {
        buildInputs = with nixpkgs.legacyPackages.aarch64-linux; [
          zola
        ];

        shellHook = ''
          echo "🚀 Entering jimmyff-website development environment"

          # Show README if it exists in workspace
          if [ -f workspace/README.md ]; then
            echo ""
            echo "📖 Project README:"
            echo "==================="
            cat workspace/README.md
            echo ""
          fi

          # Run startup script if it exists and nushell is available
          if [ -f startup.nu ] && command -v nu >/dev/null 2>&1 && nu -c "version" >/dev/null 2>&1; then
            nu startup.nu
          elif [ -f startup.nu ]; then
            echo ""
            echo "🔧 To start the development server, run: ./startup.nu"
          fi
        '';
      };

      aarch64-darwin.default = nixpkgs.legacyPackages.aarch64-darwin.mkShellNoCC {
        buildInputs = with nixpkgs.legacyPackages.aarch64-darwin; [
          zola
        ];

        shellHook = ''
          echo "🚀 Entering jimmyff-website development environment"

          # Show README if it exists in workspace
          if [ -f workspace/README.md ]; then
            echo ""
            echo "📖 Project README:"
            echo "==================="
            cat workspace/README.md
            echo ""
          fi

          # Run startup script if it exists and nushell is available
          if [ -f startup.nu ] && command -v nu >/dev/null 2>&1 && nu -c "version" >/dev/null 2>&1; then
            nu startup.nu
          elif [ -f startup.nu ]; then
            echo ""
            echo "🔧 To start the development server, run: ./startup.nu"
          fi
        '';
      };

      x86_64-darwin.default = nixpkgs.legacyPackages.x86_64-darwin.mkShellNoCC {
        buildInputs = with nixpkgs.legacyPackages.x86_64-darwin; [
          zola
        ];

        shellHook = ''
          echo "🚀 Entering jimmyff-website development environment"

          # Show README if it exists in workspace
          if [ -f workspace/README.md ]; then
            echo ""
            echo "📖 Project README:"
            echo "==================="
            cat workspace/README.md
            echo ""
          fi

          # Run startup script if it exists and nushell is available
          if [ -f startup.nu ] && command -v nu >/dev/null 2>&1 && nu -c "version" >/dev/null 2>&1; then
            nu startup.nu
          elif [ -f startup.nu ]; then
            echo ""
            echo "🔧 To start the development server, run: ./startup.nu"
          fi
        '';
      };
    };
  };
}
