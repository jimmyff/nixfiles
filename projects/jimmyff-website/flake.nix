{
  description = "Development environment for jimmyff-website";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            zola
            git-lfs
            nushell
          ];
          
          shellHook = ''
            echo "🚀 Entering jimmyff-website development environment"
            
            # Show README if it exists in workspace
            if [ -f workspace/README.md ]; then
              echo ""
              echo "📖 Project README:"
              echo "==================="
              head -20 workspace/README.md
              if [ $(wc -l < workspace/README.md) -gt 20 ]; then
                echo "..."
                echo "(README truncated - see full file for more details)"
              fi
              echo ""
            fi
            
            # Show startup instructions instead of auto-running
            if [ -f startup.nu ]; then
              echo ""
              echo "🔧 To start the development server, run: ./startup.nu"
              echo "   Or manually: cd workspace && zola serve"
            fi
          '';
        };
      });
}