{
  description = "Development environment for OSDN Platform";
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

      # gcloud with the Firestore emulator component, pinned to this project's nixpkgs.
      gcloudEmu = pkgs-stable.google-cloud-sdk.withExtraComponents [
        pkgs-stable.google-cloud-sdk.components.cloud-firestore-emulator
      ];

      # Self-contained Firestore emulator launcher for cloud-function tests.
      # Distinct binary name so it never shadows the system `gcloud` (used for
      # deploys) or `java` (Flutter/Android use zulu17). The Java-21 PATH export
      # is scoped to this subprocess only — nothing else on the system sees Java 21.
      firestoreEmulator = pkgs-stable.writeShellScriptBin "firestore-emulator" ''
        export PATH="${pkgs-stable.temurin-jre-bin-21}/bin:$PATH"
        exec ${gcloudEmu}/bin/gcloud emulators firestore start "$@"
      '';
    in
      pkgs-stable.mkShellNoCC {
        packages = [firestoreEmulator];
        shellHook = ''
          ${utils.darwinPathHook pkgs-stable}
          echo "🚀 Entering OSDN development environment"
          echo "Flutter: $(flutter --version 2>/dev/null | head -1 || echo 'Not available')"
          echo "Dart: $(dart --version 2>/dev/null || echo 'Not available')"
          echo "Flutter root: ''${FLUTTER_ROOT:-Not set}"
          echo "☕ JDK: ${pkgs-stable.jdk}"
          echo "🔥 Firestore emulator: firestore-emulator (Java 21, isolated)"
          echo ""
          ${utils.commonShellHook}
        '';
      });
  };
}
