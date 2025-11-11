{
  description = "Development environment for OSDN Platform";
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

      # Helper function to generate safe Doppler environment loading
      mkDopplerShellHook = { project, config ? "dev" }: ''
        # Load Doppler environment variables safely without eval
        set -a
        while IFS='=' read -r key value; do
          # Only export valid variable names and non-empty keys
          if [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            # Strip surrounding quotes if present
            value=''${value#\"}
            value=''${value%\"}
            export "$key"="$value"
          fi
        done < <(doppler secrets download --no-file --format env --project ${project} --config ${config})
        set +a
      '';

      # Custom base64 wrapper for Darwin to fix CocoaPods compatibility
      # This forces the use of system base64 rather than coreutils
      darwinBase64 = pkgs-stable.writeShellScriptBin "base64" ''
        exec /usr/bin/base64 "$@"
      '';
    in
      pkgs-stable.mkShellNoCC {
        buildInputs =
          [
            # JDK is provided by system-wide dart module
          ]
          ++ pkgs-stable.lib.optionals pkgs-stable.stdenv.isDarwin [
            darwinBase64 # Fix CocoaPods compatibility on macOS
          ];

        shellHook = ''
          # Load Doppler environment variables with safe parsing for special characters
          ${mkDopplerShellHook { project = "rocketware"; config = "dev"; }}
          echo "🚀 Entering OSDN development environment"
          echo "Flutter: $(flutter --version 2>/dev/null | head -1 || echo 'Not available')"
          echo "Dart: $(dart --version 2>/dev/null || echo 'Not available')"
          echo "Flutter root: ''${FLUTTER_ROOT:-Not set}"
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
