{
  description = "Development environment for jimmyff-website";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.default = pkgs.mkShellNoCC {
        buildInputs = with pkgs; [
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
    });
}
