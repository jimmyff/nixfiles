{
  description = "Development environment for libram";
  # Flutter and Dart are provided by system-level Nix configuration (~/nixfiles)
  # The system config handles platform-specific setup automatically:
  # - macOS: Writable Flutter at ~/.local/share/flutter (iOS-compatible)
  # - Linux: Read-only Flutter from Nix store
  # This keeps the project flake platform-agnostic

  inputs = {
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = {
    self,
    nixpkgs-stable,
  }: let
    utils = import ./devshell-utils.nix;
  in {
    devShells = utils.eachSystem (system: let
      pkgs-stable = nixpkgs-stable.legacyPackages.${system};
    in
      pkgs-stable.mkShellNoCC {
        shellHook = ''
          ${utils.darwinPathHook pkgs-stable}
          echo "📚 Entering libram development environment"
          echo "Flutter: $(flutter --version 2>/dev/null | head -1 || echo 'Not available')"
          echo "Dart: $(dart --version 2>/dev/null || echo 'Not available')"
          echo "☕ JDK: ${pkgs-stable.jdk}"
          echo ""
          ${utils.commonShellHook}
        '';
      });
  };
}
