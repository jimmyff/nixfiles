{
  description = "Development environment for rocket-kit";
  # Flutter and Android SDK are provided by Android Studio instead of Nix
  # This avoids iOS build issues where Xcode cannot write to read-only Flutter root
  # See: https://github.com/flutter/flutter/pull/155139

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
          echo "🚀 Entering rocket-kit development environment"
          echo "Flutter: $(flutter --version 2>/dev/null | head -1 || echo 'Not found - install via Android Studio')"
          echo "Dart: $(dart --version 2>/dev/null || echo 'Not found - install via Android Studio')"
          echo "☕ JDK: ${pkgs-stable.jdk}"
          echo ""
          ${utils.commonShellHook}
        '';
      });
  };
}
