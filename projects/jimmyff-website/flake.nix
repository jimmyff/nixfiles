{
  description = "Development environment for jimmyff-website";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];

    makeDevShell = system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      pkgs.mkShellNoCC {
        buildInputs = [
          pkgs.zola
          pkgs.nodejs_22 # Node.js and npm for MCP servers (22.12.0+ required for chrome-devtools-mcp)
        ];

        shellHook = ''
          echo "🚀 Entering jimmyff-website development environment"
          echo "🟢 Node.js: $(node --version 2>/dev/null || echo 'Not available')"
          echo "📦 npm: $(npm --version 2>/dev/null || echo 'Not available')"

          # Show README if it exists in workspace
          if [ -f workspace/README.md ]; then
            echo ""
            echo "📖 Project README:"
            echo "==================="
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
            echo "🔧 To start the development server, run: ./startup.nu"
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
