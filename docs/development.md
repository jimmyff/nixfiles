# Development

## Development Environments

**Project setup:**
- Flake-based development environments with Doppler secret integration
- Declarative dependency management via Nix
- Environment variables safely parsed to handle special characters

**Setup:** Run `dev-setup` to validate and clone projects.

## Android Keystore

Encrypted with agenix and sourced from private vault repository via flake input. Deployed to `~/.local/share/android/key.jks` on hosts with `android.enable = true`.
