# Darwin Setup

1. Install Nix: https://nixos.org/download/
2. Set hostname: `sudo scutil --set HostName jimmyff-mbp14`
3. Install Darwin: `sudo nix run --extra-experimental-features nix-command --extra-experimental-features flakes nix-darwin/master#darwin-rebuild -- switch --flake ~/nixfiles/flake.nix`
4. Setup SSH keys from Bitwarden
5. Disable system shortcuts: System Settings → Keyboard → Shortcuts
6. Launch Raycast, bind to ⌘+Space
7. Configure browser keyboard shortcuts in System Settings → Keyboard → Shortcuts → App Shortcuts: → All Applications

| Menu Title | Keybind |
|------------|---------|
| Close Tab | ^W |
| New tab | ^T |
| Focus Address Bar | ^L |
| New Tab | ^T |
| Select Next Tab | ^⌘L |
| Select Previous Tab | ^⌘H |
| Show Next Tab | ^⌘L |
| Show Previous Tab | ^⌘H |
| New Window | ^N |
| New window | ^N |
| New Incognito window | ^⇧N |
| New Private Window | ^⇧N |
| Reload This Page | ^R |
| Back | ^K |
| Forward | ^J |

## Manual Installs

- **Xcode** (App Store)
- **Affinity** (App Store)
- **Android Studio** → `~/.local/share/android/sdk`
- **Flutter** → `~/.local/share/flutter` (see development.md)
