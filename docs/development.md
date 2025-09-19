# Development

## Flutter + Android SDK (Manual Install)

**Why not Nix?**
- [Base64 encoding bug](https://github.com/flutter/flutter/pull/155139) breaks Xcode builds
- Nix packages lag behind releases
- May reconsider later

**Locations:**
- Flutter: `~/.local/share/flutter/`
- Android SDK: `~/.local/share/android/sdk/`

**Setup:** Run `dev-setup` to validate and clone projects.

## Android Keystore

Encrypted with agenix and sourced from private vault repository via flake input. Deployed to `~/.local/share/android/key.jks` on hosts with `android.enable = true`.
