# Darwin Setup

1. Install Nix: https://nixos.org/download/
2. Install Homebrew: https://brew.sh
3. Set hostname: `sudo scutil --set HostName jimmyff-mbp14`
4. Install Darwin: `sudo nix run --extra-experimental-features nix-command --extra-experimental-features flakes nix-darwin/master#darwin-rebuild -- switch --flake ~/nixfiles/flake.nix`
5. Setup SSH keys from Bitwarden
6. Disable system shortcuts: System Settings → Keyboard → Shortcuts
7. Launch Raycast, bind to ⌘+Space
8. Configure browser keyboard shortcuts in System Settings → Keyboard → Shortcuts → App Shortcuts: → All Applications

| Menu Title              | Keybind  |
| ----------------------- | -------- |
| Close Tab               | ^W       |
| New tab                 | ^T       |
| Focus Address Bar       | ^L       |
| New Tab                 | ^T       |
| Select Next Tab         | ^⌘L      |
| Select Previous Tab     | ^⌘H      |
| New Window              | ^N       |
| New window              | ^N       |
| New Incognito window    | ^⇧N      |
| New Private Window      | ^⇧N      |
| Reload This Page        | ^R       |
| Back                    | ^K       |
| Forward                 | ^J       |
| Hide Visual Studio Code | `random` |
| Hide Others             | `random` |

## Vimium keymaps

```
map <c-w> removeTab
map <c-t> createTab
map <c-m-h> previousTab
map <c-m-l> nextTab
map <c-m-j> goBack
map <c-m-k> goForward
```

## Homebrew Casks

Some macOS GUI apps (Signal, Chromium) aren't well-served by nixpkgs on darwin. These are managed declaratively via nix-darwin's homebrew module.

- **Config**: `modules/core/darwin/homebrew.nix`
- `cleanup = "zap"` removes anything not declared
- Casks are installed/upgraded automatically on `darwin-rebuild switch`

## Manual Installs

- **Xcode** (App Store)
- **Affinity** (App Store)
- **Android Studio** → `~/.local/share/android/sdk`
- **Flutter** → `~/.local/share/flutter` (see development.md)
