# Development

## Development Environments

**Project setup:**
- Flake-based development environments with Doppler secret integration
- Declarative dependency management via Nix
- Environment variables safely parsed to handle special characters

**Setup:** Run `dev-setup` to validate and clone projects.

## Flutter & Dart

**Platform-specific approach** to handle iOS writability requirements:

- **macOS**: Writable Flutter at `~/.local/share/flutter` (iOS/Xcode compatible)
- **Linux**: Read-only Flutter from Nix store (works for Android/Linux)
- **Version sync**: Both platforms use same version from `pkgs-dev-flutter` flake input
- **Project flakes**: Platform-agnostic (system config handles platform differences)

**Configuration**: `nix_modules/development/dart.nix` imports `dart-darwin.nix` or `dart-linux.nix` based on platform.

**Flutter FFI projects on macOS**: Use `mkShellNoCC` instead of `mkShell` to avoid NIX compiler toolchain interference with Xcode builds.

## Android Keystore

Encrypted with agenix and sourced from private vault repository via flake input. Deployed to `~/.local/share/android/key.jks` on hosts with `android.enable = true`.
