# Development

## Dart/Flutter + Android SDK

**Installation:**
- **Dart/Flutter:** Nix on Linux, manual on macOS ([Xcode issue](https://github.com/flutter/flutter/pull/155139))  
- **Android SDK:** Manual install via Android Studio (both platforms)

**Locations:**
- Dart/Flutter: Nix store (Linux) / `~/.local/share/flutter/` (macOS)
- Android SDK: `~/.local/share/android/sdk/`

**Setup:** Run `dev-setup` to validate and clone projects.

## Android Keystore

Encrypted with agenix and sourced from private vault repository via flake input. Deployed to `~/.local/share/android/key.jks` on hosts with `android.enable = true`.
