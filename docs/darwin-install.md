# Darwin Setup

1. Install Nix: https://nixos.org/download/
2. Install Homebrew: https://brew.sh
3. Set hostname: `sudo scutil --set HostName jimmyff-mbp14`
4. Install Darwin: `sudo nix run --extra-experimental-features nix-command --extra-experimental-features flakes nix-darwin/master#darwin-rebuild -- switch --flake ~/nixfiles/flake.nix`
5. Setup SSH keys from Bitwarden
6. System keyboard shortcuts are disabled declaratively in `modules/core/darwin/symbolic-hotkeys.nix` (applied on `darwin-rebuild switch`; a logout/restart may be needed to take full effect)
7. Launch Raycast, bind to ⌘+Space
8. **Chromium ⌃-shortcuts** are codified in `modules/core/darwin/system-defaults.nix`
   (applied on `darwin-rebuild switch`; then `killall cfprefsd` + relaunch Chromium).
   Edit that file — not System Settings (a rebuild overwrites manual changes). See
   `docs/multiplexing.md` for the keyboard-layering model.

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

### kanata home-row mods (internal keyboard)

`kanata.enable` (host config) installs two root daemons, but the DriverKit driver and the macOS
permission grants can't be done by Nix — one-time setup, in order:

1. Install **Karabiner-DriverKit-VirtualHIDDevice v6.2.0** `.pkg`
   ([release](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/tag/v6.2.0)).
   Must match `installedDriverVersion` in `modules/core/darwin/kanata.nix` (eval asserts this).
2. Activate + approve the driver:
   `sudo /Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager forceActivate`
   → System Settings → General → Login Items & Extensions → **Driver Extensions** → enable `org.pqrs…`.
   Verify with `systemextensionsctl list` (`[activated enabled]`); if missing, reboot + re-run `forceActivate`.
3. `darwin-rebuild switch` — places `/usr/local/bin/kanata`, loads both daemons
   (`system/org.nixos.kanata`, `system/org.nixos.karabiner-vhid-daemon`). Until step 4, kanata runs
   but captures nothing (`/var/log/kanata.log`: `IOHIDDeviceOpen … not permitted`).
4. Grant **Input Monitoring** AND **Accessibility** to `/usr/local/bin/kanata`
   (Privacy & Security → "+" → `⌘⇧G` → path). The daemon never retries a failed capture, so:
   `sudo launchctl kickstart -k system/org.nixos.kanata`.
5. Confirm the device name: `sudo /usr/local/bin/kanata -l` → `Apple Internal Keyboard / Trackpad`
   (else set `kanata.includeDevices` — if NO name matches, kanata grabs **all** keyboards).

**On kanata version bumps** the binary's cdhash changes, silently voiding the TCC grants — the
activation script prints a warning at switch time. Re-grant (step 4) + kickstart. Health check:
`sudo launchctl print system/org.nixos.kanata | grep -E 'state|exit'` + `tail -5 /var/log/kanata.log`.
