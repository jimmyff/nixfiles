{
  description = "Development environment for rocket-kit";

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
        devShells.default = pkgs.mkShellNoCC {
          buildInputs = with pkgs; [
            flutter  # Includes Dart SDK 3.9+
          ];
          
          shellHook = ''
            echo "🚀 Entering rocket-kit development environment"
            echo "Flutter: $(flutter --version | head -1)"
            echo "Dart: $(dart --version)"
            echo ""
            
            # Show README if it exists in workspace
            if [ -f workspace/README.md ]; then
              echo "📖 Project README:"
              echo "==================="
              head -20 workspace/README.md
              if [ $(wc -l < workspace/README.md) -gt 20 ]; then
                echo "..."
                echo "(README truncated - see full file for more details)"
              fi
              echo ""
            fi
            
            # Run startup script if it exists and we're in nushell
            if [ -f startup.nu ] && [ "$SHELL" = "${pkgs.nushell}/bin/nu" ]; then
              nu startup.nu
            fi
          '';
        };
      });
}