# Development

## Development Environments

**Project setup:**
- Flake-based development environments
- Declarative dependency management via Nix
- On-demand secrets via `sops` wrapper scripts (see `docs/secrets.md`)

**Setup:** Run `dev-setup` — bare-clones each enabled repo (`projects/repos.nix`) to
`~/projects/<project>/.bare`, adds a default-branch worktree, and runs `direnv allow`.
The flake lives in the repo, so enter the worktree (e.g. `~/projects/<project>/main`)
to activate the devshell.

## Flutter & Dart

**Platform-specific approach** to handle iOS writability requirements:

- **macOS**: Writable Flutter at `~/.local/share/flutter` (iOS/Xcode compatible)
- **Linux**: Read-only Flutter from Nix store (works for Android/Linux)
- **Version sync**: Both platforms use same version from `pkgs-dev-flutter` flake input
- **Project flakes**: Platform-agnostic (system config handles platform differences)

**Configuration**: `modules/development/dart.nix` imports `dart-darwin.nix` or `dart-linux.nix` based on platform.

**Flutter FFI projects on macOS**: Use `mkShellNoCC` instead of `mkShell` to avoid NIX compiler toolchain interference with Xcode builds.

## Android Keystore

Encrypted with agenix and sourced from private vault repository via flake input. Deployed to `~/.local/share/android/key.jks` on hosts with `android.enable = true`.
