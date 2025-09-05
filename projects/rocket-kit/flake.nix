{
  description = "Development environment for rocket-kit";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, android-nixpkgs }: {
    devShells = {
      x86_64-linux.default = let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        android-sdk = android-nixpkgs.sdk.x86_64-linux (sdkPkgs: with sdkPkgs; [
          cmdline-tools-latest
          build-tools-34-0-0
          platform-tools
          platforms-android-34
          emulator
        ]);
      in pkgs.mkShellNoCC {
        buildInputs = with pkgs; [
          flutter  # Includes Dart SDK 3.9+
          android-sdk
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
            cat workspace/README.md
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

      aarch64-linux.default = let
        pkgs = nixpkgs.legacyPackages.aarch64-linux;
        android-sdk = android-nixpkgs.sdk.aarch64-linux (sdkPkgs: with sdkPkgs; [
          cmdline-tools-latest
          build-tools-34-0-0
          platform-tools
          platforms-android-34
          emulator
        ]);
      in pkgs.mkShellNoCC {
        buildInputs = with pkgs; [
          flutter  # Includes Dart SDK 3.9+
          android-sdk
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
            cat workspace/README.md
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

      aarch64-darwin.default = let
        pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        android-sdk = android-nixpkgs.sdk.aarch64-darwin (sdkPkgs: with sdkPkgs; [
          cmdline-tools-latest
          build-tools-34-0-0
          platform-tools
          platforms-android-34
          emulator
        ]);
      in pkgs.mkShellNoCC {
        buildInputs = with pkgs; [
          flutter  # Includes Dart SDK 3.9+
          android-sdk
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
            cat workspace/README.md
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

      x86_64-darwin.default = let
        pkgs = nixpkgs.legacyPackages.x86_64-darwin;
        android-sdk = android-nixpkgs.sdk.x86_64-darwin (sdkPkgs: with sdkPkgs; [
          cmdline-tools-latest
          build-tools-34-0-0
          platform-tools
          platforms-android-34
          emulator
        ]);
      in pkgs.mkShellNoCC {
        buildInputs = with pkgs; [
          flutter  # Includes Dart SDK 3.9+
          android-sdk
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
            cat workspace/README.md
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
    };
  };
}