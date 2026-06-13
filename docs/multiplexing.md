# Multiplexing — kitty + zellij + mux

One kitty window, zellij as the only multiplexer, one named session per project
(**session = workspace**). Launch with `mux` (alias `x`).

## Keyboard layering

| Keys | Go to |
| ---- | ----- |
| ⌃ (anything) | the focused TUI — zellij is **locked by default** (Claude, Helix) |
| ⌘⌥ + home row / symbols / arrows | **zellij** — nav, resize, detach (works while locked) |
| ⌘ / ⌘⇧ + `hjkl` | aerospace — window focus / move |
| ⌥ / ⌘⌥ + top·bottom-row letter | aerospace — switch / move to workspace |
| ⌃ in Chromium | menu shortcuts — tabs, address bar |

kanata makes the modifiers from home-row holds: `a`/`;`=⌘, `s`/`l`=⌥, `d`/`k`=⌃, `f`/`j`=⇧.
So `Ctrl+s` = hold `d` + tap `s`. The **internal keyboard** gets these from the kanata daemon
(see `docs/darwin-install.md`); the **Moonlander** has the same mods baked into its QMK firmware.

## zellij keys

Sessions start **locked**, so every `Ctrl` reaches the TUI. To drive zellij:

| Key | Action |
| --- | ------ |
| `Ctrl+g` | toggle locked ↔ normal (then `Ctrl+t` tabs, `Ctrl+p` panes, …) |
| ⌘⌥ `hjkl` / arrows | move focus, or switch tab at the edge |
| ⌘⌥ `+ − =` / `[ ]` | resize / swap layout |
| ⌘⌃ `h` `l` | previous / next tab |
| ⌘⌥ `d` | detach |
| `Ctrl+g` → `Ctrl+o` `w` | session-manager (switch sessions) |

`Ctrl+g` shadows Claude's external-editor, so that's rebound to `Ctrl+E`
(`dotfiles/claude/keybindings.json`).

## mux

`mux` resolves a session name + layout from the cwd, then attaches or creates it.

| Command | Action |
| ------- | ------ |
| `mux` / `x` | launch or attach the workspace for the cwd |
| `mux reset` | delete the session, then relaunch (escape a bad resurrection) |
| `mux init` | scaffold a tabs-only `.zellij.kdl` here |
| `mux dash` | open/attach `dash` — one tab per active project |
| `mux dash reset` | delete `dash`, rescan projects, relaunch fresh |

- **Session name:** `$ZJ_SESSION` → `~/Projects/<name>/workspace` → git repo → cwd basename.
- **Layout:** `$ZJ_LAYOUT` → nearest `.zellij.kdl` → the `default_layout` fallback. That
  fallback is `jimmyff` (`dotfiles/zellij/layouts/jimmyff.kdl`, classic tab + status bar),
  used *only* when no `.zellij.kdl` is found.

`jimmyff.kdl` is the **single source of truth** for the bar chrome (`default_tab_template`).
Project `.zellij.kdl` files hold **only tabs/panes**; mux injects the current `default_tab_template`
from `jimmyff.kdl` at launch (and defensively strips any stale one a project still carries). So
editing `jimmyff.kdl` reaches every *new* session — no re-scaffolding. (Zellij has no cross-file
template inheritance, hence the launch-time injection; already-running/serialized sessions keep
their birth chrome until `mux reset`. `dev.nu` in osdn does the same injection for its dev layout.)

A project's `.zellij.kdl` lives at its repo root, in the **private** repo (layouts hold launch
commands; nixfiles is public). `~/nixfiles/.zellij.kdl` is the committed scaffold `mux init` writes.

## `mux dash`

A single session `dash`, one tab per active project — scan every workspace
without leaving zellij. Tabs-only like `mux init`; bar chrome injected at launch.

| Command | Action |
| ------- | ------ |
| `mux dash` | open/attach `dash` (attaching keeps shell state) |
| `mux dash reset` | delete `dash`, rescan, relaunch with a fresh layout |

- **Projects:** directory scan of `~/Projects/*/workspace` requiring `workspace/.git`
  (no Nix manifest), sorted by name — whatever is cloned shows up.
- **Each tab (one per folder):** vertical split — left an interactive shell, right
  `glitter overview --compact` (cached, one-shot; Enter to re-run). The left shell's
  devshell may print its own overview via `startup.nu` — harmless.
- **`~/nixfiles`:** always included as an ordinary folder (the `DASH_EXTRA` const in
  `mux.nu`) — same split; its `glitter overview` has 0 Dart packages but shows the repo's
  git status (the useful part). Add more always-on workspaces by editing that const.
- `mux dash` attaches the preserved session; use `mux dash reset` after cloning a
  new project. Run from **outside** zellij (can't nest a session).

## Applying changes

- **Live symlinks** — `dotfiles/zellij`, `dotfiles/aerospace`, `.zellij.kdl`: apply on the next
  zellij start / `aerospace reload-config`, not `darwin-rebuild`. Revert via git.
- **kitty / mux / Chromium** — `darwin-rebuild switch` (Chromium also needs `killall cfprefsd`).
- **kanata home-row mods** — edit `dotfiles/kanata/kanata-layers.kbd`, then `darwin-rebuild switch`
  (macOS) / `nixos-rebuild switch` (Linux); the daemon restarts automatically.
- Persistence is on; resurrecting **re-runs pane commands** — `mux reset` to start clean.
