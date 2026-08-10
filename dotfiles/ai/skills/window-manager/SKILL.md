---
name: window-manager
description: Control the desktop tiling window manager — AeroSpace on macOS, niri on Linux. List/focus/move windows, toggle floating/tiling. Use when arranging windows or when a launched app (simulator, Flutter run) needs its window managed.
---

# window-manager — tiling WM CLI

Pick by platform: `aerospace` (macOS), `niri msg` (Linux). Flags drift between versions — trust `--help` over this file.

## AeroSpace (macOS)

- `aerospace list-windows --all --json` — find windows (id, app, title, workspace)
- `aerospace layout floating tiling --window-id <id>` — toggle (single arg forces)
- `aerospace focus --window-id <id>` · `aerospace move-node-to-workspace <ws> --window-id <id>`
- Reference: `aerospace --help`; config: `~/nixfiles/dotfiles/aerospace/aerospace.toml`

## niri (Linux)

- `niri msg --json windows` — find windows
- `niri msg action toggle-window-floating --id <id>` (or `move-window-to-floating` / `move-window-to-tiling` to force)
- `niri msg action focus-window --id <id>` · `niri msg action move-window-to-workspace <ws>`
- Reference: `niri msg action --help`; config: `~/nixfiles/dotfiles/niri/config.kdl`
