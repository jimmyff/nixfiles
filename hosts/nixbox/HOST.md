# nixbox — headless NixOS server
- No display. GUI apps show on a workstation over waypipe (Wayland forwarding over ssh): `waypiper run <cmd>`
- `waypiper status` → the linked workstation and its host notes; "no link" means ask Jimmy to open one
- Flutter: linux desktop (via waypiper), Android over adb (Pixel 8 Pro). No Chrome, no Apple toolchain
- dart MCP can't open windows here: launch in a shell with `--print-dtd`, attach via `dtd`
